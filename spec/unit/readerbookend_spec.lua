-- Q01-Q04 through ReaderUI and the shelf, with real EPUB/PDF navigation, sidecars and history.
describe("Book end", function()
    local BookList, DocSettings, Event, FileManager, Geom, Key, ReadHistory, ReaderUI, Replacements, Screen, UIManager
    local ffiUtil, lfs, home, outside, ui, saved, saved_hist, _, C_
    local real_time, clock = os.time, 0

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
        UIManager:_checkTasks()
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

    -- 更多 → 书籍详情, then the status switch's `n`th choice (1 在读, 2 搁置, 3 读完), and back.
    local function setStatusInDetails(n)
        toolbar()
        tap(find(ui.menu.bars.top, "eink/more"))
        tap(find(ui.menu.panel, _("Book details")))
        local details = top()
        local switch = find(details, function(w) return w.toggle and w.args and w.args[3] == "complete" end)
        local r = switch.dimen
        gesture("tap", r.x + r.w * (n - 0.5) / 3, r.y + r.h / 2)
        UIManager:_checkTasks()
        UIManager:_checkTasks()
        UIManager:forceRePaint()
        details:onClose()
        UIManager:forceRePaint()
    end

    -- The book end of `file`, one turn after its last body page.
    local function bookEnd(file)
        if FileManager.instance then FileManager.instance:onClose() end
        open(file)
        lastPage()
        nextPage()
        return ui.status.book_end
    end

    local function exitReading()
        tap(find(ui.status.book_end, _("Exit reading")))
        ui = nil
        return FileManager.instance
    end

    -- 读完的第 N 本 (Q03): the number in the emblem, or nil. Its caption is the first line of the emblem's text.
    local function finishedCaption()
        return (_.pgettext("Book end", "Finished book\nNo. %1"):match("^(.-)\n"))
    end

    local function finishedNumber(page)
        local number = find(page.emblem, function(w) return type(w.text) == "string" and w.text:match("^%d+$") end)
        return number and tonumber(number.text)
    end

    -- 标记为 on the shelf (seam B), a minute after the last mark: a long press on the cover, 标记为, the status.
    local function markOnShelf(title, status)
        clock = clock + 60
        if not FileManager.instance then FileManager:showFiles(home) end
        local fm = FileManager.instance
        local cell = find(fm.shelf_view, title)
        -- The other finished books can push this one onto another shelf page.
        if not cell then
            fm.shelf_view:setPage(1)
            UIManager:forceRePaint()
            cell = find(fm.shelf_view, title)
            while not cell and fm.shelf_view.page < fm.shelf_view.pages do
                gesture("swipe", Screen:getWidth() / 2, Screen:getHeight() / 2, "west")
                cell = find(fm.shelf_view, title)
            end
        end
        assert.is_truthy(cell, "book not found on the shelf: " .. title)
        gesture("hold", cell.dimen.x + 10, cell.dimen.y + 10)
        tap(find(fm, "eink/mark"))
        tap(find(top(), C_("Status of single book", status)))
        while top().toast do UIManager:close(top()) end
        UIManager:forceRePaint()
    end

    -- A copy of the sample PDF with `summary` in its settings file and, if `opened`, in reading history.
    local function book(path, summary, opened)
        ffiUtil.copyFile("spec/front/unit/data/sample.pdf", path)
        DocSettings:open(path):purge()
        if summary then
            local doc_settings = DocSettings:open(path)
            doc_settings:saveSetting("summary", summary)
            doc_settings:flush()
        end
        BookList.resetBookInfoCache(path)
        if opened then ReadHistory:addItem(path, os.time(), true) end
        return path
    end

    -- Books marked 读完 earlier, and books not counted: 5 come before a book marked now.
    local function finishedBooks()
        local function year(y) return real_time{ year = y, month = 5, day = 1, hour = 12 } end
        local today = os.date("%Y-%m-%d")
        local books = {
            -- marked in 2019; a review written today changed `modified`, not when it was marked
            reviewed = book(home .. "/reviewed.pdf", { status = "complete", finished_time = year(2019), modified = today }, true),
            -- marked before the time was recorded: by the day of the status, before the recorded ones of that day
            legacy = book(home .. "/legacy.pdf", { status = "complete", modified = "2003-01-01" }),
            earlier = book(home .. "/earlier.pdf", { status = "complete", modified = today }),
            -- 移出书架 leaves the book status alone; a finished book outside the home is still one
            hidden = book(home .. "/hidden.pdf", { status = "complete", finished_time = year(2021), modified = "2021-05-01" }),
            outside = book(outside .. "/outside.pdf", { status = "complete", finished_time = year(2022), modified = "2022-05-01" }, true),
            gone = book(outside .. "/gone.pdf", { status = "complete", finished_time = year(2020), modified = "2020-05-01" }, true),
            reading = book(home .. "/reading.pdf", { status = "reading", modified = "2020-05-01" }, true),
            unopened = book(home .. "/unopened.pdf"),
        }
        require("apps/shelf/shelf").remove{ books.hidden }
        os.remove(books.gone)
        return books
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
        ReadHistory = require("readhistory")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        _ = require("gettext")
        C_ = _.pgettext
        require("apps/shelf/shelffilemanager")
        Replacements.reader_menu = require("apps/reader/modules/readertoolbar")
        home = ffiUtil.realpath(require("datastorage"):getDataDir()) .. "/book_end_spec"
        ffiUtil.purgeDir(home)
        lfs.mkdir(home)
        outside = ffiUtil.realpath(require("datastorage"):getDataDir()) .. "/book_end_spec_outside"
        ffiUtil.purgeDir(outside)
        lfs.mkdir(outside)
        saved_hist = ReadHistory.hist
        saved = {}
        for __, key in ipairs{ "home_dir", "lastdir", "shelf_filter", "shelf_removed", "end_document_action", "end_document_auto_mark", "collate" } do
            saved[key] = G_reader_settings:readSetting(key)
            G_reader_settings:delSetting(key)
        end
        G_reader_settings:saveSetting("home_dir", home)
    end)

    before_each(function()
        ReadHistory.hist = {} -- the finished books counted are only this file's
        -- Marks made one after another are seconds apart, as they are for a reader.
        clock = 0
        local started = real_time()
        os.time = function(t) return t and real_time(t) or started + clock end -- luacheck: ignore
        for __, file in ipairs{ "juliet.epub", "sample.pdf" } do
            ffiUtil.copyFile("spec/front/unit/data/" .. file, home .. "/" .. file)
            DocSettings:open(home .. "/" .. file):purge()
            BookList.resetBookInfoCache(home .. "/" .. file)
        end
    end)

    after_each(function()
        if ui and ui.document then
            ui.statistics = nil
            ui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
            ui:onClose()
        end
        ui = nil
        if FileManager.instance then FileManager.instance:onClose() end
        while UIManager._window_stack[1] do UIManager:close(top()) end
        G_reader_settings:delSetting("end_document_action")
        G_reader_settings:delSetting("end_document_auto_mark")
        G_reader_settings:delSetting("shelf_removed")
        os.time = real_time -- luacheck: ignore
        for __, dir in ipairs{ home, outside } do
            ffiUtil.purgeDir(dir)
            lfs.mkdir(dir)
        end
    end)

    teardown(function()
        for key, value in pairs(saved) do G_reader_settings:saveSetting(key, value) end
        for __, key in ipairs{ "home_dir", "lastdir", "shelf_filter", "shelf_removed", "end_document_action", "end_document_auto_mark", "collate" } do
            if saved[key] == nil then G_reader_settings:delSetting(key) end
        end
        ReadHistory.hist = saved_hist
        Replacements.reader_menu, Replacements.filemanager = nil, nil
        ffiUtil.purgeDir(home)
        ffiUtil.purgeDir(outside)
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
        assert.is_nil(ui.doc_settings:readSetting("summary").finished_time)
        assert.are.equal("reading", BookList.getBookStatus(file))
        assert.is_nil(finishedNumber(ui.status.book_end))
        UIManager:close(top())
        tap(ui.status.book_end.mark_button)
        assert.are.equal("complete", DocSettings:open(file):readSetting("summary").status)
        assert.are.equal(os.time(), DocSettings:open(file):readSetting("summary").finished_time)
        assert.are.equal(1, finishedNumber(ui.status.book_end))
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
        UIManager:_checkTasks()
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
            setStatusInDetails(choice[1])
            assert.are.equal(choice[2], ui.doc_settings:readSetting("summary").status)
            local label = choice[2] == "complete" and "Finished" or "Mark as finished"
            assert.is_truthy(find(ui.status.book_end, _.pgettext("Book end", label)))
            assert.are.equal(choice[2] == "complete" and 1 or nil, finishedNumber(ui.status.book_end))
            assert.are.equal(choice[2] == "complete" and os.time() or nil, ui.doc_settings:readSetting("summary").finished_time)
        end
    end)

    for __, action in ipairs{ "default", "goto_beginning", "nothing", "pop-up", "mark_read", "file_browser", "next_file" } do
        for ___, auto_mark in ipairs{ false, true } do
            it("honors " .. action .. " with auto-mark " .. tostring(auto_mark), function()
                G_reader_settings:saveSetting("end_document_auto_mark", auto_mark)
                if action ~= "default" then G_reader_settings:saveSetting("end_document_action", action) end
                G_reader_settings:saveSetting("collate", "strcoll")
                local file = home .. "/juliet.epub"
                open(file)
                lastPage()
                assert.are.equal("reading", ui.doc_settings:readSetting("summary").status)
                nextPage()
                UIManager:_checkTasks()
                UIManager:_checkTasks()
                UIManager:forceRePaint()
                if action == "file_browser" then
                    assert.are.equal(FileManager.instance, top())
                    assert.is_nil(ui.document)
                    assert.are.equal(auto_mark and "complete" or "reading", DocSettings:open(file):readSetting("summary").status)
                elseif action == "next_file" then
                    ui = ReaderUI.instance
                    assert.are.equal(ui, top())
                    assert.are.equal(home .. "/sample.pdf", ui.document.file)
                    assert.are.equal(auto_mark and "complete" or "reading", DocSettings:open(file):readSetting("summary").status)
                else
                    assert.are.equal((auto_mark or action == "mark_read") and "complete" or "reading", ui.doc_settings:readSetting("summary").status)
                    if action == "default" then
                        assert.are.equal(ui.status.book_end, top())
                        assert.is_truthy(find(top(), _.pgettext("Book end", auto_mark and "Finished" or "Mark as finished")))
                    elseif action == "pop-up" then
                        assert.are.equal("end_document", top().name)
                        assert.is_truthy(find(top(), _("Go to beginning")))
                    elseif action == "mark_read" then
                        assert.is_truthy(find(top(), _("You've reached the end of the document.\nThe current book has been marked as finished.")))
                    else
                        assert.are.equal(ui, top())
                        assert.are.equal(action == "goto_beginning" and 1 or ui.document:getPageCount(), ui:getCurrentPage())
                    end
                end
            end)
        end
    end

    for __, file in ipairs{ "juliet.epub", "sample.pdf" } do
        it("keeps the book end open across portrait and landscape rotation: " .. file, function()
            open(home .. "/" .. file)
            lastPage()
            nextPage()
            local page = ui.status.book_end
            for ___, mode in ipairs{ Screen.DEVICE_ROTATED_CLOCKWISE, Screen.DEVICE_ROTATED_UPRIGHT } do
                ui:handleEvent(Event:new("SetRotationMode", mode))
                UIManager:_checkTasks()
                UIManager:forceRePaint()
                assert.are.equal(page, ui.status.book_end)
                assert.are.equal(page, top())
                assert.are.equal(Screen:getWidth(), page.dimen.w)
                assert.are.equal(Screen:getHeight(), page.dimen.h)
                assert.is_truthy(find(page, _("The End")))
                assert.is_true(page.exit_button.dimen.y + page.exit_button.dimen.h <= page.dimen.h)
            end
            gesture("tap", Screen:getWidth() * 0.1, Screen:getHeight() / 2)
            assert.is_nil(ui.status.book_end)
        end)
    end

    it("snapshots statistics once while rebuilding the three-column card", function()
        open(home .. "/juliet.epub")
        local calls = 0
        local now = os.time()
        ui.statistics = { getStatsBookStatus = function()
            calls = calls + 1
            return { time = 33 * 60, days = 4, first_read = now - 3 * 86400, last_read = now }
        end }
        lastPage()
        nextPage()
        local page = ui.status.book_end
        assert.is_truthy(find(page, "33"))
        assert.is_truthy(find(page, "4"))
        assert.is_true(find(page, "33").face.size > find(page, _.pgettext("Time", "min")).face.size)
        assert.is_truthy(find(page, _("Last read · %1"):gsub("%%1", _("Today"))))
        toolbar()
        tap(ui.menu.bookmark_button)
        UIManager:close(top())
        tap(page.mark_button)
        ui:handleEvent(Event:new("SetDimensions", Screen:getSize()))
        UIManager:_checkTasks()
        UIManager:forceRePaint()
        assert.are.equal(1, calls)
        assert.is_truthy(find(page, _("A book full of highlights")))
        tap(page.notes_button)
        assert.are.equal(ui.menu.drawer, top())
        ui.statistics = nil
    end)

    it("keeps three columns and shows unavailable statistics as dashes", function()
        open(home .. "/juliet.epub")
        lastPage()
        nextPage()
        local page = ui.status.book_end
        assert.is_truthy(find(page, _.pgettext("Book end", "Total reading time")))
        assert.is_truthy(find(page, _("Reading days")))
        assert.is_truthy(find(page, _.pgettext("Book end", "Thoughts and notes")))
        assert.is_truthy(find(page, "—"))
        assert.is_nil(find(page, _("A book full of highlights")))
    end)

    for __, days_ago in ipairs{ 0, 1, 7 } do
        it("shows the start date and last-read date for " .. days_ago .. " days ago", function()
            open(home .. "/juliet.epub")
            local date = os.date("*t")
            date.day = date.day - days_ago
            local last_read = os.time(date)
            ui.statistics = { getStatsBookStatus = function()
                return { time = 60, days = 1, first_read = last_read, last_read = last_read }
            end }
            lastPage()
            nextPage()
            local T = ffiUtil.template
            local short_date = T(_.pgettext("Book end date", "%1/%2"), tonumber(os.date("%m", last_read)), tonumber(os.date("%d", last_read)))
            local label = days_ago == 0 and _("Today") or days_ago == 1 and _("Yesterday") or short_date
            assert.is_truthy(find(ui.status.book_end, T(_("Started reading on %1"), short_date)))
            assert.is_truthy(find(ui.status.book_end, T(_("Last read · %1"), label)))
        end)
    end

    it("enters the book end after the final viewport in scroll mode", function()
        open(home .. "/juliet.epub")
        ui:handleEvent(Event:new("SetViewMode", "scroll"))
        -- Dismiss the existing mode notification.
        while top() ~= ui do UIManager:close(top()) end
        ui:handleEvent(Event:new("GotoPercent", 100))
        UIManager:forceRePaint()
        for i = 1, 3 do
            if ui.status.book_end then break end
            nextPage()
        end
        assert.are.equal(ui.status.book_end, top())
        assert.is_truthy(find(top(), _("The End")))
    end)

    it("enters the book end at the last linear page when the appendix is hidden", function()
        local file = home .. "/hidden.epub"
        local epub = require("ffi/archiver").Writer:new{}
        assert.is_true(epub:open(file, "epub"))
        epub:setZipCompression("store")
        epub:addFileFromMemory("mimetype", "application/epub+zip", os.time())
        epub:setZipCompression("deflate")
        local files = {
            ["META-INF/container.xml"] = '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
            ["content.opf"] = '<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Hidden appendix</dc:title><dc:identifier id="id">book-end-hidden</dc:identifier><dc:language>en</dc:language></metadata><manifest><item id="body" href="body.xhtml" media-type="application/xhtml+xml"/><item id="appendix" href="appendix.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="body"/><itemref idref="appendix" linear="no"/></spine></package>',
            ["body.xhtml"] = '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>The last body page.</p></body></html>',
            ["appendix.xhtml"] = '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Hidden appendix.</p></body></html>',
        }
        for name, contents in pairs(files) do epub:addFileFromMemory(name, contents, os.time()) end
        epub:close()
        open(file)
        ui:handleEvent(Event:new("ToggleHideNonlinear"))
        assert.is_true(ui.document:hasHiddenFlows())
        ui:handleEvent(Event:new("GotoPage", ui.document:getLastLinearPage()))
        UIManager:forceRePaint()
        nextPage()
        assert.are.equal(ui.status.book_end, top())
        assert.is_truthy(find(top(), _("The End")))
        assert.is_true(ui:getCurrentPage() < ui.document:getPageCount())
    end)

    it("shows 读完的第 N 本 only when finished, counting books marked 读完 in any year", function()
        finishedBooks()
        local page = bookEnd(home .. "/juliet.epub")
        assert.is_nil(finishedNumber(page))
        assert.is_nil(find(page, finishedCaption()))
        tap(page.mark_button)
        assert.are.equal(6, finishedNumber(page))
        assert.is_truthy(find(page.emblem, finishedCaption()))
        -- counted when marked: a book finished elsewhere meanwhile is not counted when notes or rotation
        -- rebuild the page, only once its status changes again
        book(home .. "/elsewhere.pdf", { status = "complete", finished_time = 1, modified = "1970-01-01" })
        toolbar()
        tap(ui.menu.bookmark_button)
        UIManager:close(top())
        ui:handleEvent(Event:new("SetDimensions", Screen:getSize()))
        UIManager:forceRePaint()
        assert.are.equal(6, finishedNumber(page))
        setStatusInDetails(1)
        assert.is_nil(finishedNumber(page))
        setStatusInDetails(3)
        assert.are.equal(7, finishedNumber(page))
    end)

    it("keeps a book's number when it is reopened, marked again automatically, or followed by other books", function()
        local books = finishedBooks()
        local juliet = home .. "/juliet.epub"
        tap(bookEnd(juliet).mark_button)
        assert.are.equal(6, finishedNumber(ui.status.book_end))
        local marked = DocSettings:open(juliet):readSetting("summary")
        exitReading()
        markOnShelf("sample", "Finished")
        G_reader_settings:saveSetting("end_document_auto_mark", true)
        clock = clock + 60
        assert.are.equal(6, finishedNumber(bookEnd(juliet)))
        assert.are.same(marked, ui.doc_settings:readSetting("summary"))
        assert.are.equal(7, finishedNumber(bookEnd(home .. "/sample.pdf")))
        -- a book finished before the time was recorded keeps its day too
        assert.are.equal(1, finishedNumber(bookEnd(books.legacy)))
        assert.are.equal("2003-01-01", ui.doc_settings:readSetting("summary").modified)
        -- ordered by when they were marked, not by the later review
        assert.are.equal(2, finishedNumber(bookEnd(books.reviewed)))
    end)

    it("follows 读完 and 在读 set on the shelf, and numbers a book marked again as the latest", function()
        local juliet = home .. "/juliet.epub"
        finishedBooks()
        tap(bookEnd(juliet).mark_button)
        exitReading()
        markOnShelf("juliet", "Reading")
        local page = bookEnd(juliet)
        assert.is_nil(finishedNumber(page))
        assert.is_truthy(find(page, _.pgettext("Book end", "Mark as finished")))
        exitReading()
        markOnShelf("sample", "Finished")
        markOnShelf("juliet", "Finished")
        assert.are.equal(7, finishedNumber(bookEnd(juliet)))
        assert.are.equal(6, finishedNumber(bookEnd(home .. "/sample.pdf")))
    end)

    it("numbers a book marked 读完 in the original file dialog by when it was marked", function()
        local juliet = home .. "/juliet.epub"
        tap(bookEnd(juliet).mark_button)
        local fm = exitReading()
        clock = clock + 60
        fm:openFiles()
        UIManager:forceRePaint()
        local item = find(fm.file_chooser, "sample.pdf")
        gesture("hold", item.dimen.x + item.dimen.w / 2, item.dimen.y + item.dimen.h / 2)
        tap(find(top(), _("More")))
        assert.are.equal(fm.file_chooser.file_dialog, top())
        tap(find(top(), C_("Status of single book", "Finished")))
        assert.are.equal("complete", DocSettings:open(home .. "/sample.pdf"):readSetting("summary").status)
        assert.are.equal(1, finishedNumber(bookEnd(juliet)))
        assert.are.equal(2, finishedNumber(bookEnd(home .. "/sample.pdf")))
    end)
    it("reads each book's settings at most once, then only the books that changed", function()
        -- 300 books on the shelf: 100 marked 读完 earlier, 100 being read, 100 never opened
        for i = 1, 300 do
            local path = string.format("%s/stub%03d.pdf", home, i)
            local f = io.open(path, "w")
            f:write("%PDF-1.4\n")
            f:close()
            if i <= 200 then
                local doc_settings = DocSettings:open(path)
                doc_settings:saveSetting("summary", i <= 100
                    and { status = "complete", finished_time = real_time() - 86400 * (400 - i), modified = "2020-01-01" }
                    or { status = "reading", modified = "2020-01-01" })
                doc_settings:flush()
            end
            BookList.resetBookInfoCache(path)
        end
        local opened = {}
        local docsettings_open = DocSettings.open
        DocSettings.open = function(doc_settings, path, ...)
            if path:match("/stub%d+%.pdf$") then opened[path] = (opened[path] or 0) + 1 end
            return docsettings_open(doc_settings, path, ...)
        end
        -- settings files of the stub books opened since the last call, and the most any one was
        local function reads()
            local total, most = 0, 0
            for __, count in pairs(opened) do
                total, most = total + count, math.max(most, count)
            end
            opened = {}
            return total, most
        end
        local ok, err = pcall(function()
            local juliet = home .. "/juliet.epub"
            tap(bookEnd(juliet).mark_button)
            assert.are.equal(101, finishedNumber(ui.status.book_end))
            local total, most = reads()
            assert.are.equal(200, total) -- the books with a settings file, each once
            assert.are.equal(1, most)
            -- leaving and re-entering the book end, and setting its status again, read none of them
            gesture("swipe", 100, 200, "east")
            nextPage()
            setStatusInDetails(1)
            setStatusInDetails(3)
            assert.are.equal(101, finishedNumber(ui.status.book_end))
            assert.are.equal(0, (reads()))
            -- nor does another book's end; a deleted book no longer counts
            exitReading()
            os.remove(home .. "/stub001.pdf")
            clock = clock + 60
            tap(bookEnd(home .. "/sample.pdf").mark_button)
            assert.are.equal(101, finishedNumber(ui.status.book_end)) -- 99 of them, juliet and this one
            assert.are.equal(0, (reads()))
        end)
        DocSettings.open = docsettings_open
        assert(ok, err)
    end)

    it("counts two formats of one book as two books, as the shelf shows them", function()
        book(home .. "/juliet.pdf", { status = "complete", finished_time = real_time() - 3600, modified = os.date("%Y-%m-%d") })
        tap(bookEnd(home .. "/juliet.epub").mark_button)
        assert.are.equal(2, finishedNumber(ui.status.book_end))
        assert.are.equal(2, exitReading().shelf_view.counts.complete)
    end)
end)
