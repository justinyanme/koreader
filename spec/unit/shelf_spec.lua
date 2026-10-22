describe("Shelf home (FileManager replacement)", function()
    local DataStorage, DocSettings, FileManager, ReadHistory, Replacements, ShelfView, UIManager
    local lfs, ffiUtil, C_
    local home, saved_settings
    local files = {}

    local function bookPath(name)
        return home .. "/" .. name
    end

    local function names(books)
        local list = {}
        for _, book in ipairs(books) do
            table.insert(list, (book.file:gsub(".*/", "")))
        end
        return list
    end

    local function find(view, name)
        for _, book in ipairs(view.books) do
            if book.file == bookPath(name) then return book end
        end
    end

    local function openShelf()
        FileManager:showFiles(home)
        return FileManager.instance, FileManager.instance.shelf_view
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DataStorage = require("datastorage")
        DocSettings = require("docsettings")
        FileManager = require("apps/filemanager/filemanager")
        ReadHistory = require("readhistory")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        lfs = require("libs/libkoreader-lfs")
        ffiUtil = require("ffi/util")
        C_ = require("gettext").pgettext
        require("apps/shelf/shelffilemanager") -- registers the replacement
        ShelfView = require("apps/shelf/shelfview")

        home = ffiUtil.realpath(DataStorage:getDataDir()) .. "/shelf_home"
        ffiUtil.purgeDir(home)
        for _, dir in ipairs{ home, home .. "/sub", home .. "/.hidden" } do
            lfs.mkdir(dir)
        end
        local data = "spec/front/unit/data/"
        -- name, source, last read time (history), status, mtime
        local books = {
            { "a.epub", "juliet.epub", 1000, "reading", 100 },
            { "sub/b.epub", "leaves.epub", 2000, "complete", 100 },
            { "sub/c.pdf", "sample.pdf", nil, nil, 500 },
            { "d.txt", "sample.txt", nil, nil, 800 },
            { "sub/e.pdf", "2col.pdf", 1500, "abandoned", 100 },
            { ".hidden/f.epub", "juliet.epub", nil, nil, 900 },
        }
        for _, b in ipairs(books) do
            local path = bookPath(b[1])
            ffiUtil.copyFile(data .. b[2], path)
            table.insert(files, path)
            if b[4] then
                local doc_settings = DocSettings:open(path)
                doc_settings:saveSetting("summary", { status = b[4] })
                doc_settings:saveSetting("percent_finished", 0.42)
                doc_settings:flush()
            end
            if b[3] then
                ReadHistory:addItem(path, b[3])
            end
            lfs.touch(path, b[5], b[5])
        end
        saved_settings = {
            home_dir = G_reader_settings:readSetting("home_dir"),
            lastdir = G_reader_settings:readSetting("lastdir"),
            shelf_removed = G_reader_settings:readSetting("shelf_removed"),
            shelf_sort = G_reader_settings:readSetting("shelf_sort"),
        }
        G_reader_settings:saveSetting("home_dir", home)
        G_reader_settings:delSetting("shelf_removed")
        G_reader_settings:delSetting("shelf_sort")
    end)

    teardown(function()
        if FileManager.instance then FileManager.instance:onClose() end
        for _, path in ipairs(files) do
            ReadHistory:removeItemByPath(path)
        end
        for key, value in pairs(saved_settings) do
            G_reader_settings:saveSetting(key, value)
        end
        Replacements.filemanager = nil
        ffiUtil.purgeDir(home)
    end)

    it("orders read books by last read, then unread books by date added, skipping hidden folders", function()
        local fm, view = openShelf()
        assert.is_true(fm.shelf_view ~= nil)
        assert.are.same({ "b.epub", "e.pdf", "a.epub", "d.txt", "c.pdf" }, names(view.shown))
        fm:onClose()
    end)

    it("counts every filter, and shows on-hold books only under all, marked as such", function()
        local fm, view = openShelf()
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
        local fm, view = openShelf()
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
        local fm, view = openShelf()
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

    it("removes a book from the shelf but keeps the file", function()
        local fm, view = openShelf()
        local actions = view:getBookActions(find(view, "d.txt"))
        actions[5].callback() -- Remove from shelf
        assert.are.same({ "b.epub", "e.pdf", "a.epub", "c.pdf" }, names(view.shown))
        assert.are.equal("file", lfs.attributes(bookPath("d.txt"), "mode"))
        fm:onClose()
        fm, view = openShelf()
        assert.is_nil(find(view, "d.txt"))
        assert.are.equal(1, view.counts.new)
        fm:onClose()
    end)

    it("switches tabs and pages with ui refreshes of the content only", function()
        local fm, view = openShelf()
        fastforward_ui_events()
        local refreshes = {}
        local orig_setDirty = UIManager.setDirty
        UIManager.setDirty = function(self, widget, refreshtype, region, ...)
            table.insert(refreshes, { type = refreshtype, region = region })
            return orig_setDirty(self, widget, refreshtype, region, ...)
        end
        view:setFilter("new")
        view:setPage(1)
        fm:switchTab("files")
        assert.are.equal(fm.files_ui, fm.content[1])
        fm:switchTab("shelf")
        assert.are.equal(fm.shelf_view, fm.content[1])
        UIManager.setDirty = orig_setDirty
        assert.is_true(#refreshes >= 6)
        local screen_h = require("device").screen:getHeight()
        for _, r in ipairs(refreshes) do
            assert.are.equal("ui", r.type)
            assert.is_true(r.region.h < screen_h)
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
end)
