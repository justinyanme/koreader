--[[--
Search page of the e-ink redesign (搜索页, see DESIGN.md, Other pages): the book's full-text search on a
full-screen page (ui/widget/fullscreenpage), after WeChat Read's 04-contents-and-search/04-search-input.png,
05-search-results.png and 08-search-no-results.png.

On top, the book title; then the search field with 取消 at its right, and a rule. The field holds the query
in bold, or a bold 搜索全书内容 when empty, and a round clear button once it holds text. Below the rule:
nothing while the first query is typed, the searching line, the hits grouped under their chapters, or
没有找到相关内容. A hit is an excerpt of at most two lines with the matched text paper on ink; a page that
goes on with a chapter repeats its heading. At the bottom, the back arrow, 书签 when the page is over the
contents page, and the page capsule.

The page searches nothing itself: its owner (apps/reader/modules/readerfulltextsearch) gets the query from
`on_submit(query)` (the keyboard's enter key), shows the searching line with setSearching() and the hits
with showResults() (or, when the search is cancelled, what was shown before), and gets the hit tapped from
`on_hit(index)`. A tap on the field brings the keyboard
back to change the query; a tap elsewhere puts it away. 取消 closes the page, back to the contents page
under it or to the book; the back arrow and the Back key close the contents page too; 书签 goes to the
contents page's bookmarks.

Showing and closing the page repaint it whole, and the searching line, the hits and turning a page repaint
the content and the bar (all "ui"); typing repaints the field ("ui"). The keyboard is KOReader's own.
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local FullscreenPage = require("ui/widget/fullscreenpage")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputText = require("ui/widget/inputtext")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TocPage = require("apps/reader/modules/readertocpage")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Tappable = require("apps/shelf/shelfwidgets").Tappable
local util = require("util")
local Screen = Device.screen
local _ = require("gettext")

local function dp(v) return Screen:scaleBySize(v) end

local GUTTER = dp(24)
local FIELD_H = dp(40) -- as on the contents page, whose field this page takes over
local FIELD_TARGET_H = dp(50)
local FIELD_PAD = dp(14) -- before the search icon
local FIELD_GAP = dp(6) -- from the field to 取消's target
local CLEAR_W = dp(44) -- the clear button's target, at the field's right end
local CLEAR_D = dp(18) -- its disc
local HEAD_H = dp(46) -- a chapter heading's row
local HIT_PAD = dp(15) -- above and below an excerpt
local LEAD_MAX = 1/3 -- of a line: the most the text before a hit takes
local SNIPPET_LINE = 0.45 -- TextBoxWidget's line_height: 1.45, the Body role's

local function text(str, face, color, max_width, bold)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width, bold = bold }
end

local function textWidth(str, face, bold)
    local widget = TextWidget:new{ text = str, face = Font:getFace(face), bold = bold }
    local w = widget:getSize().w
    widget:free()
    return w
end

local function rule(w)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = Size.border.default }, background = Palette.rule }
end

local function icon(name, size)
    return IconWidget:new{ icon = name, width = size, height = size, alpha = true }
end

-- The query: an InputText whose taps bring the keyboard back once the page stopped typing.
local SearchInput = InputText:extend{}

function SearchInput:onTapTextBox(arg, ges)
    if not self.parent.typing then
        self.parent:startTyping()
        return true
    end
    return InputText.onTapTextBox(self, arg, ges)
end

-- Holds the query field across the page's rebuilds, which free the old widgets (the field goes with the
-- page, on CloseWidget), and draws the placeholder after the cursor while the field is empty.
local FieldSlot = WidgetContainer:extend{
    placeholder = nil, -- TextWidget
}

function FieldSlot:getSize()
    return self[1]:getSize()
end

function FieldSlot:paintTo(bb, x, y)
    local input = self[1]
    input:paintTo(bb, x, y)
    if input:getText() == "" then
        local p = self.placeholder
        p:paintTo(bb, x + dp(3), y + math.floor((input:getSize().h - p:getSize().h) / 2))
    end
end

function FieldSlot:free() end

-- The clear button: a paper × on an ink disc, drawn only while the field holds text.
local ClearDisc = Widget:extend{
    input = nil,
    width = nil,
    height = nil,
}

function ClearDisc:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function ClearDisc:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    if self.input:getText() == "" then return end
    local cx, cy = x + math.floor((self.width - CLEAR_D) / 2), y + math.floor((self.height - CLEAR_D) / 2)
    bb:paintRoundedRect(cx, cy, CLEAR_D, CLEAR_D, Palette.ink, math.floor(CLEAR_D / 2))
    if not self.cross then
        -- flattened on paper, then inverted: a paper × on an ink square, which fits in the disc
        self.cross = IconWidget:new{ icon = "eink/close", width = math.floor(CLEAR_D * 0.6), height = math.floor(CLEAR_D * 0.6), invert = true }
    end
    local s = self.cross:getSize().w
    self.cross:paintTo(bb, cx + math.floor((CLEAR_D - s) / 2), cy + math.floor((CLEAR_D - s) / 2))
end

function ClearDisc:free()
    if self.cross then
        self.cross:free()
        self.cross = nil
    end
end

-- An excerpt around a hit, at most two lines, with the hit's characters paper on ink (in bold).
local HitSnippet = TextBoxWidget:extend{
    hit_start = nil, -- index of the hit's first character in the text (without the formatting marks)
    hit_end = nil,
}

function HitSnippet:_renderText(start_row_idx, end_row_idx)
    TextBoxWidget._renderText(self, start_row_idx, end_row_idx)
    -- the shown lines are shaped by now
    local first, last = math.max(1, start_row_idx), math.min(end_row_idx, #self.vertical_string_list)
    if first > last then return end
    local rects
    if self.use_xtext then
        rects = self:getXtextHighlightRects(self.hit_start, self.hit_end, first, last)
    else
        rects = self:getNonXtextHighlightRects(self.hit_start, self.hit_end, first, last)
    end
    for _, r in ipairs(rects) do
        self._bb:invertRect(r.x, r.y, r.w, r.h)
    end
end

-- Whether two pieces of the text read apart: crengine drops the spaces between words, and only Latin words
-- want one back (CJK text runs on).
local function apart(before, after)
    if before == "" or after == "" or before:find("%s$") or after:find("^%s") then return false end
    return before:byte(-1) < 0x80 and after:byte(1) < 0x80
end

local SearchPage = FullscreenPage:extend{
    ui = nil,
    contents = nil, -- the contents page under this one, when opened from it
    query = "", -- the field's text to start with
    results = nil, -- the hits shown (none: nothing found); nil before the first search
    on_submit = nil, -- function(query)
    on_hit = nil, -- function(index), of the hit tapped in `results`
    on_close = nil, -- function, called once the page is closed
    is_always_active = true, -- the field and the buttons still take taps under the keyboard
    typing = false, -- the keyboard is up
    searching = false, -- the owner searches
}

function SearchPage:init()
    self.title = self.ui.doc_props.display_title
    FullscreenPage.init(self)
    self.content_w = self.dimen.w - 2 * GUTTER
    -- the content: the search row's target, 15dp, a rule, then the rows (as on the contents page)
    local head_h = FIELD_TARGET_H + dp(15)
    self.list_rect = Geom:new{ x = 0, y = self.content_rect.y + head_h, w = self.dimen.w, h = self.content_rect.h - head_h }
    local snippet_face = Font:getFace("ui_body")
    self.snippet_line_h = math.floor((1 + SNIPPET_LINE) * snippet_face.size + 0.5) -- as TextBoxWidget does
    self.hit_h = 2 * HIT_PAD + 2 * self.snippet_line_h + Size.border.default
    self:initField()
    if self.results then
        self:paginate()
    end
    self:build()
end

function SearchPage:initField()
    local bw = Size.border.default
    self.cancel_w = textWidth(_("Cancel"), "ui_label_large", true) + 2 * dp(8)
    self.field_w = self.content_w - self.cancel_w - FIELD_GAP
    -- a real bold face: TextBoxWidget then emboldens the CJK fallback too
    local face = Font:getAdjustedFace(Font:getFace("ui_body"), true)
    self.placeholder = text(_("Search the whole book"), "ui_body", nil, nil, true)
    self.input = SearchInput:new{
        text = self.query,
        face = face,
        width = self.field_w - 2 * bw - FIELD_PAD - dp(24) - dp(8) - CLEAR_W,
        height = math.floor(1.3 * face.size + 0.5), -- one line (TextBoxWidget's default line height)
        padding = 0, margin = 0, bordersize = 0,
        focused = false,
        parent = self,
        enter_callback = function() self:submit() end,
        edit_callback = function() self:onQueryEdited() end,
    }
    self.query_empty = self.query == ""
end

function SearchPage:buildTitle()
    local rect = self.title_rect
    local w = rect.w - 2 * GUTTER
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = GUTTER },
        LeftContainer:new{
            dimen = Geom:new{ w = w, h = rect.h },
            text(self.title, "ui_title_large", nil, w - dp(8), true),
        },
    }
end

function SearchPage:buildSearchRow()
    local bw = Size.border.default
    self.clear_button = Tappable:new{
        callback = function() self:clearQuery() end,
        ClearDisc:new{ input = self.input, width = CLEAR_W, height = FIELD_H - 2 * bw },
    }
    local field = FrameContainer:new{
        radius = math.floor(FIELD_H / 2), bordersize = bw, color = Palette.ink, background = Palette.paper,
        padding = 0, padding_left = FIELD_PAD,
        LeftContainer:new{
            dimen = Geom:new{ w = self.field_w - FIELD_PAD - 2 * bw, h = FIELD_H - 2 * bw },
            HorizontalGroup:new{
                align = "center",
                icon("eink/search", dp(24)),
                HorizontalSpan:new{ width = dp(8) },
                FieldSlot:new{ placeholder = self.placeholder, self.input },
                self.clear_button,
            },
        },
    }
    self.search_field = Tappable:new{
        callback = function() self:startTyping() end,
        CenterContainer:new{ dimen = Geom:new{ w = self.field_w, h = FIELD_TARGET_H }, field },
    }
    self.cancel_button = Tappable:new{
        callback = function() self:close("ui") end,
        CenterContainer:new{
            dimen = Geom:new{ w = self.cancel_w, h = FIELD_TARGET_H },
            text(_("Cancel"), "ui_label_large", nil, nil, true),
        },
    }
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = GUTTER },
        self.search_field,
        HorizontalSpan:new{ width = FIELD_GAP },
        self.cancel_button,
    }
end

--- Rows of the hits: each chapter's heading (none for hits before the first entry), then its hits.
function SearchPage:paginate()
    local toc = self.ui.toc
    local document = self.ui.document
    -- The chapter of a hit is the one of its page, looked up once per page (there may be thousands of hits),
    -- except on a page where a chapter starts: there it depends on where the hit is.
    toc:fillToc()
    local starts, by_page = {}, {}
    for _, entry in ipairs(toc.toc) do
        starts[entry.page] = true
    end
    local function chapterOf(item)
        local page = self.ui.rolling and document:getPageFromXPointer(item.start) or item.start
        if starts[page] and self.ui.rolling then
            return toc:getTocIndexByPage(item.start)
        end
        if by_page[page] == nil then
            by_page[page] = toc:getTocIndexByPage(page) or false
        end
        return by_page[page] or nil
    end
    local rows, chapter = {}, false
    for i, item in ipairs(self.results) do
        local index = chapterOf(item)
        if index ~= chapter then
            chapter = index
            if index then
                table.insert(rows, { title = toc:cleanUpTocTitle(toc.toc[index].title, true), h = HEAD_H })
            end
        end
        table.insert(rows, { index = i, h = self.hit_h })
    end
    -- a heading never ends a page, and a page that goes on with a chapter starts with its heading again
    local max_h = self.list_rect.h - Size.border.default
    local pages, page, used, heading = {}, {}, 0, nil
    for _, row in ipairs(rows) do
        if not row.index then
            heading = row
        end
        if #page > 0 and used + row.h + (row.index and 0 or self.hit_h) > max_h then
            table.insert(pages, page)
            page, used = {}, 0
            if row.index and heading then
                table.insert(page, heading)
                used = heading.h
            end
        end
        table.insert(page, row)
        used = used + row.h
    end
    if #page > 0 then
        table.insert(pages, page)
    end
    self.pages = pages
end

function SearchPage:buildHeading(row)
    return LeftContainer:new{
        dimen = Geom:new{ w = self.dimen.w, h = HEAD_H },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = GUTTER },
            text(row.title, "ui_title", nil, self.content_w),
        },
    }
end

--- The excerpt of hit `item`: a little of the text before it (cut at the start), the hit, and the text after.
function SearchPage:buildSnippet(item)
    local face = Font:getFace("ui_body")
    local function clean(str) return str and str:gsub("%s+", " ") or "" end
    local hit = clean(item.matched_text)
    local before = clean(item.prev_text) .. clean(item.matched_word_prefix)
    local after = clean(item.matched_word_suffix) .. clean(item.next_text)
    if apart(before, hit) then
        before = before .. " "
    end
    if apart(hit, after) and not after:find("^%p") then
        after = " " .. after
    end
    local max = math.floor(self.content_w * LEAD_MAX)
    local chars = util.splitToChars(before)
    local first = 1
    while first <= #chars and RenderText:sizeUtf8Text(0, Screen:getWidth(), face, "…" .. table.concat(chars, "", first), true).x > max do
        first = first + 1
    end
    if first > 1 then
        before = "…" .. table.concat(chars, "", first)
    end
    local hit_start = #util.splitToChars(before) + 1
    local function snippet(height)
        return HitSnippet:new{
            text = TextBoxWidget.PTF_HEADER .. before .. TextBoxWidget.PTF_BOLD_START .. hit .. TextBoxWidget.PTF_BOLD_END .. after,
            hit_start = hit_start,
            hit_end = hit_start + #util.splitToChars(hit) - 1,
            face = face, width = self.content_w, line_height = SNIPPET_LINE,
            height = height, height_overflow_show_ellipsis = height ~= nil,
            fgcolor = Palette.ink, bgcolor = Palette.paper,
        }
    end
    local widget = snippet()
    if #widget.vertical_string_list > 2 then
        widget:free()
        widget = snippet(2 * self.snippet_line_h)
    end
    return widget
end

--- A hit's row, its excerpt in the middle, over a rule-gray divider; a tap opens the hit.
function SearchPage:buildHit(row)
    local snippet = self:buildSnippet(self.results[row.index])
    local hit = Tappable:new{
        callback = function() self:openHit(row.index) end,
        VerticalGroup:new{
            align = "left",
            LeftContainer:new{
                dimen = Geom:new{ w = self.dimen.w, h = row.h - Size.border.default },
                HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, snippet },
            },
            HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, rule(self.content_w) },
        },
    }
    hit.hit_index, hit.snippet = row.index, snippet
    return hit
end

--- The search row, a rule, and below it the searching line, 没有找到相关内容, or the rows of the shown page;
-- `self.shown_rows` gets the rows (headings and hits).
function SearchPage:buildContent(rect)
    local list = VerticalGroup:new{
        align = "left",
        self:buildSearchRow(),
        VerticalSpan:new{ width = self.list_rect.y - rect.y - FIELD_TARGET_H },
        HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, rule(self.content_w) },
    }
    self.shown_rows = {}
    self.message = nil
    if self.searching then
        -- the reason line alone (DESIGN.md, Loading, empty and error states)
        self.message = text(_("Searching… (tap to cancel)"), "ui_label", nil, self.content_w)
    elseif self.results and #self.results == 0 then
        self.message = text(_("No matching content found"), "ui_title", nil, self.content_w)
    end
    if self.message then
        -- in the middle of the page above the bar, as in the reference
        local bottom = self.content_rect.y + self.content_rect.h
        table.insert(list, CenterContainer:new{
            dimen = Geom:new{ w = rect.w, h = math.max(self.message:getSize().h, bottom - 2 * self.list_rect.y) },
            self.message,
        })
        return list, 1
    end
    if not self.results then
        return list, 1
    end
    self.page = math.max(1, math.min(self.page, #self.pages))
    for _, row in ipairs(self.pages[self.page] or {}) do
        local widget = row.index and self:buildHit(row) or self:buildHeading(row)
        table.insert(list, widget)
        table.insert(self.shown_rows, widget)
    end
    return list, math.max(1, #self.pages)
end

function SearchPage:buildBarParts()
    if not self.contents then return end
    self.bookmarks_button = TocPage.bookmarksButton(function() self:openBookmarks() end)
    return nil, { self.bookmarks_button }
end

--- Rebuilds the page and repaints its content and bar.
function SearchPage:refreshList()
    self:build()
    UIManager:setDirty(self, "ui", self.body_rect)
end

function SearchPage:refreshField()
    if self.search_field.dimen then
        UIManager:setDirty(self, "ui", self.search_field.dimen)
    end
end

--- Shows the keyboard (unless a physical one is used instead, as InputText decides), with the cursor in the field.
function SearchPage:startTyping()
    if self.typing or self.closed then return end
    self.typing = true
    self.input:focus()
    if not ((Device:hasKeyboard() or Device:hasScreenKB()) and G_reader_settings:nilOrFalse("virtual_keyboard_enabled")) then
        self.input:onShowKeyboard()
    end
    self:refreshField()
end

--- Puts the keyboard away.
function SearchPage:stopTyping()
    if not self.typing then return end
    self.typing = false
    self.input:onCloseKeyboard()
    self.input:unfocus()
    self:refreshField()
end

--- The clear button repaints as the field fills or empties.
function SearchPage:onQueryEdited()
    if not self.input then return end -- the field's first text, from its init
    local empty = self.input:getText() == ""
    if empty ~= self.query_empty then
        self.query_empty = empty
        if self.clear_button and self.clear_button.dimen then
            UIManager:setDirty(self, "ui", self.clear_button.dimen)
        end
    end
end

function SearchPage:clearQuery()
    if self.input:getText() ~= "" then
        self.input:setText("")
    end
    self:startTyping()
end

--- The enter key: hands the query over, if there is one.
function SearchPage:submit()
    if self.closed then return end
    local query = util.trim(self.input:getText())
    if query == "" then return end
    self:stopTyping()
    self.on_submit(query)
end

--- While the owner searches.
function SearchPage:setSearching()
    self.shown_before = { results = self.results, page = self.page }
    self.searching = true
    self.results = nil
    self:refreshList()
end

--- Shows `results` on their page `page`, or 没有找到相关内容 when empty; nil (a search cancelled) shows again what
-- was shown before it.
function SearchPage:showResults(results, page)
    self.searching = false
    if results == nil then
        results, page = self.shown_before.results, self.shown_before.page
    end
    self.results = results
    self.page = page or 1
    if results then
        self:paginate()
    end
    self:refreshList()
end

function SearchPage:openHit(index)
    if self.closed then return end
    self.on_hit(index)
end

--- Closes the page (once), with a repaint of the screen when `refresh` is given.
function SearchPage:close(refresh)
    if self.closed then return end
    self.closed = true
    self:stopTyping()
    UIManager:close(self, refresh, refresh and self.dimen)
end

--- Closes the contents page under this one (without a repaint of its own), then this page.
function SearchPage:leave(refresh)
    if self.closed then return end
    if self.contents and UIManager:isWidgetShown(self.contents) then
        UIManager:close(self.contents)
    end
    self:close(refresh)
end

--- The back arrow and the Back key: back to the book.
function SearchPage:goBack()
    self:leave("ui")
end

function SearchPage:openBookmarks()
    if self.closed then return end
    self:close()
    self.contents:openBookmarks()
end

--- A tap outside the field puts the keyboard away.
function SearchPage:onTapBlock(_, ges)
    if self.typing then
        local keyboard = self.input.keyboard
        if not (keyboard and keyboard.dimen and ges and ges.pos:intersectWith(keyboard.dimen)) then
            self:stopTyping()
        end
    end
    return true
end

-- The keyboard's own Back key closed it.
function SearchPage:onKeyboardClosed()
    self:stopTyping()
end

-- A physical keyboard's Back key in the field.
function SearchPage:onCloseDialog()
    self:goBack()
    return true
end

-- InputText asks it on devices with a D-pad; nothing here takes focus.
function SearchPage:getFocusableWidgetXY() end

function SearchPage:onCloseWidget()
    self.placeholder:free()
    if self.on_close then self.on_close() end
end

return SearchPage
