--[[--
Selection and highlight popovers of the e-ink redesign (see DESIGN.md, Selection
popover and Highlights).

Replaces ReaderHighlight (apps/replacements reader_highlight slot):
- a long-press selects a word, dragging extends it, and releasing shows the
  white selection popover: copy, highlight, write note, look up, search, each an
  icon over its label;
- tapping a highlight shows its styles (marker, line, wave) over write or edit
  note, copy, look up, delete;
- a note is written in a bottom sheet; highlights with a note get a small mark
  after their last character.

The style last picked is used for new highlights in every book.

Refreshes: the selection popover shows and closes with "fast" on its own rect
(it is black and white). The highlight popover shows a gray marker swatch and a
gray line between its rows, so it uses "ui" on its rect. Saving, restyling or
deleting a highlight refreshes its own lines with "ui"; nothing here refreshes
the whole screen.
]]

local BottomSheet = require("ui/widget/bottomsheet")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputText = require("ui/widget/inputtext")
local Notification = require("ui/widget/notification")
local Palette = require("ui/palette")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderView = require("apps/reader/modules/readerview")
local SelectionBubble = require("ui/widget/selectionbubble")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
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

-- marker, line, wave (doc/adr/0003-wavy-highlight-style.md)
local STYLES = { "lighten", "underscore", "wave" }

--- Style swatch on the popover: a serif 文 drawn in the style, ink on paper.
local StyleSwatch = Widget:extend{
    drawer = nil,
}

function StyleSwatch:init()
    self.glyph = TextWidget:new{ text = "文", face = Font:getFace("ui_excerpt"), fgcolor = Palette.ink }
    local g = self.glyph:getSize()
    self.pad = Screen:scaleBySize(3)
    self.glyph_h = g.h
    self.dimen = Geom:new{ w = g.w + 2 * self.pad, h = g.h + Screen:scaleBySize(6) }
end

function StyleSwatch:paintTo(bb, x, y)
    local w = self.dimen.w
    if self.drawer == "lighten" then
        bb:paintRect(x, y, w, self.glyph_h, Palette.mark)
    end
    self.glyph:paintTo(bb, x + self.pad, y)
    local line_y = y + self.glyph_h + Screen:scaleBySize(2)
    if self.drawer == "underscore" then
        bb:paintRect(x, line_y, w, Screen:scaleBySize(2), Palette.ink)
    elseif self.drawer == "wave" then
        ReaderView.paintWave(bb, x, line_y, w, Palette.ink)
    end
end

function StyleSwatch:onCloseWidget()
    self.glyph:free()
end

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

--- Registers the bubbles in their replacement slot.
-- Touch devices only, like the toolbar: the bubbles have no key navigation.
function ReaderHighlightBubble.register()
    if Device:isTouchDevice() then
        require("apps/replacements").reader_highlight = ReaderHighlightBubble
    end
end

function ReaderHighlightBubble:init()
    ReaderHighlight.init(self)
    self.view:registerViewModule("note_marks", NoteMarks:new{ highlight = self })
end

function ReaderHighlightBubble:onReadSettings(config)
    ReaderHighlight.onReadSettings(self, config)
    -- the style last picked in any book wins over the one saved with this book
    self.view.highlight.saved_drawer = G_reader_settings:readSetting("highlight_drawing_style") or self.view.highlight.saved_drawer
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

--- Clears the selection, repainting only its lines (upstream repaints the whole page).
-- With fast, uses "fast" where nothing gray is under it; otherwise "ui", as upstream save paths
-- (dictionary, highlight prompt, select mode) clear right after painting a gray marker.
function ReaderHighlightBubble:clear(clear_id, fast)
    if (clear_id and clear_id ~= self.clear_id) or not self.hold_pos or not self.ui.document then
        return ReaderHighlight.clear(self, clear_id)
    end
    -- selections spanning pages turn pages back: those need the whole page
    local region = not self.restore_page_mode_func and self:linesRegion(self:selectionRects())
    self.hold_pos = nil
    ReaderHighlight.clear(self, clear_id)
    self.selected_text = nil
    if region then
        UIManager:setDirty(self.dialog, fast and self:refreshTypeOver(region) or "ui", region)
    else
        UIManager:setDirty(self.dialog, "ui")
    end
    return true
end

function ReaderHighlightBubble:showBubble(bubble)
    self:closeBubble()
    bubble.close_refresh_type = bubble.refresh_type == "ui" and "ui" or self:refreshTypeOver(bubble:getRefreshRegion())
    self.highlight_dialog = bubble
    UIManager:show(bubble, bubble.refresh_type, bubble:getRefreshRegion())
end

function ReaderHighlightBubble:closeBubble()
    local bubble = self.highlight_dialog
    self.highlight_dialog = nil
    if not bubble then return end
    if not bubble.getRefreshRegion then -- upstream dialog
        return UIManager:close(bubble)
    end
    local region = bubble:getRefreshRegion()
    UIManager:close(bubble, bubble.close_refresh_type, region)
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
    -- a single word gets the bubble too, not the dictionary straight away
    self:_resetHoldTimer(true)
    self.is_word_selection = false
    self:onShowHighlightMenu()
    return true
end

--- Selection popover: copy, highlight, write note, look up, search.
function ReaderHighlightBubble:onShowHighlightMenu(index)
    if not self.selected_text then return end
    local rects = self:selectionRects()
    if #rects == 0 then -- e.g. multi-page selection in select mode
        return ReaderHighlight.onShowHighlightMenu(self, index)
    end
    local text = util.cleanupSelectedText(self.selected_text.text)
    local bubble = SelectionBubble:new{
        rows = { {
            { icon = "eink/copy", text = C_("Text", "Copy"), callback = function()
                Device.input.setClipboardText(text)
                self:dismiss()
                UIManager:show(Notification:new{ text = _("Selection copied to clipboard.") })
            end },
            { icon = "eink/highlight", text = C_("Highlight bubble", "Highlight"), callback = function()
                -- a selection across pages turns back to its first page when cleared: wait for the repaint
                local turns_back = self.restore_page_mode_func ~= nil
                local index = self:saveSelection()
                if not index then return end
                if turns_back then
                    UIManager:nextTick(function() self:showHighlightBubble(index) end)
                else
                    self:showHighlightBubble(index, rects)
                end
            end },
            { icon = "eink/thought", text = C_("Highlight bubble", "Write note"), callback = function()
                local index = self:saveSelection()
                if index then self:showNoteSheet(index, true) end
            end },
            { icon = "eink/search", text = C_("Highlight bubble", "Look up"), callback = function()
                self:closeBubble()
                -- the dictionary popup clears the selection
                if self.selected_text.text == "" and self.selected_text.sboxes then
                    self:lookupDictWord() -- scanned page: OCR
                else
                    self:lookupDict()
                end
            end },
            { icon = "eink/search-text", text = _("Search"), callback = function()
                self:dismiss()
                self.ui.search:searchCallback(nil, text) -- all results, paginated
            end },
        } },
        anchor_rects = rects,
        tap_close_callback = function() self:dismiss() end,
    }
    bubble.refresh_type = "fast" -- black and white
    self:showBubble(bubble)
end

--- Saves the selection as a highlight in the last picked style; returns its index.
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

--- Highlight popover: styles, then write or edit note, copy, look up, delete.
-- rects: screen rects of the highlight when it has not been painted yet
function ReaderHighlightBubble:showHighlightBubble(index, rects)
    local item = self.ui.annotation.annotations[index]
    rects = rects or self:highlightRects(index)
    if #rects == 0 then
        return ReaderHighlight.showHighlightNoteOrDialog(self, index)
    end
    local styles = {}
    for i, drawer in ipairs(STYLES) do
        styles[i] = {
            widget = StyleSwatch:new{ drawer = drawer },
            selected = item.drawer == drawer,
            callback = function()
                self:setHighlightStyle(index, drawer, rects)
                self:showHighlightBubble(index, rects)
            end,
        }
    end
    local bubble = SelectionBubble:new{
        rows = {
            styles,
            {
                { icon = "eink/thought",
                  text = item.note and C_("Highlight bubble", "Edit note") or C_("Highlight bubble", "Write note"),
                  callback = function()
                    self:closeBubble()
                    self:showNoteSheet(index)
                end },
                { icon = "eink/copy", text = C_("Text", "Copy"), callback = function()
                    Device.input.setClipboardText(item.text)
                    self:closeBubble()
                    UIManager:show(Notification:new{ text = _("Selection copied to clipboard.") })
                end },
                { icon = "eink/search", text = C_("Highlight bubble", "Look up"), callback = function()
                    self:closeBubble()
                    self.selected_text = util.tableDeepCopy(item)
                    self:lookupDict(index)
                end },
                { icon = "eink/highlight-off", text = _("Delete"), callback = function()
                    self:closeBubble()
                    self:deleteHighlight(index)
                end },
            },
        },
        anchor_rects = rects,
        tap_close_callback = function() self:closeBubble() end,
    }
    bubble.refresh_type = "ui" -- the marker swatch and the line between the rows are gray
    self:showBubble(bubble)
end

function ReaderHighlightBubble:setHighlightStyle(index, drawer, rects)
    local item = self.ui.annotation.annotations[index]
    -- as ReaderHighlight:editHighlightStyle()
    self:writePdfAnnotation("delete", item)
    item.drawer = drawer
    if self.ui.paging then
        self:writePdfAnnotation("save", item)
        if item.note then
            self:writePdfAnnotation("content", item, item.note)
        end
    end
    self.view.highlight.saved_drawer = drawer
    G_reader_settings:saveSetting("highlight_drawing_style", drawer)
    self.ui:handleEvent(Event:new("AnnotationsModified", { item }))
    UIManager:setDirty(self.dialog, "ui", self:linesRegion(rects or self:highlightRects(index)))
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
