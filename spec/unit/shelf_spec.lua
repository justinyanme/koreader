describe("Shelf home (FileManager replacement)", function()
    local DataStorage, DocSettings, Event, FileManager, Geom, Key, Palette, ReadHistory, ReaderUI, Replacements
    local SelectionBubble, ShelfView, UIManager, Screen
    local filemanagerutil, lfs, ffiUtil, util, T, _, C_
    local saved_settings
    local cleanup_files = {}

    local function dp(n) return Screen:scaleBySize(n) end

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    -- The innermost painted tap target around the first text or icon equal to `label` (or nil).
    local function find(node, label, around)
        if type(node) ~= "table" then return end
        if (node.callback or node.hold_callback or node.on_tap or node.onTapSelect) and node.dimen and node.dimen.x then
            around = node
        end
        if node.text == label or node.icon == label then return around or node end
        for __, child in ipairs(node) do
            local found = find(child, label, around)
            if found then return found end
        end
        for __, key in ipairs{ "frame", "content" } do
            local child = rawget(node, key)
            if type(child) == "table" and child ~= node then
                local found = find(child, label, around)
                if found then return found end
            end
        end
    end

    -- Input is sent the way it arrives, and the screen is repainted after it, as before the next input.
    local function gesture(ges, x, y)
        UIManager:sendEvent(Event:new("Gesture", { ges = ges, pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
        UIManager:forceRePaint()
    end

    local function tap(rect)
        gesture("tap", rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2))
    end

    local function swipe(direction)
        UIManager:sendEvent(Event:new("Gesture", { ges = "swipe", direction = direction, distance = 200, time = 0,
            pos = Geom:new{ x = Screen:getWidth() / 2, y = Screen:getHeight() / 2, w = 0, h = 0 } }))
        UIManager:forceRePaint()
    end

    local function press(key_name)
        UIManager:sendEvent(Event:new("KeyPress", Key:new(key_name, {})))
        UIManager:forceRePaint()
    end

    -- the painted gray level at (x, y): 0 is ink, 255 is paper
    local function gray(x, y)
        return Screen.bb:getPixel(x, y):getColor8().a
    end

    local function titleText(view)
        return view.title_button[1][1].text
    end

    -- the page capsule of the bottom band
    local function capsule(fm)
        return fm.layout_group[2][1].capsule
    end

    local function names(books)
        local list = {}
        for __, book in ipairs(books) do
            table.insert(list, (book.file:gsub(".*/", "")))
        end
        return list
    end

    local function openShelf(home)
        FileManager:showFiles(home)
        UIManager:forceRePaint()
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
        for __, b in ipairs(books) do
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
        Key = require("device/key")
        Palette = require("ui/palette")
        ReadHistory = require("readhistory")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        SelectionBubble = require("ui/widget/selectionbubble")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        filemanagerutil = require("apps/filemanager/filemanagerutil")
        lfs = require("libs/libkoreader-lfs")
        ffiUtil = require("ffi/util")
        util = require("util")
        T = ffiUtil.template
        _ = require("gettext")
        C_ = _.pgettext
        require("apps/shelf/shelffilemanager") -- registers the replacement
        ShelfView = require("apps/shelf/shelfview")
        saved_settings = {}
        for __, key in ipairs{ "home_dir", "lastdir", "shelf_removed", "shelf_sort", "shelf_filter", "back_in_filemanager" } do
            saved_settings[key] = G_reader_settings:readSetting(key)
            G_reader_settings:delSetting(key)
        end
    end)

    teardown(function()
        if FileManager.instance then FileManager.instance:onClose() end
        for __, path in ipairs(cleanup_files) do
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
        local function bookNamed(view, name)
            for __, book in ipairs(view.books) do
                if book.file == bookPath(name) then return book end
            end
        end

        before_each(function()
            G_reader_settings:delSetting("shelf_filter")
            G_reader_settings:delSetting("shelf_sort")
        end)

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

        it("puts the search field on top, then the 书架 title, then the covers, over the band of tab icons and the capsule", function()
            local fm, view = openShelf(home)
            local screen = Screen:getSize()
            local field = find(view, _("Search books"))
            local title = view.title_button
            assert.are.equal(_("Shelf"), titleText(view))
            -- the search field runs the width between the 22dp gutters, the title is under it at the left
            assert.are.equal(dp(22), field.dimen.x)
            assert.are.equal(screen.w - 2 * dp(22), field.dimen.w)
            assert.are.equal(dp(50), field.dimen.h)
            assert.are.equal(dp(22), title.dimen.x)
            assert.is_true(title.dimen.y >= field.dimen.y + field.dimen.h)
            local cover = find(view, "b") -- the first book's typographic cover
            assert.is_true(cover.dimen.y >= title.dimen.y + title.dimen.h)
            -- no chips, sort button or 书源 button on the shelf any more
            assert.is_nil(find(view, C_("Status of group of books", "Reading")))
            assert.is_nil(find(view, "eink/sliders"))
            assert.is_nil(find(view, "eink/source"))
            -- the bottom band: icons only, the current one filled, and the capsule at the right
            local band = fm.tabbar_dimen
            assert.are.equal(screen.h, band.y + band.h)
            assert.are.equal(dp(58), band.h)
            assert.are.equal(Palette.rule:getColor8().a, gray(math.floor(screen.w / 2), band.y))
            local tabs = {}
            for __, icon in ipairs{ "eink/shelf.bold", "eink/user" } do
                local tab = find(fm, icon)
                assert.is_truthy(tab, icon)
                assert.is_true(tab.dimen.y >= band.y and tab.dimen.h >= dp(44))
                table.insert(tabs, tab)
            end
            -- 书源 comes first only with its plugin (disabled here); 文件 has no tab, 导入 and 我 lead to it
            assert.is_nil(find(fm, "eink/compass"))
            assert.is_nil(find(fm, "eink/folder"))
            assert.are.equal(0, tabs[1].dimen.x)
            assert.are.equal(tabs[1].dimen.x + tabs[1].dimen.w, tabs[2].dimen.x)
            assert.are.equal(dp(91), tabs[1].dimen.w)
            local pager = capsule(fm)
            assert.is_true(pager.dimen.x > screen.w / 2 and pager.dimen.y > band.y)
            fm:onClose()
        end)

        it("filters from the title menu, 搁置 included, names the filter in the title and keeps it", function()
            local fm, view = openShelf(home)
            assert.are.same({ all = 5, reading = 1, new = 2, complete = 1, abandoned = 1 }, view.counts)
            local expected = {
                { "all", { "b.epub", "e.pdf", "a.epub", "d.txt", "c.pdf" } },
                { "reading", { "a.epub" } },
                { "new", { "d.txt", "c.pdf" } },
                { "complete", { "b.epub" } },
                { "abandoned", { "e.pdf" } },
            }
            local labels = {
                all = C_("Status of group of books", "All"),
                reading = C_("Status of group of books", "Reading"),
                new = C_("Status of group of books", "New"),
                complete = C_("Status of group of books", "Finished"),
                abandoned = C_("Status of group of books", "On hold"),
            }
            -- the menu lists the five filters with their counts, the current one framed; it is black and white: "fast"
            local refreshes, restore = spyRefreshes()
            tap(view.title_button.dimen)
            restore()
            local menu = topWidget()
            assert.are.same({ type = "fast", region = menu:getRefreshRegion(), requested = true }, refreshes[1])
            assert.are.equal(SelectionBubble, getmetatable(menu).__index)
            assert.are.equal(5, #menu.rows)
            for i, pair in ipairs(expected) do
                assert.is_truthy(find(menu.rows[i][1].widget, labels[pair[1]]))
                assert.is_truthy(find(menu.rows[i][1].widget, tostring(#pair[2])))
                assert.are.equal(i == 1, menu.rows[i][1].selected == true)
            end
            -- a tap beside it closes it and changes nothing
            refreshes, restore = spyRefreshes()
            gesture("tap", Screen:getWidth() - dp(10), view.dimen.h - dp(10))
            restore()
            assert.are.equal(fm, topWidget())
            assert.are.equal("all", view.filter)
            for __, r in ipairs(refreshes) do assert.are.equal("ui", r.type or "ui") end
            for i = 2, #expected do
                local filter, list = expected[i][1], expected[i][2]
                tap(view.title_button.dimen)
                refreshes, restore = spyRefreshes()
                tap(find(topWidget(), labels[filter]).dimen)
                restore()
                assert.are.equal(fm, topWidget())
                assert.are.equal(filter, view.filter)
                assert.are.same(list, names(view.shown))
                assert.are.equal(labels[filter] .. " ▾", titleText(view))
                -- from the title row down and the band, nothing above
                for __, r in ipairs(refreshes) do
                    assert.are.equal("ui", r.type or "ui")
                    if r.requested then assert.is_true(r.region.y >= view:titleRect().y) end
                end
            end
            -- the filter stays across visits
            fm:onClose()
            fm, view = openShelf(home)
            assert.are.equal("abandoned", view.filter)
            assert.are.equal(labels.abandoned .. " ▾", titleText(view))
            assert.are.same({ "e.pdf" }, names(view.shown))
            -- 全部 reads plain 书架
            tap(view.title_button.dimen)
            tap(find(topWidget(), labels.all).dimen)
            assert.are.equal(_("Shelf"), titleText(view))
            assert.are.equal("all", G_reader_settings:readSetting("shelf_filter"))
            local on_hold = bookNamed(view, "sub/e.pdf")
            assert.are.equal(C_("Shelf book status", "On hold"), ShelfView.statusText(on_hold))
            fm:onClose()
        end)

        it("marks finished books with the 读完 tag at the cover's top right, and nothing else", function()
            local fm, view = openShelf(home)
            local finished = C_("Status of single book", "Finished")
            for __, book in ipairs(view.shown) do
                local title = book.file:gsub(".*/", ""):gsub("%.%w+$", "")
                local cell = find(view, title)
                assert.is_truthy(cell, title)
                local cover = cell[1][1] -- the cover, or the cover with the tag over it
                if book.status == "complete" then
                    local tag = cover[2]
                    assert.is_truthy(find(tag, finished) or find(tag, util.splitToChars(finished)[1]))
                    assert.are.equal(cover[1].dimen.x + cover[1].dimen.w, tag.dimen.x + tag.dimen.w)
                    assert.are.equal(cover[1].dimen.y, tag.dimen.y)
                else
                    assert.is_nil(find(cell, finished))
                end
                -- no downloaded check before local titles, and one bold line under the cover: no status line
                assert.is_nil(find(cell, "eink/check"))
                local column = cell[1]
                assert.are.equal(3, #column)
                assert.are.equal(book.title, column[3].text)
                assert.is_true(column[3].bold)
            end
            fm:onClose()
        end)

        it("orders the shelf from 设置 → 书架, 最近阅读 by default, and keeps the order", function()
            local fm, view = openShelf(home)
            fm:handleEvent(Event:new("ShowEinkSettings", "shelf"))
            UIManager:forceRePaint()
            local settings = topWidget()
            local row = find(settings, _("Sort by"))
            assert.is_truthy(row)
            assert.is_truthy(find(row, _("Recently read")))
            tap(row.dimen)
            assert.are.equal(_("Sort by"), settings.title)
            tap(find(settings, _("Title")).dimen)
            assert.are.equal("title", G_reader_settings:readSetting("shelf_sort"))
            -- the shelf is reordered under the settings page, and shows it once the page closes
            assert.are.same({ "a.epub", "b.epub", "c.pdf", "d.txt", "e.pdf" }, names(view.shown))
            local refreshes, restore = spyRefreshes()
            tap(settings.bar.back.dimen)
            tap(settings.bar.back.dimen)
            restore()
            assert.are.equal(fm, topWidget())
            -- closing the page repaints the whole screen, which shows the new order
            assert.is_true(#refreshes > 0)
            local screen, whole = Screen:getSize(), false
            for __, r in ipairs(refreshes) do
                assert.are.equal("ui", r.type or "ui")
                if r.region and r.region.x == 0 and r.region.y == 0 and r.region.w == screen.w and r.region.h == screen.h then
                    whole = true
                end
            end
            assert.is_true(whole)
            fm:onClose()
            fm, view = openShelf(home)
            assert.are.same({ "a.epub", "b.epub", "c.pdf", "d.txt", "e.pdf" }, names(view.shown))
            -- searching still narrows the shelf in place until the search page replaces it
            view:setQuery("B")
            assert.are.same({ "b.epub" }, names(view.shown))
            assert.are.equal(1, view.counts.all)
            view:setQuery(nil)
            -- and back to 最近阅读
            fm:handleEvent(Event:new("ShowEinkSettings", "shelf_sort"))
            UIManager:forceRePaint()
            settings = topWidget()
            tap(find(settings, _("Recently read")).dimen)
            settings:closeMenu()
            UIManager:forceRePaint()
            assert.are.same({ "b.epub", "e.pdf", "a.epub", "d.txt", "c.pdf" }, names(view.shown))
            fm:onClose()
        end)

        it("changes status from the long-press actions", function()
            local fm, view = openShelf(home)
            local actions = view:getBookActions(bookNamed(view, "a.epub"))
            assert.are.equal(5, #actions)
            actions[4].callback() -- Put on hold
            assert.are.same({ all = 5, reading = 0, new = 2, complete = 1, abandoned = 2 }, view.counts)
            assert.are.equal("abandoned", DocSettings:open(bookPath("a.epub")):readSetting("summary").status)
            actions = view:getBookActions(bookNamed(view, "a.epub"))
            actions[4].callback() -- Mark as reading
            assert.are.equal(1, view.counts.reading)
            fm:onClose()
        end)

        it("removes a book from the shelf but keeps the file, until the book is opened again", function()
            local fm, view = openShelf(home)
            view:getBookActions(bookNamed(view, "d.txt"))[5].callback() -- Remove from shelf
            assert.are.same({ "b.epub", "e.pdf", "a.epub", "c.pdf" }, names(view.shown))
            assert.are.equal("file", lfs.attributes(bookPath("d.txt"), "mode"))
            fm:onClose()
            fm, view = openShelf(home)
            assert.is_nil(bookNamed(view, "d.txt"))
            assert.are.equal(1, view.counts.new)
            fm:onClose()
            -- opened again (from 文件 or anywhere): back on the shelf
            ReadHistory:addItem(bookPath("d.txt"), os.time() + 10)
            fm, view = openShelf(home)
            assert.is_truthy(bookNamed(view, "d.txt"))
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
            fm:openFiles()
            assert.are.equal(fm.files_ui, fm.content[1])
            fm:closeFiles()
            assert.are.equal(fm.shelf_view, fm.content[1])
            restore()
            assert.is_true(#refreshes >= 5)
            local screen_h = require("device").screen:getHeight()
            for __, r in ipairs(refreshes) do
                assert.are.equal("ui", r.type)
                -- requested rects stay inside the content or the tab bar (UIManager may merge adjacent ones)
                if r.requested then
                    assert.is_true(r.region.h < screen_h)
                end
            end
            fm:switchTab("me")
            assert.are.equal(fm.me_view, fm.content[1])
            -- rotation rebuilds the layout and keeps 文件, and where it was opened from
            fm:openFiles()
            fm:reinit()
            assert.are.equal(fm.files_ui, fm.content[1])
            tap(fm.layout_group[2][1].back.dimen)
            assert.are.equal("me", fm.current_tab)
            assert.are.equal(fm.me_view, fm.content[1])
            fm:onClose()
        end)

        it("brings 文件 forward when the file browser is sent to a folder", function()
            local fm = openShelf(home)
            assert.are.equal("shelf", fm.current_tab)
            filemanagerutil.genShowFolderButton(bookPath("sub/c.pdf"), function() end).callback()
            assert.are.equal("files", fm.current_tab)
            assert.are.equal(fm.files_ui, fm.content[1])
            assert.are.equal(home .. "/sub", fm.file_chooser.path)
            -- a folder change inside 文件 keeps it, and the back arrow returns to 书架
            fm.file_chooser:changeToPath(home)
            assert.are.equal("files", fm.current_tab)
            tap(fm.layout_group[2][1].back.dimen)
            assert.are.equal("shelf", fm.current_tab)
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
                for __, r in ipairs(refreshes) do
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
                -- the home opened on 文件: its back arrow leads to 书架
                tap(fm.layout_group[2][1].back.dimen)
                assert.are.equal("shelf", fm.current_tab)
                assert.are.equal(fm.shelf_view, fm.content[1])
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

        it("opens a book from a tap on its cover, where it was left, and puts it first when back", function()
            local fm, view = openShelf(home)
            assert.are.equal("shelf", fm.current_tab)
            assert.are.equal("b.epub", names(view.shown)[1])
            tap(find(view, "a").dimen)
            fastforward_ui_events()
            local reader = ReaderUI.instance
            assert.is_truthy(reader)
            assert.are.equal(bookPath("a.epub"), reader.document.file)
            reader:handleEvent(Event:new("GotoPage", 3))
            local page = reader:getCurrentPage()
            assert.are.equal(3, page)
            reader:onHome()
            fm = FileManager.instance
            view = fm.shelf_view
            UIManager:forceRePaint()
            assert.are.equal("shelf", fm.current_tab)
            assert.are.equal("a.epub", names(view.shown)[1])
            tap(find(view, "a").dimen)
            fastforward_ui_events()
            reader = ReaderUI.instance
            assert.are.equal(bookPath("a.epub"), reader.document.file)
            assert.are.equal(page, reader:getCurrentPage())
            reader:onHome()
            FileManager.instance:onClose()
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

        before_each(function()
            G_reader_settings:delSetting("shelf_filter")
        end)

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
                prepare = function(_conn, sql)
                    table.insert(stub.sqls, sql)
                    local list = {}
                    for __, row in pairs(stub.rows) do table.insert(list, row) end
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
            for __, sql in ipairs(stub.sqls) do
                assert.is_nil(sql:find("cover_bb_data", 1, true))
            end
            -- only book03 has a usable cover; book02's is ignored
            for __, file in ipairs(stub.cover_reads) do
                assert.are.equal(home .. "/book03.txt", file)
            end
            local by_file = {}
            for __, book in ipairs(view.books) do by_file[book.file:gsub(".*/", "")] = book end
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

        it("turns pages from the band's capsule, swipes up and down and the page keys, gray at the ends", function()
            local fm, view = openShelf(home)
            view:stop()
            local per_page = view.grid.cols * view.grid.rows
            local function showsPage(p)
                return find(view, view.shown[(p - 1) * per_page + 1].title) ~= nil
                    and (p == 1 or find(view, view.shown[(p - 2) * per_page + 1].title) == nil)
            end
            local pager = capsule(fm)
            local top = pager.dimen.y
            local left_x, right_x = pager.dimen.x + math.floor(pager.dimen.w / 4), pager.dimen.x + math.floor(pager.dimen.w * 3 / 4)
            assert.is_false(pager.prev_enabled)
            assert.is_true(pager.next_enabled)
            assert.are.equal(Palette.rule:getColor8().a, gray(left_x, top))
            assert.are.equal(Palette.ink:getColor8().a, gray(right_x, top))
            -- a page turn repaints the grid and the band, nothing above
            local refreshes, restore = spyRefreshes()
            tap(pager.next_rect)
            restore()
            assert.are.equal(2, view.page)
            assert.is_true(showsPage(2))
            assert.is_true(#refreshes > 0)
            for __, r in ipairs(refreshes) do
                assert.are.equal("ui", r.type or "ui")
                if r.requested then assert.is_true(r.region.y >= view:gridRect().y) end
            end
            pager = capsule(fm)
            assert.is_true(pager.prev_enabled)
            assert.are.equal(Palette.ink:getColor8().a, gray(left_x, top))
            -- as on full-screen pages: up to the next page, down to the previous one; and the page keys
            swipe("north")
            assert.are.equal(3, view.page)
            swipe("south")
            assert.are.equal(2, view.page)
            press("RPgFwd")
            assert.are.equal(3, view.page)
            press("LPgBack")
            assert.are.equal(2, view.page)
            tap(capsule(fm).prev_rect)
            assert.are.equal(1, view.page)
            assert.is_true(showsPage(1))
            -- the last page: the down half is gray and does nothing
            for __ = 2, view.pages do
                tap(capsule(fm).next_rect)
            end
            assert.are.equal(view.pages, view.page)
            pager = capsule(fm)
            assert.is_false(pager.next_enabled)
            assert.are.equal(Palette.rule:getColor8().a, gray(right_x, top))
            refreshes, restore = spyRefreshes()
            tap(pager.next_rect)
            restore()
            assert.are.equal(view.pages, view.page)
            assert.are.same({}, refreshes)
            -- 我 pages itself: the capsule is gray, and the keys leave the shelf alone
            tap(find(fm, "eink/user").dimen)
            assert.are.equal("me", fm.current_tab)
            assert.is_truthy(find(fm, "eink/user.bold"))
            pager = capsule(fm)
            assert.is_false(pager.prev_enabled or pager.next_enabled)
            press("LPgBack")
            assert.are.equal(view.pages, view.page)
            -- on 文件 (from 我) the file browser takes the page keys, as before
            tap(find(fm.me_view, _("Files")).dimen)
            assert.are.equal("files", fm.current_tab)
            local fc_page = fm.file_chooser.page
            press("RPgFwd")
            assert.are.equal(fc_page + 1, fm.file_chooser.page)
            assert.are.equal(view.pages, view.page)
            -- back to 我, then on 书架, on the page it was left
            tap(capsule(fm).dimen) -- gray on 文件: nothing happens
            assert.are.equal("files", fm.current_tab)
            tap(fm.layout_group[2][1].back.dimen)
            assert.are.equal("me", fm.current_tab)
            tap(find(fm, "eink/shelf").dimen)
            assert.are.equal("shelf", fm.current_tab)
            assert.are.equal(view.pages, view.page)
            assert.is_true(capsule(fm).prev_enabled)
            fm:onClose()
        end)

        it("lays four columns out on a 7-inch panel, the next page's first row cut off under the band", function()
            local orig_dpi = Screen.getDPI
            Screen.getDPI = function() return 142 end -- 600px across a Leaf5's 4.2 inches
            local long_title = "A title far too long to fit on one line under its cover"
            addRow("book04.txt", { title = long_title })
            local ok, err = pcall(function()
                local fm, view = openShelf(home)
                view:stop()
                local g = view.grid
                assert.are.equal(4, g.cols)
                -- 22dp gutters and gaps, covers about 123 × 178dp, one bold title line ending in an ellipsis
                assert.are.equal(dp(22), g.gutter)
                assert.is_true(math.abs(g.col_gap - dp(22)) <= 1)
                assert.is_true(math.abs(g.cover_w - dp(122)) <= 1)
                assert.are.equal(math.floor(g.cover_w * 1.45 + 0.5), g.cover_h)
                local cell = find(view, long_title)
                local title = cell[1][3]
                assert.are.equal(long_title, title.text)
                assert.is_true(title.bold)
                assert.is_true(title:isTruncated())
                assert.is_true(title:getSize().w <= g.cover_w)
                -- under the whole rows, the next page's first row, cut off by the band
                assert.is_truthy(g.peek)
                local per_page = g.cols * g.rows
                local next_book = view.shown[per_page + 1]
                local peek = find(view, next_book.title)
                local grid = view:gridRect()
                local band = fm.tabbar_dimen
                assert.is_truthy(peek)
                assert.are.equal(grid.y + g.rows * (g.cell_h + g.row_gap), peek.dimen.y)
                assert.is_true(peek.dimen.y + peek.dimen.h > band.y)
                -- the band is painted over it, and takes the touches there
                local x = peek.dimen.x + math.floor(peek.dimen.w / 2)
                assert.are.equal(Palette.paper:getColor8().a, gray(x, band.y + dp(4)))
                gesture("hold", x, band.y + math.floor(band.h / 2))
                assert.are.equal(fm, topWidget())
                -- what shows of it is the book
                gesture("hold", x, band.y - dp(10))
                assert.are_not.equal(fm, topWidget())
                assert.are.equal(next_book.title, topWidget().title)
                topWidget():onClose()
                UIManager:forceRePaint()
                -- turning the page brings that row to the top
                tap(capsule(fm).next_rect)
                assert.are.equal(grid.y, find(view, next_book.title).dimen.y)
                fm:onClose()
            end)
            Screen.getDPI = orig_dpi
            stub.rows[home .. "/book04.txt"] = nil
            assert(ok, err)
        end)

        it("says so when a filter has no books, with the capsule gray", function()
            local fm, view = openShelf(home)
            view:stop()
            tap(view.title_button.dimen)
            tap(find(topWidget(), C_("Status of group of books", "Reading")).dimen)
            assert.are.same({}, view.shown)
            assert.is_truthy(find(view, _("No books here yet.")))
            local pager = capsule(fm)
            assert.is_false(pager.prev_enabled or pager.next_enabled)
            tap(view.title_button.dimen)
            tap(find(topWidget(), C_("Status of group of books", "All")).dimen)
            assert.are.equal(_("Shelf"), titleText(view))
            fm:onClose()
        end)

        it("repaints the title row when indexing ends under a book's sheet, which only repaints itself on closing", function()
            stub.jobs = {}
            local added = {}
            local ok, err = pcall(function()
                local fm, view = openShelf(home)
                -- indexing under way: its progress is in the title row
                stub.extracting = false
                view:pollExtraction()
                UIManager:forceRePaint()
                local progress = T(_("Indexing books %1 / %2…"), 0, 42)
                assert.is_truthy(find(view, progress))
                -- a book's long-press sheet covers the lower part of the shelf
                local cell = find(view, view.shown[1].title)
                gesture("hold", cell.dimen.x + dp(10), cell.dimen.y + dp(10))
                local sheet = topWidget()
                assert.are_not.equal(fm, sheet)
                assert.is_false(view:titleRect():intersectWith(sheet.sheet_dimen))
                -- indexing ends under it: the cache now has every book
                for __, book in ipairs(view.books) do
                    if book.needs_extract then
                        addRow((book.file:gsub(".*/", "")))
                        table.insert(added, book.file)
                    end
                end
                local refreshes, restore = spyRefreshes()
                stub.extracting = false
                view:pollExtraction()
                UIManager:forceRePaint()
                assert.is_nil(view.extracting)
                -- a tap beside the sheet closes it; the title row was repainted without the progress
                gesture("tap", math.floor(Screen:getWidth() / 2), dp(20))
                restore()
                assert.are.equal(fm, topWidget())
                assert.is_nil(find(view, progress))
                local title_repainted = false
                for __, r in ipairs(refreshes) do
                    assert.are.equal("ui", r.type or "ui")
                    if r.region and r.region:intersectWith(view:titleRect()) then title_repainted = true end
                end
                assert.is_true(title_repainted)
            end)
            for __, file in ipairs(added) do stub.rows[file] = nil end
            while topWidget() ~= FileManager.instance do UIManager:close(topWidget()) end
            FileManager.instance:onClose()
            assert(ok, err)
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
            -- the progress shows beside the title
            assert.is_truthy(find(view, T(_("Indexing books %1 / %2…"), 0, 42)))
            -- the job is killed before writing anything: the same books are queued again
            stub.extracting = false
            view:pollExtraction()
            assert.are.equal(2, #stub.jobs)
            assert.are.same(stub.jobs[1], stub.jobs[2])
            -- this time it completes; the 2 books left come next
            for __, f in ipairs(stub.jobs[2]) do addRow((f.filepath:gsub(".*/", ""))) end
            stub.extracting = false
            view:pollExtraction()
            assert.are.equal(3, #stub.jobs)
            assert.are.equal(2, #stub.jobs[3])
            for __, f in ipairs(stub.jobs[3]) do addRow((f.filepath:gsub(".*/", ""))) end
            stub.extracting = false
            view:pollExtraction()
            assert.is_nil(view.extracting)
            assert.are.equal(3, #stub.jobs)
            fm:onClose()
        end)
    end)
end)
