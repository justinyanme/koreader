--[[--
Contents page of the e-ink redesign (目录页, see DESIGN.md, Navigation): the book's table of contents
on a full-screen page (ui/widget/fullscreenpage), after WeChat Read's 04-contents-and-search/01-contents.png.

Opened by "ShowToc" (ReaderToolbar), from the toolbar and gestures alike. On top, the book title with
↓去底部 at the right (↑去顶部 on the last page, nothing with a single page) and the 搜索全书内容 field;
then the entries in bold with their start pages, indented by level; at the bottom, the back arrow, 书签
and the page capsule. A top-level entry with entries under it is a group: a tap on its chevron (before
its title) collapses or expands them, and the groups the reader collapses stay collapsed for the book.
The page opens on the page that holds the current chapter, showing it even when its group is
collapsed, and draws that chapter's page number ink-filled. Entries are measured once (without
rendering) and only the shown page's rows are built.

The search field opens the search page (apps/reader/modules/readersearchpage) over this page. 书签
opens the notes page (apps/reader/modules/readernotespage) on the bookmarks, through "ShowNotes".

Opening and closing repaint the page; turning a page or collapsing a group repaints the content and
the bar, and the title band too when ↓去底部 and ↑去顶部 swap (all "ui"). A jump closes the page
with the reader's "partial", which the jump's own repaint joins (the reader may not repaint when the
entry is on the page shown); the position left is pushed onto the location stack, for going back to it
(ReaderLink, the Back key).
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local FullscreenPage = require("ui/widget/fullscreenpage")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TocDrawer = require("apps/reader/modules/readertocdrawer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Tappable = require("apps/shelf/shelfwidgets").Tappable
local Screen = require("device").screen
local _ = require("gettext")

local function dp(v) return Screen:scaleBySize(v) end

local GUTTER = dp(24)
local CHEVRON_W = dp(22) -- the column of group chevrons, before the top-level titles, when there are groups
local INDENT = dp(15) -- per level below the top one
local ROW_H = dp(53)
local FIELD_H = dp(40)
local FIELD_TARGET_H = dp(50) -- the search field takes taps 5dp around it
local NUMBER_GAP = dp(16) -- between a title and its page number
local CURRENT_PAD = dp(8) -- each side of the current chapter's page number, inside its ink pill
local COLLAPSED_SETTING = "contents_page_collapsed" -- entry index => title of each collapsed group

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

local function icon(name, size, rotation_angle)
    return IconWidget:new{ icon = name, width = size, height = size, alpha = true, rotation_angle = rotation_angle }
end

local TocPage = FullscreenPage:extend{
    ui = nil,
    on_close = nil, -- function, called once the page is closed (back, a jump or 书签, here or on the search page)
    on_bookmarks = nil, -- function, opens the bookmarks after 书签 closed the page
}

function TocPage:init()
    self.title = self.ui.doc_props.display_title
    FullscreenPage.init(self)
    self.content_w = self.dimen.w - 2 * GUTTER
    -- the content: the search field's target, 15dp, a rule, then the rows
    local head_h = FIELD_TARGET_H + dp(15)
    self.list_rect = Geom:new{ x = 0, y = self.content_rect.y + head_h, w = self.dimen.w, h = self.content_rect.h - head_h }
    self.line_h = math.floor(1.3 * Font:getFace("ui_body").size + 0.5) -- a TextBoxWidget line (see TextBoxWidget:init)

    local toc = self.ui.toc
    toc:fillToc()
    self.entries = toc.toc
    self.top_depth = math.huge
    for _, entry in ipairs(self.entries) do
        self.top_depth = math.min(self.top_depth, entry.depth or 1)
    end
    self.group_end = {} -- index of a group => index of its last entry
    local group
    for i, entry in ipairs(self.entries) do
        if (entry.depth or 1) == self.top_depth then
            group = i
        elseif group then
            self.group_end[group] = i
        end
    end
    self.lead_w = next(self.group_end) and CHEVRON_W or 0 -- flat contents start at the gutter
    -- what the reader collapsed, as saved; the current chapter's group shows open whatever it says
    self.collapsed = {}
    for i, title in pairs(self.ui.doc_settings:readSetting(COLLAPSED_SETTING) or {}) do
        if self.group_end[i] and self.entries[i].title == title then
            self.collapsed[i] = true
        end
    end
    if #self.entries > 0 then
        self.current = toc:getTocIndexByPage(self.ui.rolling and self.ui.document:getXPointer() or self.ui:getCurrentPage())
    end
    for g, last in pairs(self.group_end) do
        if self.current and g < self.current and self.current <= last then
            self.opened = g
        end
    end
    self.measures = {} -- entry index => measured row
    self:paginate()
    self.page = self:pageOf(self.current) or 1
    self:build()
end

function TocPage:isCollapsed(i)
    return self.collapsed[i] and i ~= self.opened
end

--- Measured row of entry `i`: plain sizes, nothing rendered.
function TocPage:measure(i)
    local m = self.measures[i]
    if m then return m end
    local entry = self.entries[i]
    local ui = self.ui
    local page = ui.bookmark:getBookmarkPageString(ui.rolling and entry.xpointer or entry.page)
    local indent = self.lead_w + math.min(INDENT * ((entry.depth or 1) - self.top_depth), math.floor(self.content_w / 3))
    local title = ui.toc:cleanUpTocTitle(entry.title, true)
    -- the current chapter's page number takes its pill's padding from the title, so it ends where the others do
    local number_w = textWidth(page, "ui_label_large") + (i == self.current and 2 * CURRENT_PAD or 0)
    local title_w = self.content_w - indent - NUMBER_GAP - number_w
    local lines = math.max(1, math.min(2, math.ceil(textWidth(title, "ui_body", true) / title_w)))
    m = {
        index = i, page = page, title = title, indent = indent, title_w = title_w, lines = lines,
        h = math.max(ROW_H, lines * self.line_h + 2 * dp(8) + Size.border.default),
    }
    self.measures[i] = m
    return m
end

--- The shown entries (none inside a collapsed group) and their pages; an open group never ends a page.
function TocPage:paginate()
    local items = {}
    local i = 1
    while i <= #self.entries do
        local m = self:measure(i)
        m.is_header = self.group_end[i] ~= nil and not self:isCollapsed(i)
        table.insert(items, m)
        i = (self:isCollapsed(i) and self.group_end[i] or i) + 1
    end
    self.items = items
    self.pages = TocDrawer.paginate(items, self.list_rect.h - Size.border.default)
end

--- The page that shows entry `index`, or nil.
function TocPage:pageOf(index)
    for p, indexes in ipairs(self.pages) do
        for _, k in ipairs(indexes) do
            if self.items[k].index == index then return p end
        end
    end
end

--- Where the title band's action goes: the last page (↓去底部), or the first from the last (↑去顶部); nil with one page.
function TocPage:actionTarget()
    if self.page_count <= 1 then return end
    return self.page < self.page_count and self.page_count or 1
end

function TocPage:buildTitle()
    local rect = self.title_rect
    local target = self:actionTarget()
    local right
    if target then
        local to_top = target == 1
        local label = HorizontalGroup:new{
            align = "center",
            icon("eink/arrow.down", dp(16), to_top and 180 or nil),
            HorizontalSpan:new{ width = dp(2) },
            text(to_top and _("Go to top") or _("Go to bottom"), "ui_label_large", nil, nil, true),
        }
        -- 8dp each side: the label ends 32dp from the edge, and the target is the band's height
        right = Tappable:new{
            callback = function() self:goToPage(target) end,
            CenterContainer:new{ dimen = Geom:new{ w = label:getSize().w + 2 * dp(8), h = rect.h }, label },
        }
    else
        right = HorizontalSpan:new{ width = 0 }
    end
    self.action_button = target and right or nil
    local title_w = rect.w - 2 * GUTTER - right:getSize().w
    return HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = GUTTER },
        LeftContainer:new{
            dimen = Geom:new{ w = title_w, h = rect.h },
            text(self.title, "ui_title_large", nil, title_w - dp(8), true),
        },
        right,
        HorizontalSpan:new{ width = GUTTER },
    }
end

function TocPage:buildSearch()
    local bw = Size.border.default
    local pad = dp(14)
    local field = FrameContainer:new{
        radius = math.floor(FIELD_H / 2), bordersize = bw, color = Palette.ink, background = Palette.paper,
        padding = 0, padding_left = pad,
        LeftContainer:new{
            dimen = Geom:new{ w = self.content_w - pad - 2 * bw, h = FIELD_H - 2 * bw },
            HorizontalGroup:new{
                align = "center",
                icon("eink/search", dp(24)),
                HorizontalSpan:new{ width = dp(8) },
                text(_("Search the whole book"), "ui_body", nil, self.content_w - pad - dp(40), true),
            },
        },
    }
    self.search_field = Tappable:new{
        callback = function() self:search() end,
        CenterContainer:new{ dimen = Geom:new{ w = self.content_w, h = FIELD_TARGET_H }, field },
    }
    return HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, self.search_field }
end

--- An entry's row, over a rule-gray divider: a group's chevron (its own target, from the edge to the title),
-- the title and the page number, ink-filled for the current chapter. A tap elsewhere goes to the entry.
function TocPage:buildRow(m)
    local inner_h = m.h - Size.border.default
    local group = self.group_end[m.index] ~= nil
    local lead
    if group then
        local collapsed = self:isCollapsed(m.index)
        lead = Tappable:new{
            callback = function() self:toggle(m.index) end,
            LeftContainer:new{
                dimen = Geom:new{ w = GUTTER + m.indent, h = inner_h },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = GUTTER },
                    icon(collapsed and "eink/chev" or "eink/chev.up", dp(16), not collapsed and 180 or nil),
                },
            },
        }
    else
        lead = HorizontalSpan:new{ width = GUTTER + m.indent }
    end
    local is_current = m.index == self.current
    local number = text(m.page, "ui_label_large", is_current and Palette.paper or Palette.ink)
    if is_current then
        local h = number:getSize().h + dp(4)
        number = FrameContainer:new{
            bordersize = 0, background = Palette.ink, radius = math.floor(h / 2),
            padding = 0, padding_left = CURRENT_PAD, padding_right = CURRENT_PAD,
            CenterContainer:new{ dimen = Geom:new{ w = number:getSize().w, h = h }, number },
        }
    end
    local number_box = RightContainer:new{
        dimen = Geom:new{ w = self.content_w - m.indent - m.title_w - NUMBER_GAP, h = inner_h },
        number,
    }
    local title = TextBoxWidget:new{
        text = m.title, face = Font:getFace("ui_body"), width = m.title_w, bold = true,
        height = m.lines * self.line_h, height_overflow_show_ellipsis = true,
        fgcolor = Palette.ink, bgcolor = Palette.paper,
    }
    local row = Tappable:new{
        callback = function() self:jump(self.entries[m.index]) end,
        VerticalGroup:new{
            align = "left",
            LeftContainer:new{
                dimen = Geom:new{ w = self.dimen.w, h = inner_h },
                HorizontalGroup:new{
                    align = "center",
                    lead,
                    title,
                    HorizontalSpan:new{ width = NUMBER_GAP },
                    number_box,
                },
            },
            HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, rule(self.content_w) },
        },
    }
    row.toc_index, row.is_current, row.is_group, row.chevron = m.index, is_current, group, group and lead or nil
    row.title, row.number = title, number_box
    return row
end

--- The search field, a rule, and the rows of the shown page; `self.shown_rows` gets the rows.
function TocPage:buildContent(rect)
    self.page = math.max(1, math.min(self.page, #self.pages))
    local list = VerticalGroup:new{
        align = "left",
        self:buildSearch(),
        VerticalSpan:new{ width = self.list_rect.y - rect.y - FIELD_TARGET_H },
        HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, rule(self.content_w) },
    }
    self.shown_rows = {}
    if #self.entries == 0 then
        table.insert(list, CenterContainer:new{
            dimen = Geom:new{ w = rect.w, h = dp(80) },
            text(_("No table of contents"), "ui_body", nil, self.content_w, true),
        })
    end
    for _, k in ipairs(self.pages[self.page] or {}) do
        local row = self:buildRow(self.items[k])
        table.insert(list, row)
        table.insert(self.shown_rows, row)
    end
    return list, math.max(1, #self.pages)
end

--- The 书签 pill beside the page capsule, which takes taps over the bar's height; also on the search page.
function TocPage.bookmarksButton(callback)
    local h = EinkControls.PageCapsule.height -- the pill matches the capsule, as in the reference
    local bw = Size.border.default
    local label = HorizontalGroup:new{
        align = "center",
        icon("eink/bookmark", dp(26)),
        HorizontalSpan:new{ width = dp(6) },
        text(_("Bookmarks"), "ui_label_large", nil, nil, true),
    }
    local pill = FrameContainer:new{
        radius = math.floor(h / 2), bordersize = bw, color = Palette.ink, background = Palette.paper,
        padding = 0, padding_left = dp(14), padding_right = dp(16),
        CenterContainer:new{ dimen = Geom:new{ w = label:getSize().w, h = h - 2 * bw }, label },
    }
    return Tappable:new{
        callback = callback,
        CenterContainer:new{
            dimen = Geom:new{ w = pill:getSize().w, h = EinkControls.BottomBar.height - Size.border.default },
            pill,
        },
    }
end

function TocPage:buildBarParts()
    self.bookmarks_button = TocPage.bookmarksButton(function() self:openBookmarks() end)
    return nil, { self.bookmarks_button }
end

--- After a rebuild that repainted the content and the bar, repaints the title band too if its action changed.
function TocPage:refreshTitle(target_before)
    if self:actionTarget() ~= target_before then
        UIManager:setDirty(self, "ui", self.title_rect)
    end
end

function TocPage:goToPage(page)
    local target = self:actionTarget()
    FullscreenPage.goToPage(self, page)
    self:refreshTitle(target)
end

--- Collapses or expands group `index`, keeps the choice, and stays on the page that shows the group.
function TocPage:toggle(index)
    local target = self:actionTarget()
    if self:isCollapsed(index) then
        self.collapsed[index] = nil
    else
        self.collapsed[index] = true
    end
    if index == self.opened then
        self.opened = nil -- the reader decided for the current chapter's group too
    end
    local saved = {}
    for i in pairs(self.collapsed) do
        saved[i] = self.entries[i].title
    end
    if next(saved) then
        self.ui.doc_settings:saveSetting(COLLAPSED_SETTING, saved)
    else
        self.ui.doc_settings:delSetting(COLLAPSED_SETTING)
    end
    self:paginate()
    self.page = self:pageOf(index)
    self:build()
    UIManager:setDirty(self, "ui", self.body_rect)
    self:refreshTitle(target)
end

function TocPage:jump(entry)
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "partial", self.dimen)
    self.ui.link:addCurrentLocationToStack()
    if entry.xpointer then
        self.ui:handleEvent(Event:new("GotoXPointer", entry.xpointer, entry.xpointer))
    else
        self.ui:handleEvent(Event:new("GotoPage", entry.page))
    end
end

--- The search page opens over this page, which 取消 there comes back to.
function TocPage:search()
    if self.closed then return end
    if not self.ui:handleEvent(Event:new("ShowSearchPage", nil, self)) then
        -- no search page (apps/reader/modules/readerfulltextsearch): the original search input
        self:goBack()
        self.ui:handleEvent(Event:new("ShowFulltextSearchInput"))
    end
end

function TocPage:openBookmarks()
    self:goBack()
    if self.on_bookmarks then self.on_bookmarks() end
end

function TocPage:onCloseWidget()
    if self.on_close then self.on_close() end
end

return TocPage
