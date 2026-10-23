--[[--
Selection and highlight popovers of the e-ink redesign (see DESIGN.md, Selection
popover and Highlights).

Replaces ReaderHighlight (apps/replacements reader_highlight slot):
- a long-press selects a word, dragging extends it, and releasing shows the
  white selection popover: highlight, look up (查询, for CJK text) or translate
  (翻译, for other text, such as English), write note, copy, each an icon over
  its label;
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
(the toast is solid, so it always shows with "fast").
Saving, restyling or deleting a highlight refreshes its own lines with "ui";
nothing here refreshes the whole screen.
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
    if not bubble.getRefreshRegion then -- upstream dialog
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
        return ReaderHighlight.onShowHighlightMenu(self, index)
    end
    local text = util.cleanupSelectedText(self.selected_text.text)
    local bubble = SelectionBubble:new{
        rows = { {
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
        anchor_rects = rects,
        tap_close_callback = function() self:dismiss() end,
    }
    self:showBubble(bubble)
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
