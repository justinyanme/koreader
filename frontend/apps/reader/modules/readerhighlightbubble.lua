--[[--
Selection and highlight popovers of the e-ink redesign (see DESIGN.md, Selection
popover and Highlights).

Replaces ReaderHighlight (apps/replacements reader_highlight slot):
- a long-press selects a word, dragging extends it, and releasing shows the
  white selection popover: highlight, look up (查询, for CJK text) or translate
  (翻译, for other text, such as English), write note, copy, each an icon over
  its label;
- the selection is an ink underline with an ink drop handle under each end (not
  the engine's gray); dragging a handle moves that end across lines, and across
  pages from the page corners as a long-press drag does, the popover hidden
  meanwhile; expanding either way saves one highlight on release and shows
  Delete highlight, unless an explicit legacy action is configured;
- a tap on a highlight, or a long-press on a word of it, shows the same four
  actions with "Delete highlight" in the first place; after a long-press, the
  look-up is for the word pressed;
- copying closes the popover and confirms with a toast;
- a note is written in a bottom sheet; highlights with a note get a small mark
  after their last character.

New highlights are lines unless a default style was saved, in 设置 → 阅读 →
划线样式 (genDefaultStyleMenuItem, which sends "DefaultHighlightStyleChanged" to the
open book) or the original menu. Existing highlights keep their own style: markers
and waves keep showing, and the popovers offer no restyling
(doc/adr/0006-straight-line-default-highlight.md).

Refreshes: both popovers and the toast are black and white, so they show and
close with "fast" on their own rect, or "ui" where the page under them is gray
(the toast is solid, so it always shows with "fast"). So do the selection's
lines and handles when it changes or clears (the old and new ones together).
Saving, restyling or deleting a highlight refreshes its own lines with "ui";
nothing here refreshes the whole screen, but a selection across pages (the
page scrolled), as upstream.
]]

local BottomSheet = require("ui/widget/bottomsheet")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputText = require("ui/widget/inputtext")
local Palette = require("ui/palette")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local SelectionBubble = require("ui/widget/selectionbubble")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Toast = require("ui/widget/toast")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local ffi = require("ffi")
require("ffi/posix_h") -- free()
local util = require("util")
local Screen = Device.screen
local _ = require("gettext")
local C_ = _.pgettext

--- Paints a note mark after the last visible box of every highlight with a note.
local NoteMarks = Widget:extend{
    highlight = nil, -- ReaderHighlightBubble
}

function NoteMarks:init()
    self.size = Screen:scaleBySize(10)
    self.icon = IconWidget:new{ icon = "eink/note", width = self.size, height = self.size, alpha = true }
end

function NoteMarks:paintTo(bb, x, y)
    local annotations = self.highlight.ui.annotation.annotations
    local last = {}
    for _, box in ipairs(self.highlight.view.highlight.visible_boxes or {}) do
        local item = annotations[box.index]
        if item and item.note then
            last[box.index] = box
        end
    end
    for _, box in pairs(last) do
        local r = self.highlight:boxToScreen(box)
        if r then
            -- raised into the line gap: page text cannot reflow around it
            self.icon:paintTo(bb, x + r.x + r.w, y + r.y - math.floor(self.size / 2))
        end
    end
end

--- Paints the selection (DESIGN.md, Selection): a 1dp ink underline under the selected text, where a line
-- highlight would be, and an ink drop handle hanging under each end. Remembers the handles it painted, which
-- are what can be grabbed (ReaderHighlightBubble:handleAt()).
local SelectionMarks = Widget:extend{
    highlight = nil, -- ReaderHighlightBubble
    handles = nil, -- screen rects of the painted handles, by end ("start", "end"), with the side they hang to
    paints_over_footer = true, -- so that ReaderFooter paints it again when it repaints itself alone
}

-- Whether a line of a selection is on the screen, all of it, or some of it (across pages, the page scrolls
-- under the selection).
local function onScreen(r, partly)
    if partly then
        return r.y + r.h > 0 and r.y < Screen:getHeight()
    end
    return r.y >= 0 and r.y + r.h <= Screen:getHeight()
end

-- A disc with its top corner toward the text squared (it hangs to the other side): that corner points at the
-- end of the selection.
local function paintHandle(bb, x, y, d, hang)
    local half = math.floor(d / 2)
    bb:paintRoundedRect(x, y, d, d, Palette.ink, half)
    bb:paintRect(hang == "left" and x + d - half or x, y, half, half, Palette.ink)
end

function SelectionMarks:paintTo(bb, x, y)
    self.handles = nil
    local highlight = self.highlight
    if not (highlight.hold_pos and highlight.selected_text) then return end
    local rects = highlight:selectionRects()
    if #rects == 0 then return end
    local tops, handles = highlight:selectionMarks(bb, rects)
    if not tops then return end
    for i, r in ipairs(rects) do
        if onScreen(r, true) then
            bb:paintRect(x + r.x, y + tops[i], r.w, Size.border.default, Palette.ink)
        end
    end
    self.handles = handles
    for _, h in pairs(handles) do
        paintHandle(bb, x + h.x, y + h.y, h.w, h.hang)
    end
end

--- The selection popover, which also takes the gestures that drag the selection's handles: on top, it gets
-- every gesture on the page first. It paints nothing while hidden (a handle is being dragged).
local SelectionPopover = SelectionBubble:extend{
    page_gesture = nil, -- function(ges): a gesture outside the popover's cells; true if it was taken
    hidden = false,
}

function SelectionPopover:init()
    SelectionBubble.init(self)
    local hold_pan_rate = G_reader_settings:readSetting("hold_pan_rate") or (Screen.low_pan_rate and 5.0 or 30.0)
    local ranges = {}
    for _, ges in ipairs{ "touch", "hold", "hold_pan", "hold_release", "pan", "pan_release", "swipe", "multiswipe" } do
        local moves = ges == "pan" or ges == "hold_pan"
        table.insert(ranges, GestureRange:new{ ges = ges, range = self.dimen, rate = moves and hold_pan_rate or nil })
    end
    self.ges_events.PageGesture = ranges
end

function SelectionPopover:onPageGesture(_, ges)
    return self.page_gesture(ges)
end

-- A tap on a handle keeps the selection.
function SelectionPopover:onTapClose(arg, ges)
    if self.hidden or self.page_gesture(ges) then return true end
    return SelectionBubble.onTapClose(self, arg, ges)
end

function SelectionPopover:paintTo(bb, x, y)
    if not self.hidden then
        SelectionBubble.paintTo(self, bb, x, y)
    end
end

--- Note sheet: stays above the on-screen keyboard.
local NoteSheet = BottomSheet:extend{
    input = nil, -- InputText
    is_always_active = true, -- taps outside the keyboard on top of us still reach us, as with InputDialog
    close_on_scrim = false, -- a stray tap must not lose the text being typed
}

function NoteSheet:fitKeyboard()
    local old = self:getRefreshRegion()
    self.bottom_inset = self.input:isKeyboardVisible() and self.input:getKeyboardDimen().h or 0
    self:build()
    UIManager:setDirty("all", "ui", old:combine(self:getRefreshRegion()))
end
NoteSheet.onKeyboardHeightChanged = NoteSheet.fitKeyboard
NoteSheet.onKeyboardClosed = NoteSheet.fitKeyboard

-- A tap on the text area once the keyboard was hidden: as InputText does without a parent, then make room again.
function NoteSheet:onSwitchFocus(input)
    if not ((Device:hasKeyboard() or Device:hasScreenKB()) and G_reader_settings:nilOrFalse("virtual_keyboard_enabled")) then
        input:onShowKeyboard()
    end
    Device:startTextInput()
    input.focused = true
    self:fitKeyboard()
end

function NoteSheet:onClose()
    -- the keyboard is freed with the input text, so hide it first
    self.input:onCloseKeyboard()
    return BottomSheet.onClose(self)
end

local ReaderHighlightBubble = ReaderHighlight:extend{}

--- Styles for new highlights: line, marker, wave. The original menu's other styles (strikethrough, invert)
-- stay available there.
ReaderHighlightBubble.STYLES = {
    { C_("Highlight style", "Underline"), "underscore" },
    { C_("Highlight style", "Marker"), "lighten" },
    { _("Wavy underline"), "wave" }, -- fork-only style, see doc/adr/0003-wavy-highlight-style.md
}

-- new highlights are lines until a default style is saved (doc/adr/0006-straight-line-default-highlight.md)
local DEFAULT_DRAWER = "underscore"

--- The style of new highlights: the saved default, else a line.
function ReaderHighlightBubble.getDefaultDrawer()
    return G_reader_settings:readSetting("highlight_drawing_style") or DEFAULT_DRAWER
end

--- The 划线样式 row of the reorganized settings (ui/elements/eink_settings_order.lua): line, marker or
-- wave as one choice for new highlights; existing highlights keep their own style. A default saved in
-- another style from the original menu (strikethrough, invert) is listed too, checked, so that it shows
-- as the row's value.
function ReaderHighlightBubble.genDefaultStyleMenuItem()
    local styles = {}
    local default, listed = ReaderHighlightBubble.getDefaultDrawer(), false
    for _, style in ipairs(ReaderHighlightBubble.STYLES) do
        table.insert(styles, style)
        if style[2] == default then listed = true end
    end
    if not listed then
        for _, style in ipairs(ReaderHighlight.getHighlightStyles()) do
            if style[2] == default then table.insert(styles, style) end
        end
    end
    local sub_item_table = {}
    for _, style in ipairs(styles) do
        local drawer = style[2]
        table.insert(sub_item_table, {
            text = style[1],
            radio = true,
            checked_func = function()
                return ReaderHighlightBubble.getDefaultDrawer() == drawer
            end,
            callback = function()
                G_reader_settings:saveSetting("highlight_drawing_style", drawer)
                -- for the open book's next highlight
                UIManager:broadcastEvent(Event:new("DefaultHighlightStyleChanged"))
            end,
        })
    end
    return { text = C_("Settings", "Highlight style"), sub_item_table = sub_item_table }
end

--- Registers the bubbles in their replacement slot.
-- Touch devices only, like the toolbar: the bubbles have no key navigation.
function ReaderHighlightBubble.register()
    if Device:isTouchDevice() then
        require("apps/replacements").reader_highlight = ReaderHighlightBubble
    end
end

function ReaderHighlightBubble:init()
    ReaderHighlight.init(self)
    self._fallback_drawer = DEFAULT_DRAWER -- starred in the original menu while no default is saved
    self.view:registerViewModule("note_marks", NoteMarks:new{ highlight = self })
    self.selection_marks = SelectionMarks:new{ highlight = self }
    self.view:registerViewModule("selection_marks", self.selection_marks)
end

function ReaderHighlightBubble:onReadSettings(config)
    self._book_drawer = config:readSetting("highlight_drawer")
    ReaderHighlight.onReadSettings(self, config)
    -- not the style saved with this book: upstream saves the current one on every close
    self:onDefaultHighlightStyleChanged()
end

-- Upstream saves the current style with the book: keep the book's own instead, for upstream KOReader and
-- devices without touch that open the same book settings.
function ReaderHighlightBubble:onSaveSettings()
    ReaderHighlight.onSaveSettings(self)
    if self._book_drawer then
        self.ui.doc_settings:saveSetting("highlight_drawer", self._book_drawer)
    else
        self.ui.doc_settings:delSetting("highlight_drawer")
    end
end

--- New highlights take the default style (after it was changed in the settings).
function ReaderHighlightBubble:onDefaultHighlightStyleChanged()
    self.view.highlight.saved_drawer = ReaderHighlightBubble.getDefaultDrawer()
    self:setSelectionColor()
end

--- Screen rects of boxes; on fixed-layout pages boxes are in page coordinates (item gives the page).
function ReaderHighlightBubble:toScreen(boxes, item)
    local rects = {}
    for _, box in ipairs(boxes or {}) do
        local page = self.ui.paging and item and item.pos0 and item.pos0.page
        local r = self.view:pageToScreenTransform(page, box)
        if r then table.insert(rects, r) end
    end
    return rects
end

function ReaderHighlightBubble:selectionRects()
    return self.selected_text and self:toScreen(self.selected_text.sboxes or self.selected_text.pboxes, self.selected_text) or {}
end

--- Screen rect of a visible highlight box (fixed-layout boxes carry their page).
function ReaderHighlightBubble:boxToScreen(box)
    local item = self.ui.annotation.annotations[box.index]
    return self.view:pageToScreenTransform(box.page or (item and item.pos0 and item.pos0.page), box.rect)
end

function ReaderHighlightBubble:highlightRects(index)
    local rects = {}
    for _, box in ipairs(self.view.highlight.visible_boxes or {}) do
        if box.index == index then
            table.insert(rects, self:boxToScreen(box))
        end
    end
    return rects
end

--- The lines of some text: their bounding box, grown by the note mark and the underlines below the text,
-- and as wide as the screen when notes are marked in the margin.
function ReaderHighlightBubble:linesRegion(rects)
    if #rects == 0 then return end
    local pad = Screen:scaleBySize(10)
    local r = Geom.boundingBox(rects)
    local note_mark = self.view.highlight.note_mark
    if note_mark == "sideline" or note_mark == "sidemark" then
        return Geom:new{ x = 0, y = r.y - pad, w = Screen:getWidth(), h = r.h + 2 * pad }
    end
    return Geom:new{ x = r.x - pad, y = r.y - pad, w = r.w + 2 * pad, h = r.h + 2 * pad }
end

-- "fast" only renders black and white: use "ui" over scanned or rendered pages, marker highlights and images.
function ReaderHighlightBubble:refreshTypeOver(region)
    if self.ui.paging then return "ui" end
    for _, box in ipairs(self.view.highlight.visible_boxes or {}) do
        if box.drawer == "lighten" then
            local r = self:boxToScreen(box)
            if r and region:intersectWith(r) then
                return "ui"
            end
        end
    end
    -- ponytail: samples a 3×3 grid, so an image smaller than a ninth of the region can be missed
    local cre = self.ui.document._document
    for i = 0, 2 do
        for j = 0, 2 do
            local data = cre:getImageDataFromPosition(region.x + math.floor(region.w * (1 + 2 * i) / 6),
                region.y + math.floor(region.h * (1 + 2 * j) / 6))
            if data then
                ffi.C.free(data)
                return "ui"
            end
        end
    end
    return "fast"
end

--- The tops of the selection's underline, one per rect: where a line highlight would be (DESIGN.md,
-- Highlights), under the glyphs of each line of reflowable text, at the bottom of the box on fixed-layout pages.
-- On a line that has one already, where that one is: the glyphs can no longer be told from it on the page.
function ReaderHighlightBubble:underlineTops(bb, rects)
    local tops = {}
    if self.ui.paging then
        for i, r in ipairs(rects) do tops[i] = r.y + r.h - 1 end
        return tops
    end
    local lines, line_tops = {}, {} -- the segments of one line share its box's y and h
    for _, r in ipairs(rects) do
        local key = r.y .. ":" .. r.h
        lines[key] = lines[key] or {}
        table.insert(lines[key], r)
    end
    local highlighted = self.view.highlight.line_tops or {}
    for key, segments in pairs(lines) do
        local r = segments[1]
        -- lines out of the screen (across pages) cannot be read: the bottom of their box
        line_tops[key] = highlighted[key] or (onScreen(r, true) and self.view:underlineY(bb, segments)) or r.y + r.h - 1
    end
    for i, r in ipairs(rects) do tops[i] = line_tops[r.y .. ":" .. r.h] end
    return tops
end

-- U+0590–U+08FF (Hebrew to Arabic Extended-A) and their presentation forms, U+FB1D–U+FDFF and U+FE70–U+FEFF
local function hasRightToLeftText(text)
    return text:find("\xD6[\x90-\xBF]") or text:find("[\xD7-\xDF]") or text:find("\xE0[\xA0-\xA3]")
        or text:find("\xEF\xAC[\x9D-\xBF]") or text:find("\xEF[\xAD-\xB7]") or text:find("\xEF\xB9[\xB0-\xBF]")
        or text:find("\xEF[\xBA\xBB]")
end

--- The two ends of the selection in the order of the text, "start" and "end": the index of the line rect each
-- is on, the x of its edge there and the side its handle hangs to, away from the text. On a right-to-left
-- line a selection starts at the right: its first and last characters tell. On fixed-layout pages, lines are
-- taken as left to right, and right-to-left text has no ends.
function ReaderHighlightBubble:selectionEnds(rects)
    local first, last = rects[1], rects[#rects]
    local starts_right, ends_left = false, false
    if self.ui.rolling then
        local doc, selected = self.ui.document, self.selected_text
        local function charBox(xp0, xp1)
            local boxes = xp0 and xp1 and doc:getScreenBoxesFromPositions(xp0, xp1, true)
            return boxes and boxes[1]
        end
        local function mid(r) return r.x + r.w / 2 end
        local a = charBox(selected.pos0, doc:getNextVisibleChar(selected.pos0))
        local b = charBox(doc:getPrevVisibleChar(selected.pos1), selected.pos1)
        starts_right = a and mid(a) > mid(first) or false
        ends_left = b and mid(b) < mid(last) or false
    elseif hasRightToLeftText(self.selected_text.text or "") then
        return {}
    end
    return {
        start = { index = 1, x = starts_right and first.x + first.w or first.x, hang = starts_right and "right" or "left" },
        ["end"] = { index = #rects, x = ends_left and last.x or last.x + last.w, hang = ends_left and "left" or "right" },
    }
end

--- The handles of the selection (screen rects, by end, with the side they hang to), given the tops of its
-- underline: about 25dp ink drops hanging under its ends, flat tops level with the glyphs' bottom (4dp above
-- the underline), as in WeChat Read. Kept on the screen; an end whose line is out of the screen (across pages)
-- has none.
function ReaderHighlightBubble:handleRects(rects, tops)
    local d, rise = Screen:scaleBySize(25), Screen:scaleBySize(4)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local handles = {}
    for side, e in pairs(self:selectionEnds(rects)) do
        if onScreen(rects[e.index]) then
            handles[side] = Geom:new{
                x = math.max(0, math.min(sw - d, e.hang == "left" and e.x - d or e.x)),
                y = math.max(0, math.min(sh - d, tops[e.index] - rise)),
                w = d,
                h = d,
                hang = e.hang,
            }
        end
    end
    return handles
end

--- The underline tops and handles of the selection on the page as painted (bb), kept while its lines stay
-- where they are: repainted over the footer alone, the page already has the underline, which is not glyphs.
-- Nothing (yet) when a changed selection is repainted over a page that still has the old one's marks.
function ReaderHighlightBubble:selectionMarks(bb, rects)
    local key = {}
    for i, r in ipairs(rects) do key[i] = r.x .. "," .. r.y .. "," .. r.w .. "," .. r.h end
    key = table.concat(key, ";")
    local marks = self.painted_marks
    local page_paints = self.view.highlight.page_paints
    if not (marks and marks.selection == self.selected_text and marks.key == key) then
        if marks and marks.page_paints == page_paints then return end -- the page repaint is on its way
        local tops = self:underlineTops(bb, rects)
        marks = { selection = self.selected_text, key = key, tops = tops, handles = self:handleRects(rects, tops) }
        self.painted_marks = marks
    end
    marks.page_paints = page_paints
    return marks.tops, marks.handles
end

--- What the handles can cover before they are painted (the glyphs set their height): from the top of their
-- line down to the lowest they can hang, from an underline at the bottom of the box.
function ReaderHighlightBubble:handleBounds(rects)
    local lowest = {}
    for i, r in ipairs(rects) do lowest[i] = r.y + r.h - 1 end
    local bounds = {}
    for side, h in pairs(self:handleRects(rects, lowest)) do
        local top = math.min(h.y, (side == "start" and rects[1] or rects[#rects]).y)
        bounds[side] = Geom:new{ x = h.x, y = top, w = h.w, h = h.y + h.h - top }
    end
    return bounds
end

--- The lines of the selection and its handles, on the screen: what changing or clearing it repaints.
function ReaderHighlightBubble:selectionRegion()
    local rects = self:selectionRects()
    local region = self:linesRegion(rects)
    if not region then return end
    for _, bound in pairs(self:handleBounds(rects)) do
        region = region:combine(bound)
    end
    local screen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    return region:intersectWith(screen) and region:intersect(screen) or nil
end

--- The popover's anchors: the selection, its last line down to the handles under it, so that a popover below
-- the selection (at the top of the page) stays clear of them.
function ReaderHighlightBubble:popoverAnchors(rects)
    local anchors = {}
    for i, r in ipairs(rects) do anchors[i] = r end
    local last = rects[#rects]
    local bottom = last.y + last.h
    for _, bound in pairs(self:handleBounds(rects)) do
        bottom = math.max(bottom, bound.y + bound.h)
    end
    anchors[#rects] = Geom:new{ x = last.x, y = last.y, w = last.w, h = bottom - last.y }
    return anchors
end

--- The engine's own way of showing a selection (crengine's gray, the boxes ReaderView paints on fixed-layout
-- pages) is not used: SelectionMarks paints it. Each new selection from the engine shows it again.
function ReaderHighlightBubble:hideEngineSelection()
    if self.ui.paging then
        if self.hold_pos then
            self.view.highlight.temp[self.hold_pos.page] = nil
        end
    else
        self.ui.document:clearSelection()
    end
end

--- Repaints the selection once it changed (ReaderHighlight hook point): the lines and handles of the old and
-- new selections, "fast" where they are black and white; the whole page across pages, the page scrolled.
function ReaderHighlightBubble:refreshSelection()
    local scrolled = self.restore_page_mode_func ~= nil
    local region = not scrolled and self:selectionRegion() or nil
    local old = not scrolled and self.shown_selection_region or nil -- a selection lost leaves its old lines
    local dirty = region and old and region:combine(old) or region or old
    self.shown_selection_region = region
    if dirty then
        UIManager:setDirty(self.dialog, self:refreshTypeOver(dirty), dirty)
    else
        UIManager:setDirty(self.dialog, "ui")
    end
end

function ReaderHighlightBubble:onHold(arg, ges)
    local handled = ReaderHighlight.onHold(self, arg, ges)
    self.selection_before_drag = self.selected_text
    if self.hold_pos and self.selected_text then -- a word: its underline and handles
        self:hideEngineSelection()
        self.shown_selection_region = nil
        self:refreshSelection()
    end
    return handled
end

function ReaderHighlightBubble:onHoldPan(arg, ges)
    local handled = ReaderHighlight.onHoldPan(self, arg, ges)
    -- also when the text did not change, and nothing is repainted: crengine selected it again
    self:hideEngineSelection()
    if self.ui.rolling and self.restore_page_mode_func and self.selected_text and self.selected_text.pos0 then
        -- the page scrolled (or turned) from a corner: the selection's lines moved with it
        self.selected_text.sboxes = self.ui.document:getScreenBoxesFromPositions(self.selected_text.pos0,
            self.selected_text.pos1, true)
    end
    return handled
end

--- Which handle a screen position grabs, if any: the nearest one within a 44dp square around it.
function ReaderHighlightBubble:handleAt(pos)
    local reach = math.floor(Screen:scaleBySize(44) / 2)
    local found, found_d
    for side, h in pairs(self.selection_marks.handles or {}) do
        local dx, dy = pos.x - (h.x + h.w / 2), pos.y - (h.y + h.h / 2)
        if math.abs(dx) <= math.max(reach, h.w / 2) and math.abs(dy) <= math.max(reach, h.h / 2) then
            local d = dx * dx + dy * dy
            if not found_d or d < found_d then
                found, found_d = side, d
            end
        end
    end
    return found
end

--- A gesture on the page while the selection popover is up: a hold or a pan from a handle drags it, until the
-- finger lifts; a tap on a handle keeps the selection. Returns true when it took the gesture.
function ReaderHighlightBubble:pageGesture(ges)
    local kind = ges.ges
    if kind == "touch" then
        self.touch_pos = ges.pos -- a hold is reported where the finger is by then, which may be off the handle
        return false
    end
    if not self.handle_drag then
        if kind == "tap" then
            return self:handleAt(ges.pos) ~= nil
        end
        if kind ~= "hold" and kind ~= "pan" and kind ~= "swipe" and kind ~= "multiswipe" then return false end
        -- where the finger went down: pans say so, swipes are reported there
        local start = ges.start_pos or (kind == "hold" and self.touch_pos) or ges.pos
        local side = self.hold_pos and self.selected_text and self:handleAt(start)
        if not side then return false end
        self:startHandleDrag(side, start)
    end
    if kind == "pan" or kind == "hold_pan" then
        self:dragHandleTo(ges.pos)
    elseif kind == "pan_release" or kind == "hold_release" then
        self:endHandleDrag(ges.pos)
    elseif kind == "swipe" or kind == "multiswipe" then
        self:endHandleDrag(ges.end_pos)
    end
    return true
end

--- Grabs a handle: the other end of the selection stays, as where a long-press started, and the grabbed one
-- follows the finger at the distance it was grabbed from, so that the finger does not hide it. The drag goes
-- through ReaderHighlight:onHoldPan(), for its selection across pages from the corners. The popover hides
-- meanwhile.
function ReaderHighlightBubble:startHandleDrag(side, pos)
    self.selection_before_drag = self.selected_text
    local rects = self:selectionRects()
    local ends = self:selectionEnds(rects)
    -- points in the first and the last character, next to the edge of the selection
    local function point(e)
        local r = rects[e.index]
        return Geom:new{ x = e.x + (e.hang == "left" and 1 or -2), y = r.y + math.floor(r.h / 2), w = 0, h = 0 }
    end
    local fixed, moving = point(ends.start), point(ends["end"])
    if side == "start" then
        fixed, moving = moving, fixed
    end
    self.hold_pos = self.view:screenToPageTransform(fixed)
    if self.ui.rolling then
        -- where a selection across pages measures the scrolling from, and puts its marker once done
        self.selected_text_start_xpointer = side == "start" and self.selected_text.pos1 or self.selected_text.pos0
    end
    self.allow_hold_pan_corner_scroll = false -- as after a long-press: not in the corner it starts in
    self.was_in_some_corner = nil
    self.handle_drag = { dx = moving.x - pos.x, dy = moving.y - pos.y }
    local popover = self.highlight_dialog
    if popover then
        popover.hidden = true
        UIManager:setDirty(self.dialog, popover.refresh_type, popover:getRefreshRegion())
    end
end

--- Moves the grabbed end to the text at the finger, kept on the page.
function ReaderHighlightBubble:dragHandleTo(pos)
    local drag = self.handle_drag
    local area = self.view:getScreenPageArea(self.hold_pos.page)
    self:onHoldPan(nil, { pos = Geom:new{
        x = math.max(area.x, math.min(area.x + area.w - 1, pos.x + drag.dx)),
        y = math.max(area.y, math.min(area.y + area.h - 1, pos.y + drag.dy)),
        w = 0,
        h = 0,
    } })
end

--- The finger lifted: use the same save/preference path as a continuous long-press drag.
function ReaderHighlightBubble:endHandleDrag(pos)
    if pos then
        self:dragHandleTo(pos)
    end
    self.handle_drag = nil
    if self.selected_text then
        self:closeBubble()
        self:onHoldRelease()
    else
        self:dismiss()
    end
end

--- Clears the selection, repainting only its lines and handles (upstream repaints the whole page).
-- With fast, uses "fast" where nothing gray is under it; otherwise "ui", as upstream save paths
-- (dictionary, highlight prompt, select mode) clear right after painting a gray marker.
function ReaderHighlightBubble:clear(clear_id, fast)
    if (clear_id and clear_id ~= self.clear_id) or not self.hold_pos or not self.ui.document then
        return ReaderHighlight.clear(self, clear_id)
    end
    -- selections spanning pages turn pages back: those need the whole page
    local region = not self.restore_page_mode_func and self:selectionRegion()
    self.hold_pos = nil
    self.handle_drag = nil
    self.selection_before_drag = nil
    self.shown_selection_region = nil
    ReaderHighlight.clear(self, clear_id)
    self.selected_text = nil
    if region then
        UIManager:setDirty(self.dialog, fast and self:refreshTypeOver(region) or "ui", region)
    else
        UIManager:setDirty(self.dialog, "ui")
    end
    return true
end

-- The popover's corners and the strip beside its arrow show the page: "fast" only where it is black and white.
function ReaderHighlightBubble:showBubble(bubble)
    self:closeBubble()
    bubble.refresh_type = self:refreshTypeOver(bubble:getRefreshRegion())
    self.highlight_dialog = bubble
    UIManager:show(bubble, bubble.refresh_type, bubble:getRefreshRegion())
end

function ReaderHighlightBubble:closeBubble()
    local bubble = self.highlight_dialog
    self.highlight_dialog = nil
    if not bubble then return end
    -- upstream dialog, or hidden while a handle was dragged: the page is already repainted there
    if not bubble.getRefreshRegion or bubble.hidden then
        return UIManager:close(bubble)
    end
    local region = bubble:getRefreshRegion()
    UIManager:close(bubble, bubble.refresh_type, region)
end

--- Closes the selection bubble and clears the selection, both "fast" where possible.
function ReaderHighlightBubble:dismiss()
    self:closeBubble()
    self:clear(nil, true)
end

function ReaderHighlightBubble:onClose(keep_highlight)
    self:closeBubble()
    if not keep_highlight then
        self:clear()
    end
end

function ReaderHighlightBubble:onHoldRelease()
    if not self.hold_pos and not self.select_mode then
        -- nothing was selected (blank area, "Do nothing" long-press action...): drop a selection left over
        -- from looking up a highlight, so that it does not come back as a new bubble
        self.selected_text = nil
    end
    if self.clear_id or self.select_mode or not self.hold_pos or not self.selected_text then
        return ReaderHighlight.onHoldRelease(self)
    end
    if (G_reader_settings:has("default_highlight_action") and not self.is_word_selection)
            or (self.is_word_selection and G_reader_settings:has("highlight_action_on_single_word"))
            or self.ui.keyselection:isActive() then
        return ReaderHighlight.onHoldRelease(self)
    end
    local before = self.selection_before_drag
    local changed = before and (not util.tableEquals(before.pos0, self.selected_text.pos0)
        or not util.tableEquals(before.pos1, self.selected_text.pos1))
    if before and self.ui.paging then
        -- PDF positions are raw touch points: compare the selected words, not finger jitter within them.
        changed = before.pos0.page ~= self.selected_text.pos0.page
            or before.pos1.page ~= self.selected_text.pos1.page
            or not util.tableEquals(before.pboxes, self.selected_text.pboxes)
    end
    if changed and not self.is_word_selection then
        self:_resetHoldTimer(true)
        self:saveAndShowHighlight()
        return true
    end
    self:_resetHoldTimer(true)
    -- a long-press on a word of a highlight (no drag) shows that highlight's popover, as a tap does
    local highlights = self.is_word_selection and self:highlightsAt(self.hold_pos) or {}
    self.is_word_selection = false
    if #highlights > 0 then
        local word = self.selected_text
        self:clear(nil, true)
        if #highlights == 1 then
            self:showHighlightBubble(highlights[1], nil, word)
        else
            self:showChooseHighlightDialog(highlights) -- overlapping highlights: upstream's list
        end
        return true
    end
    -- a single word gets the bubble too, not the dictionary straight away
    self:onShowHighlightMenu()
    return true
end

--- Indexes of the highlights shown at a page position, as ReaderHighlight:onTap() finds them.
function ReaderHighlightBubble:highlightsAt(pos)
    local indexes, seen = {}, {}
    for _, box in ipairs(self.view.highlight.visible_boxes or {}) do
        local r = box.rect
        if not seen[box.index] and (not box.page or box.page == pos.page)
                and pos.x >= r.x and pos.x <= r.x + r.w and pos.y >= r.y and pos.y <= r.y + r.h then
            seen[box.index] = true
            table.insert(indexes, box.index)
        end
    end
    return indexes
end

-- languages whose text is looked up (查询) rather than translated: book metadata and OCR codes
local CJK_LANGUAGES = { "^zh", "^ja", "^ko", "^chi", "^jpn", "^kor" }

--- Whether text is looked up (查询, as CJK text) rather than translated (翻译, other text such as English),
-- as WeChat Read names them. Without text (a selection on a scanned page), the book's language decides:
-- its metadata, or an OCR language other than the default; CJK when unknown.
function ReaderHighlightBubble:isLookedUp(text)
    if text:find("%S") then
        for c in text:gmatch(util.UTF8_CHAR_PATTERN) do
            if util.isCJKWordChar(c) then return true end
        end
        return false
    end
    local lang = self.ui.doc_props and self.ui.doc_props.language
    if not lang or lang == "" then
        local ocr_lang = self.ui.document.configurable and self.ui.document.configurable.doc_language
        if ocr_lang ~= G_defaults:readSetting("DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE") then
            lang = ocr_lang
        end
    end
    if not lang or lang == "" then return true end
    lang = lang:lower()
    for _, pattern in ipairs(CJK_LANGUAGES) do
        if lang:find(pattern) then return true end
    end
    return false
end

--- The look-up cell for some text (see isLookedUp). Both actions open the dictionary sheet.
function ReaderHighlightBubble:lookupCell(text, callback)
    if self:isLookedUp(text) then
        return { icon = "eink/search", text = C_("Highlight bubble", "Look up"), callback = callback }
    end
    return { icon = "eink/translate", text = _("Translate"), callback = callback }
end

--- Copies text to the clipboard, and says so in a toast over the lower part of the page.
function ReaderHighlightBubble:copyText(text)
    Device.input.setClipboardText(text)
    local toast = Toast:new{ text = C_("Highlight bubble", "Copied") }
    toast.close_refresh_type = self:refreshTypeOver(toast.dimen)
    UIManager:show(toast)
end

--- Selection popover: highlight, look up or translate, write note, copy.
function ReaderHighlightBubble:onShowHighlightMenu(index)
    if not self.selected_text then return end
    local rects = self:selectionRects()
    if #rects == 0 then -- e.g. multi-page selection in select mode
        self:closeBubble() -- one hidden while a handle was dragged would take every tap
        return ReaderHighlight.onShowHighlightMenu(self, index)
    end
    local text = util.cleanupSelectedText(self.selected_text.text)
    local anchors = self:popoverAnchors(rects)
    local bubble = SelectionPopover:new{
        rows = { {
            { icon = "eink/highlight", text = C_("Highlight bubble", "Highlight"), callback = function()
                self:saveAndShowHighlight()
            end },
            self:lookupCell(text, function()
                self:closeBubble()
                -- the dictionary popup clears the selection
                if self.selected_text.text == "" and self.selected_text.sboxes then
                    self:lookupDictWord() -- scanned page: OCR
                else
                    self:lookupDict()
                end
            end),
            { icon = "eink/thought", text = C_("Highlight bubble", "Write note"), callback = function()
                local index = self:saveSelection()
                if index then self:showNoteSheet(index, true) end
            end },
            { icon = "eink/copy", text = C_("Text", "Copy"), callback = function()
                self:dismiss()
                self:copyText(text)
            end },
        } },
        anchor_rects = anchors,
        tap_close_callback = function() self:dismiss() end,
        page_gesture = function(ges) return self:pageGesture(ges) end,
    }
    self:showBubble(bubble)
end

--- Saves once on release or on the Highlight action, keeping Delete highlight immediately available.
function ReaderHighlightBubble:saveAndShowHighlight()
    local rects = self:selectionRects()
    local anchors = #rects > 0 and self:popoverAnchors(rects) or nil
    -- Clearing a selection across pages turns back: position the popover after that repaint.
    local turns_back = self.restore_page_mode_func ~= nil
    local index = self:saveSelection()
    if not index then return end
    if turns_back then
        UIManager:nextTick(function() self:showHighlightBubble(index) end)
    else
        self:showHighlightBubble(index, anchors)
    end
end

--- Saves the selection as a highlight in the default style; returns its index.
function ReaderHighlightBubble:saveSelection()
    self:closeBubble()
    local index = self:saveHighlight()
    self:clear(nil, "ui")
    return index
end

-- Upstream opens a note viewer or the edit dialog; both become the highlight bubble.
function ReaderHighlightBubble:showHighlightNoteOrDialog(index)
    self:showHighlightBubble(index)
end

--- Highlight popover: the selection popover's actions, with "Delete highlight" in the first place.
-- rects: screen rects of the highlight when it has not been painted yet
-- word: the selection of a word long-pressed in it, which the look-up is for instead of the whole highlight
function ReaderHighlightBubble:showHighlightBubble(index, rects, word)
    local item = self.ui.annotation.annotations[index]
    rects = rects or self:highlightRects(index)
    if #rects == 0 then
        return ReaderHighlight.showHighlightNoteOrDialog(self, index)
    end
    local bubble = SelectionBubble:new{
        rows = { {
            { icon = "eink/highlight-off", text = C_("Highlight bubble", "Delete highlight"), callback = function()
                self:closeBubble()
                self:deleteHighlight(index)
            end },
            self:lookupCell((word or item).text, function()
                self:closeBubble()
                self.selected_text = util.tableDeepCopy(word or item)
                self:lookupDict(not word and index or nil)
            end),
            { icon = "eink/thought",
              text = item.note and C_("Highlight bubble", "Edit note") or C_("Highlight bubble", "Write note"),
              callback = function()
                self:closeBubble()
                self:showNoteSheet(index)
              end },
            { icon = "eink/copy", text = C_("Text", "Copy"), callback = function()
                self:closeBubble()
                self:copyText(item.text)
            end },
        } },
        anchor_rects = rects,
        tap_close_callback = function() self:closeBubble() end,
    }
    self:showBubble(bubble)
end

function ReaderHighlightBubble:deleteHighlight(index)
    local region = self:linesRegion(self:highlightRects(index))
    local item = self.ui.annotation.annotations[index]
    self:writePdfAnnotation("delete", item)
    self.ui.bookmark:removeItemByIndex(index)
    UIManager:setDirty(self.dialog, "ui", region) -- whole page when not visible, as upstream
end

--- Sets or clears (empty text) the note of a highlight, as ReaderBookmark:setBookmarkNote().
function ReaderHighlightBubble:setNote(index, text)
    local annotation = self.ui.annotation.annotations[index]
    local value = text ~= "" and text or nil
    local type_before = self.ui.bookmark.getBookmarkType(annotation)
    annotation.note = value
    self:writePdfAnnotation("content", annotation, value or "")
    local type_after = self.ui.bookmark.getBookmarkType(annotation)
    if type_before == type_after then
        self.ui.annotation:onAnnotationsModified({ annotation })
    elseif type_before == "highlight" then
        self.ui:handleEvent(Event:new("AnnotationsModified", { annotation, nb_highlights_added = -1, nb_notes_added = 1 }))
    else
        self.ui:handleEvent(Event:new("AnnotationsModified", { annotation, nb_highlights_added = 1, nb_notes_added = -1 }))
    end
end

--- Note sheet: the quoted text, a text area, cancel and save.
-- is_new: the highlight was made for this note, so cancelling removes it
function ReaderHighlightBubble:showNoteSheet(index, is_new)
    local item = self.ui.annotation.annotations[index]
    local content_w = BottomSheet.getContentWidth()
    local border, pad, gap = Size.border.button, Screen:scaleBySize(12), Screen:scaleBySize(10)
    local sheet
    local input = InputText:new{
        text = item.note or "",
        hint = _("Write down your thoughts…"),
        face = Font:getFace("ui_body"),
        width = content_w - 2 * (border + pad),
        height = Screen:scaleBySize(118) - 2 * (border + pad),
        scroll = true,
        bordersize = 0,
        padding = 0,
        margin = 0,
    }
    local saved = false
    local function done(save)
        saved = save
        if save then
            self:setNote(index, input:getText())
        end
        local region = self:linesRegion(self:highlightRects(index))
        sheet:onClose()
        if region then
            UIManager:setDirty(self.dialog, "ui", region)
        end
    end
    local quote_args = { text = item.text, face = Font:getFace("ui_excerpt"), fgcolor = Palette.ink_2, width = content_w }
    local quote = TextBoxWidget:new(quote_args)
    if #quote.vertical_string_list > 2 then -- clamp to 2 lines
        quote_args.height = 2 * quote:getLineHeight()
        quote:free()
        quote_args.height_overflow_show_ellipsis = true
        quote = TextBoxWidget:new(quote_args)
    end
    local button_w = math.floor((content_w - gap) / 2)
    sheet = NoteSheet:new{
        title = item.note and C_("Note sheet", "Edit note") or C_("Highlight bubble", "Write note"),
        input = input,
        content = VerticalGroup:new{
            align = "left",
            quote,
            VerticalSpan:new{ width = pad },
            FrameContainer:new{
                bordersize = border,
                color = Palette.ink,
                radius = gap,
                padding = pad,
                input,
            },
            VerticalSpan:new{ width = Screen:scaleBySize(14) },
            HorizontalGroup:new{
                EinkControls.PillButton:new{ text = _("Cancel"), width = button_w, callback = function() done(false) end },
                HorizontalSpan:new{ width = gap },
                EinkControls.PillButton:new{ text = _("Save"), solid = true, width = button_w, callback = function() done(true) end },
            },
        },
        bottom_inset = input:getKeyboardDimen().h,
        on_close = function()
            if is_new and not saved then
                self:deleteHighlight(index)
            end
        end,
    }
    input.parent = sheet
    UIManager:show(sheet, "ui", sheet:getRefreshRegion())
    input:onShowKeyboard()
end

return ReaderHighlightBubble
