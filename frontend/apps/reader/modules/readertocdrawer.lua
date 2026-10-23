--[[--
The old contents drawer, now only its bookmarks and notes (the contents moved to the full-screen
contents page, apps/reader/modules/readertocpage), kept as the way to them until the notes page
replaces it.

Opened by "ShowNotes" (ReaderToolbar:onShowNotes): the toolbar's 笔记 on the notes tab, the contents
page's 书签 on the bookmarks tab. A left panel with the book's cover, title, author and progress over
two tabs, bookmarks and notes. Lists are paginated, never scrolled, and a group header never ends a
page. Each tab is measured and paginated once per drawer (without rendering), and only the rows of the
shown page are built.

Opening, closing and switching tabs refresh the panel ("ui"), turning a list page only
refreshes the list ("ui"). Jumps close the drawer without a refresh of its own and let
the reader repaint the page ("partial"); the position left is pushed onto the location
stack, for "Return to last position".
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local RenderImage = require("ui/renderimage")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local util = require("util")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext

local dp = function(v) return Screen:scaleBySize(v) end

local function text(str, face, color, max_width, bold)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width, bold = bold }
end

-- Line height of a TextBoxWidget in `face` (see TextBoxWidget:init).
local function lineHeight(face, line_height)
    return math.floor((1 + (line_height or 0.3)) * Font:getFace(face).size + 0.5)
end

local function textSize(str, face, bold)
    local widget = TextWidget:new{ text = str, face = Font:getFace(face), bold = bold }
    local size = widget:getSize()
    widget:free()
    return size
end

-- Lines `str` needs at `width`, at most max_lines, estimated from its unwrapped width (nothing is rendered).
local function lineCount(str, face, width, max_lines, bold)
    return math.max(1, math.min(max_lines, math.ceil(textSize(str, face, bold).w / width)))
end

-- Wrapped text; with `lines`, exactly that tall, with an ellipsis when it needs more.
local function textBox(str, face, width, lines, opts)
    local args = { text = str, face = Font:getFace(face), width = width, fgcolor = Palette.ink, bgcolor = Palette.paper }
    for k, v in pairs(opts or {}) do args[k] = v end
    if lines then
        args.height = lines * lineHeight(face, args.line_height)
        args.height_overflow_show_ellipsis = true
    end
    return TextBoxWidget:new(args)
end

local function rule(w, color)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = dp(1) }, background = color }
end

-- First characters of a string, whitespace collapsed.
local function snippet(str, max_chars)
    str = util.trim(((str or ""):gsub("%s+", " ")))
    local chars = util.splitToChars(str)
    if #chars > max_chars then
        return table.concat(chars, "", 1, max_chars) .. "…"
    end
    return str
end

--- Highlight style swatch (18 × 10dp), drawn only from an annotation's drawer string, so styles
-- added later (wave) show without their drawing code: lighten (marker), underscore (line),
-- strikeout, invert and wave; anything else is drawn as the marker.
local Swatch = Widget:extend{
    drawer = nil,
}

function Swatch:init()
    self.dimen = Geom:new{ w = dp(18), h = dp(10) }
end

function Swatch:paintTo(bb, x, y)
    local w, h = self.dimen.w, self.dimen.h
    local line = dp(2)
    if self.drawer == "underscore" then
        bb:paintRect(x, y + h - line, w, line, Palette.ink)
    elseif self.drawer == "strikeout" then
        bb:paintRect(x, y + math.floor((h - line) / 2), w, line, Palette.ink)
    elseif self.drawer == "invert" then
        bb:paintRect(x, y, w, h, Palette.ink)
    elseif self.drawer == "wave" then
        local amp, period, thick = dp(1.5), dp(6), math.max(1, dp(1.3))
        local base = y + h - thick - amp
        for i = 0, w - 1 do
            local dy = math.floor(amp * math.sin(2 * math.pi * i / period) + 0.5)
            bb:paintRect(x + i, base - dy, 1, thick, Palette.ink)
        end
    else
        bb:paintRect(x, y, w, h, Palette.mark)
    end
end

-- A list item: content over a divider; tappable when it has a callback.
local ListRow = InputContainer:extend{
    callback = nil,
    is_header = false,
}

function ListRow:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ w = size.w, h = size.h }
    if self.callback then
        self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
end

function ListRow:onTapSelect()
    self.callback()
    return true
end

-- Drawer tab: ink and bold with a 3dp underline across the middle 40% when selected.
local TabCell = InputContainer:extend{
    text = nil,
    selected = false,
    width = nil,
    height = nil,
    callback = nil,
}

function TabCell:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = CenterContainer:new{
        dimen = self.dimen:copy(),
        text(self.text, "ui_label_large", self.selected and Palette.ink or Palette.ink_2, self.width, self.selected),
    }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function TabCell:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    if self.selected then
        local w = math.floor(self.width * 0.4)
        -- overlaps the tab bar's 1dp rule by one dp, like the prototype
        bb:paintRect(x + math.floor((self.width - w) / 2), y + self.height - dp(2), w, dp(3), Palette.ink)
    end
end

function TabCell:onTapSelect()
    self.callback()
    return true
end

local TocDrawer = InputContainer:extend{
    ui = nil,
    tab = "bookmarks", -- "bookmarks" or "notes"
    on_close = nil, -- function, called once the drawer is closed
}

local thumbnails = setmetatable({}, { __mode = "k" }) -- document => cover thumbnail, or false

--[[--
Splits measured rows into pages that fit `max_h`.
@tparam table items array of { h = height, is_header = bool }
@treturn table array of pages, each an array of item indexes
A group header that would end a page moves to the next one; a row taller than a page gets one of its own.
]]
function TocDrawer.paginate(items, max_h)
    local pages, page, used = {}, {}, 0
    for i, item in ipairs(items) do
        if #page > 0 and used + item.h > max_h then
            local last = page[#page]
            if items[last].is_header and #page > 1 then
                table.remove(page)
                table.insert(pages, page)
                page, used = { last }, items[last].h
            else
                table.insert(pages, page)
                page, used = {}, 0
            end
        end
        table.insert(page, i)
        used = used + item.h
    end
    if #page > 0 then
        table.insert(pages, page)
    end
    return pages
end

function TocDrawer:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.panel_rect = Geom:new{ x = 0, y = 0, w = math.min(math.floor(sw * 0.86), dp(560)), h = sh }
    self.content_w = self.panel_rect.w - dp(1) - 2 * dp(24)
    self.ges_events.TapScrim = { GestureRange:new{ ges = "tap", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.bookmarks, self.notes = {}, {}
    for _, item in ipairs(self.ui.annotation.annotations) do
        table.insert(item.drawer and self.notes or self.bookmarks, item)
    end
    self.cache = {} -- tab => { items = measured rows, pages = paginate(items), page = shown page }
    self:build()
end

function TocDrawer:build()
    local w = self.content_w
    local header = self:buildHeader()
    local tabs = self:buildTabs()
    local export = self.tab == "notes" and #self.notes > 0 and self.ui.exporter and self:buildExportRow()
    local pager_h = dp(44)
    local top_h = header:getSize().h + tabs:getSize().h
    local list_h = self.panel_rect.h - top_h - pager_h - (export and export:getSize().h or 0)
    self.list_rect = Geom:new{ x = 0, y = top_h, w = self.panel_rect.w, h = self.panel_rect.h - top_h }

    local tab = self:getTab(list_h)
    self.shown_rows = {}
    local list = VerticalGroup:new{ align = "left" }
    local used = 0
    for _, i in ipairs(tab.pages[tab.page] or {}) do
        local item = tab.items[i]
        local row = self:buildRow(item)
        table.insert(list, row)
        table.insert(self.shown_rows, row)
        used = used + item.h
    end
    table.insert(list, VerticalSpan:new{ width = math.max(0, list_h - used) })

    local column = VerticalGroup:new{ align = "left", header, tabs, list }
    if export then
        table.insert(column, export)
    end
    table.insert(column, EinkControls.Pager:new{
        width = w, page = tab.page, pages = #tab.pages,
        on_change = function(p) self:goToListPage(p) end,
    })
    if self.panel then
        self.panel:free()
    end
    self.panel = FrameContainer:new{
        bordersize = 0, padding = 0, background = Palette.paper,
        HorizontalGroup:new{
            align = "top",
            HorizontalSpan:new{ width = dp(24) },
            column,
            HorizontalSpan:new{ width = dp(24) },
            LineWidget:new{ dimen = Geom:new{ w = dp(1), h = self.panel_rect.h }, background = Palette.ink },
        },
    }
end

--- The current tab's measured rows and pages, computed once per drawer.
function TocDrawer:getTab(list_h)
    local tab = self.cache[self.tab]
    if not tab then
        local items = self.tab == "notes" and self:noteItems() or self:bookmarkItems()
        tab = { items = items, pages = self.paginate(items, list_h), page = 1 }
        self.cache[self.tab] = tab
    end
    return tab
end

function TocDrawer:getCover(w, h)
    local doc = self.ui.document
    if thumbnails[doc] == nil then
        local bb = self.ui.bookinfo and self.ui.bookinfo:getCoverImage(doc)
        if bb then
            local scale = math.min(w / bb:getWidth(), h / bb:getHeight())
            bb = RenderImage:scaleBlitBuffer(bb, math.floor(bb:getWidth() * scale), math.floor(bb:getHeight() * scale), true)
        end
        thumbnails[doc] = bb or false
    end
    if thumbnails[doc] then
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            ImageWidget:new{ image = thumbnails[doc], image_disposable = false },
        }
    end
    -- ponytail: plain stock card until #9's typographic covers can be shared
    return FrameContainer:new{
        bordersize = dp(1), color = Palette.rule, background = Palette.cover_stock, padding = 0,
        CenterContainer:new{ dimen = Geom:new{ w = w - 2 * dp(1), h = h - 2 * dp(1) }, VerticalSpan:new{ width = 0 } },
    }
end

function TocDrawer:buildHeader()
    local cover_w, cover_h = dp(52), dp(69)
    local text_w = self.content_w - cover_w - dp(14)
    local props = self.ui.doc_props
    local page, page_count = self.ui:getCurrentPage(), self.ui.document:getPageCount()
    local percent = math.floor(page / page_count * 100)
    local chapters = #(self.ui.toc:getTocTicks(1) or {})
    local info = VerticalGroup:new{
        align = "left",
        text(props.display_title, "ui_title_large", Palette.ink, text_w),
    }
    if props.authors and props.authors ~= "" then
        table.insert(info, text((props.authors:gsub("\n", ", ")), "ui_label", Palette.ink_2, text_w))
    end
    table.insert(info, VerticalSpan:new{ width = dp(4) })
    table.insert(info, text(chapters > 0 and T(_("Read %1% · %2 chapters"), percent, chapters) or T(C_("Contents drawer", "Read %1%"), percent),
                            "ui_caption", Palette.ink_2, text_w))
    return VerticalGroup:new{
        VerticalSpan:new{ width = dp(22) },
        HorizontalGroup:new{
            align = "center",
            self:getCover(cover_w, cover_h),
            HorizontalSpan:new{ width = dp(14) },
            info,
        },
        VerticalSpan:new{ width = dp(16) },
    }
end

function TocDrawer:buildTabs()
    local cell_w = math.floor(self.content_w / 2)
    local function cell(tab, label)
        return TabCell:new{
            text = label, selected = tab == self.tab, width = cell_w, height = dp(44) - dp(1),
            callback = function() self:switchTab(tab) end,
        }
    end
    local nb, nn = #self.bookmarks, #self.notes
    return VerticalGroup:new{
        HorizontalGroup:new{
            cell("bookmarks", nb > 0 and T(_("Bookmarks %1"), nb) or _("Bookmarks")),
            cell("notes", nn > 0 and T(C_("Contents drawer", "Notes %1"), nn) or C_("Contents drawer", "Notes")),
        },
        rule(self.content_w, Palette.ink),
    }
end

function TocDrawer:buildExportRow()
    local w, h = self.content_w, dp(48)
    local icon = dp(18)
    return ListRow:new{
        callback = function() self:export() end,
        VerticalGroup:new{
            rule(w, Palette.rule),
            LeftContainer:new{
                dimen = Geom:new{ w = w, h = h - dp(1) },
                HorizontalGroup:new{
                    IconWidget:new{ icon = "eink/export", width = icon, height = icon, alpha = true },
                    HorizontalSpan:new{ width = dp(8) },
                    text(_("Export notes"), "ui_label_large", Palette.ink, w - 2 * icon - dp(8)),
                },
            },
        },
    }
end

-- A list row `h` tall: content (vertically centered) over a rule-gray divider.
local function row(w, h, content, callback)
    return ListRow:new{
        callback = callback,
        VerticalGroup:new{
            LeftContainer:new{ dimen = Geom:new{ w = w, h = h - dp(1) }, content },
            rule(w, Palette.rule),
        },
    }
end

function TocDrawer:pageString(pn_or_xp)
    return self.ui.bookmark:getBookmarkPageString(pn_or_xp)
end

--- Text at the top of a bookmarked page, or nil.
function TocDrawer:pageStartText(item)
    local doc = self.ui.document
    if self.ui.rolling then
        local page = doc:getPageFromXPointer(item.page)
        local next_xp = page < doc:getPageCount() and doc:getPageXPointer(page + 1)
        return next_xp and doc:getTextFromXPointers(item.page, next_xp) or doc:getTextFromXPointer(item.page)
    end
    -- the text layer only: no reflow segmentation of scanned pages
    local boxes = doc.getPageTextBoxes and doc:getPageTextBoxes(item.page)
    if not boxes then return end
    local words = {}
    for _, line in ipairs(boxes) do
        for _, word in ipairs(line) do
            table.insert(words, word.word)
        end
        if #words > 60 then break end
    end
    return table.concat(words, " ")
end

local function date(item)
    return (item.datetime or ""):sub(1, 10)
end

--[[--
Measured rows of each tab: plain tables with the row's height `h` (and `is_header`), and what
buildRow() needs to build it. Heights come from text widths, so measuring renders nothing.
]]
function TocDrawer:bookmarkItems()
    if #self.bookmarks == 0 then
        return { { kind = "empty", h = 0, title = _("No bookmarks yet"),
                   hint = _("Show the toolbar and tap the bookmark icon at the top right.") } }
    end
    local w = self.content_w
    local line_h, caption_h = lineHeight("ui_excerpt", 0.6), textSize("0", "ui_caption").h
    local items = {}
    for __, item in ipairs(self.bookmarks) do
        local excerpt = snippet(self:pageStartText(item), 120)
        if excerpt == "" then
            excerpt = item.chapter or self.ui.doc_props.display_title
        end
        local page = self:pageString(item.page)
        local lines = lineCount(excerpt, "ui_excerpt", w, 3)
        table.insert(items, {
            kind = "bookmark", item = item, excerpt = excerpt, lines = lines,
            meta = item.chapter and T(_("%1 · Page %2 · %3"), item.chapter, page, date(item))
                                 or T(_("Page %1 · %2"), page, date(item)),
            h = lines * line_h + dp(4) + caption_h + 2 * dp(12) + dp(1),
        })
    end
    return items
end

--[[--
Measured rows shared with other note lists (the 我的 tab's all-notes page): a group header,
a highlight with its note and date, and an empty state. Build them with TocDrawer.groupHeader,
TocDrawer.buildNoteRow and TocDrawer.emptyState, `w` wide. `metrics` (TocDrawer.noteMetrics())
holds the sizes every row shares: measure it once per list.
]]
function TocDrawer.noteMetrics()
    return {
        excerpt_h = lineHeight("ui_excerpt", 0.6),
        label_h = lineHeight("ui_label_large"),
        caption_h = textSize("0", "ui_caption").h,
        thought_w = textSize(_("Thought"), "ui_label_large", true).w + dp(4),
    }
end

function TocDrawer.headerItem(title, metrics)
    return { kind = "header", is_header = true, title = title, h = dp(18) + metrics.caption_h + dp(6) + dp(1) }
end

function TocDrawer.emptyItem(title, hint)
    return { kind = "empty", h = 0, title = title, hint = hint }
end

--- Measured row of an annotation with a drawer (a highlight), `w` wide.
function TocDrawer.noteItem(w, item, metrics)
    local excerpt = snippet(item.text, 400)
    local lines = lineCount(excerpt, "ui_excerpt", w - dp(24), 3)
    local note = item.note and item.note ~= "" and snippet(item.note, 200)
    local note_lines = note and lineCount(note, "ui_label_large", w - metrics.thought_w, 2) or 0
    return {
        kind = "note", item = item, excerpt = excerpt, lines = lines, note = note, note_lines = note_lines,
        h = lines * metrics.excerpt_h + (note and dp(6) + note_lines * metrics.label_h or 0)
            + dp(4) + metrics.caption_h + 2 * dp(12) + dp(1),
    }
end

function TocDrawer:noteItems()
    if #self.notes == 0 then
        return { self.emptyItem(_("No notes yet"), _("Long-press text, then tap Highlight or Add note.")) }
    end
    local metrics = self.noteMetrics()
    local items, chapter = {}, nil
    for __, item in ipairs(self.notes) do
        local item_chapter = item.chapter or self.ui.doc_props.display_title
        if item_chapter ~= chapter then
            chapter = item_chapter
            table.insert(items, self.headerItem(chapter, metrics))
        end
        table.insert(items, self.noteItem(self.content_w, item, metrics))
    end
    return items
end

function TocDrawer.emptyState(w, it)
    local group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = dp(40) },
        text(it.title, "ui_body", Palette.ink, w, true),
    }
    if it.hint then
        table.insert(group, VerticalSpan:new{ width = dp(4) })
        table.insert(group, textBox(it.hint, "ui_label_large", w - dp(16), nil, { alignment = "center", fgcolor = Palette.ink_2 }))
    end
    return ListRow:new{ CenterContainer:new{ dimen = Geom:new{ w = w, h = group:getSize().h }, group } }
end

function TocDrawer.groupHeader(w, it)
    return ListRow:new{
        is_header = true,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = dp(18) },
            text(it.title, "ui_caption", Palette.ink_2, w),
            VerticalSpan:new{ width = dp(6) },
            rule(w, Palette.ink),
        },
    }
end

--- A note row (style swatch, excerpt, note, date) from TocDrawer.noteItem; `callback` on tap.
function TocDrawer.buildNoteRow(w, it, callback)
    local swatch_w = dp(24)
    local content = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            align = "top",
            LeftContainer:new{
                dimen = Geom:new{ w = swatch_w, h = lineHeight("ui_excerpt", 0.6) },
                Swatch:new{ drawer = it.item.drawer },
            },
            textBox(it.excerpt, "ui_excerpt", w - swatch_w, it.lines, { line_height = 0.6 }),
        },
    }
    if it.note then
        local label = text(_("Thought"), "ui_label_large", Palette.ink, nil, true)
        local gap = dp(4)
        table.insert(content, VerticalSpan:new{ width = dp(6) })
        table.insert(content, HorizontalGroup:new{
            align = "top",
            label,
            HorizontalSpan:new{ width = gap },
            textBox(it.note, "ui_label_large", w - label:getSize().w - gap, it.note_lines),
        })
    end
    table.insert(content, VerticalSpan:new{ width = dp(4) })
    table.insert(content, text(date(it.item), "ui_caption", Palette.ink_2, w))
    local r = row(w, it.h, content, callback)
    r.note = it.item
    return r
end

function TocDrawer:buildRow(it)
    local w = self.content_w
    if it.kind == "empty" then
        return self.emptyState(w, it)
    elseif it.kind == "header" then
        return self.groupHeader(w, it)
    elseif it.kind == "bookmark" then
        return row(w, it.h, VerticalGroup:new{
            align = "left",
            textBox(it.excerpt, "ui_excerpt", w, it.lines, { line_height = 0.6 }),
            VerticalSpan:new{ width = dp(4) },
            text(it.meta, "ui_caption", Palette.ink_2, w),
        }, function() self:goTo(it.item) end)
    end
    return self.buildNoteRow(w, it, function() self:goTo(it.item) end)
end

function TocDrawer:goTo(item)
    self:jump(function() self.ui.bookmark:gotoBookmark(item.page, item.pos0) end)
end

function TocDrawer:switchTab(tab)
    if tab == self.tab then return end
    self.tab = tab
    self:build()
    UIManager:setDirty(self, "ui", self.panel_rect)
end

function TocDrawer:goToListPage(page)
    self.cache[self.tab].page = page
    self:build()
    UIManager:setDirty(self, "ui", self.list_rect)
end
-- Closes without a refresh of its own: the jump repaints the page.
function TocDrawer:jump(fn)
    UIManager:close(self)
    if self.on_close then self.on_close() end
    self.ui.link:addCurrentLocationToStack()
    fn()
end

function TocDrawer:export()
    self:onClose()
    local exporter = self.ui.exporter
    if exporter:isReady() then
        exporter:onExportCurrentNotes()
    else
        -- no format or service enabled yet: where the exporter's settings live
        self.ui.menu:showOriginalMenuTab("appbar.tools")
    end
end

function TocDrawer:paintTo(bb, x, y)
    self.panel:paintTo(bb, x, y)
end

function TocDrawer:propagateEvent(event)
    return self.panel:handleEvent(event)
end

function TocDrawer:onTapScrim(_, ges)
    if not self.panel_rect:contains(ges.pos) then
        self:onClose()
    end
    return true
end

function TocDrawer:onClose()
    UIManager:close(self, "ui", self.panel_rect)
    if self.on_close then self.on_close() end
    return true
end

function TocDrawer:onCloseWidget()
    self.panel:free()
end

TocDrawer.Swatch = Swatch

return TocDrawer
