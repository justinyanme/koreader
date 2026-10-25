describe("Shelf home, 我 tab", function()
    local BookList, DataStorage, Device, DocSettings, Event, FileManager, Geom, LuaSettings, Me, ReadHistory
    local ReaderUI, Replacements, SQ3, Screen, UIManager, Version
    local ffiUtil, lfs, T, _, C_, N_
    local home, saved_settings, saved_hist, saved_dbs
    local SETTINGS = { "home_dir", "lastdir", "shelf_removed", "me_nickname" } -- changed here, restored after
    local today -- this week's day of today, Monday = 1

    -- minutes read N days before today; the week runs from Monday
    local reading = { [0] = 25, [1] = 40, [2] = 10, [4] = 60, [10] = 300 }

    local function dayAt(offset, hour)
        local t = os.date("*t")
        return os.time{ year = t.year, month = t.month, day = t.day - offset, hour = hour }
    end

    -- A statistics database as the plugin keeps it: page reading sessions `{ start_time, seconds }` of one book,
    -- the index on their start times, and the book's total.
    local function writeStats(path, sessions)
        os.remove(path)
        local conn = SQ3.open(path)
        conn:exec([[
            CREATE TABLE book (id integer PRIMARY KEY autoincrement, title text, authors text, notes integer,
                last_open integer, highlights integer, pages integer, series text, language text, md5 text,
                total_read_time integer, total_read_pages integer);
            CREATE TABLE page_stat_data (id_book integer, page integer NOT NULL DEFAULT 0,
                start_time integer NOT NULL DEFAULT 0, duration integer NOT NULL DEFAULT 0,
                total_pages integer NOT NULL DEFAULT 0, UNIQUE (id_book, page, start_time));
            CREATE INDEX page_stat_data_start_time ON page_stat_data(start_time);
        ]])
        local total = 0
        for i, session in ipairs(sessions) do
            conn:exec(string.format("INSERT INTO page_stat_data VALUES (1, %d, %d, %d, 100);", i, session[1], session[2]))
            total = total + session[2]
        end
        conn:exec(string.format("INSERT INTO book (id, title, total_read_time, total_read_pages) VALUES (1, 'A book', %d, %d);",
            total, #sessions))
        conn:close()
    end

    local function seedStats(path)
        local sessions = {}
        for offset, minutes in pairs(reading) do
            -- two sessions per day, to check they add up
            local first = math.floor(minutes * 60 / 3)
            table.insert(sessions, { dayAt(offset, 9), first })
            table.insert(sessions, { dayAt(offset, 21), minutes * 60 - first })
        end
        writeStats(path, sessions)
    end

    local function seedVocab(path)
        os.remove(path)
        local conn = SQ3.open(path)
        conn:exec([[
            CREATE TABLE vocabulary (word TEXT NOT NULL UNIQUE, title_id INTEGER, create_time INTEGER NOT NULL,
                review_time INTEGER, due_time INTEGER NOT NULL, review_count INTEGER NOT NULL DEFAULT 0,
                prev_context TEXT, next_context TEXT, streak_count INTEGER NOT NULL DEFAULT 0, highlight TEXT);
            CREATE TABLE title (id INTEGER NOT NULL UNIQUE, name TEXT UNIQUE, filter INTEGER NOT NULL DEFAULT 1);
            INSERT INTO title VALUES (1, 'Walden', 1);
            INSERT INTO vocabulary (word, title_id, create_time, due_time, prev_context, next_context)
                VALUES ('sojourner', 1, 1000, 1000, 'At present I am a ', ' in civilized life again.');
            INSERT INTO vocabulary (word, title_id, create_time, due_time) VALUES ('囫囵吞枣', 1, 2000, 2000);
        ]])
        conn:close()
    end

    local function addBook(name, source, title, annotations, summary, last_read)
        local path = home .. "/" .. name
        ffiUtil.copyFile("spec/front/unit/data/" .. source, path)
        local doc_settings = DocSettings:open(path)
        doc_settings:saveSetting("doc_props", { title = title })
        doc_settings:saveSetting("annotations", annotations)
        if summary then doc_settings:saveSetting("summary", summary) end
        doc_settings:flush()
        BookList.resetBookInfoCache(path)
        ReadHistory:addItem(path, last_read, true) -- not flushed: the real history file is left alone
        return path
    end

    local function highlight(text, chapter)
        return { drawer = "lighten", text = text, chapter = chapter, page = "/body/p[1]", pos0 = "/body/p[1].0",
            pos1 = "/body/p[1].5", datetime = "2026-10-01 10:00:00" }
    end

    local function spyRefreshes()
        local refreshes = {}
        local orig_setDirty = UIManager.setDirty
        UIManager.setDirty = function(self, widget, refreshtype, region, ...)
            if refreshtype then table.insert(refreshes, { type = refreshtype, region = region }) end
            return orig_setDirty(self, widget, refreshtype, region, ...)
        end
        return refreshes, function() UIManager.setDirty = orig_setDirty end
    end

    local tap -- defined below

    -- 我 opened with a tap on its tab; with `statistics`, in place of the statistics plugin (not loaded otherwise)
    local function openMe(statistics)
        FileManager:showFiles(home)
        UIManager:forceRePaint()
        local fm = FileManager.instance
        if statistics then fm.statistics = statistics end
        local tab
        local function findTab(w)
            if type(w) ~= "table" or tab then return end
            if w.callback and w.dimen and w.dimen.x then
                for _, child in ipairs(w) do
                    if type(child) == "table" and (child.icon == "eink/user" or (child[1] and child[1].icon == "eink/user")) then
                        tab = w
                        return
                    end
                end
            end
            for _, child in ipairs(w) do findTab(child) end
        end
        findTab(fm.layout_group[2])
        tap(tab.dimen)
        assert.are.equal("me", fm.current_tab)
        return fm, fm.me_view
    end

    -- the statistics plugin, as far as 我 uses it: its reading progress page, on controlled data
    local function fakeStatistics()
        local ReaderProgress = dofile("plugins/statistics.koplugin/readerprogress.lua")
        return {
            ReaderProgress = ReaderProgress,
            onShowReaderProgress = function()
                local week = {}
                for i = 1, 7 do
                    table.insert(week, { 12, 600, os.date("%Y-%m-%d", os.time() - (i - 1) * 86400) })
                end
                UIManager:show(ReaderProgress:new{
                    dates = week, current_duration = 600, current_pages = 12, today_duration = 600, today_pages = 12,
                })
            end,
        }
    end

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    -- Input is sent the way it arrives, and the screen is repainted after it.
    function tap(rect)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap",
            pos = Geom:new{ x = rect.x + math.floor(rect.w / 2), y = rect.y + math.floor(rect.h / 2), w = 0, h = 0 } }))
        UIManager:forceRePaint()
    end

    -- the first widget under `widget` that `pred` accepts
    local function find(widget, pred)
        if type(widget) ~= "table" then return end
        if pred(widget) then return widget end
        for _, child in ipairs(widget) do
            local found = find(child, pred)
            if found then return found end
        end
    end

    local function textWidget(widget, str)
        return find(widget, function(w) return w.text == str and w.face ~= nil end)
    end

    -- the Tappable (a home row, the name, the time) holding the text `str`
    local function tappable(widget, str)
        return find(widget, function(w) return w.callback ~= nil and w.dimen ~= nil and textWidget(w, str) ~= nil end)
    end

    -- the home rows shown, top to bottom: { title, subtitle, row }
    local function shownRows(view)
        local rows = {}
        find(view[1], function(w)
            if getmetatable(w) and getmetatable(w).__index == require("apps/shelf/shelfwidgets").Tappable
                    and w ~= view.name_tap and w ~= view.time_tap then
                local strs = {}
                find(w, function(c) if c.text and c.face then table.insert(strs, c.text) end return false end)
                table.insert(rows, { strs[1], strs[2], w })
            end
            return false
        end)
        return rows
    end

    local function writeKOSync(settings)
        local kosync = LuaSettings:open(Me.kosync_settings)
        kosync:saveSetting("settings", settings)
        kosync:flush()
    end

    -- the text of every TextWidget/TextBoxWidget under `widget`
    local function texts(widget, out)
        out = out or {}
        if type(widget) ~= "table" then return out end
        if widget.text and (widget.face) then table.insert(out, widget.text) end
        for _, child in ipairs(widget) do texts(child, out) end
        return out
    end

    -- a swipe sent the way input arrives: through the file manager's event dispatch
    local function swipe(fm, direction, x, y)
        local screen = require("device").screen
        fm:handleEvent(Event:new("Gesture", {
            ges = "swipe", direction = direction, distance = 200, time = 0,
            pos = Geom:new{ x = x or screen:getWidth() / 2, y = y or screen:getHeight() / 2, w = 0, h = 0 },
        }))
    end

    -- the tap callback of an entry row
    local function tapRow(view, i)
        view.items[i].build().callback()
    end

    local function contains(list, value)
        for _, v in ipairs(list) do
            if v == value then return true end
        end
        return false
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        BookList = require("ui/widget/booklist")
        DataStorage = require("datastorage")
        Device = require("device")
        DocSettings = require("docsettings")
        Event = require("ui/event")
        FileManager = require("apps/filemanager/filemanager")
        Geom = require("ui/geometry")
        LuaSettings = require("luasettings")
        Me = require("apps/shelf/me")
        ReadHistory = require("readhistory")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        SQ3 = require("lua-ljsqlite3/init")
        Screen = Device.screen
        UIManager = require("ui/uimanager")
        Version = require("version")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        T = ffiUtil.template
        _ = require("gettext")
        C_ = _.pgettext
        N_ = _.ngettext
        require("apps/shelf/shelffilemanager") -- registers the replacement

        saved_settings = {}
        for _, key in ipairs(SETTINGS) do
            saved_settings[key] = G_reader_settings:readSetting(key)
        end
        G_reader_settings:delSetting("me_nickname")
        saved_hist = ReadHistory.hist
        ReadHistory.hist = {}
        saved_dbs = { Me.stats_db, Me.vocab_db, Me.kosync_settings }
        local data_dir = ffiUtil.realpath(DataStorage:getDataDir())
        Me.stats_db = data_dir .. "/me_spec_statistics.sqlite3"
        Me.vocab_db = data_dir .. "/me_spec_vocabulary.sqlite3"
        Me.kosync_settings = data_dir .. "/me_spec_kosync.lua"
        os.remove(Me.kosync_settings)
        seedStats(Me.stats_db)
        seedVocab(Me.vocab_db)

        home = data_dir .. "/me_home"
        ffiUtil.purgeDir(home)
        lfs.mkdir(home)
        G_reader_settings:saveSetting("home_dir", home)
        local year = os.date("%Y")
        addBook("juliet.epub", "juliet.epub", "Romeo and Juliet", {
            highlight("Two households, both alike in dignity", "Prologue"),
            { page = "/body/p[3]", text = "a bookmark, not a note", chapter = "Act 1", datetime = "2026-10-02 10:00:00" },
            highlight("In fair Verona, where we lay our scene", "Prologue"),
        }, { status = "complete", modified = year .. "-03-01" }, 2000)
        addBook("leaves.epub", "leaves.epub", "Leaves of Grass", {
            highlight("I celebrate myself", "Song of Myself"),
        }, { status = "complete", modified = "2001-01-01" }, 1000)
        -- finished this year before the time it was marked was recorded: counted by its `modified` date
        addBook("legacy.pdf", "sample.pdf", "Finished before the time was kept", {},
            { status = "complete", modified = year .. "-04-01" }, 400)
        -- finished last year; a review written this year moved `modified`, not the year it was finished
        addBook("sample.pdf", "sample.pdf", "No notes here", {}, {
            status = "complete", finished_time = os.time{ year = year - 1, month = 6, day = 1, hour = 12 },
            modified = year .. "-02-01",
        }, 500)

        today = (os.date("*t").wday + 5) % 7 + 1
    end)

    teardown(function()
        if FileManager.instance then FileManager.instance:onClose() end
        ReadHistory.hist = saved_hist
        os.remove(Me.kosync_settings)
        Me.stats_db, Me.vocab_db, Me.kosync_settings = saved_dbs[1], saved_dbs[2], saved_dbs[3]
        for _, key in ipairs(SETTINGS) do
            if saved_settings[key] == nil then
                G_reader_settings:delSetting(key)
            else
                G_reader_settings:saveSetting(key, saved_settings[key])
            end
        end
        G_reader_settings:flush()
        Replacements.filemanager = nil
        ffiUtil.purgeDir(home)
    end)

    it("shows the name, the reading time and the streak over six rows, without a weekly chart", function()
        local fm, view = openMe(fakeStatistics())
        assert.are.equal(view, fm.content[1])
        assert.are.equal("me", fm.current_tab)

        -- every day recorded, and this week's from Monday; days in a row up to today
        local total, week = 0, 0
        for offset, minutes in pairs(reading) do
            total = total + minutes
            if offset < today then week = week + minutes end
        end
        assert.are.same({ name = Device.model, total_minutes = total, week_minutes = week, streak = 3,
            note_count = 4, word_count = 2 }, view.home)
        -- 累计阅读 X 小时 Y 分钟 with figure-sized numbers, then 本周阅读 … | 连续 N 天
        local shown = table.concat(texts(view))
        assert.is_truthy(shown:find(T(_("Total reading %1 h %2 min"), math.floor(total / 60), total % 60), 1, true))
        assert.is_truthy(shown:find(T(_("This week %1 h %2 min | %3-day streak"),
            math.floor(week / 60), week % 60, 3), 1, true))
        local name = textWidget(view, Device.model)
        local hours = textWidget(view, tostring(math.floor(total / 60)))
        local minutes = textWidget(view, tostring(total % 60))
        assert.are.equal(28, name.face.orig_size)
        assert.is_truthy(name.face.realname:find("Serif"))
        assert.are.equal(24, hours.face.orig_size)
        assert.are.equal(24, minutes.face.orig_size)
        -- the name's tap above the time's
        local name_tap, time_tap = view.name_tap.dimen, view.time_tap.dimen
        assert.are.equal(name_tap.y + name_tap.h, time_tap.y)
        assert.is_nil(view.chart)
        assert.is_nil(textWidget(view, _("Reading this week")))

        -- the rows, in the ruling's order, each with its real subtitle
        local rows = shownRows(view)
        local expected = {
            { C_("Me page", "Notes in all books"), T(N_("1 note", "%1 notes", 4), 4) },
            { C_("Me page", "Vocabulary"), T(_("%1 words"), 2) },
            { _("Files"), home },
            { _("Sync and transfer"), "KOSync · Calibre · OPDS" },
            { _("Settings"), _("Reading · Screen · Network · Device") },
            { C_("Me page", "Version update"), T(_("Current version %1"), Version:getShortVersion()) },
        }
        assert.are.equal(#expected, #rows)
        local content = fm.content_dimen
        for i, row in ipairs(rows) do
            assert.are.same(expected[i], { row[1], row[2] })
            -- 94dp rows under the time, as in the reference, each led by a ringed icon, all above the tab bar
            assert.are.equal(Screen:scaleBySize(94), row[3].dimen.h)
            assert.is_true(row[3].dimen.y >= view.time_tap.dimen.y + view.time_tap.dimen.h)
            assert.is_true(row[3].dimen.y + row[3].dimen.h <= content.y + content.h)
            assert.is_truthy(find(row[3], function(w) return w.glyph ~= nil end))
            -- a chevron where the row leads somewhere
            assert.are.equal(row[3].callback ~= nil, find(row[3], function(w) return w.icon == "eink/me.chev" end) ~= nil)
        end
        for i = 1, 5 do
            assert.is_truthy(rows[i][3].callback)
        end
        assert.is_true(rows[1][3].dimen.y <= Screen:scaleBySize(140))
        fm:onClose()
    end)

    it("opens the reading progress from the reading time, and says when the statistics plugin is off", function()
        local statistics = fakeStatistics()
        local fm, view = openMe(statistics)
        tap(view.time_tap.dimen)
        local progress = topWidget()
        assert.are.equal(statistics.ReaderProgress, getmetatable(progress).__index)
        progress:onClose()
        UIManager:forceRePaint()
        assert.are.equal(fm, topWidget())
        fm:onClose()

        -- without the plugin: no time to show, nothing to tap, and no number made up
        fm, view = openMe()
        assert.is_nil(view.time_tap)
        assert.is_truthy(textWidget(view, _("Reading statistics are off")))
        assert.is_nil(tappable(view, _("Reading statistics are off")))
        assert.is_nil(textWidget(view, tostring(view.home.total_minutes % 60)))
        fm:onClose()
    end)

    it("names the reader by the nickname, else the KOSync user name, else the device model, and edits it", function()
        local fm, view = openMe()
        assert.are.equal(Device.model, view.home.name)
        fm:onClose()
        -- logged out of KOSync, the user name is kept and still names the reader
        writeKOSync{ username = "kosync-reader" }
        fm, view = openMe()
        assert.are.equal("kosync-reader", view.home.name)
        assert.is_truthy(textWidget(view, "kosync-reader"))

        local function nameDialog()
            tap(view.name_tap.dimen)
            local dialog = topWidget()
            assert.are.equal(require("ui/widget/inputdialog"), getmetatable(dialog).__index)
            return dialog
        end
        local function button(dialog, label)
            return find(dialog, function(w) return w.text == label and w.callback ~= nil and w.dimen ~= nil end)
        end

        -- the field holds the nickname only: the name shown is its hint
        local dialog = nameDialog()
        assert.are.equal("", dialog:getInputText())
        assert.are.equal("kosync-reader", dialog.input_hint)
        dialog:setInputText("  小明  ")
        local refreshes, restore = spyRefreshes()
        tap(button(dialog, _("Save")).dimen)
        restore()
        assert.are.equal(fm, topWidget())
        assert.are.equal("小明", view.home.name)
        assert.is_truthy(textWidget(view, "小明"))
        -- the page repaints with "ui" (the button's own flash aside), nothing flashes
        local covered = false
        for _, r in ipairs(refreshes) do
            -- the dialog closing asks for "ui" over itself through a function
            local mode, region = r.type, r.region
            if type(mode) == "function" then mode, region = mode() end
            assert.is_true(mode == "ui" or mode == "fast", mode)
            if mode == "ui" and region and region:contains(view.name_tap.dimen) then covered = true end
        end
        assert.is_true(covered)
        -- written at once: a restart reads it
        assert.are.equal("小明", LuaSettings:open(G_reader_settings.file):readSetting("me_nickname"))

        -- cancel keeps it; the hint still says what an empty name shows
        dialog = nameDialog()
        assert.are.equal("小明", dialog:getInputText())
        assert.are.equal("kosync-reader", dialog.input_hint)
        dialog:setInputText("someone else")
        tap(button(dialog, _("Cancel")).dimen)
        assert.are.equal(fm, topWidget())
        assert.are.equal("小明", G_reader_settings:readSetting("me_nickname"))
        assert.is_truthy(textWidget(view, "小明"))
        fm:onClose()

        -- kept on the next visit; saved empty, the KOSync user name, then the device model come back
        fm, view = openMe()
        assert.is_truthy(textWidget(view, "小明"))
        dialog = nameDialog()
        dialog:setInputText(" ")
        tap(button(dialog, _("Save")).dimen)
        assert.is_nil(G_reader_settings:readSetting("me_nickname"))
        assert.is_nil(LuaSettings:open(G_reader_settings.file):readSetting("me_nickname"))
        assert.is_truthy(textWidget(view, "kosync-reader"))
        fm:onClose()
        os.remove(Me.kosync_settings)
        fm, view = openMe()
        assert.is_truthy(textWidget(view, Device.model))
        fm:onClose()
    end)

    it("shows the version and how to update this build from 版本更新, never checking KOReader's updates", function()
        local OTAManager = require("ui/otamanager")
        local InfoMessage = require("ui/widget/infomessage")
        local orig_has, orig_check, orig_fetch = Device.hasOTAUpdates, OTAManager.checkUpdate, OTAManager.fetchAndProcessUpdate
        local checks = 0
        OTAManager.checkUpdate = function() checks = checks + 1 end
        OTAManager.fetchAndProcessUpdate = function() checks = checks + 1 end
        local ok, err = pcall(function()
            -- even where KOReader could update the device: its updates are upstream builds, which would replace this one
            for __, has_ota in ipairs{ true, false } do
                Device.hasOTAUpdates = function() return has_ota end
                local fm, view = openMe()
                local row = shownRows(view)[6]
                assert.are.equal(C_("Me page", "Version update"), row[1])
                assert.are.equal(T(_("Current version %1"), Version:getShortVersion()), row[2])
                assert.is_truthy(find(row[3], function(w) return w.icon == "eink/me.chev" end))
                tap(row[3].dimen)
                local info = topWidget()
                assert.are.equal(InfoMessage, getmetatable(info).__index)
                -- KOReader's About, then how this build is updated
                assert.is_truthy(info.text:find(T(_("KOReader %1\n\nA document viewer for E Ink devices.\n\nLicensed under Affero GPL v3. All dependencies are free software.\n\nhttp://koreader.rocks"),
                    require("ui/bidi").ltr(Version:getCurrentRevision())), 1, true))
                assert.is_truthy(info.text:find(_("This is a custom build made for this device. To update it, install a new APK."), 1, true))
                assert.are.equal(0, checks)
                tap(info.dimen) -- a tap closes it
                assert.are.equal(fm, topWidget())
                fm:onClose()
            end
        end)
        Device.hasOTAUpdates, OTAManager.checkUpdate, OTAManager.fetchAndProcessUpdate = orig_has, orig_check, orig_fetch
        assert(ok, err)
    end)

    it("keeps the version row on the injected iOS device and describes TestFlight installation", function()
        local ios = require("device/sdl/device"):createVariant{
            platform = "iOS", native_bridge = require("iosbridge").new(),
        }
        stub(Device, "hasOTAUpdates", ios.hasOTAUpdates)
        stub(Device, "getUpdateInstructions", ios.getUpdateInstructions)
        local fm
        local ok, err = pcall(function()
            local view
            fm, view = openMe()
            local row = shownRows(view)[6]
            assert.are.equal(C_("Me page", "Version update"), row[1])
            assert.are.equal(T(_("Current version %1"), Version:getShortVersion()), row[2])
            tap(row[3].dimen)
            local info = topWidget()
            assert.is_truthy(info.text:find(_("To update it, install the new build from TestFlight."), 1, true))
            assert.is_nil(info.text:find("APK", 1, true))
            tap(info.dimen)
        end)
        Device.hasOTAUpdates:revert()
        Device.getUpdateInstructions:revert()
        if fm then fm:onClose() end
        assert(ok, err)
    end)

    it("counts days in a row up to yesterday while today has none yet, and as far back as they go", function()
        -- the fixture's days: today, 1 and 2 days ago, then 4 and 10 days ago
        Me.now = function() return dayAt(-1, 12) end -- tomorrow: nothing read yet
        local fm, view = openMe(fakeStatistics())
        assert.are.equal(3, view.home.streak)
        assert.is_truthy(table.concat(texts(view)):find("| " .. T(_("This week %1 h %2 min | %3-day streak"), 0, 0, 3):match("| (.*)$"), 1, true))
        fm:onClose()
        Me.now = function() return dayAt(3, 12) end -- nothing 3 days ago, the day before was read, not the one before it
        fm, view = openMe(fakeStatistics())
        assert.are.equal(1, view.home.streak)
        fm:onClose()
        Me.now = function() return dayAt(5, 12) end -- nothing that day nor the day before
        fm, view = openMe(fakeStatistics())
        assert.are.equal(0, view.home.streak)
        fm:onClose()
        Me.now = os.time

        -- streaks longer than the days looked at first (60): up to the first of them, past it, and far past it
        local saved = Me.stats_db
        Me.stats_db = ffiUtil.realpath(DataStorage:getDataDir()) .. "/me_spec_streak.sqlite3"
        for _, case in ipairs{ { days = 60, gap = true }, { days = 61, gap = true }, { days = 400 } } do
            local sessions = {}
            for offset = 0, case.days - 1 do
                table.insert(sessions, { dayAt(offset, 10), 600 })
            end
            if case.gap then -- a day read after a day without reading
                table.insert(sessions, { dayAt(case.days + 1, 10), 600 })
            end
            writeStats(Me.stats_db, sessions)
            fm, view = openMe(fakeStatistics())
            assert.are.equal(case.days, view.home.streak)
            fm:onClose()
        end
        os.remove(Me.stats_db)
        Me.stats_db = saved
    end)

    it("opens the reading progress of the statistics plugin itself, loaded as KOReader loads it", function()
        local saved = Me.stats_db
        local plugin_db = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        local had_db = lfs.attributes(plugin_db, "mode") == "file"
        load_plugin("statistics.koplugin")
        local ok, err = pcall(function()
            -- the plugin makes its database as it first loads, and says so; a tap dismisses that
            FileManager:showFiles(home)
            UIManager:forceRePaint()
            local fm = FileManager.instance
            assert.are.equal("filemanagerstatistics", fm.statistics.name) -- the plugin, as the file manager names it
            if topWidget() ~= fm then tap(topWidget().dimen) end
            assert.are.equal(fm, topWidget())
            fm:onClose()
            -- a book read today and yesterday, as the plugin records it
            local conn = SQ3.open(plugin_db)
            conn:exec("INSERT INTO book (title, authors, notes, last_open, highlights, pages, series, language, md5, "
                .. "total_read_time, total_read_pages) VALUES ('Romeo and Juliet', 'N/A', 0, 0, 0, 100, 'N/A', 'en', 'me_spec', 5400, 2);")
            local id = tonumber(conn:rowexec("SELECT id FROM book WHERE md5 = 'me_spec';"))
            conn:exec(string.format("INSERT INTO page_stat_data VALUES (%d, 1, %d, 3600, 100);", id, dayAt(0, 9)))
            conn:exec(string.format("INSERT INTO page_stat_data VALUES (%d, 2, %d, 1800, 100);", id, dayAt(1, 9)))
            conn:close()
            Me.stats_db = plugin_db
            local view
            fm, view = openMe()
            assert.is_true(view.home.total_minutes >= 90)
            assert.is_true(view.home.streak >= 2)
            tap(view.time_tap.dimen)
            local progress = topWidget()
            assert.are.equal(package.loaded["readerprogress"], getmetatable(progress).__index)
            progress:onClose()
            UIManager:forceRePaint()
            assert.are.equal(fm, topWidget())
            fm:onClose()
        end)
        Me.stats_db = saved
        disable_plugins()
        if not had_db then
            for _, suffix in ipairs{ "", "-wal", "-shm", "-journal" } do os.remove(plugin_db .. suffix) end
        end
        assert(ok, err)
    end)

    it("keeps every row on screen in landscape, at a tappable height", function()
        local fm = openMe(fakeStatistics())
        local rotation = Screen:getRotationMode()
        fm:onSetRotationMode(rotation == 0 and 1 or 0)
        fm = FileManager.instance
        UIManager:forceRePaint()
        local ok, err = pcall(function()
            assert.is_true(Screen:getWidth() > Screen:getHeight())
            assert.are.equal("me", fm.current_tab)
            local rows = shownRows(fm.me_view)
            assert.are.equal(6, #rows)
            local content = fm.content_dimen
            for _, row in ipairs(rows) do
                assert.is_true(row[3].dimen.h >= Screen:scaleBySize(44))
                assert.is_true(row[3].dimen.y + row[3].dimen.h <= content.y + content.h)
            end
        end)
        FileManager.instance:onSetRotationMode(rotation)
        FileManager.instance:onClose()
        assert(ok, err)
    end)

    it("lists every book's notes grouped by book, bookmarks included, and opens a note's book", function()
        local fm, view = openMe()
        assert.is_true(contains(texts(view), T(N_("1 note", "%1 notes", 4), 4)))
        tap(tappable(view, C_("Me page", "Notes in all books")).dimen)
        assert.are.equal("notes", view.subpage)
        assert.is_truthy(textWidget(view, C_("Me page", "Notes in all books")))
        local shown = texts(view)
        -- last read book first; the bookmark counts as a note, as on the book's notes page
        local first = T(_("%1 · %2 notes"), "Romeo and Juliet", 3)
        local second = T(_("%1 · %2 notes"), "Leaves of Grass", 1)
        assert.is_true(contains(shown, first))
        assert.is_true(contains(shown, second))
        local function index(value) for i, v in ipairs(shown) do if v == value then return i end end end
        assert.is_true(index(first) < index(second))
        assert.is_nil(index("No notes here"))
        -- a row per note: the bookmark in book order, with a bookmark in place of the highlight style, reading
        -- its chapter (its own text is not the book's)
        local rows = {}
        local function collect(w)
            if type(w) ~= "table" then return end
            if type(w.note) == "table" then table.insert(rows, w) end
            for __, child in ipairs(w) do collect(child) end
        end
        collect(view)
        assert.are.equal(4, #rows)
        assert.are.equal(2, #view.books)
        assert.are.equal(3, #view.books[1].notes)
        assert.are.equal(1, #view.books[2].notes)
        local bookmark = rows[2]
        assert.is_nil(bookmark.note.drawer)
        assert.is_truthy(find(bookmark, function(w) return w.icon == "eink/bookmark" end))
        assert.is_truthy(textWidget(bookmark, "Act 1"))
        assert.is_false(contains(shown, "a bookmark, not a note"))
        assert.is_nil(find(rows[1], function(w) return w.icon == "eink/bookmark" end))

        -- a tap on a note opens its book, pushes the position it opened on, then jumps to the note: a highlight
        -- to its text, a bookmark to its page
        local orig = ReaderUI.showReader
        local function tapNote(row)
            local opened
            ReaderUI.showReader = function(_, file, _, _, _, after_open) opened = { file = file, after_open = after_open } end
            tap(row.dimen)
            ReaderUI.showReader = orig
            local calls = {}
            opened.after_open{
                link = { addCurrentLocationToStack = function() table.insert(calls, "stack") end },
                bookmark = { gotoBookmark = function(_, page, pos0) table.insert(calls, { page, pos0 }) end },
            }
            return opened.file, calls
        end
        local file, calls = tapNote(rows[4])
        local note = view.books[2].notes[1]
        assert.are.equal(home .. "/leaves.epub", file)
        assert.are.same({ "stack", { note.page, note.pos0 } }, calls)
        file, calls = tapNote(bookmark)
        assert.are.equal(home .. "/juliet.epub", file)
        assert.are.same({ "stack", { "/body/p[3]" } }, calls)

        -- notes are dropped with the subpage
        view:close()
        assert.is_nil(view.books)
        fm:onClose()
    end)

    it("lists the vocabulary, newest first", function()
        local fm, view = openMe()
        assert.is_true(contains(texts(view), T(_("%1 words"), 2)))
        tap(tappable(view, C_("Me page", "Vocabulary")).dimen)
        assert.are.equal("vocab", view.subpage)
        local shown = texts(view)
        assert.are.equal("囫囵吞枣", view.words[1].word)
        assert.are.equal("sojourner", view.words[2].word)
        assert.is_true(contains(shown, "sojourner"))
        local context
        for __, str in ipairs(shown) do
            context = context or str:find("At present I am a sojourner in civilized life again.", 1, true)
        end
        assert.is_truthy(context)
        fm:onClose()
    end)

    it("enters and leaves subpages with ui refreshes of the content area only", function()
        local fm, view = openMe()
        fastforward_ui_events()
        local refreshes, restore = spyRefreshes()
        for _, kind in ipairs{ "notes", "vocab", "sync" } do
            view:open(kind)
            assert.are.equal(kind, view.subpage)
            assert.is_true(view:onBack())
            assert.is_nil(view.subpage)
        end
        -- on the home page, Back is left to the file manager
        assert.is_false(view:onBack())
        restore()
        assert.are.equal(6, #refreshes)
        for _, r in ipairs(refreshes) do
            assert.are.equal("ui", r.type)
            assert.is_true(r.region.y + r.region.h <= fm.content_dimen.y + fm.content_dimen.h)
        end
        fm:onClose()
    end)

    it("pages a long list under the nav bar, with swipes through the file manager", function()
        local fm, view = openMe()
        local orig = Me.notes
        Me.notes = function()
            local books = orig()
            for i = 1, 40 do
                table.insert(books[1].notes, highlight("Highlight number " .. i, "Prologue"))
            end
            return books
        end
        view:open("notes")
        assert.is_true(#view.pages > 1)
        local shelf_page = fm.shelf_view.page
        local refreshes, restore = spyRefreshes()
        swipe(fm, "west")
        assert.are.equal(2, view.page)
        swipe(fm, "east")
        restore()
        assert.are.equal(1, view.page)
        assert.are.equal(shelf_page, fm.shelf_view.page)
        assert.are.equal(2, #refreshes)
        for _, r in ipairs(refreshes) do
            assert.are.equal("ui", r.type)
            assert.is_true(r.region.y > fm.content_dimen.y)
        end
        -- a rebuild (rotation) keeps the subpage and its page
        view:goToPage(2)
        fm:reinit()
        assert.are.equal("me", fm.current_tab)
        assert.are.equal(fm.me_view, fm.content[1])
        assert.are_not.equal(view, fm.me_view)
        assert.are.equal("notes", fm.me_view.subpage)
        assert.are.equal(2, fm.me_view.page)
        Me.notes = orig
        fm:onClose()
    end)

    it("opens the reorganized settings from the settings row", function()
        local fm, view = openMe()
        local row = find(view, function(w)
            return w.callback and find(w, function(c) return c.text == _("Settings") end) ~= nil
        end)
        row.callback()
        local EinkSettings = require("apps/settings/einksettings")
        local top = UIManager._window_stack[#UIManager._window_stack].widget
        assert.are.equal(EinkSettings, getmetatable(top).__index)
        assert.is_nil(fm.menu.menu_container)
        top:closeMenu()
        fm:onClose()
    end)

    it("leaves the menu swipe to the file manager", function()
        local fm = openMe()
        assert.is_nil(fm.menu.menu_container)
        swipe(fm, "south", nil, 5)
        assert.is_truthy(fm.menu.menu_container)
        fm.menu:onCloseFileManagerMenu()
        fm:onClose()
    end)

    it("exports all notes when the exporter is ready, or opens its settings in the menu", function()
        local fm, view = openMe()
        local ready, exported = false, 0
        fm.exporter = { isReady = function() return ready end, onExportAllNotes = function() exported = exported + 1 end }
        view:open("notes")
        tapRow(view, 1)
        assert.are.equal(0, exported)
        local menu = fm.menu.menu_container[1]
        assert.are.equal("appbar.tools", fm.menu.tab_item_table[menu.cur_tab].icon)
        fm.menu:onCloseFileManagerMenu()
        ready = true
        tapRow(view, 1)
        assert.are.equal(1, exported)
        fm.exporter = nil
        fm:onClose()
    end)

    it("counts a week from Monday 00:00", function()
        local saved = Me.stats_db
        Me.stats_db = ffiUtil.realpath(DataStorage:getDataDir()) .. "/me_spec_week.sqlite3"
        local sunday = os.time{ year = 2026, month = 10, day = 18, hour = 23, min = 59, sec = 0 }
        local monday = os.time{ year = 2026, month = 10, day = 19, hour = 0, min = 0, sec = 0 }
        -- 30s more, on the Monday after: minutes are rounded, as the statistics plugin's pages do
        writeStats(Me.stats_db, { { sunday, 600 }, { monday, 1200 }, { monday + 3600, 30 } })

        Me.now = function() return sunday + 30 end
        local fm, view = openMe(fakeStatistics())
        assert.are.equal(10, view.home.week_minutes)
        assert.are.equal(31, view.home.total_minutes) -- all that is recorded: 30 min 30 s
        fm:onClose()

        Me.now = function() return monday + 30 end
        fm, view = openMe(fakeStatistics())
        assert.are.equal(21, view.home.week_minutes)
        assert.are.equal(31, view.home.total_minutes)
        assert.are.equal(2, view.home.streak)
        assert.is_truthy(table.concat(texts(view)):find(T(_("Total reading %1 h %2 min"), 0, 31), 1, true))
        fm:onClose()

        Me.now = os.time
        os.remove(Me.stats_db)
        Me.stats_db = saved
    end)

    it("reads a missing or older database as empty", function()
        local saved = { Me.stats_db, Me.vocab_db }
        local data_dir = ffiUtil.realpath(DataStorage:getDataDir())
        Me.stats_db = data_dir .. "/me_spec_missing.sqlite3"
        Me.vocab_db = data_dir .. "/me_spec_old_vocab.sqlite3"
        os.remove(Me.stats_db)
        os.remove(Me.vocab_db)
        local conn = SQ3.open(Me.vocab_db)
        conn:exec("CREATE TABLE words (word TEXT);") -- no vocabulary table
        conn:close()

        local fm, view = openMe(fakeStatistics())
        assert.are.equal(0, view.home.total_minutes)
        assert.are.equal(0, view.home.week_minutes)
        assert.is_truthy(table.concat(texts(view)):find(T(_("Total reading %1 h %2 min"), 0, 0), 1, true))
        assert.are.equal(0, view.home.streak)
        assert.are.equal(0, view.home.word_count)
        view:open("vocab")
        assert.are.equal(0, #view.words)
        assert.is_true(contains(texts(view), _("Your vocabulary is empty")))
        fm:onClose()

        os.remove(Me.vocab_db)
        Me.stats_db, Me.vocab_db = saved[1], saved[2]
    end)

    it("reads highlights from sidecars older than annotations, like the exporter", function()
        local path = home .. "/legacy.epub"
        ffiUtil.copyFile("spec/front/unit/data/juliet.epub", path)
        local doc_settings = DocSettings:open(path)
        doc_settings:saveSetting("doc_props", { title = "Legacy" })
        doc_settings:saveSetting("highlight", {
            [3] = {
                { text = "kept, with a note", datetime = "2020-01-01 10:00:00", pos0 = "/body/p[1].0", drawer = "lighten" },
                { text = "no bookmark: not exported", datetime = "2020-01-01 11:00:00", pos0 = "/body/p[2].0" },
            },
        })
        doc_settings:saveSetting("bookmarks", {
            { datetime = "2020-01-01 10:00:00", page = "/body/p[1].0", text = "my thought", highlighted = true },
            { datetime = "2020-01-02 10:00:00", page = "/body/p[5].0", text = "Page 3 @ 2020-01-02 10:00:00" },
            { datetime = "2020-01-03 10:00:00", page = "/body/p[6].0", text = "remember this page" },
        })
        doc_settings:flush()
        BookList.resetBookInfoCache(path)
        ReadHistory:addItem(path, 3000, true)

        -- and one with bookmarks only, no highlight
        local bookmarked = home .. "/bookmarked.epub"
        ffiUtil.copyFile("spec/front/unit/data/juliet.epub", bookmarked)
        doc_settings = DocSettings:open(bookmarked)
        doc_settings:saveSetting("doc_props", { title = "Bookmarked only" })
        doc_settings:saveSetting("bookmarks", {
            { datetime = "2020-02-01 10:00:00", page = "/body/p[2].0", text = "Page 2 @ 2020-02-01 10:00:00" },
        })
        doc_settings:flush()
        BookList.resetBookInfoCache(bookmarked)
        ReadHistory:addItem(bookmarked, 2500, true)

        local fm, view = openMe()
        assert.are.equal(8, view.home.note_count)
        tap(tappable(view, C_("Me page", "Notes in all books")).dimen)
        assert.is_truthy(textWidget(view, T(_("%1 · %2 notes"), "Bookmarked only", 1)))
        local legacy = view.books[1]
        assert.are.equal("Legacy", legacy.title)
        assert.are.equal(3, #legacy.notes)
        assert.are.equal("kept, with a note", legacy.notes[1].text)
        assert.are.equal("my thought", legacy.notes[1].note)
        -- the page bookmarks of the old format follow the highlights, with the note written on one, not the text
        -- KOReader filled in
        assert.are.equal("/body/p[5].0", legacy.notes[2].page)
        assert.is_nil(legacy.notes[2].drawer)
        assert.is_nil(legacy.notes[2].note)
        assert.are.equal("remember this page", legacy.notes[3].note)
        assert.is_truthy(textWidget(view, "remember this page"))
        fm:onClose()

        table.remove(ReadHistory.hist, ReadHistory:getIndexByFile(ffiUtil.realpath(path)))
        table.remove(ReadHistory.hist, ReadHistory:getIndexByFile(ffiUtil.realpath(bookmarked)))
    end)

    it("shows sync and transfer entries, plugins that are off as disabled", function()
        local fm, view = openMe()
        tap(tappable(view, _("Sync and transfer")).dimen)
        assert.are.equal("sync", view.subpage)
        local shown = texts(view)
        for _, entry in ipairs{ _("Progress sync"), _("Calibre wireless connection"), _("Book sources (OPDS)"), _("Cloud storage") } do
            assert.is_true(contains(shown, entry))
        end
        -- plugins are not loaded in specs
        assert.is_true(contains(shown, _("Plugin disabled")))
        fm:onClose()
    end)
end)
