--[[--
Contents drawer of the e-ink redesign (see DESIGN.md, Navigation, and the prototype's openDrawer).

Opened by the reader toolbar's "Contents" (the "ShowToc" event): a left panel with the
book's cover, title, author and progress over three tabs, contents, bookmarks and notes.
Lists are paginated, never scrolled, and a group header never ends a page.

Opening, closing and switching tabs refresh the panel ("ui"), turning a list page only
refreshes the list ("ui"). Jumps close the drawer without a refresh of its own and let
the reader repaint the page ("partial"); the position left is pushed onto the location
stack, for "Return to last position".
]]

local CenterContainer = require("ui/widget/container/centercontainer")
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
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
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

-- Wrapped text clamped to max_lines, with an ellipsis when it overflows.
local function textBox(str, face, width, max_lines, opts)
    local args = { text = str, face = Font:getFace(face), width = width, fgcolor = Palette.ink, bgcolor = Palette.paper }
    for k, v in pairs(opts or {}) do args[k] = v end
    local box = TextBoxWidget:new(args)
    if max_lines and #box.vertical_string_list > max_lines then
        args.height = max_lines * box.line_height_px
        args.height_overflow_show_ellipsis = true
        box:free()
        box = TextBoxWidget:new(args)
    end
    return box
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
    tab = "toc", -- "toc", "bookmarks" or "notes"
    on_close = nil, -- function, called once the drawer is closed
}

local covers = setmetatable({}, { __mode = "k" }) -- document => cover blitbuffer or false

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
    self.ui.toc:fillToc()
    self.bookmarks, self.notes = {}, {}
    for _, item in ipairs(self.ui.annotation.annotations) do
        table.insert(item.drawer and self.notes or self.bookmarks, item)
    end
    self.pages = {} -- tab => current list page
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

    local rows, current = self:buildRows()
    local measured = {}
    for i, row in ipairs(rows) do
        measured[i] = { h = row:getSize().h, is_header = row.is_header }
    end
    local pages = self.paginate(measured, list_h)
    local page = self.pages[self.tab]
    if not page then
        page = 1
        for p, indexes in ipairs(pages) do
            for _, i in ipairs(indexes) do
                if i == current then page = p end
            end
        end
    end
    page = math.max(1, math.min(page, #pages))
    self.pages[self.tab] = page
    self.page_count = #pages
    self.shown_rows = {}
    local list = VerticalGroup:new{ align = "left" }
    local used = 0
    for _, i in ipairs(pages[page] or {}) do
        table.insert(list, rows[i])
        table.insert(self.shown_rows, rows[i])
        used = used + rows[i]:getSize().h
    end
    table.insert(list, VerticalSpan:new{ width = list_h - used })

    local column = VerticalGroup:new{ align = "left", header, tabs, list }
    if export then
        table.insert(column, export)
    end
    table.insert(column, EinkControls.Pager:new{
        width = w, page = page, pages = #pages,
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

function TocDrawer:getCover(w, h)
    local doc = self.ui.document
    if covers[doc] == nil then
        covers[doc] = self.ui.bookinfo and self.ui.bookinfo:getCoverImage(doc) or false
    end
    if covers[doc] then
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            ImageWidget:new{ image = covers[doc], image_disposable = false, width = w, height = h, scale_factor = 0 },
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
    table.insert(info, text(chapters > 0 and T(_("Read %1% · %2 chapters"), percent, chapters) or T(_("Read %1%"), percent),
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
    local cell_w = math.floor(self.content_w / 3)
    local function cell(tab, label)
        return TabCell:new{
            text = label, selected = tab == self.tab, width = cell_w, height = dp(44) - dp(1),
            callback = function() self:switchTab(tab) end,
        }
    end
    local nb, nn = #self.bookmarks, #self.notes
    return VerticalGroup:new{
        HorizontalGroup:new{
            cell("toc", C_("Reader toolbar", "Contents")),
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

-- Content over a rule-gray divider, at least min_h tall with pad_v above and below.
local function row(w, content, pad_v, min_h, callback)
    local h = math.max(min_h or 0, content:getSize().h + 2 * pad_v)
    return ListRow:new{
        callback = callback,
        VerticalGroup:new{
            LeftContainer:new{ dimen = Geom:new{ w = w, h = h - dp(1) }, content },
            rule(w, Palette.rule),
        },
    }
end

local function emptyState(w, title, hint)
    local group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = dp(40) },
        text(title, "ui_body", Palette.ink, w, true),
    }
    if hint then
        table.insert(group, VerticalSpan:new{ width = dp(4) })
        table.insert(group, textBox(hint, "ui_label_large", w - dp(16), nil, { alignment = "center", fgcolor = Palette.ink_2 }))
    end
    return ListRow:new{ CenterContainer:new{ dimen = Geom:new{ w = w, h = group:getSize().h }, group } }
end

local function groupHeader(w, title)
    return ListRow:new{
        is_header = true,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = dp(18) },
            text(title, "ui_caption", Palette.ink_2, w),
            VerticalSpan:new{ width = dp(6) },
            rule(w, Palette.ink),
        },
    }
end

--- Rows of the current tab, and the index of the row to open on (the current chapter).
function TocDrawer:buildRows()
    if self.tab == "bookmarks" then
        return self:buildBookmarkRows()
    elseif self.tab == "notes" then
        return self:buildNoteRows()
    end
    return self:buildTocRows()
end

function TocDrawer:pageString(pn_or_xp)
    return self.ui.bookmark:getBookmarkPageString(pn_or_xp)
end

function TocDrawer:buildTocRows()
    local w = self.content_w
    local toc = self.ui.toc
    if #toc.toc == 0 then
        return { emptyState(w, _("No table of contents")) }
    end
    local current = toc:getTocIndexByPage(self.ui.rolling and self.ui.document:getXPointer() or self.ui:getCurrentPage())
    local rows = {}
    for i, entry in ipairs(toc.toc) do
        local is_current = i == current
        local indent = dp(16) * math.max(0, (entry.depth or 1) - 1)
        local right = HorizontalGroup:new{ align = "center" }
        if is_current then
            table.insert(right, HorizontalSpan:new{ width = dp(8) })
            table.insert(right, FrameContainer:new{
                bordersize = dp(1), color = Palette.ink, radius = dp(9), padding = 0,
                padding_left = dp(7), padding_right = dp(7),
                text(_("Reading"), "ui_micro", Palette.ink),
            })
        end
        table.insert(right, HorizontalSpan:new{ width = dp(12) })
        local pn_or_xp = self.ui.rolling and entry.xpointer or entry.page
        table.insert(right, text(self:pageString(pn_or_xp), "ui_caption", is_current and Palette.ink or Palette.ink_2))
        local title_w = w - indent - right:getSize().w
        local title = textBox(self.ui.toc:cleanUpTocTitle(entry.title, true), "ui_body", title_w, 2, { bold = is_current })
        rows[i] = row(w, HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = indent },
            title,
            right,
        }, dp(8), dp(50), function()
            self:jump(function()
                if entry.xpointer then
                    self.ui:handleEvent(Event:new("GotoXPointer", entry.xpointer, entry.xpointer))
                else
                    self.ui:handleEvent(Event:new("GotoPage", entry.page))
                end
            end)
        end)
        rows[i].toc_index = i
        rows[i].is_current = is_current
    end
    return rows, current
end

--- Text at the top of a bookmarked page, or nil.
function TocDrawer:pageStartText(item)
    local doc = self.ui.document
    if self.ui.rolling then
        local page = doc:getPageFromXPointer(item.page)
        local next_xp = page < doc:getPageCount() and doc:getPageXPointer(page + 1)
        return next_xp and doc:getTextFromXPointers(item.page, next_xp)
    end
    local boxes = doc:getTextBoxes(item.page)
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

function TocDrawer:goTo(item)
    self:jump(function() self.ui.bookmark:gotoBookmark(item.page, item.pos0) end)
end

function TocDrawer:buildBookmarkRows()
    local w = self.content_w
    if #self.bookmarks == 0 then
        return { emptyState(w, _("No bookmarks yet"), _("Show the toolbar and tap the bookmark icon at the top right.")) }
    end
    local rows = {}
    for __, item in ipairs(self.bookmarks) do
        local excerpt = snippet(self:pageStartText(item), 120)
        if excerpt == "" then
            excerpt = item.chapter or self.ui.doc_props.display_title
        end
        local page = self:pageString(item.page)
        local meta = item.chapter and T(_("%1 · Page %2 · %3"), item.chapter, page, date(item))
                                   or T(_("Page %1 · %2"), page, date(item))
        table.insert(rows, row(w, VerticalGroup:new{
            align = "left",
            textBox(excerpt, "ui_excerpt", w, 3, { line_height = 0.6 }),
            VerticalSpan:new{ width = dp(4) },
            text(meta, "ui_caption", Palette.ink_2, w),
        }, dp(12), nil, function() self:goTo(item) end))
    end
    return rows
end

function TocDrawer:buildNoteRows()
    local w = self.content_w
    if #self.notes == 0 then
        return { emptyState(w, _("No notes yet"), _("Long-press text, then tap Highlight or Add note.")) }
    end
    local rows, chapter = {}, nil
    local swatch_w = dp(24)
    for __, item in ipairs(self.notes) do
        local item_chapter = item.chapter or self.ui.doc_props.display_title
        if item_chapter ~= chapter then
            chapter = item_chapter
            table.insert(rows, groupHeader(w, chapter))
        end
        local excerpt = textBox(snippet(item.text, 400), "ui_excerpt", w - swatch_w, 3, { line_height = 0.6 })
        local content = VerticalGroup:new{
            align = "left",
            HorizontalGroup:new{
                align = "top",
                LeftContainer:new{
                    dimen = Geom:new{ w = swatch_w, h = excerpt.line_height_px },
                    Swatch:new{ drawer = item.drawer },
                },
                excerpt,
            },
        }
        if item.note and item.note ~= "" then
            local label = text(_("Thought"), "ui_label_large", Palette.ink, nil, true)
            local gap = dp(4)
            table.insert(content, VerticalSpan:new{ width = dp(6) })
            table.insert(content, HorizontalGroup:new{
                align = "top",
                label,
                HorizontalSpan:new{ width = gap },
                textBox(snippet(item.note, 200), "ui_label_large", w - label:getSize().w - gap, 2),
            })
        end
        table.insert(content, VerticalSpan:new{ width = dp(4) })
        table.insert(content, text(date(item), "ui_caption", Palette.ink_2, w))
        table.insert(rows, row(w, content, dp(12), nil, function() self:goTo(item) end))
        rows[#rows].note = item
    end
    return rows
end

function TocDrawer:switchTab(tab)
    if tab == self.tab then return end
    self.tab = tab
    self:build()
    UIManager:setDirty(self, "ui", self.panel_rect)
end

function TocDrawer:goToListPage(page)
    self.pages[self.tab] = page
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
