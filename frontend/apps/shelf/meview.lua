--[[--
The 我的 tab: this week's reading, a streak line, and entries for all notes,
the vocabulary, sync and transfer, and settings.

Subpages open over the content area, above the tab bar, with a nav bar and a
paged list. Entering, leaving and paging repaint the content area (or the list
under the nav bar) with a "ui" refresh; nothing here flashes. Back leaves a
subpage (on the home it reaches the file manager); the file manager's swipe
handler pages the current list through MeView:swipe().

The home page shows counts only, cached until invalidate(); a subpage loads its
notes or words when it opens and drops them when it closes.
]]

local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
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
local TocDrawer = require("apps/reader/modules/readertocdrawer")
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

local function getFace(face)
    return type(face) == "string" and Font:getFace(face) or face
end

local function text(str, face, color, max_width, bold)
    return TextWidget:new{ text = str, face = getFace(face),
        fgcolor = color or Palette.ink, max_width = max_width, bold = bold, padding = 0 }
end

-- Line height of a TextBoxWidget in `face` (see TextBoxWidget:init).
local function lineHeight(face)
    return math.floor(1.3 * getFace(face).size + 0.5)
end

local function textSize(str, face, bold)
    local widget = TextWidget:new{ text = str, face = getFace(face), bold = bold }
    local size = widget:getSize()
    widget:free()
    return size
end

-- Wrapped text exactly `lines` tall, with an ellipsis when it needs more.
local function textBox(str, face, width, lines, color)
    return TextBoxWidget:new{ text = str, face = getFace(face), width = width, fgcolor = color or Palette.ink,
        height = lines * lineHeight(face), height_overflow_show_ellipsis = true }
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

local MeView = InputContainer:extend{
    ui = nil, -- the FileManager
    width = nil,
    height = nil,
}

function MeView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.inner_w = self.width - 2 * GUTTER
    if Device:hasKeys() then
        self.key_events.Back = { { Device.input.group.Back } }
    end
end

--[[--
Shows the home page, or the subpage of `state` (from getState()), reading the home data unless
cached; the caller refreshes. Called each time the tab opens and when the layout is rebuilt.
]]
function MeView:reset(state)
    self.home = self.home or state and state.home
    if not self.home then
        local counts = Me.counts()
        self.home = {
            week = Me.week(),
            streak = Me.streak(),
            note_count = counts.note_count,
            finished_this_year = counts.finished_this_year,
            word_count = Me.vocabCount(),
        }
    end
    self:unload()
    if state and state.subpage then
        self:load(state.subpage, state.page)
    end
    self:build()
end

--- Drops the cached home data (books or statistics changed).
function MeView:invalidate()
    self.home = nil
end

function MeView:getState()
    return { subpage = self.subpage, page = self.page, home = self.home }
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
    local home = self.home
    local total = text(durationText(home.week.total_minutes), "ui_label")
    self.chart = WeekChart:new{ week = home.week, width = self.inner_w }
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
        text(T(_("%1-day reading streak · %2 finished this year"), home.streak, home.finished_this_year),
            "ui_caption", Palette.ink_2, self.inner_w),
    }
    local rows = VerticalGroup:new{
        align = "left",
        self:entryRow(C_("Me page", "Notes"), T(_("%1 highlights and notes"), home.note_count),
            function() self:open("notes") end),
        self:entryRow(C_("Me page", "Vocabulary"), T(_("%1 words"), home.word_count),
            function() self:open("vocab") end),
        self:entryRow(_("Sync and transfer"), "KOSync · Calibre · OPDS", function() self:open("sync") end),
        self:entryRow(_("Settings"), _("Reading · Screen · Network · Device"), function()
            self.ui:handleEvent(Event:new("ShowEinkSettings"))
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

-- subpage => title and the method measuring its list rows
local subpages = {
    notes = { title = function() return C_("Me page", "Notes") end, items = "notesItems" },
    vocab = { title = function() return C_("Me page", "Vocabulary") end, items = "vocabItems" },
    sync = { title = function() return _("Sync and transfer") end, items = "syncItems" },
}

-- Loads a subpage's data and measures its rows (nothing rendered), paginated once;
-- only the shown page is built.
function MeView:load(kind, page)
    self.subpage = kind
    if kind == "notes" then
        self.books = Me.notes()
    elseif kind == "vocab" then
        self.words = Me.vocab()
    end
    self.items = self[subpages[kind].items](self)
    self.pages = TocDrawer.paginate(self.items, self.height - NAV_H - PAGER_H - dp(4))
    self.page = math.max(1, math.min(page or 1, #self.pages))
end

function MeView:unload()
    self.subpage, self.items, self.pages, self.books, self.words = nil, nil, nil, nil, nil
end

--- Opens a subpage ("notes", "vocab" or "sync") over the content area.
function MeView:open(kind)
    self:load(kind)
    self:build()
    UIManager:setDirty(self.ui, "ui", self.dimen)
end

--- Leaves the subpage for the home page.
function MeView:close()
    self:unload()
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
    local list = VerticalGroup:new{ align = "left" }
    for __, i in ipairs(self.pages[self.page] or {}) do
        table.insert(list, self.items[i].build())
    end
    return VerticalGroup:new{
        align = "left",
        self:buildNavBar(subpages[self.subpage].title()),
        VerticalSpan:new{ width = dp(4) },
        TopContainer:new{ dimen = Geom:new{ w = self.width, h = self.height - NAV_H - PAGER_H - dp(4) }, padded(list) },
        EinkControls.Pager:new{ width = self.width, page = self.page, pages = #self.pages,
            on_change = function(page) self:goToPage(page) end },
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

-- A measured list row: its height and how to build it.
local function item(h, build)
    return { h = h, build = build }
end

-- An entry row (56dp), measured.
function MeView:entryItem(title, subtitle, callback)
    return item(ROW_H, function() return self:entryRow(title, subtitle, callback) end)
end

-- TocDrawer's measured rows (note, group header, empty state), with how to build them here.
function MeView:drawerItem(it, build, callback)
    it.build = function() return build(self.inner_w, it, callback) end
    return it
end

function MeView:emptyItem(title, hint)
    return self:drawerItem(TocDrawer.emptyItem(title, hint), TocDrawer.emptyState)
end

--- Opens the note's book at the note (a full refresh, as for opening any book), keeping the
-- position it opened on for "Return to last position", as the contents drawer does.
function MeView:openNote(book, note)
    filemanagerutil.openFile(self.ui, book.file, nil, nil, function(ui)
        ui.link:addCurrentLocationToStack()
        ui.bookmark:gotoBookmark(note.page, note.pos0)
    end)
end

--- Exports all notes, or with no format or service enabled yet, opens the menu where the exporter's settings live.
function MeView:exportNotes()
    local exporter, menu = self.ui.exporter, self.ui.menu
    if exporter:isReady() then
        return exporter:onExportAllNotes()
    end
    if menu.tab_item_table == nil then
        menu:setUpdateItemTable()
    end
    for i, tab in ipairs(menu.tab_item_table) do
        if tab.icon == "appbar.tools" then
            return menu:onShowMenu(i)
        end
    end
    menu:onShowMenu()
end

function MeView:notesItems()
    if #self.books == 0 then
        return { self:emptyItem(_("No notes yet"), _("Long-press text in a book, then tap Highlight or Add note.")) }
    end
    local items = {}
    if self.ui.exporter then
        table.insert(items, self:entryItem(_("Export notes"), nil, function() self:exportNotes() end))
    end
    local metrics = TocDrawer.noteMetrics()
    for __, book in ipairs(self.books) do
        table.insert(items, self:drawerItem(TocDrawer.headerItem(T(_("%1 · %2 notes"), book.title, #book.notes), metrics),
            TocDrawer.groupHeader))
        for __, note in ipairs(book.notes) do
            table.insert(items, self:drawerItem(TocDrawer.noteItem(self.inner_w, note, metrics), TocDrawer.buildNoteRow,
                function() self:openNote(book, note) end))
        end
    end
    return items
end

function MeView:vocabItems()
    local items = {}
    local vocabbuilder = self.ui.vocabbuilder
    if vocabbuilder then
        table.insert(items, self:entryItem(C_("Vocabulary builder", "Review"), nil,
            function() vocabbuilder:onShowVocabBuilder() end))
    end
    if #self.words == 0 then
        table.insert(items, self:emptyItem(_("Your vocabulary is empty"),
            _("When looking up a word, tap Add to vocabulary builder.")))
        return items
    end
    local word_face, context_face = Font:getFace("ui_vocab_word"), Font:getFace("ui_vocab_context")
    local caption_h = textSize("0", "ui_caption").h
    for __, w in ipairs(self.words) do
        local word_h = textSize(w.word, word_face).h
        local context = ((w.prev_context or "") ~= "" or (w.next_context or "") ~= "")
            and BD.auto((table.concat({ w.prev_context or "", w.word, w.next_context or "" }):gsub("%s+", " ")))
        local lines = context and math.max(1, math.min(2, math.ceil(textSize(context, context_face).w / self.inner_w))) or 0
        local meta = {}
        if w.book and w.book ~= "" then table.insert(meta, w.book) end
        if w.create_time then table.insert(meta, os.date("%Y-%m-%d", w.create_time)) end
        local h = dp(12) + word_h + (context and dp(2) + lines * lineHeight(context_face) or 0)
            + dp(4) + caption_h + dp(12) + Size.border.default
        table.insert(items, item(h, function()
            local group = VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = dp(12) },
                text(w.word, word_face, Palette.ink, self.inner_w),
            }
            if context then
                table.insert(group, VerticalSpan:new{ width = dp(2) })
                table.insert(group, textBox(context, context_face, self.inner_w, lines, Palette.ink_2))
            end
            table.insert(group, VerticalSpan:new{ width = dp(4) })
            table.insert(group, text(table.concat(meta, " · "), "ui_caption", Palette.ink_2, self.inner_w))
            table.insert(group, VerticalSpan:new{ width = dp(12) })
            table.insert(group, rule(self.inner_w, Palette.rule))
            return group
        end))
    end
    return items
end

function MeView:syncItems()
    local disabled = G_reader_settings:readSetting("plugins_disabled") or {}
    local items = {}
    -- KOSync only runs in the reader: show its account, and where to set it up
    if disabled.kosync then
        table.insert(items, self:entryItem(_("Progress sync"), _("Plugin disabled")))
    else
        local kosync = LuaSettings:open(DataStorage:getSettingsDir() .. "/kosync.lua"):readSetting("settings") or {}
        table.insert(items, self:entryItem(_("Progress sync"),
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
        table.insert(items, self:entryItem(_("Calibre wireless connection"),
            connected and _("Connected") or _("Not connected"), function()
                self.ui:handleEvent(Event:new(connected and "CloseWirelessConnection" or "StartWirelessConnection"))
                self:open("sync")
            end))
    else
        table.insert(items, self:entryItem(_("Calibre wireless connection"), _("Plugin disabled")))
    end
    table.insert(items, self:entryItem(_("Book sources (OPDS)"), not self.ui.opds and _("Plugin disabled") or nil,
        self.ui.opds and function() self.ui.opds:onShowOPDSCatalog() end))
    table.insert(items, self:entryItem(_("Cloud storage"), not self.ui.cloudstorage and _("Plugin disabled") or nil,
        self.ui.cloudstorage and function() self.ui.cloudstorage:onShowCloudStorageList() end))
    return items
end

--- Pages the current subpage's list on a west or east swipe; called by the file manager's swipe handler.
function MeView:swipe(ges)
    if self.subpage then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self:goToPage(self.page + 1)
        elseif direction == "east" then
            self:goToPage(self.page - 1)
        end
    end
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
