describe("Shelf home, 我的 tab", function()
    local BookList, DataStorage, DocSettings, Event, FileManager, Geom, Me, ReadHistory, ReaderUI, Replacements, SQ3, UIManager
    local ffiUtil, lfs, T, _
    local home, saved_settings, saved_hist, saved_dbs
    local today -- this week's day of today, Monday = 1

    -- minutes read N days before today; the week runs from Monday
    local reading = { [0] = 25, [1] = 40, [2] = 10, [4] = 60, [10] = 300 }

    local function dayAt(offset, hour)
        local t = os.date("*t")
        return os.time{ year = t.year, month = t.month, day = t.day - offset, hour = hour }
    end

    local function seedStats(path)
        os.remove(path)
        local conn = SQ3.open(path)
        conn:exec("CREATE TABLE page_stat_data (id_book integer, page integer, start_time integer, duration integer, total_pages integer);")
        for offset, minutes in pairs(reading) do
            -- two sessions per day, to check they add up
            local first = math.floor(minutes * 60 / 3)
            conn:exec(string.format("INSERT INTO page_stat_data VALUES (1, 1, %d, %d, 100);", dayAt(offset, 9), first))
            conn:exec(string.format("INSERT INTO page_stat_data VALUES (1, 2, %d, %d, 100);", dayAt(offset, 21), minutes * 60 - first))
        end
        conn:close()
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

    local function openMe()
        FileManager:showFiles(home)
        local fm = FileManager.instance
        fm:switchTab("me")
        return fm, fm.me_view
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
        DocSettings = require("docsettings")
        Event = require("ui/event")
        FileManager = require("apps/filemanager/filemanager")
        Geom = require("ui/geometry")
        Me = require("apps/shelf/me")
        ReadHistory = require("readhistory")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        SQ3 = require("lua-ljsqlite3/init")
        UIManager = require("ui/uimanager")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        T = ffiUtil.template
        _ = require("gettext")
        require("apps/shelf/shelffilemanager") -- registers the replacement

        saved_settings = {}
        for _, key in ipairs{ "home_dir", "lastdir", "shelf_removed" } do
            saved_settings[key] = G_reader_settings:readSetting(key)
        end
        saved_hist = ReadHistory.hist
        ReadHistory.hist = {}
        saved_dbs = { Me.stats_db, Me.vocab_db }
        local data_dir = ffiUtil.realpath(DataStorage:getDataDir())
        Me.stats_db = data_dir .. "/me_spec_statistics.sqlite3"
        Me.vocab_db = data_dir .. "/me_spec_vocabulary.sqlite3"
        seedStats(Me.stats_db)
        seedVocab(Me.vocab_db)

        home = data_dir .. "/me_home"
        ffiUtil.purgeDir(home)
        lfs.mkdir(home)
        G_reader_settings:saveSetting("home_dir", home)
        local year = os.date("%Y")
        addBook("juliet.epub", "juliet.epub", "Romeo and Juliet", {
            highlight("Two households, both alike in dignity", "Prologue"),
            { page = "/body/p[3]", text = "a bookmark, not a note", datetime = "2026-10-02 10:00:00" },
            highlight("In fair Verona, where we lay our scene", "Prologue"),
        }, { status = "complete", modified = year .. "-03-01" }, 2000)
        addBook("leaves.epub", "leaves.epub", "Leaves of Grass", {
            highlight("I celebrate myself", "Song of Myself"),
        }, { status = "complete", modified = "2001-01-01" }, 1000)
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
        Me.stats_db, Me.vocab_db = saved_dbs[1], saved_dbs[2]
        for key, value in pairs(saved_settings) do
            G_reader_settings:saveSetting(key, value)
        end
        Replacements.filemanager = nil
        ffiUtil.purgeDir(home)
    end)

    it("shows this week's reading time, a bar per day so far, and the streak line", function()
        local fm, view = openMe()
        assert.are.equal(view, fm.content[1])
        assert.are.equal("me", fm.current_tab)

        local expected, total = {}, 0
        for i = 1, today do
            expected[i] = reading[today - i] or 0
            total = total + expected[i]
        end
        assert.are.same(expected, view.home.week.minutes)
        local shown = texts(view)
        assert.is_true(contains(shown, T(_("%1 h %2 min"), math.floor(total / 60), total % 60)))
        assert.is_true(contains(shown, T(_("%1-day reading streak · %2 finished this year"), 3, 1)))

        -- bars are proportional to minutes; days to come have none
        local chart = view.chart
        local max = math.max(table.unpack(expected))
        for i = 1, 7 do
            if i > today then
                assert.is_nil(chart.bar_heights[i])
            elseif expected[i] == 0 then
                assert.are.equal(0, chart.bar_heights[i])
            else
                assert.is_true(math.abs(chart.bar_heights[i] - expected[i] / max * chart.bar_max) <= 1)
            end
        end
        assert.are.equal(_("Today"), chart.labels[today].text)
        fm:onClose()
    end)

    it("lists every book's notes grouped by book, without bookmarks, and opens a note's book", function()
        local fm, view = openMe()
        assert.is_true(contains(texts(view), T(_("%1 highlights and notes"), 3)))
        view:open("notes")
        assert.are.equal("notes", view.subpage)
        local shown = texts(view)
        -- last read book first
        local first = T(_("%1 · %2 notes"), "Romeo and Juliet", 2)
        local second = T(_("%1 · %2 notes"), "Leaves of Grass", 1)
        assert.is_true(contains(shown, first))
        assert.is_true(contains(shown, second))
        local function index(value) for i, v in ipairs(shown) do if v == value then return i end end end
        assert.is_true(index(first) < index(second))
        assert.is_false(contains(shown, "a bookmark, not a note"))
        assert.is_nil(index("No notes here"))
        -- the contents drawer's note rows, one per highlight
        local rows = {}
        local function collect(w)
            if type(w) ~= "table" then return end
            if type(w.note) == "table" then table.insert(rows, w.note) end
            for __, child in ipairs(w) do collect(child) end
        end
        collect(view)
        assert.are.equal(3, #rows)
        assert.are.equal(2, #view.books)
        assert.are.equal(2, #view.books[1].notes)
        assert.are.equal(1, #view.books[2].notes)

        -- a note opens its book, pushes the position it opened on, then jumps to the note
        local opened
        local orig = ReaderUI.showReader
        ReaderUI.showReader = function(_, file, _, _, _, after_open) opened = { file = file, after_open = after_open } end
        local note = view.books[2].notes[1]
        view:openNote(view.books[2], note)
        ReaderUI.showReader = orig
        assert.are.equal(home .. "/leaves.epub", opened.file)
        local calls = {}
        opened.after_open{
            link = { addCurrentLocationToStack = function() table.insert(calls, "stack") end },
            bookmark = { gotoBookmark = function(_, page, pos0) table.insert(calls, { page, pos0 }) end },
        }
        assert.are.same({ "stack", { note.page, note.pos0 } }, calls)

        -- notes are dropped with the subpage
        view:close()
        assert.is_nil(view.books)
        fm:onClose()
    end)

    it("lists the vocabulary, newest first", function()
        local fm, view = openMe()
        assert.is_true(contains(texts(view), T(_("%1 words"), 2)))
        view:open("vocab")
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
        local function find(widget, pred)
            if type(widget) ~= "table" then return end
            if pred(widget) then return widget end
            for _, child in ipairs(widget) do
                local found = find(child, pred)
                if found then return found end
            end
        end
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
        os.remove(Me.stats_db)
        local conn = SQ3.open(Me.stats_db)
        conn:exec("CREATE TABLE page_stat_data (id_book integer, page integer, start_time integer, duration integer, total_pages integer);")
        local sunday = os.time{ year = 2026, month = 10, day = 18, hour = 23, min = 59, sec = 0 }
        local monday = os.time{ year = 2026, month = 10, day = 19, hour = 0, min = 0, sec = 0 }
        conn:exec(string.format("INSERT INTO page_stat_data VALUES (1, 1, %d, 600, 100);", sunday))
        conn:exec(string.format("INSERT INTO page_stat_data VALUES (1, 2, %d, 1200, 100);", monday))
        conn:close()

        Me.now = function() return sunday + 30 end
        local fm, view = openMe()
        assert.are.same({ 0, 0, 0, 0, 0, 0, 10 }, view.home.week.minutes)
        assert.are.equal(10, view.home.week.total_minutes)
        fm:onClose()

        Me.now = function() return monday + 30 end
        fm, view = openMe()
        assert.are.same({ 20 }, view.home.week.minutes)
        assert.are.equal(20, view.home.week.total_minutes)
        assert.are.equal(2, view.home.streak)
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

        local fm, view = openMe()
        for i = 1, view.home.week.today do
            assert.are.equal(0, view.home.week.minutes[i])
        end
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
        })
        doc_settings:flush()
        BookList.resetBookInfoCache(path)
        ReadHistory:addItem(path, 3000, true)

        local fm, view = openMe()
        assert.are.equal(4, view.home.note_count)
        view:open("notes")
        local legacy = view.books[1]
        assert.are.equal("Legacy", legacy.title)
        assert.are.equal(1, #legacy.notes)
        assert.are.equal("kept, with a note", legacy.notes[1].text)
        assert.are.equal("my thought", legacy.notes[1].note)
        fm:onClose()

        table.remove(ReadHistory.hist, ReadHistory:getIndexByFile(ffiUtil.realpath(path)))
    end)

    it("shows sync and transfer entries, plugins that are off as disabled", function()
        local fm, view = openMe()
        view:open("sync")
        local shown = texts(view)
        for _, entry in ipairs{ _("Progress sync"), _("Calibre wireless connection"), _("Book sources (OPDS)"), _("Cloud storage") } do
            assert.is_true(contains(shown, entry))
        end
        -- plugins are not loaded in specs
        assert.is_true(contains(shown, _("Plugin disabled")))
        fm:onClose()
    end)
end)
