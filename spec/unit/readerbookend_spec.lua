-- Q01/Q02/Q04 through ReaderUI and the shelf, with real EPUB/PDF navigation and sidecars.
describe("Book end", function()
    local BookList, DocSettings, Event, FileManager, Geom, Key, ReaderUI, Replacements, Screen, UIManager
    local ffiUtil, lfs, home, ui, saved, _

    local function top()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function find(w, label, around)
        if type(w) ~= "table" then return end
        if w.callback and w.dimen then around = w end
        if type(label) == "function" and label(w) or w.text == label or w.icon == label then return around or w end
        for __, child in ipairs(w) do
            local found = find(child, label, around)
            if found then return found end
        end
    end

    local function gesture(kind, x, y, direction)
        UIManager:sendEvent(Event:new("Gesture", {
            ges = kind, pos = Geom:new{ x = x, y = y }, direction = direction, distance = 0, time = require("ui/time").now(),
        }))
        UIManager:forceRePaint()
    end

    local function tap(w)
        local r = w.dimen
        gesture("tap", r.x + r.w / 2, r.y + r.h / 2)
    end

    local function nextPage()
        gesture("tap", Screen:getWidth() * 0.9, Screen:getHeight() / 2)
    end

    local function toolbar()
        gesture("swipe", Screen:getWidth() / 2, Screen:getHeight() * 0.8, "north")
        assert.is_truthy(ui.menu.bars)
    end

    local function open(file)
        ui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = require("document/documentregistry"):openDocument(file),
        }
        UIManager:show(ui)
        if ui.paging then
            ui:handleEvent(Event:new("SetScrollMode", false))
            ui:handleEvent(Event:new("SetZoomMode", "page"))
        end
        UIManager:forceRePaint()
    end

    local function lastPage()
        ui:handleEvent(Event:new("GotoPercent", 100))
        UIManager:forceRePaint()
        assert.are.equal(ui.document:getPageCount(), ui:getCurrentPage())
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        BookList = require("ui/widget/booklist")
        DocSettings = require("docsettings")
        Event = require("ui/event")
        FileManager = require("apps/filemanager/filemanager")
        Geom = require("ui/geometry")
        Key = require("device/key")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        _ = require("gettext")
        require("apps/shelf/shelffilemanager")
        Replacements.reader_menu = require("apps/reader/modules/readertoolbar")
        home = ffiUtil.realpath(require("datastorage"):getDataDir()) .. "/book_end_spec"
        ffiUtil.purgeDir(home)
        lfs.mkdir(home)
        saved = {}
        for __, key in ipairs{ "home_dir", "lastdir", "shelf_filter", "end_document_action", "end_document_auto_mark" } do
            saved[key] = G_reader_settings:readSetting(key)
            G_reader_settings:delSetting(key)
        end
        G_reader_settings:saveSetting("home_dir", home)
    end)

    before_each(function()
        for __, file in ipairs{ "juliet.epub", "sample.pdf" } do
            ffiUtil.copyFile("spec/front/unit/data/" .. file, home .. "/" .. file)
            DocSettings:open(home .. "/" .. file):purge()
            BookList.resetBookInfoCache(home .. "/" .. file)
        end
    end)

    after_each(function()
        if ui and ui.document then ui:onClose() end
        ui = nil
        if FileManager.instance then FileManager.instance:onClose() end
        while UIManager._window_stack[1] do UIManager:close(top()) end
        G_reader_settings:delSetting("end_document_action")
        G_reader_settings:delSetting("end_document_auto_mark")
    end)

    teardown(function()
        for key, value in pairs(saved) do G_reader_settings:saveSetting(key, value) end
        for __, key in ipairs{ "home_dir", "lastdir", "shelf_filter", "end_document_action", "end_document_auto_mark" } do
            if saved[key] == nil then G_reader_settings:delSetting(key) end
        end
        Replacements.reader_menu, Replacements.filemanager = nil, nil
        ffiUtil.purgeDir(home)
    end)

    for __, file in ipairs{ "juliet.epub", "sample.pdf" } do
        it("keeps 100% separate from finishing, and returns from the book end to the last body page: " .. file, function()
            open(home .. "/" .. file)
            lastPage()
            assert.is_nil(ui.status.book_end)
            assert.are.equal("reading", ui.doc_settings:readSetting("summary").status)
            nextPage()
            local page = ui.status.book_end
            assert.are.equal(page, top())
            assert.is_true(page.covers_fullscreen)
            assert.is_truthy(find(page, _("The End")))
            assert.is_truthy(find(page, _.pgettext("Book end", "Mark as finished")))
            assert.are.equal("reading", ui.doc_settings:readSetting("summary").status)
            gesture("swipe", 100, 200, "east")
            assert.is_nil(ui.status.book_end)
            assert.are.equal(ui, top())
            assert.are.equal(ui.document:getPageCount(), ui:getCurrentPage())
            nextPage()
            UIManager:sendEvent(Event:new("KeyPress", Key:new("LPgBack", {})))
            UIManager:forceRePaint()
            assert.is_nil(ui.status.book_end)
            assert.are.equal(ui.document:getPageCount(), ui:getCurrentPage())
        end)
    end

    it("marks manually, persists to the shelf and reopens with the finished state", function()
        local file = home .. "/juliet.epub"
        open(file)
        lastPage()
        nextPage()
        local refreshes = {}
        local refresh = UIManager._refresh
        UIManager._refresh = function(manager, mode, region, ...)
            if mode then table.insert(refreshes, { mode = mode, region = region }) end
            return refresh(manager, mode, region, ...)
        end
        local ok, err = pcall(tap, ui.status.book_end.mark_button)
        UIManager._refresh = refresh
        assert(ok, err)
        assert.is_true(#refreshes > 0)
        for __, r in ipairs(refreshes) do
            assert.are.equal("ui", r.mode)
            assert.is_true(r.region.h < Screen:getHeight())
        end
        assert.are.equal("complete", DocSettings:open(file):readSetting("summary").status)
        assert.is_nil(find(ui.status.book_end, _.pgettext("Book end", "Mark as finished")))
        assert.is_truthy(find(ui.status.book_end, _.pgettext("Book end", "Finished")))
        tap(find(ui.status.book_end, _("Exit reading")))
        assert.is_nil(ui.document)
        ui = nil
        assert.is_truthy(FileManager.instance.shelf_view)
        assert.are.equal(1, FileManager.instance.shelf_view.counts.complete)
        assert.are.equal("complete", BookList.getBookStatus(file))
        FileManager.instance:onClose()
        open(file)
        lastPage()
        nextPage()
        assert.is_truthy(find(ui.status.book_end, _.pgettext("Book end", "Finished")))
    end)

    it("leaves the book reading on the shelf when exiting without marking", function()
        local file = home .. "/juliet.epub"
        open(file)
        lastPage()
        nextPage()
        tap(find(ui.status.book_end, _("Exit reading")))
        assert.is_nil(ui.document)
        ui = nil
        assert.are.equal(0, FileManager.instance.shelf_view.counts.complete)
        assert.are.equal("reading", DocSettings:open(file):readSetting("summary").status)
    end)

    it("keeps the old status and offers a retry when saving fails", function()
        local file = home .. "/juliet.epub"
        open(file)
        lastPage()
        nextPage()
        local flush = ui.doc_settings.flush
        ui.doc_settings.flush = function() return nil end
        tap(ui.status.book_end.mark_button)
        ui.doc_settings.flush = flush
        assert.is_true(top().toast)
        assert.are.equal(_("Could not save the book status."), top().text)
        assert.are.equal("reading", ui.doc_settings:readSetting("summary").status)
        assert.are.equal("reading", BookList.getBookStatus(file))
        UIManager:close(top())
        tap(ui.status.book_end.mark_button)
        assert.are.equal("complete", DocSettings:open(file):readSetting("summary").status)
    end)

    it("uses the Menu and page keys on the book end without turning past the body", function()
        open(home .. "/juliet.epub")
        lastPage()
        nextPage()
        local page = ui.status.book_end
        UIManager:sendEvent(Event:new("KeyPress", Key:new("LPgFwd", {})))
        assert.are.equal(page, top())
        UIManager:sendEvent(Event:new("KeyPress", Key:new("Menu", {})))
        UIManager:forceRePaint()
        assert.is_truthy(ui.menu.bars)
        gesture("tap", Screen:getWidth() / 2, Screen:getHeight() / 2)
        assert.are.equal(page, top())
        UIManager:sendEvent(Event:new("KeyPress", Key:new("Back", {})))
        assert.is_nil(ui.status.book_end)
    end)

    it("opens the toolbars, contents and notes, and drops the book end after a chapter jump", function()
        open(home .. "/juliet.epub")
        lastPage()
        nextPage()
        local page = ui.status.book_end
        toolbar()
        -- The toolbar's icon cells, rather than an internal notes entry.
        tap(find(ui.menu.bars.bottom, "eink/notes"))
        local notes = ui.menu.drawer
        assert.is_truthy(notes)
        tap(notes.bar.back)
        assert.are.equal(page, top())
        toolbar()
        tap(find(ui.menu.bars.bottom, "eink/toc"))
        local toc = ui.menu.drawer
        assert.is_truthy(toc)
        tap(toc.bar.back)
        assert.are.equal(page, top())
        ui:handleEvent(Event:new("GotoPercent", 0))
        UIManager:forceRePaint()
        assert.is_nil(ui.status.book_end)
        assert.are.equal(ui, top())
    end)

    it("lets a long diagonal swipe reach the reader's screenshot action", function()
        open(home .. "/juliet.epub")
        lastPage()
        nextPage()
        local shot = stub(ui.screenshot, "onSwipeDiagonal", function() return true end)
        UIManager:sendEvent(Event:new("Gesture", {
            ges = "swipe", pos = Geom:new{ x = 0, y = 0 }, direction = "southeast",
            distance = math.sqrt(Screen:getWidth()^2 + Screen:getHeight()^2), time = require("ui/time").now(),
        }))
        local calls = #shot.calls
        shot:revert()
        assert.are.equal(1, calls)
        assert.is_truthy(ui.status.book_end)
    end)

    it("updates the book end's note count when the toolbar adds and removes a bookmark", function()
        open(home .. "/juliet.epub")
        lastPage()
        nextPage()
        assert.is_truthy(find(ui.status.book_end, "0"))
        toolbar()
        tap(ui.menu.bookmark_button)
        UIManager:close(top()) -- bookmark toast
        UIManager:forceRePaint()
        assert.are.equal(1, #ui.annotation.annotations)
        assert.is_truthy(find(ui.status.book_end, "1"))
        toolbar()
        tap(ui.menu.bookmark_button)
        UIManager:close(top())
        UIManager:forceRePaint()
        assert.are.equal(0, #ui.annotation.annotations)
        assert.is_truthy(find(ui.status.book_end, "0"))
    end)

    it("reads back status changes made through More and Book details", function()
        open(home .. "/juliet.epub")
        lastPage()
        nextPage()
        for __, choice in ipairs{ { 3, "complete" }, { 1, "reading" } } do
            toolbar()
            tap(find(ui.menu.bars.top, "eink/more"))
            tap(find(ui.menu.panel, _("Book details")))
            local details = top()
            local switch = find(details, function(w) return w.toggle and w.args and w.args[3] == "complete" end)
            local r = switch.dimen
            gesture("tap", r.x + r.w * (choice[1] - 0.5) / 3, r.y + r.h / 2)
            UIManager:_checkTasks()
            UIManager:_checkTasks()
            UIManager:forceRePaint()
            assert.are.equal(choice[2], ui.doc_settings:readSetting("summary").status)
            details:onClose()
            UIManager:forceRePaint()
            local label = choice[2] == "complete" and "Finished" or "Mark as finished"
            assert.is_truthy(find(ui.status.book_end, _.pgettext("Book end", label)))
        end
    end)

    it("keeps explicit automatic marking and end actions", function()
        G_reader_settings:saveSetting("end_document_auto_mark", true)
        open(home .. "/juliet.epub")
        lastPage()
        assert.are.equal("reading", ui.doc_settings:readSetting("summary").status)
        nextPage()
        assert.are.equal("complete", ui.doc_settings:readSetting("summary").status)
        assert.is_truthy(find(ui.status.book_end, _.pgettext("Book end", "Finished")))
        gesture("swipe", 100, 200, "east")
        G_reader_settings:saveSetting("end_document_action", "goto_beginning")
        nextPage()
        assert.is_nil(ui.status.book_end)
        assert.are.equal(1, ui:getCurrentPage())
        G_reader_settings:saveSetting("end_document_action", "nothing")
        lastPage()
        nextPage()
        assert.is_nil(ui.status.book_end)
    end)
end)
