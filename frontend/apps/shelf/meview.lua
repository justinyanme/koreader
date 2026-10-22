--[[--
The 我的 tab: this week's reading, a streak line, and entries for all notes,
the vocabulary, sync and transfer, and settings.

Subpages open over the content area, above the tab bar, with a nav bar and a
paged list. Entering, leaving and paging repaint the content area (or the list
under the nav bar) with a "ui" refresh; nothing here flashes. Swipes page the
current list, and Back leaves a subpage (on the home it reaches the file manager).
]]

local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local LuaSettings = require("luasettings")
local Me = require("apps/shelf/me")
local Palette = require("ui/palette")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local datetime = require("datetime")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext

local function dp(n) return Screen:scaleBySize(n) end

local GUTTER = dp(24)
local NAV_H = dp(52)
local PAGER_H = dp(44)
local ROW_H = dp(56)
local CHART_H = dp(118)
local WEEKDAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

local function text(str, face, color, max_width, bold)
    return TextWidget:new{ text = str, face = type(face) == "string" and Font:getFace(face) or face,
        fgcolor = color or Palette.ink, max_width = max_width, bold = bold, padding = 0 }
end

-- Wrapped text clamped to max_lines, with an ellipsis when it overflows.
local function textBox(str, face, width, max_lines, color, bold)
    local args = { text = str, face = type(face) == "string" and Font:getFace(face) or face, width = width,
        fgcolor = color or Palette.ink, bold = bold }
    local box = TextBoxWidget:new(args)
    if #box.vertical_string_list > max_lines then
        args.height = max_lines * box.line_height_px
        args.height_overflow_show_ellipsis = true
        box:free()
        box = TextBoxWidget:new(args)
    end
    return box
end

local function rule(w, color)
    return LineWidget:new{ background = color, dimen = Geom:new{ w = w, h = Size.border.default } }
end

local function durationText(minutes)
    return T(_("%1 h %2 min"), math.floor(minutes / 60), minutes % 60)
end

--- Bars of minutes read per day, Monday first, at heights proportional to the week's longest day.
local WeekChart = Widget:extend{
    week = nil, -- Me.week()
    width = nil,
}

function WeekChart:init()
    self.dimen = Geom:new{ w = self.width, h = CHART_H }
    self.gap = dp(10)
    self.col_w = math.floor((self.width - 6 * self.gap) / 7)
    self.labels, self.values = {}, {}
    local max = 0
    for i = 1, 7 do
        local today = i == self.week.today
        local minutes = self.week.minutes[i]
        self.labels[i] = text(today and _("Today") or datetime.shortDayOfWeekTranslation[WEEKDAYS[i]], "ui_micro",
            today and Palette.ink or Palette.ink_2, self.col_w, today)
        if minutes then
            self.values[i] = text(tostring(minutes), "ui_micro", today and Palette.ink or Palette.ink_2, self.col_w, today)
            max = math.max(max, minutes)
        end
    end
    self.label_h = self.labels[1]:getSize().h
    self.bar_max = CHART_H - 2 * self.label_h - 2 * dp(4)
    -- bar heights in px, nil for days to come; a non-zero day gets at least 1px
    self.bar_heights = {}
    for i = 1, self.week.today do
        local minutes = self.week.minutes[i]
        self.bar_heights[i] = minutes > 0 and math.max(1, math.floor(minutes / max * self.bar_max + 0.5)) or 0
    end
end

function WeekChart:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local base = y + CHART_H - self.label_h - dp(4) -- bottom of the bars
    local bar_w = math.floor(self.col_w * 0.6)
    for i = 1, 7 do
        local cx = x + (i - 1) * (self.col_w + self.gap)
        local function center(widget, wy)
            widget:paintTo(bb, cx + math.floor((self.col_w - widget:getSize().w) / 2), wy)
        end
        center(self.labels[i], base + dp(4))
        local bx = cx + math.floor((self.col_w - bar_w) / 2)
        local h = self.bar_heights[i]
        if h then
            bb:paintRect(bx, base - h, bar_w, h, Palette.ink)
            center(self.values[i], base - h - dp(4) - self.label_h)
        else
            -- a day to come: a dashed stub
            local stub, line = dp(6), Size.border.default
            for dx = 0, bar_w - 1, dp(4) do
                bb:paintRect(bx + dx, base - stub, math.min(dp(2), bar_w - dx), line, Palette.ink_3)
            end
            bb:paintRect(bx, base - stub, line, stub, Palette.ink_3)
            bb:paintRect(bx + bar_w - line, base - stub, line, stub, Palette.ink_3)
        end
    end
end

function WeekChart:free()
    for __, w in pairs(self.labels) do w:free() end
    for __, w in pairs(self.values) do w:free() end
end

-- Splits measured rows into pages that fit max_h; a group header never ends a page.
-- ponytail: same as TocDrawer.paginate (#17); switch to it once that lands.
local function paginate(items, max_h)
    local pages, page, used = {}, {}, 0
    for i, item in ipairs(items) do
        local h = item:getSize().h
        if #page > 0 and used + h > max_h then
            local last = page[#page]
            if items[last].is_header and #page > 1 then
                table.remove(page)
                table.insert(pages, page)
                page, used = { last }, items[last]:getSize().h
            else
                table.insert(pages, page)
                page, used = {}, 0
            end
        end
        table.insert(page, i)
        used = used + h
    end
    if #page > 0 then table.insert(pages, page) end
    return pages
end

local MeView = InputContainer:extend{
    ui = nil, -- the FileManager
    width = nil,
    height = nil,
}

function MeView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.inner_w = self.width - 2 * GUTTER
    self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.Back = { { Device.input.group.Back } }
    end
end

--- Reads the data and shows the home page; the caller refreshes. Called each time the tab opens.
function MeView:reset()
    self.subpage = nil
    self.week = Me.week()
    self.streak = Me.streak()
    self.library = Me.library()
    self.words = Me.vocab()
    self:build()
end

function MeView:build()
    if self[1] then self[1]:free() end
    self[1] = self.subpage and self:buildSubpage() or self:buildHome()
end

--- A 56dp list row: a first line, an optional gray second line and a chevron; dimmed without a callback.
function MeView:entryRow(title, subtitle, callback)
    local chev_w = dp(24)
    local lines = VerticalGroup:new{ align = "left",
        text(title, "ui_body", callback and Palette.ink or Palette.ink_3, self.inner_w - chev_w) }
    if subtitle then
        table.insert(lines, VerticalSpan:new{ width = dp(2) })
        table.insert(lines, text(subtitle, "ui_caption", callback and Palette.ink_2 or Palette.ink_3, self.inner_w - chev_w))
    end
    return ShelfWidgets.Tappable:new{
        callback = callback,
        VerticalGroup:new{
            HorizontalGroup:new{
                LeftContainer:new{ dimen = Geom:new{ w = self.inner_w - chev_w, h = ROW_H - Size.border.default }, lines },
                CenterContainer:new{ dimen = Geom:new{ w = chev_w, h = ROW_H - Size.border.default },
                    callback and IconWidget:new{ icon = "eink/chev", width = dp(18), height = dp(18), dim = true }
                        or HorizontalSpan:new{ width = 0 } },
            },
            rule(self.inner_w, Palette.rule),
        },
    }
end

local function padded(widget, top, bottom)
    return FrameContainer:new{
        bordersize = 0, padding = 0,
        padding_left = GUTTER, padding_right = GUTTER, padding_top = top or 0, padding_bottom = bottom or 0,
        widget,
    }
end

function MeView:buildHome()
    local heading = text(_("Reading this week"), "ui_body", Palette.ink, nil, true)
    local total = text(durationText(self.week.total_minutes), "ui_label")
    self.chart = WeekChart:new{ week = self.week, width = self.inner_w }
    local stats = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            align = "bottom",
            heading,
            HorizontalSpan:new{ width = self.inner_w - heading:getSize().w - total:getSize().w },
            total,
        },
        VerticalSpan:new{ width = dp(12) },
        self.chart,
        VerticalSpan:new{ width = dp(10) },
        text(T(_("%1-day reading streak · %2 finished this year"), self.streak, self.library.finished_this_year),
            "ui_caption", Palette.ink_2, self.inner_w),
    }
    local rows = VerticalGroup:new{
        align = "left",
        self:entryRow(C_("Me page", "Notes"), T(_("%1 highlights and notes"), self.library.note_count),
            function() self:open("notes") end),
        self:entryRow(C_("Me page", "Vocabulary"), T(_("%1 words"), #self.words),
            function() self:open("vocab") end),
        self:entryRow(_("Sync and transfer"), "KOSync · Calibre · OPDS", function() self:open("sync") end),
        self:entryRow(_("Settings"), _("Reading · Screen · Network · Device"), function()
            -- until #12 reorganizes settings, the file manager's menu
            self.ui.menu:onShowMenu()
        end),
    }
    return VerticalGroup:new{
        align = "left",
        padded(text(_("Me"), "ui_headline", Palette.ink, self.inner_w), dp(14), dp(6)),
        padded(stats, dp(4), dp(14)),
        rule(self.width, Palette.ink),
        padded(rows),
    }
end

-- subpage => title and the method building its list rows
local subpages = {
    notes = { title = function() return C_("Me page", "Notes") end, items = "buildNotesItems" },
    vocab = { title = function() return C_("Me page", "Vocabulary") end, items = "buildVocabItems" },
    sync = { title = function() return _("Sync and transfer") end, items = "buildSyncItems" },
}

--- Opens a subpage ("notes", "vocab" or "sync") over the content area.
function MeView:open(kind)
    self.subpage = kind
    self.page = 1
    self:build()
    UIManager:setDirty(self.ui, "ui", self.dimen)
end

--- Leaves the subpage for the home page.
function MeView:close()
    self.subpage = nil
    self:build()
    UIManager:setDirty(self.ui, "ui", self.dimen)
end

function MeView:buildNavBar(title)
    local back_w = dp(52)
    local h = NAV_H - Size.border.default
    return VerticalGroup:new{
        HorizontalGroup:new{
            ShelfWidgets.Tappable:new{
                callback = function() self:close() end,
                CenterContainer:new{ dimen = Geom:new{ w = back_w, h = h },
                    IconWidget:new{ icon = "eink/back", width = dp(24), height = dp(24) } },
            },
            CenterContainer:new{ dimen = Geom:new{ w = self.width - 2 * back_w, h = h },
                text(title, "ui_title", Palette.ink, self.width - 2 * back_w, true) },
            HorizontalSpan:new{ width = back_w },
        },
        rule(self.width, Palette.ink),
    }
end

function MeView:buildSubpage()
    local subpage = subpages[self.subpage]
    local items = self[subpage.items](self)
    local list_h = self.height - NAV_H - PAGER_H - dp(4)
    self.pages = paginate(items, list_h)
    self.page = math.max(1, math.min(self.page, #self.pages))
    local list = VerticalGroup:new{ align = "left" }
    for __, i in ipairs(self.pages[self.page] or {}) do
        table.insert(list, items[i])
    end
    local pager = HorizontalGroup:new{}
    if #self.pages > 1 then
        pager = ShelfWidgets.Pager:new{ page = self.page, pages = #self.pages,
            on_change = function(page) self:goToPage(page) end }
    end
    return VerticalGroup:new{
        align = "left",
        self:buildNavBar(subpage.title()),
        VerticalSpan:new{ width = dp(4) },
        TopContainer:new{ dimen = Geom:new{ w = self.width, h = list_h }, padded(list) },
        CenterContainer:new{ dimen = Geom:new{ w = self.width, h = PAGER_H }, pager },
    }
end

--- Shows a page of the current subpage's list, repainting the list under the nav bar.
function MeView:goToPage(page)
    if not self.subpage or page < 1 or page > #self.pages or page == self.page then return end
    self.page = page
    self:build()
    UIManager:setDirty(self.ui, "ui", Geom:new{ x = self.dimen.x, y = self.dimen.y + NAV_H,
        w = self.width, h = self.height - NAV_H })
end

function MeView:emptyState(title, hint)
    local group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = dp(40) },
        text(title, "ui_body", Palette.ink, self.inner_w, true),
        VerticalSpan:new{ width = dp(4) },
        textBox(hint, "ui_label_large", self.inner_w - dp(16), 3, Palette.ink_2),
    }
    return CenterContainer:new{ dimen = Geom:new{ w = self.inner_w, h = group:getSize().h }, group }
end

function MeView:groupHeader(title)
    local header = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = dp(18) },
        text(title, "ui_caption", Palette.ink_2, self.inner_w),
        VerticalSpan:new{ width = dp(6) },
        rule(self.inner_w, Palette.ink),
    }
    header.is_header = true
    return header
end

-- ponytail: stand-in until #17's note rows can be reused (TocDrawer.buildNoteRow).
function MeView:noteRow(book, item)
    local content = VerticalGroup:new{
        align = "left",
        textBox(item.text or "", "ui_excerpt", self.inner_w, 3),
        VerticalSpan:new{ width = dp(4) },
        text((item.datetime or ""):sub(1, 10), "ui_caption", Palette.ink_2, self.inner_w),
    }
    return ShelfWidgets.Tappable:new{
        callback = function() self:openNote(book, item) end,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = dp(12) },
            content,
            VerticalSpan:new{ width = dp(12) },
            rule(self.inner_w, Palette.rule),
        },
    }
end

--- Opens the note's book at the note (a full refresh, as for opening any book).
function MeView:openNote(book, item)
    filemanagerutil.openFile(self.ui, book.file, nil, nil, function(ui)
        ui.bookmark:gotoBookmark(item.page, item.pos0)
    end)
end

function MeView:buildNotesItems()
    local items = {}
    if self.library.note_count == 0 then
        return { self:emptyState(_("No notes yet"), _("Long-press text in a book, then tap Highlight or Add note.")) }
    end
    if self.ui.exporter then
        table.insert(items, self:entryRow(_("Export notes"), nil, function() self.ui.exporter:onExportAllNotes() end))
    end
    for __, book in ipairs(self.library.books) do
        table.insert(items, self:groupHeader(T(_("%1 · %2 notes"), book.title, #book.notes)))
        for __, item in ipairs(book.notes) do
            table.insert(items, self:noteRow(book, item))
        end
    end
    return items
end

function MeView:buildVocabItems()
    local items = {}
    local vocabbuilder = self.ui.vocabbuilder
    if vocabbuilder then
        table.insert(items, self:entryRow(C_("Vocabulary builder", "Review"), nil,
            function() vocabbuilder:onShowVocabBuilder() end))
    end
    if #self.words == 0 then
        table.insert(items, self:emptyState(_("Your vocabulary is empty"),
            _("When looking up a word, tap Add to vocabulary builder.")))
        return items
    end
    for __, w in ipairs(self.words) do
        local group = VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = dp(12) },
            text(w.word, Font:getFace("ui_excerpt", 17), Palette.ink, self.inner_w, true),
        }
        local context = table.concat({ w.prev_context or "", w.word, w.next_context or "" }):gsub("%s+", " ")
        if (w.prev_context or "") ~= "" or (w.next_context or "") ~= "" then
            table.insert(group, VerticalSpan:new{ width = dp(2) })
            table.insert(group, textBox(BD.auto(context), Font:getFace("ui_excerpt", 13), self.inner_w, 2, Palette.ink_2))
        end
        local meta = {}
        if w.book and w.book ~= "" then table.insert(meta, w.book) end
        if w.create_time then table.insert(meta, os.date("%Y-%m-%d", w.create_time)) end
        table.insert(group, VerticalSpan:new{ width = dp(4) })
        table.insert(group, text(table.concat(meta, " · "), "ui_caption", Palette.ink_2, self.inner_w))
        table.insert(group, VerticalSpan:new{ width = dp(12) })
        table.insert(group, rule(self.inner_w, Palette.rule))
        table.insert(items, group)
    end
    return items
end

function MeView:buildSyncItems()
    local disabled = G_reader_settings:readSetting("plugins_disabled") or {}
    local items = {}
    -- KOSync only runs in the reader: show its account, and where to set it up
    if disabled.kosync then
        table.insert(items, self:entryRow(_("Progress sync"), _("Plugin disabled")))
    else
        local kosync = LuaSettings:open(DataStorage:getSettingsDir() .. "/kosync.lua"):readSetting("settings") or {}
        table.insert(items, self:entryRow(_("Progress sync"),
            kosync.userkey and kosync.username and T(_("Logged in as %1"), kosync.username) or _("Not logged in"),
            function()
                UIManager:show(InfoMessage:new{
                    text = _("Progress sync is set up in the reader: open a book, then Tools › Progress sync."),
                })
            end))
    end
    if self.ui.calibre then
        -- ponytail: state as of building the page; a connection made in the background shows on the next visit
        local wireless = package.loaded["wireless"]
        local connected = wireless and wireless.calibre_socket ~= nil
        table.insert(items, self:entryRow(_("Calibre wireless connection"),
            connected and _("Connected") or _("Not connected"), function()
                self.ui:handleEvent(Event:new(connected and "CloseWirelessConnection" or "StartWirelessConnection"))
                self:build()
                UIManager:setDirty(self.ui, "ui", self.dimen)
            end))
    else
        table.insert(items, self:entryRow(_("Calibre wireless connection"), _("Plugin disabled")))
    end
    table.insert(items, self:entryRow(_("OPDS catalog"), not self.ui.opds and _("Plugin disabled") or nil,
        self.ui.opds and function() self.ui.opds:onShowOPDSCatalog() end))
    table.insert(items, self:entryRow(_("Cloud storage"), not self.ui.cloudstorage and _("Plugin disabled") or nil,
        self.ui.cloudstorage and function() self.ui.cloudstorage:onShowCloudStorageList() end))
    return items
end

function MeView:onSwipe(__, ges)
    if self.subpage then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self:goToPage(self.page + 1)
        elseif direction == "east" then
            self:goToPage(self.page - 1)
        end
    end
    -- never let the hidden shelf or file browser turn their pages
    return true
end

function MeView:onBack()
    if self.subpage then
        self:close()
        return true
    end
    return false
end

return MeView
