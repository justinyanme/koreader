describe("Shelf home (FileManager replacement)", function()
    local DataStorage, DocSettings, Event, FileManager, Geom, ReadHistory, ReaderUI, Replacements, ShelfView, UIManager
    local filemanagerutil, lfs, ffiUtil, C_
    local saved_settings
    local cleanup_files = {}

    local function names(books)
        local list = {}
        for _, book in ipairs(books) do
            table.insert(list, (book.file:gsub(".*/", "")))
        end
        return list
    end

    local function openShelf(home)
        FileManager:showFiles(home)
        return FileManager.instance, FileManager.instance.shelf_view
    end

    local function spyRefreshes()
        local refreshes = {}
        local orig_setDirty, orig_refresh = UIManager.setDirty, UIManager._refresh
        UIManager.setDirty = function(self, widget, refreshtype, region, ...)
            if refreshtype then table.insert(refreshes, { type = refreshtype, region = region, requested = true }) end
            return orig_setDirty(self, widget, refreshtype, region, ...)
        end
        UIManager._refresh = function(self, refreshtype, region, ...)
            table.insert(refreshes, { type = refreshtype, region = region })
            return orig_refresh(self, refreshtype, region, ...)
        end
        return refreshes, function()
            UIManager.setDirty, UIManager._refresh = orig_setDirty, orig_refresh
        end
    end

    local function makeHome(name, books)
        local home = ffiUtil.realpath(DataStorage:getDataDir()) .. "/" .. name
        ffiUtil.purgeDir(home)
        lfs.mkdir(home)
        for _, b in ipairs(books) do
            local path = home .. "/" .. b.name
            lfs.mkdir((path:match("^(.*)/")))
            if b.source then
                ffiUtil.copyFile("spec/front/unit/data/" .. b.source, path)
            else
                local f = io.open(path, "w")
                f:write("Sample text.\n")
                f:close()
            end
            table.insert(cleanup_files, path)
            if b.status then
                local doc_settings = DocSettings:open(path)
                doc_settings:saveSetting("summary", { status = b.status })
                doc_settings:saveSetting("percent_finished", 0.42)
                doc_settings:flush()
            end
            if b.last_read then
                ReadHistory:addItem(path, b.last_read)
            end
            if b.mtime then
                lfs.touch(path, b.mtime, b.mtime)
            end
        end
        G_reader_settings:saveSetting("home_dir", home)
        return home
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DataStorage = require("datastorage")
        DocSettings = require("docsettings")
        Event = require("ui/event")
        FileManager = require("apps/filemanager/filemanager")
        Geom = require("ui/geometry")
        ReadHistory = require("readhistory")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        filemanagerutil = require("apps/filemanager/filemanagerutil")
        lfs = require("libs/libkoreader-lfs")
        ffiUtil = require("ffi/util")
        C_ = require("gettext").pgettext
        require("apps/shelf/shelffilemanager") -- registers the replacement
        ShelfView = require("apps/shelf/shelfview")
        saved_settings = {}
        for _, key in ipairs{ "home_dir", "lastdir", "shelf_removed", "shelf_sort", "back_in_filemanager" } do
            saved_settings[key] = G_reader_settings:readSetting(key)
            G_reader_settings:delSetting(key)
        end
    end)

    teardown(function()
        if FileManager.instance then FileManager.instance:onClose() end
        for _, path in ipairs(cleanup_files) do
            ReadHistory:removeItemByPath(path)
        end
        for key, value in pairs(saved_settings) do
            G_reader_settings:saveSetting(key, value)
        end
        Replacements.filemanager = nil
    end)

    describe("with a small library", function()
        local home
        local function bookPath(name) return home .. "/" .. name end
        local function find(view, name)
            for _, book in ipairs(view.books) do
                if book.file == bookPath(name) then return book end
            end
        end

        setup(function()
            home = makeHome("shelf_home", {
                { name = "a.epub", source = "juliet.epub", last_read = 1000, status = "reading", mtime = 100 },
                { name = "sub/b.epub", source = "leaves.epub", last_read = 2000, status = "complete", mtime = 100 },
                { name = "sub/c.pdf", source = "sample.pdf", mtime = 500 },
                { name = "d.txt", source = "sample.txt", mtime = 800 },
                { name = "sub/e.pdf", source = "2col.pdf", last_read = 1500, status = "abandoned", mtime = 100 },
                { name = ".hidden/f.epub", source = "juliet.epub", mtime = 900 },
            })
        end)

        teardown(function()
            ffiUtil.purgeDir(home)
        end)

        it("orders read books by last read, then unread books by date added, skipping hidden folders", function()
            local fm, view = openShelf(home)
            assert.are.equal("shelf", fm.current_tab)
            assert.are.same({ "b.epub", "e.pdf", "a.epub", "d.txt", "c.pdf" }, names(view.shown))
            fm:onClose()
        end)

        it("counts every filter, and shows on-hold books only under all, marked as such", function()
            local fm, view = openShelf(home)
            assert.are.same({ all = 5, reading = 1, new = 2, complete = 1 }, view.counts)
            local expected = { reading = { "a.epub" }, new = { "d.txt", "c.pdf" }, complete = { "b.epub" } }
            for filter, list in pairs(expected) do
                view:setFilter(filter)
                assert.are.same(list, names(view.shown))
            end
            view:setFilter("all")
            local on_hold = find(view, "sub/e.pdf")
            assert.are.equal("abandoned", on_hold.status)
            assert.are.equal(C_("Shelf book status", "On hold"), ShelfView.statusText(on_hold))
            fm:onClose()
        end)

        it("searches titles, and sorts by title", function()
            local fm, view = openShelf(home)
            view:setQuery("B")
            assert.are.same({ "b.epub" }, names(view.shown))
            assert.are.equal(1, view.counts.all)
            view:setQuery(nil)
            view:setSort("title")
            assert.are.same({ "a.epub", "b.epub", "c.pdf", "d.txt", "e.pdf" }, names(view.shown))
            view:setSort("recent")
            fm:onClose()
        end)

        it("changes status from the long-press actions", function()
            local fm, view = openShelf(home)
            local actions = view:getBookActions(find(view, "a.epub"))
            assert.are.equal(5, #actions)
            actions[4].callback() -- Put on hold
            assert.are.same({ all = 5, reading = 0, new = 2, complete = 1 }, view.counts)
            assert.are.equal("abandoned", DocSettings:open(bookPath("a.epub")):readSetting("summary").status)
            actions = view:getBookActions(find(view, "a.epub"))
            actions[4].callback() -- Mark as reading
            assert.are.equal(1, view.counts.reading)
            fm:onClose()
        end)

        it("removes a book from the shelf but keeps the file, until the book is opened again", function()
            local fm, view = openShelf(home)
            view:getBookActions(find(view, "d.txt"))[5].callback() -- Remove from shelf
            assert.are.same({ "b.epub", "e.pdf", "a.epub", "c.pdf" }, names(view.shown))
            assert.are.equal("file", lfs.attributes(bookPath("d.txt"), "mode"))
            fm:onClose()
            fm, view = openShelf(home)
            assert.is_nil(find(view, "d.txt"))
            assert.are.equal(1, view.counts.new)
            fm:onClose()
            -- opened again (from 文件 or anywhere): back on the shelf
            ReadHistory:addItem(bookPath("d.txt"), os.time() + 10)
            fm, view = openShelf(home)
            assert.is_truthy(find(view, "d.txt"))
            assert.is_nil(G_reader_settings:readSetting("shelf_removed")[bookPath("d.txt")])
            fm:onClose()
            ReadHistory:removeItemByPath(bookPath("d.txt"))
            lfs.touch(bookPath("d.txt"), 800, 800)
        end)

        it("prunes removed entries whose file is gone", function()
            G_reader_settings:saveSetting("shelf_removed", { [home .. "/gone.epub"] = os.time() })
            local fm = openShelf(home)
            assert.is_nil(G_reader_settings:readSetting("shelf_removed")[home .. "/gone.epub"])
            fm:onClose()
        end)

        it("switches tabs and filters with ui refreshes of the content only", function()
            local fm, view = openShelf(home)
            fastforward_ui_events()
            local refreshes, restore = spyRefreshes()
            view:setFilter("new")
            fm:switchTab("files")
            assert.are.equal(fm.files_ui, fm.content[1])
            fm:switchTab("shelf")
            assert.are.equal(fm.shelf_view, fm.content[1])
            restore()
            assert.is_true(#refreshes >= 5)
            local screen_h = require("device").screen:getHeight()
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.type)
                -- requested rects stay inside the content or the tab bar (UIManager may merge adjacent ones)
                if r.requested then
                    assert.is_true(r.region.h < screen_h)
                end
            end
            -- 我的 opens the original menu on top until #11, and the current tab stays
            fm:switchTab("me")
            assert.is_truthy(fm.menu.menu_container)
            assert.are.equal("shelf", fm.current_tab)
            fm.menu:onCloseFileManagerMenu()
            -- rotation rebuilds the layout and keeps the tab
            fm:switchTab("files")
            fm:reinit()
            assert.are.equal(fm.files_ui, fm.content[1])
            fm:onClose()
        end)

        it("brings 文件 forward when the file browser is sent to a folder", function()
            local fm = openShelf(home)
            assert.are.equal("shelf", fm.current_tab)
            filemanagerutil.genShowFolderButton(bookPath("sub/c.pdf"), function() end).callback()
            assert.are.equal("files", fm.current_tab)
            assert.are.equal(fm.files_ui, fm.content[1])
            assert.are.equal(home .. "/sub", fm.file_chooser.path)
            fm:onClose()
        end)

        it("keeps Back and Home away from the hidden file browser", function()
            local fm = openShelf(home)
            local path = fm.file_chooser.path
            G_reader_settings:saveSetting("back_in_filemanager", "parent_folder")
            fm:handleEvent(Event:new("Back"))
            fm:onHome()
            assert.are.equal(path, fm.file_chooser.path)
            assert.are.equal("shelf", fm.current_tab)
            G_reader_settings:delSetting("back_in_filemanager")
            fm:onClose()
        end)

        it("closes the hidden file browser with the home", function()
            local fm = openShelf(home)
            local closed = false
            local orig = fm.file_chooser.onCloseWidget
            fm.file_chooser.onCloseWidget = function(...)
                closed = true
                if orig then return orig(...) end
            end
            fm:onClose()
            assert.is_true(closed)
        end)

        describe("coming back from the reader", function()
            local sample = "spec/front/unit/data/juliet.epub"
            teardown(function()
                ReadHistory:removeItemByPath(ffiUtil.realpath(sample))
            end)

            it("lands on 书架 with a full refresh", function()
                ReaderUI:doShowReader(sample)
                local refreshes, restore = spyRefreshes()
                ReaderUI.instance:onHome()
                restore()
                local fm = FileManager.instance
                assert.are.equal("shelf", fm.current_tab)
                local full = false
                for _, r in ipairs(refreshes) do
                    if r.type == "full" then full = true end
                end
                assert.is_true(full)
                fm:onClose()
            end)

            it("lands on 文件 for Show folder, with the book focused", function()
                local book = ffiUtil.realpath(sample) -- as listed: spec/front is a symlink
                ReaderUI:doShowReader(book)
                filemanagerutil.genShowFolderButton(book, function() end).callback()
                local fm = FileManager.instance
                assert.are.equal("files", fm.current_tab)
                assert.are.equal(ffiUtil.realpath("spec/front/unit/data"), fm.file_chooser.path)
                assert.is_nil(FileManager.open_on_files)
                local fc = fm.file_chooser
                assert.is_true(fc:getFocusItem().focused)
                assert.are.equal(book, fc.item_table[(fc.page - 1) * fc.perpage + fc.selected.y].path)
                fm:onClose()
            end)

            it("lands on 文件 for a folder target", function()
                ReaderUI:doShowReader(sample)
                local readerui = ReaderUI.instance
                readerui:onClose()
                readerui:showFileManager(home .. "/sub/")
                local fm = FileManager.instance
                assert.are.equal("files", fm.current_tab)
                fm:onClose()
            end)
        end)
    end)

    describe("with the cover cache", function()
        local home
        local stub
        local LIGHT_COLS = { "directory", "filename", "title", "authors", "cover_fetched", "has_cover", "cover_sizetag",
            "cover_w", "cover_h", "ignore_cover", "ignore_meta" }

        local function addRow(name, fields)
            local path = home .. "/" .. name
            local row = { path:match("^(.*/)"), path:match("([^/]+)$") }
            fields = fields or {}
            fields.cover_fetched = fields.cover_fetched or "Y"
            for i = 3, #LIGHT_COLS do
                row[i] = fields[LIGHT_COLS[i]]
            end
            row.n = #LIGHT_COLS
            stub.rows[path] = row
        end

        setup(function()
            local books = {}
            for i = 1, 45 do
                table.insert(books, { name = string.format("book%02d.txt", i), mtime = 1000 - i })
            end
            table.insert(books, { name = "photo.png" })
            table.insert(books, { name = "outside/outside.txt" })
            home = makeHome("shelf_cache_home", books)
            -- a folder outside the shelf linked in, and a link back to home that would loop
            os.rename(home .. "/outside", home .. "_outside")
            lfs.link(home .. "_outside", home .. "/linked", true)
            lfs.link(home, home .. "/loop", true)

            stub = {
                rows = {},
                sqls = {},
                jobs = {},
                cover_reads = {},
                extracting = false,
                openDbConnection = function() end,
                isCachedCoverInvalid = function() return false end,
                terminateBackgroundJobs = function() end,
            }
            stub.db_conn = {
                prepare = function(_, sql)
                    table.insert(stub.sqls, sql)
                    local list = {}
                    for _, row in pairs(stub.rows) do table.insert(list, row) end
                    local i = 0
                    return {
                        rows = function() return function() i = i + 1 return list[i] end end,
                        close = function() end,
                    }
                end,
            }
            function stub:getBookInfo(file, get_cover)
                if get_cover then table.insert(self.cover_reads, file) end
            end
            function stub:isExtractingInBackground() return self.extracting end
            function stub:extractInBackground(files)
                table.insert(self.jobs, files)
                self.extracting = true
                return true
            end
            package.loaded["bookinfomanager"] = stub

            addRow("book01.txt", { title = "Meta Title", ignore_meta = "Y" })
            addRow("book02.txt", { has_cover = "Y", ignore_cover = "Y" })
            addRow("book03.txt", { title = "Call to Arms", authors = "Lu Xun", has_cover = "Y" })
        end)

        teardown(function()
            package.loaded["bookinfomanager"] = nil
            os.remove(home .. "/loop")
            os.remove(home .. "/linked")
            ffiUtil.purgeDir(home)
            ffiUtil.purgeDir(home .. "_outside")
        end)

        it("reads metadata with one light query, and covers for the visible page only", function()
            local fm, view = openShelf(home)
            view:stop()
            assert.are.equal(45, #view.books) -- no photo, nothing through the symlinked folders
            for _, sql in ipairs(stub.sqls) do
                assert.is_nil(sql:find("cover_bb_data", 1, true))
            end
            -- only book03 has a usable cover; book02's is ignored
            for _, file in ipairs(stub.cover_reads) do
                assert.are.equal(home .. "/book03.txt", file)
            end
            local by_file = {}
            for _, book in ipairs(view.books) do by_file[book.file:gsub(".*/", "")] = book end
            assert.are.equal("book01", by_file["book01.txt"].title) -- ignore_meta
            assert.is_false(by_file["book02.txt"].has_cover) -- ignore_cover
            view:setQuery("lu xun")
            assert.are.same({ "book03.txt" }, names(view.shown))
            fm:onClose()
        end)

        it("turns pages with the pager and with a swipe, not the hidden file browser's", function()
            local fm, view = openShelf(home)
            view:stop()
            assert.is_true(view.pages > 1)
            local first = names(view.shown)[1]
            local fc_page = fm.file_chooser.page
            fm:onSwipeFM{ direction = "west", pos = Geom:new{ x = 10, y = 10, w = 0, h = 0 } }
            assert.are.equal(2, view.page)
            assert.are.equal(fc_page, fm.file_chooser.page)
            view:turnPage(-1)
            assert.are.equal(1, view.page)
            assert.are.equal(first, names(view.shown)[1])
            fm:onClose()
        end)

        it("extracts in chunks and re-queues books a killed job left behind", function()
            stub.jobs = {}
            local fm, view = openShelf(home)
            assert.are.equal(42, view.extracting.total)
            -- another job (the file browser's) is running: wait for it
            stub.extracting = true
            view:pollExtraction()
            assert.are.equal(0, #stub.jobs)
            stub.extracting = false
            view:pollExtraction()
            assert.are.equal(1, #stub.jobs)
            assert.are.equal(40, #stub.jobs[1])
            -- the job is killed before writing anything: the same books are queued again
            stub.extracting = false
            view:pollExtraction()
            assert.are.equal(2, #stub.jobs)
            assert.are.same(stub.jobs[1], stub.jobs[2])
            -- this time it completes; the 2 books left come next
            for _, f in ipairs(stub.jobs[2]) do addRow((f.filepath:gsub(".*/", ""))) end
            stub.extracting = false
            view:pollExtraction()
            assert.are.equal(3, #stub.jobs)
            assert.are.equal(2, #stub.jobs[3])
            for _, f in ipairs(stub.jobs[3]) do addRow((f.filepath:gsub(".*/", ""))) end
            stub.extracting = false
            view:pollExtraction()
            assert.is_nil(view.extracting)
            assert.are.equal(3, #stub.jobs)
            fm:onClose()
        end)
    end)
end)
