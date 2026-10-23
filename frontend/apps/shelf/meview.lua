--[[--
The 我 tab (13-reading-preferences/01-profile-entry.png): the reader's name in the display serif, the reading time
the statistics plugin recorded (累计阅读 X 小时 Y 分钟 over 本周阅读 X 小时 Y 分钟 | 连续 N 天), then rows with a
circled icon, a title over a subtitle and a chevron: 全部书笔记, 生词本, 文件, 同步与传书, 设置 and 版本更新.

The name is the nickname set here, else the KOSync user name, else the device model (Me.name()); a tap on it edits
the nickname, and saving it empty goes back to the others. A tap on the reading time opens the statistics plugin's
reading progress, as 更多 → 阅读统计 does in the reader; without the plugin the time says so and takes no tap.
版本更新 shows the version running and checks for a new one as the original menu's Update does; on a device
without KOReader's updates it is dimmed and takes no tap.

Subpages open over the content area, above the tab bar, with a nav bar and a
paged list. Entering, leaving and paging repaint the content area (or the list
under the nav bar) with a "ui" refresh, and so does a new name; nothing here
flashes. Back leaves a subpage (on the home it reaches the file manager); the
file manager's swipe handler pages the current list through MeView:swipe().

The home page shows counts only, cached until invalidate(); a subpage loads its
notes or words when it opens and drops them when it closes.
]]

local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
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
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Me = require("apps/shelf/me")
local OverlapGroup = require("ui/widget/overlapgroup")
local Palette = require("ui/palette")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TocDrawer = require("apps/reader/modules/readertocdrawer")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local Version = require("version")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext

local function dp(n) return Screen:scaleBySize(n) end

local GUTTER = dp(24) -- subpages
local NAV_H = dp(52)
local PAGER_H = dp(44)
local ROW_H = dp(56) -- subpage rows
-- The home page, measured on the reference (the name's top from where the shelf's search field starts).
local HOME_GUTTER = dp(22)
local NAME_SIZE = 28 -- the display serif
local FIGURE_SIZE = 24 -- the Figure role: the numbers of 累计阅读
local NAME_BASELINE = dp(51)
local TOTAL_BASELINE = dp(85) -- 累计阅读
local WEEK_BASELINE = dp(108) -- 本周阅读 | 连续
local HEADER_H = dp(136) -- down to the rule over the rows, at least
local HOME_ROW_H = dp(94)
local RING = dp(37)
local RING_ICON = dp(21)
local RING_GAP = dp(18) -- from the ring to the title
local CHEV_W, CHEV_H = dp(9), dp(17) -- the ink chevron, ending at the gutter
local TITLE_GAP = dp(4) -- between a row's title and its subtitle

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

--[[--
A translated template set on one baseline: its %1, %2… are `figures`, in `figure_face`, and the words around them in
`word_face`; bold or not. Returns the line and its baseline.
]]
local function figureLine(template, figures, word_face, figure_face, bold)
    local parts, pos = {}, 1
    while true do
        local s, e, n = template:find("%%(%d)", pos)
        local words = template:sub(pos, s and s - 1 or -1)
        if words ~= "" then
            table.insert(parts, text(words, word_face, Palette.ink, nil, bold))
        end
        if not s then break end
        table.insert(parts, text(tostring(figures[tonumber(n)]), figure_face, Palette.ink, nil, bold))
        pos = e + 1
    end
    local baseline = 0
    for __, part in ipairs(parts) do
        baseline = math.max(baseline, part:getBaseline())
    end
    local line = HorizontalGroup:new{ align = "top" }
    for __, part in ipairs(parts) do
        table.insert(line, VerticalGroup:new{ VerticalSpan:new{ width = baseline - part:getBaseline() }, part })
    end
    return line, baseline
end

--- A row's icon in a 37dp rule-gray ring.
local Ring = Widget:extend{
    icon = nil,
    dim = nil,
}

function Ring:init()
    self.dimen = Geom:new{ w = RING, h = RING }
    self.glyph = IconWidget:new{ icon = self.icon, width = RING_ICON, height = RING_ICON, alpha = true, dim = self.dim }
end

function Ring:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintBorder(x, y, RING, RING, Size.border.default, Palette.rule, math.floor(RING / 2),
        G_reader_settings:nilOrTrue("anti_alias_ui"))
    local offset = math.floor((RING - RING_ICON) / 2)
    self.glyph:paintTo(bb, x + offset, y + offset)
end

function Ring:free()
    self.glyph:free()
end

local MeView = InputContainer:extend{
    ui = nil, -- the FileManager
    width = nil,
    height = nil,
}

function MeView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.inner_w = self.width - 2 * GUTTER
    self.home_w = self.width - 2 * HOME_GUTTER
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
        local time = Me.readingTime()
        self.home = {
            name = Me.name(),
            total_minutes = time.total_minutes,
            week_minutes = time.week_minutes,
            streak = Me.streak(),
            note_count = Me.noteCount(),
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

-- Hours and minutes of `minutes`.
local function hoursMinutes(minutes)
    return math.floor(minutes / 60), minutes % 60
end

--- The name, then the reading time, each line on its baseline as measured, the measures growing with the interface
-- font size. Returns the header and its lines' Tappables (the name; the time, without the statistics plugin nil).
function MeView:buildHeader()
    local home = self.home
    local name = text(home.name, Font:getFace("ui_headword", NAME_SIZE), Palette.ink, self.home_w)
    local lines = { { widget = name, baseline = name:getBaseline(), at = NAME_BASELINE } }
    if self.ui.statistics then
        local total_h, total_min = hoursMinutes(home.total_minutes)
        local week_h, week_min = hoursMinutes(home.week_minutes)
        -- @translators On the Me page: all the reading time recorded, %1 hours and %2 minutes; the numbers are shown large. Chinese: 累计阅读 %1 小时 %2 分钟
        local total, total_baseline = figureLine(_("Total reading %1 h %2 min"), { total_h, total_min },
            "ui_label", Font:getFace("ui_headline", FIGURE_SIZE), true)
        -- @translators On the Me page, under the total reading time: this week's, %1 hours and %2 minutes, and %3 days in a row with reading. Chinese: 本周阅读 %1 小时 %2 分钟 | 连续 %3 天
        local week, week_baseline = figureLine(_("This week %1 h %2 min | %3-day streak"),
            { week_h, week_min, home.streak }, "ui_label", "ui_caption")
        table.insert(lines, { widget = total, baseline = total_baseline, at = TOTAL_BASELINE })
        table.insert(lines, { widget = week, baseline = week_baseline, at = WEEK_BASELINE })
    else
        -- @translators On the Me page in place of the reading time, while the reading statistics plugin is disabled.
        local off = text(_("Reading statistics are off"), "ui_label", Palette.ink_3, self.home_w)
        table.insert(lines, { widget = off, baseline = off:getBaseline(), at = TOTAL_BASELINE })
    end
    local scale = Font:getUIScale()
    local group = VerticalGroup:new{ align = "left" }
    local bottom = 0 -- of the lines so far
    for __, line in ipairs(lines) do
        local top = math.floor(line.at * scale) - line.baseline
        table.insert(group, VerticalSpan:new{ width = top - bottom })
        table.insert(group, line.widget)
        bottom = top + line.widget:getSize().h
    end
    table.insert(group, VerticalSpan:new{ width = math.max(math.floor(HEADER_H * scale), bottom) - bottom })
    -- the name's tap reaches down to the time, the time's down to the rule
    local name_h = group[1].width + name:getSize().h
    local name_tap = ShelfWidgets.Tappable:new{
        callback = function() self:editName() end,
        LeftContainer:new{ dimen = Geom:new{ w = self.home_w, h = name_h }, VerticalSpan:new{ width = 0 } },
    }
    local time_tap = self.ui.statistics and ShelfWidgets.Tappable:new{
        callback = function() self.ui.statistics:onShowReaderProgress() end,
        LeftContainer:new{ dimen = Geom:new{ w = self.home_w, h = group:getSize().h - name_h },
            VerticalSpan:new{ width = 0 } },
    }
    return group, name_tap, time_tap
end

--- Edits the nickname: saved, it shows at once; saved empty, the KOSync user name or the device model shows again.
function MeView:editName()
    local dialog
    dialog = InputDialog:new{
        -- @translators Title of the dialog editing the name shown on the Me page.
        title = _("Nickname"),
        input = Me.nickname() or "",
        input_hint = Me.defaultName(), -- what saving it empty shows
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    UIManager:close(dialog)
                    Me.setNickname(dialog:getInputText())
                    self.home.name = Me.name()
                    if not self.subpage then
                        self:build()
                        UIManager:setDirty(self.ui, "ui", self.dimen)
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- A home row's title over its subtitle, `w` wide.
local function rowText(title, subtitle, color, w)
    return VerticalGroup:new{
        align = "left",
        text(title, "ui_title_large", color, w),
        VerticalSpan:new{ width = TITLE_GAP },
        text(subtitle, "ui_label", color, w),
    }
end

--- A home row `h` tall (94dp, less where the screen is short): a ringed icon, a bold title over a subtitle and a
-- chevron; dimmed without a callback. `row` is one of homeRows().
function MeView:homeRow(row, h)
    local text_w = self.home_w - RING - RING_GAP - CHEV_W
    local inner_h = h - Size.border.default
    return ShelfWidgets.Tappable:new{
        callback = row.callback,
        VerticalGroup:new{
            HorizontalGroup:new{
                CenterContainer:new{ dimen = Geom:new{ w = RING, h = inner_h },
                    Ring:new{ icon = row.icon, dim = not row.callback or nil } },
                HorizontalSpan:new{ width = RING_GAP },
                LeftContainer:new{ dimen = Geom:new{ w = text_w, h = inner_h },
                    rowText(row.title, row.subtitle, row.callback and Palette.ink or Palette.ink_3, text_w - dp(12)) },
                CenterContainer:new{ dimen = Geom:new{ w = CHEV_W, h = inner_h },
                    row.callback and IconWidget:new{ icon = "eink/me.chev", width = CHEV_W, height = CHEV_H, alpha = true }
                        or HorizontalSpan:new{ width = 0 } },
            },
            rule(self.home_w, Palette.rule),
        },
    }
end

-- The home rows, top to bottom: { icon, title, subtitle, callback (nil: dimmed) }.
function MeView:homeRows()
    local home = self.home
    return {
        {
            icon = "eink/me.notes",
            -- @translators On the Me page and as its page title: the notes of all books together (not the notes of a whole book). Chinese: 全部书笔记
            title = C_("Me page", "Notes in all books"),
            -- @translators On the Me page, under 全部书笔记: the notes of all books, highlights, thoughts and bookmarks together.
            subtitle = T(N_("1 note", "%1 notes", home.note_count), home.note_count),
            callback = function() self:open("notes") end,
        },
        {
            icon = "eink/me.vocabulary", title = C_("Me page", "Vocabulary"), subtitle = T(_("%1 words"), home.word_count),
            callback = function() self:open("vocab") end,
        },
        -- 文件 shows in the file manager's content area, on the folder named here; its back arrow returns here
        {
            icon = "eink/folder", title = _("Files"), subtitle = BD.dirpath(self.ui.file_chooser.path),
            callback = function() self.ui:openFiles() end,
        },
        {
            icon = "eink/me.sync", title = _("Sync and transfer"), subtitle = "KOSync · Calibre · OPDS",
            callback = function() self:open("sync") end,
        },
        {
            icon = "eink/me.settings", title = _("Settings"), subtitle = _("Reading · Screen · Network · Device"),
            callback = function() self.ui:handleEvent(Event:new("ShowEinkSettings")) end,
        },
        {
            icon = "eink/me.update",
            -- @translators On the Me page: checks for a new version of KOReader. Chinese: 版本更新
            title = C_("Me page", "Version update"),
            -- @translators On the Me page, under 版本更新: the version running.
            subtitle = T(_("Current version %1"), Version:getShortVersion()),
            callback = Device:hasOTAUpdates() and function() require("ui/otamanager"):fetchAndProcessUpdate() end or nil,
        },
    }
end

function MeView:buildHome()
    local header, name_tap, time_tap = self:buildHeader()
    local rows = self:homeRows()
    -- the rows keep their height where it fits (the Leaf5, portrait), and share what is left under the rule otherwise
    local probe = rowText("0", "0")
    local row_h = math.max(probe:getSize().h + dp(12), math.min(HOME_ROW_H,
        math.floor((self.height - header:getSize().h - Size.border.default) / #rows)))
    probe:free()
    local list = VerticalGroup:new{ align = "left", rule(self.home_w, Palette.rule) }
    for __, row in ipairs(rows) do
        table.insert(list, self:homeRow(row, row_h))
    end
    self.name_tap, self.time_tap = name_tap, time_tap
    local taps = VerticalGroup:new{ align = "left", name_tap }
    if time_tap then table.insert(taps, time_tap) end
    return FrameContainer:new{
        bordersize = 0, padding = 0, padding_left = HOME_GUTTER, padding_right = HOME_GUTTER,
        VerticalGroup:new{
            align = "left",
            OverlapGroup:new{
                dimen = Geom:new{ w = self.home_w, h = header:getSize().h },
                header,
                taps,
            },
            list,
        },
    }
end

-- subpage => title and the method measuring its list rows
local subpages = {
    notes = { title = function() return C_("Me page", "Notes in all books") end, items = "notesItems" },
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
-- position it opened on for going back to it (ReaderLink, the Back key), as the contents page does.
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
        -- @translators On the notes of all books, while there are none.
        return { self:emptyItem(_("No notes yet"), _("Long-press text in a book to highlight it or write a thought, or bookmark a page from the toolbar.")) }
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
        local kosync = Me.kosyncSettings()
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
