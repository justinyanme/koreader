describe("Shelf home (FileManager replacement)", function()
    local DataStorage, DocSettings, Event, FileManager, Geom, Key, Palette, ReadHistory, ReaderUI, Replacements
    local SelectionBubble, ShelfView, UIManager, Screen
    local filemanagerutil, lfs, ffiUtil, util, T, _, C_, N_, NC_
    local saved_settings
    local cleanup_files = {}

    local function dp(n) return Screen:scaleBySize(n) end

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    -- The text of the toast on screen, if any.
    local function toastText()
        for __, window in ipairs(UIManager._window_stack) do
            if window.widget.toast then return window.widget.text end
        end
    end

    local function closeToasts()
        for i = #UIManager._window_stack, 1, -1 do
            local widget = UIManager._window_stack[i].widget
            if widget.toast then UIManager:close(widget) end
        end
        UIManager:forceRePaint()
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
        N_ = _.ngettext
        NC_ = _.npgettext
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

    describe("shelf state from the reader toolbar", function()
        local home, old_menu
        before_each(function()
            old_menu = Replacements.reader_menu
            Replacements.reader_menu = require("apps/reader/modules/readertoolbar")
            G_reader_settings:delSetting("shelf_removed")
            G_reader_settings:delSetting("shelf_filter")
            home = makeHome("reader_shelf_home", {
                { name = "book.epub", source = "juliet.epub", status = "complete" },
                { name = "book.pdf", source = "sample.pdf", status = "abandoned" },
            })
        end)
        after_each(function()
            closeToasts()
            if ReaderUI.instance then ReaderUI.instance:onClose() end
            if FileManager.instance then FileManager.instance:onClose() end
            Replacements.reader_menu = old_menu
            G_reader_settings:delSetting("shelf_removed")
            ffiUtil.purgeDir(home)
        end)

        local function toolbar()
            gesture("tap", Screen:getWidth() / 2, Screen:getHeight() / 2)
            return ReaderUI.instance.menu.bars
        end

        for __, name in ipairs{ "book.epub", "book.pdf" } do
            it("confirms hiding, keeps it hidden on exit and reopen, and explicitly restores " .. name, function()
                local path = home .. "/" .. name
                local original = util.readFromFile(path)
                ReaderUI:doShowReader(path)
                UIManager:forceRePaint()
                local page = ReaderUI.instance:getCurrentPage()
                tap(find(toolbar(), "eink/shelf-on").dimen)
                local layer = topWidget()
                assert.are.equal(require("ui/widget/confirmlayer"), getmetatable(layer).__index)
                assert.is_truthy(layer.text:find(ReaderUI.instance.doc_props.display_title, 1, true))
                tap(find(layer, _("Cancel")).dimen)
                assert.are.equal(page, ReaderUI.instance:getCurrentPage())
                assert.is_nil(G_reader_settings:readSetting("shelf_removed"))
                tap(find(toolbar(), "eink/shelf-on").dimen)
                press("Back")
                assert.are.equal(ReaderUI.instance, topWidget())
                tap(find(toolbar(), "eink/shelf-on").dimen)
                tap(find(topWidget(), C_("Shelf", "Remove")).dimen)
                assert.are.equal(_("Removed from shelf"), toastText())
                assert.are.equal(page, ReaderUI.instance:getCurrentPage())
                assert.are.equal(original, util.readFromFile(path))
                local bars = toolbar()
                assert.is_truthy(find(bars, "eink/shelf"))
                tap(find(bars.bottom, "eink/arrow.left").dimen)
                local fm = FileManager.instance
                assert.are.equal(1, #fm.shelf_view.books)
                assert.are_not.equal(path, fm.shelf_view.books[1].file)
                fm:onClose()
                -- Reopen the file through the real ReaderUI entry, without adding it back implicitly.
                ReaderUI:doShowReader(path)
                UIManager:forceRePaint()
                bars = toolbar()
                assert.is_truthy(find(bars, "eink/shelf"))
                local icon_rect = find(bars, "eink/shelf").dimen:copy()
                local refreshes, restore = spyRefreshes()
                tap(icon_rect)
                restore()
                assert.are.equal(_("Added to shelf"), toastText())
                assert.are.equal(bars, ReaderUI.instance.menu.bars)
                local icon_refreshed = false
                for __, r in ipairs(refreshes) do
                    if r.requested then
                        assert.are.equal("fast", r.type)
                        if icon_rect:contains(r.region) then
                            icon_refreshed = true
                        else
                            assert.is_true(topWidget().dimen:contains(r.region)) -- the toast only
                        end
                    end
                end
                assert.is_true(icon_refreshed)
                assert.is_truthy(find(bars, "eink/shelf-on"))
                tap(find(bars.bottom, "eink/arrow.left").dimen)
                fm = FileManager.instance
                assert.are.equal(2, #fm.shelf_view.books)
                assert.are.equal(1, fm.shelf_view.counts.complete)
                assert.are.equal(1, fm.shelf_view.counts.abandoned)
                assert.are.equal(original, util.readFromFile(path))
            end)
        end

        it("shares removal and restoration between a shelf symlink and its target opened from history", function()
            local target = home .. "/book.epub"
            local link = home .. "/linked.epub"
            assert(lfs.link(target, link, true))
            -- A persisted removal from the old shelf may use the link's path.
            G_reader_settings:saveSetting("shelf_removed", { [link] = os.time() })
            ReaderUI:doShowReader(target)
            UIManager:forceRePaint()
            local bars = toolbar()
            assert.is_truthy(find(bars, "eink/shelf"))
            tap(find(bars, "eink/shelf").dimen)
            assert.is_truthy(find(bars, "eink/shelf-on"))
            tap(find(bars.bottom, "eink/arrow.left").dimen)
            assert.are.equal(3, #FileManager.instance.shelf_view.books)
            FileManager.instance:onClose()
            ReaderUI:doShowReader(target)
            UIManager:forceRePaint()
            tap(find(toolbar(), "eink/shelf-on").dimen)
            tap(find(topWidget(), C_("Shelf", "Remove")).dimen)
            bars = toolbar()
            tap(find(bars.bottom, "eink/arrow.left").dimen)
            assert.are.equal(1, #FileManager.instance.shelf_view.books)
            assert.are.equal("link", lfs.symlinkattributes(link, "mode"))
            assert.are.equal("file", lfs.attributes(target, "mode"))
        end)

        it("immediately hides every alias when a shelf cover is removed in selection mode", function()
            local target, link = home .. "/book.epub", home .. "/linked.epub"
            assert(lfs.link(target, link, true))
            local fm, view = openShelf(home)
            assert.are.equal(3, #view.books)
            local cell = find(view, "linked")
            assert.is_truthy(cell)
            gesture("hold", cell.dimen.x + view.grid.cover_w / 2, cell.dimen.y + view.grid.cover_h / 2)
            tap(find(fm, "eink/shelf.remove").dimen)
            tap(find(topWidget(), C_("Shelf", "Remove")).dimen)
            assert.are.equal(1, #view.books)
            assert.are.equal(home .. "/book.pdf", view.books[1].file)
            assert.are.equal("file", lfs.attributes(target, "mode"))
            assert.are.equal("link", lfs.symlinkattributes(link, "mode"))
            closeToasts()
            fm:onClose()
            fm, view = openShelf(home)
            assert.are.equal(1, #view.books)
        end)

        it("retains hidden books on an unavailable volume and only prunes after it returns", function()
            local attributes = lfs.attributes
            local online = true
            local device = attributes(home, "dev")
            lfs.attributes = function(path, key)
                if key == "dev" and online and (path == home or path:sub(1, #home + 1) == home .. "/") then
                    return device + 1 -- filesystem boundary, independent of the Docker mount layout
                end
                return attributes(path, key)
            end
            local ok, err = pcall(function()
                ReaderUI:doShowReader(home .. "/book.epub")
                UIManager:forceRePaint()
                tap(find(toolbar(), "eink/shelf-on").dimen)
                tap(find(topWidget(), C_("Shelf", "Remove")).dimen)
                closeToasts()
                ReaderUI.instance:onClose()
                assert(os.rename(home, home .. ".offline"))
                assert(lfs.mkdir(home)) -- an unmounted volume can leave its mountpoint behind
                online = false
                local fm = openShelf(home)
                assert.is_truthy(G_reader_settings:readSetting("shelf_removed")[home .. "/book.epub"])
                fm:onClose()
                assert(lfs.rmdir(home))
                assert(os.rename(home .. ".offline", home))
                online = true
                fm = openShelf(home)
                assert.are.equal(1, #fm.shelf_view.books)
                fm:onClose()
                assert(os.remove(home .. "/book.epub"))
                fm = openShelf(home)
                assert.is_nil(G_reader_settings:readSetting("shelf_removed")[home .. "/book.epub"])
                fm:onClose()
            end)
            lfs.attributes = attributes
            if lfs.attributes(home .. ".offline") then
                ffiUtil.purgeDir(home)
                os.rename(home .. ".offline", home)
            end
            assert(ok, err)
        end)

        it("checks reader membership without enumerating the home tree", function()
            ReaderUI:doShowReader(home .. "/book.epub")
            UIManager:forceRePaint()
            local dir = lfs.dir
            lfs.dir = function() error("toolbar must not enumerate directories") end
            local ok, err = pcall(function()
                assert.is_truthy(find(toolbar(), "eink/shelf-on"))
            end)
            lfs.dir = dir
            assert(ok, err)
        end)

        it("does not show a picture opened from the home folder as a shelf book", function()
            local path = home .. "/photo.png"
            Screen:shot(path)
            table.insert(cleanup_files, path)
            ReaderUI:doShowReader(path)
            UIManager:forceRePaint()
            local bars = toolbar()
            assert.is_nil(find(bars, "eink/shelf-on"))
            assert.is_truthy(find(bars, "eink/shelf"))
            tap(find(bars.bottom, "eink/arrow.left").dimen)
            assert.are.equal(2, #FileManager.instance.shelf_view.books)
        end)

        it("explains the home-folder rule for an outside book without pretending it was added", function()
            local path = ffiUtil.realpath("spec/front/unit/data/juliet.epub")
            ReaderUI:doShowReader(path)
            UIManager:forceRePaint()
            tap(find(toolbar(), "eink/shelf").dimen)
            local message = topWidget()
            assert.are.equal(T(_("To add this book to the shelf, place its file in the home folder:\n%1"), home), message.text)
            UIManager:close(message)
            local bars = toolbar()
            assert.is_nil(find(bars, "eink/shelf-on"))
            tap(find(bars.bottom, "eink/arrow.left").dimen)
            assert.are.equal(2, #FileManager.instance.shelf_view.books)
            assert.are.equal("file", lfs.attributes(path, "mode"))
        end)
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
                local cover = cell[1][1][1] -- the cover, or the cover with the tag over it, in its selection-mode frame
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

        it("changes status from the book sheet's actions, which 文件 shows on a long press", function()
            local fm, view = openShelf(home)
            local actions = view:getBookActions(bookNamed(view, "a.epub"))
            assert.are.equal(5, #actions)
            actions[4].callback() -- Put on hold
            assert.are.same({ all = 5, reading = 0, new = 2, complete = 1, abandoned = 2 }, view.counts)
            assert.are.equal("abandoned", DocSettings:open(bookPath("a.epub")):readSetting("summary").status)
            assert.are.equal(T(N_("Marked 1 book as %2", "Marked %1 books as %2", 1), 1,
                C_("Status of single book", "On hold")), toastText())
            actions = view:getBookActions(bookNamed(view, "a.epub"))
            actions[4].callback() -- Mark as reading
            assert.are.equal(1, view.counts.reading)
            closeToasts()
            fm:onClose()
        end)

        it("keeps a removed book hidden even when its reading history changes", function()
            local fm, view = openShelf(home)
            view:getBookActions(bookNamed(view, "d.txt"))[5].callback() -- Remove from shelf, once confirmed
            UIManager:forceRePaint()
            tap(find(topWidget(), C_("Shelf", "Remove")).dimen)
            assert.are.same({ "b.epub", "e.pdf", "a.epub", "c.pdf" }, names(view.shown))
            assert.are.equal("file", lfs.attributes(bookPath("d.txt"), "mode"))
            closeToasts()
            fm:onClose()
            fm, view = openShelf(home)
            assert.is_nil(bookNamed(view, "d.txt"))
            assert.are.equal(1, view.counts.new)
            fm:onClose()
            -- Reading and closing update history, but must not undo an explicit removal.
            ReadHistory:addItem(bookPath("d.txt"), os.time() + 10)
            fm, view = openShelf(home)
            assert.is_nil(bookNamed(view, "d.txt"))
            assert.is_truthy(G_reader_settings:readSetting("shelf_removed")[bookPath("d.txt")])
            fm:onClose()
            ReadHistory:removeItemByPath(bookPath("d.txt"))
            lfs.touch(bookPath("d.txt"), 800, 800)
        end)

        it("retains legacy missing entries whose volume is unknown", function()
            G_reader_settings:saveSetting("shelf_removed", { [home .. "/gone.epub"] = os.time() })
            local fm = openShelf(home)
            assert.is_truthy(G_reader_settings:readSetting("shelf_removed")[home .. "/gone.epub"])
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

    describe("in selection mode", function()
        local home
        local count = 14
        local function bookPath(i) return string.format("%s/s%02d.txt", home, i) end
        local function title(i) return string.format("s%02d", i) end

        -- The cover of a book on the page shown, from its cell (the tap target around its title).
        local function coverRect(view, i)
            local cell = find(view, title(i))
            if not cell then return end
            return Geom:new{ x = cell.dimen.x, y = cell.dimen.y, w = view.grid.cover_w, h = view.grid.cover_h }
        end

        -- A selected cover has an ink frame around it.
        local function framed(view, i)
            local cover = coverRect(view, i)
            return gray(cover.x - dp(2), cover.y + math.floor(cover.h / 2)) == Palette.ink:getColor8().a
        end

        local function selectedTitle(n)
            return T(NC_("Shelf", "1 book selected", "%1 books selected", n), n)
        end

        -- Every refresh is "ui", each requested one lies inside one of `allowed`, and each rect of `covered` is
        -- inside a requested one.
        local function assertUiRefreshes(refreshes, allowed, covered)
            assert.is_true(#refreshes > 0)
            for __, r in ipairs(refreshes) do
                assert.are.equal("ui", r.type)
                if r.requested then
                    local inside = false
                    for __, rect in ipairs(allowed) do
                        if rect:contains(r.region) then inside = true end
                    end
                    assert.is_true(inside, tostring(r.region))
                end
            end
            for __, rect in ipairs(covered) do
                local repainted = false
                for __, r in ipairs(refreshes) do
                    if r.requested and r.region:contains(rect) then repainted = true end
                end
                assert.is_true(repainted, tostring(rect))
            end
        end

        -- From the title row down to the band.
        local function belowHeader(view)
            local row = view:titleRect()
            return Geom:new{ x = 0, y = row.y, w = view.width, h = view.height - (row.y - view.dimen.y) }
        end

        before_each(function()
            G_reader_settings:delSetting("shelf_filter")
            G_reader_settings:delSetting("shelf_sort")
            G_reader_settings:delSetting("shelf_removed")
        end)

        setup(function()
            local books = {}
            -- unread books, newest first: s01, s02, …
            for i = 1, count do
                table.insert(books, { name = string.format("s%02d.txt", i), source = "sample.txt", mtime = 2000 - i })
            end
            home = makeHome("shelf_select_home", books)
        end)

        teardown(function()
            ffiUtil.purgeDir(home)
        end)

        it("enters from 选择 with nothing selected, selects covers instead of opening them, and leaves with 取消", function()
            local fm, view = openShelf(home)
            local screen_w = Screen:getWidth()
            -- 选择 ends the title row, after 导入
            local select = find(view, _("Select"))
            local import = find(view, C_("Shelf", "Import"))
            assert.is_truthy(select)
            assert.is_true(select.dimen.x > import.dimen.x + import.dimen.w)
            assert.are.equal(screen_w - dp(22), select.dimen.x + select.dimen.w)
            assert.is_truthy(find(select, "eink/check.circle"))
            local refreshes, restore = spyRefreshes()
            tap(select.dimen)
            restore()
            -- 全选 at the left, 选择书籍 in the middle, 取消 at the right, all over the title row
            local all, heading, cancel = find(view, _("Select all")), find(view, _("Select books")), find(view, _("Cancel"))
            assert.is_truthy(all)
            assert.is_truthy(heading)
            assert.is_truthy(cancel)
            assert.is_nil(find(view, _("Shelf")))
            assert.is_nil(find(view, C_("Shelf", "Import")))
            local row = view:titleRect()
            assert.are.equal(dp(22), all.dimen.x)
            assert.are.equal(screen_w - dp(22), cancel.dimen.x + cancel.dimen.w)
            -- the heading's ink is centered on the screen
            local min_x, max_x
            for x = all.dimen.x + all.dimen.w + dp(4), cancel.dimen.x - dp(4) do
                for y = row.y, row.y + row.h - 1 do
                    if gray(x, y) < 0x80 then
                        min_x, max_x = min_x or x, x
                        break
                    end
                end
            end
            assert.is_truthy(min_x)
            assert.is_true(math.abs((min_x + max_x) / 2 - screen_w / 2) <= 2)
            for __, target in ipairs{ all, cancel } do
                assert.is_true(target.dimen.w >= dp(44) and target.dimen.h >= dp(44))
                assert.is_true(target.dimen.y >= row.y and target.dimen.y + target.dimen.h <= row.y + row.h)
            end
            -- the band swaps the tab icons for 移出书架 and 标记为, gray while nothing is selected
            assert.is_nil(find(fm, "eink/shelf.bold"))
            assert.is_nil(find(fm, "eink/user"))
            local remove, mark = find(fm, "eink/shelf.remove"), find(fm, "eink/mark")
            assert.is_truthy(remove)
            assert.is_truthy(mark)
            assert.is_true(remove.dimen.y >= fm.tabbar_dimen.y and mark.dimen.x >= remove.dimen.x + remove.dimen.w)
            tap(remove.dimen)
            tap(mark.dimen)
            assert.are.equal(fm, topWidget())
            -- from the title row down and the band, as "ui": the title row, the covers' rings and the band
            assertUiRefreshes(refreshes, { belowHeader(view), fm.tabbar_dimen },
                { row, coverRect(view, 1), fm.tabbar_dimen })
            -- a tap on a cover selects it and never opens the book
            assert.is_false(framed(view, 2))
            refreshes, restore = spyRefreshes()
            tap(coverRect(view, 2))
            restore()
            assert.are.equal(fm, topWidget())
            assert.is_nil(ReaderUI.instance)
            assert.is_true(framed(view, 2))
            assert.is_false(framed(view, 1))
            assert.is_truthy(find(view, selectedTitle(1)))
            -- only the cover with its frame, the title row and the band (its actions now enabled) were repainted
            local cover = coverRect(view, 2)
            local around = Geom:new{ x = cover.x - dp(5), y = cover.y - dp(5), w = cover.w + dp(10), h = cover.h + dp(10) }
            assertUiRefreshes(refreshes, { around, row, fm.tabbar_dimen }, { cover, row, fm.tabbar_dimen })
            tap(coverRect(view, 3))
            assert.is_truthy(find(view, selectedTitle(2)))
            -- a second tap leaves it out again
            tap(coverRect(view, 2))
            assert.is_false(framed(view, 2))
            assert.is_truthy(find(view, selectedTitle(1)))
            -- 取消 leaves selection mode: the shelf as it was, and a tap opens books again
            tap(find(view, _("Cancel")).dimen)
            assert.are.equal(_("Shelf"), titleText(view))
            assert.is_truthy(find(fm, "eink/shelf.bold"))
            assert.is_nil(find(fm, "eink/shelf.remove"))
            assert.is_false(framed(view, 3))
            -- entering again starts with nothing selected
            tap(find(view, _("Select")).dimen)
            assert.is_truthy(find(view, _("Select books")))
            assert.is_false(framed(view, 3))
            fm:onClose()
        end)

        it("enters on a long press with that book selected, and Back leaves it", function()
            local fm, view = openShelf(home)
            local refreshes, restore = spyRefreshes()
            local cover = coverRect(view, 4)
            gesture("hold", cover.x + dp(10), cover.y + dp(10))
            restore()
            -- no sheet, no book opened: selection mode with s04 selected
            assert.are.equal(fm, topWidget())
            assert.is_nil(ReaderUI.instance)
            assert.is_truthy(find(view, selectedTitle(1)))
            assert.is_true(framed(view, 4))
            assert.is_truthy(find(fm, "eink/shelf.remove"))
            assertUiRefreshes(refreshes, { belowHeader(view), fm.tabbar_dimen },
                { view:titleRect(), coverRect(view, 4), fm.tabbar_dimen })
            -- another long press selects that one too, and one on a selected cover leaves it out
            gesture("hold", coverRect(view, 5).x + dp(10), coverRect(view, 5).y + dp(10))
            assert.is_truthy(find(view, selectedTitle(2)))
            gesture("hold", cover.x + dp(10), cover.y + dp(10))
            assert.is_truthy(find(view, selectedTitle(1)))
            assert.is_false(framed(view, 4))
            -- Back leaves selection mode, not the shelf
            press("Back")
            assert.are.equal(fm, topWidget())
            assert.are.equal(FileManager.instance, fm)
            assert.is_nil(view.selected)
            assert.are.equal(_("Shelf"), titleText(view))
            assert.is_false(framed(view, 5))
            fm:onClose()
        end)

        it("selects across pages, and 全选 takes the whole shelf, not only the page", function()
            local fm, view = openShelf(home)
            assert.is_true(view.pages > 1)
            local per_page = view.grid.cols * view.grid.rows
            tap(find(view, _("Select")).dimen)
            tap(coverRect(view, 1))
            -- the next page: s01 stays selected while another is picked there
            tap(capsule(fm).next_rect)
            assert.are.equal(2, view.page)
            local on_next = per_page + 1
            assert.is_false(framed(view, on_next))
            tap(coverRect(view, on_next))
            assert.is_truthy(find(view, selectedTitle(2)))
            swipe("south")
            assert.are.equal(1, view.page)
            assert.is_true(framed(view, 1))
            assert.is_false(framed(view, 2))
            -- 全选: every book on every page, and it turns into 取消全选
            local refreshes, restore = spyRefreshes()
            tap(find(view, _("Select all")).dimen)
            restore()
            assert.is_truthy(find(view, selectedTitle(count)))
            assert.is_nil(find(view, _("Select all")))
            assert.is_truthy(find(view, _("Deselect all")))
            for i = 1, per_page do assert.is_true(framed(view, i)) end
            assertUiRefreshes(refreshes, { belowHeader(view), fm.tabbar_dimen },
                { view:titleRect(), coverRect(view, 1), coverRect(view, per_page) })
            for __ = 2, view.pages do tap(capsule(fm).next_rect) end
            assert.is_true(framed(view, count))
            -- leaving one out brings 全选 back
            tap(coverRect(view, count))
            assert.is_truthy(find(view, selectedTitle(count - 1)))
            assert.is_truthy(find(view, _("Select all")))
            tap(coverRect(view, count))
            -- 取消全选 clears the selection and stays in selection mode, the actions gray again
            tap(find(view, _("Deselect all")).dimen)
            assert.is_truthy(find(view, _("Select books")))
            assert.is_false(framed(view, count))
            local remove = find(fm, "eink/shelf.remove")
            tap(remove.dimen)
            assert.are.equal(fm, topWidget())
            fm:onClose()
        end)

        it("keeps selection mode and the selection when the home is rebuilt (rotation) or refreshed", function()
            local fm, view = openShelf(home)
            tap(find(view, _("Select")).dimen)
            tap(coverRect(view, 2))
            tap(coverRect(view, 3))
            local function stillSelecting()
                view = fm.shelf_view
                assert.is_truthy(find(view, selectedTitle(2)))
                assert.is_true(framed(view, 2) and framed(view, 3))
                assert.is_false(framed(view, 1))
                assert.is_nil(find(fm, "eink/shelf.bold"))
                assert.is_truthy(find(fm, "eink/shelf.remove"))
            end
            -- rotation lays the home out again, with a new shelf view
            local before = view
            fm:reinit()
            UIManager:forceRePaint()
            assert.are_not.equal(before, fm.shelf_view)
            stillSelecting()
            -- a refresh (books changed on the device) walks the home folder again
            fm:onRefresh()
            UIManager:forceRePaint()
            stillSelecting()
            -- and the actions still take the selection
            tap(find(fm, "eink/mark").dimen)
            assert.are.equal(T(N_("Mark 1 book as", "Mark %1 books as", 2), 2), topWidget().text)
            tap(find(topWidget(), _("Cancel")).dimen)
            fm:onClose()
        end)

        it("follows a rescan: a selected book that leaves is no longer counted, nor selected when it comes back", function()
            local away = home .. "_away_s03.txt"
            local new_book = home .. "/s00.txt"
            local ok, err = pcall(function()
                local fm, view = openShelf(home)
                tap(find(view, _("Select")).dimen)
                tap(coverRect(view, 2))
                tap(coverRect(view, 3))
                assert.is_truthy(find(view, selectedTitle(2)))
                -- s03 is moved off the home folder (over USB, say): gone, and out of the count
                os.rename(bookPath(3), away)
                fm:onRefresh()
                UIManager:forceRePaint()
                assert.is_nil(find(view, title(3)))
                assert.is_truthy(find(view, selectedTitle(1)))
                assert.is_true(framed(view, 2))
                -- a book that comes in is not selected
                local f = io.open(new_book, "w")
                f:write("Sample text.\n")
                f:close()
                lfs.touch(new_book, 3000, 3000)
                fm:onRefresh()
                UIManager:forceRePaint()
                assert.is_truthy(find(view, title(0)))
                assert.is_false(framed(view, 0))
                assert.is_truthy(find(view, selectedTitle(1)))
                -- s03 back: on the shelf again, not selected
                os.rename(away, bookPath(3))
                fm:onRefresh()
                UIManager:forceRePaint()
                assert.is_truthy(find(view, title(3)))
                assert.is_false(framed(view, 3))
                assert.is_truthy(find(view, selectedTitle(1)))
                -- 全选 counts what is shown
                tap(find(view, _("Select all")).dimen)
                assert.is_truthy(find(view, selectedTitle(count + 1)))
                fm:onClose()
            end)
            if lfs.attributes(away, "mode") then os.rename(away, bookPath(3)) end
            os.remove(new_book)
            assert(ok, err)
        end)

        it("takes no taps on the search field or its clear button while selecting", function()
            local fm, view = openShelf(home)
            local function inputDialog()
                for __, window in ipairs(UIManager._window_stack) do
                    if window.widget.getInputText then return window.widget end
                end
            end
            -- a search narrows the shelf in place
            tap(find(view, _("Search books")).dimen)
            local dialog = inputDialog()
            assert.is_truthy(dialog)
            dialog:setInputText("s0")
            tap(find(dialog, _("Search")).dimen)
            assert.is_nil(inputDialog())
            assert.are.equal(9, #view.shown)
            tap(find(view, _("Select")).dimen)
            -- the field and its clear button do nothing while selecting
            local refreshes, restore = spyRefreshes()
            tap(find(view, "s0").dimen)
            local clear = find(view, "close")
            tap(clear.dimen)
            restore()
            assert.is_nil(inputDialog())
            assert.are.equal(fm, topWidget())
            assert.are.equal(9, #view.shown)
            assert.is_truthy(find(view, _("Select books")))
            assert.are.same({}, refreshes)
            -- out of selection mode, they work again
            tap(find(view, _("Cancel")).dimen)
            tap(clear.dimen)
            assert.are.equal(count, #view.shown)
            fm:onClose()
        end)

        it("says which statuses could not be saved, and leaves those books as they were", function()
            -- a folder that takes no settings file: read-only, with KOReader's own docsettings folder blocked too
            -- (by a file where the book's folder there would go), so DocSettings has nowhere to fall back to
            local folder = home .. "/zz_ro"
            local book = folder .. "/ro.txt"
            local fallback = DocSettings:getSidecarDir(book, "dir")
            local util_ = require("util")
            local ok, err = pcall(function()
                lfs.mkdir(folder)
                local f = io.open(book, "w")
                f:write("Sample text.\n")
                f:close()
                lfs.touch(book, 3000, 3000) -- first on the shelf
                f = io.open(folder .. "/ro.sdr", "w") -- in case the tests run as root, where the mode is ignored
                f:close()
                os.execute("chmod 555 '" .. folder .. "'")
                util_.makePath((fallback:match("^(.*)/")))
                f = io.open(fallback, "w")
                f:close()
                local fm, view = openShelf(home)
                local finished = C_("Status of single book", "Finished")
                local function holdReadOnly()
                    local cell = find(view, "ro")
                    gesture("hold", cell.dimen.x + dp(10), cell.dimen.y + dp(10))
                end
                assert.is_truthy(find(view, "ro"))
                -- three books, one of which cannot be saved
                tap(find(view, _("Select")).dimen)
                tap(find(view, "ro").dimen)
                tap(coverRect(view, 1))
                tap(coverRect(view, 2))
                tap(find(fm, "eink/mark").dimen)
                tap(find(topWidget(), finished).dimen)
                assert.are.equal(T(_("Marked %1 of %2 books as %3. The rest could not be saved."), 2, 3, finished),
                    toastText())
                closeToasts()
                assert.are.same({ all = count + 1, reading = 0, new = count - 1, complete = 2, abandoned = 0 }, view.counts)
                assert.are.equal("new", view.shown[1].status)
                assert.is_false(DocSettings:hasSidecarFile(book))
                assert.is_nil(find(find(view, "ro"), finished))
                assert.are.equal("complete", DocSettings:open(bookPath(1)):readSetting("summary").status)
                -- that book alone
                holdReadOnly()
                tap(find(fm, "eink/mark").dimen)
                tap(find(topWidget(), C_("Status of single book", "On hold")).dimen)
                assert.are.equal(T(N_("Could not save the status of 1 book.", "Could not save the status of %1 books.", 1), 1),
                    toastText())
                closeToasts()
                assert.are.equal("new", view.shown[1].status)
                -- read-only alone, the status goes to KOReader's docsettings folder, and is saved
                os.remove(fallback)
                holdReadOnly()
                tap(find(fm, "eink/mark").dimen)
                tap(find(topWidget(), C_("Status of single book", "On hold")).dimen)
                assert.are.equal(T(N_("Marked 1 book as %2", "Marked %1 books as %2", 1), 1,
                    C_("Status of single book", "On hold")), toastText())
                closeToasts()
                assert.are.equal("abandoned", DocSettings:open(book):readSetting("summary").status)
                fm:onClose()
            end)
            DocSettings:open(book):purge()
            os.execute("chmod 755 '" .. folder .. "'")
            os.remove(fallback)
            ffiUtil.purgeDir(folder)
            for _, path in ipairs{ book, bookPath(1), bookPath(2) } do
                DocSettings:open(path):purge()
                require("ui/widget/booklist").resetBookInfoCache(path)
            end
            assert(ok, err)
        end)

        it("takes only the books of the current filter with 全选", function()
            for i = 1, 3 do
                local doc_settings = DocSettings:open(bookPath(i))
                doc_settings:saveSetting("summary", { status = "reading" })
                doc_settings:flush()
                require("ui/widget/booklist").resetBookInfoCache(bookPath(i))
            end
            local ok, err = pcall(function()
                local fm, view = openShelf(home)
                tap(view.title_button.dimen)
                tap(find(topWidget(), C_("Status of group of books", "Reading")).dimen)
                assert.are.equal(3, #view.shown)
                tap(find(view, _("Select")).dimen)
                tap(find(view, _("Select all")).dimen)
                assert.is_truthy(find(view, selectedTitle(3)))
                assert.is_truthy(find(view, _("Deselect all")))
                fm:onClose()
            end)
            for i = 1, 3 do
                DocSettings:open(bookPath(i)):purge()
                require("ui/widget/booklist").resetBookInfoCache(bookPath(i))
            end
            assert(ok, err)
        end)

        it("removes the selected books from the shelf once confirmed, and keeps their files", function()
            local fm, view = openShelf(home)
            local before = names(view.shown)
            tap(find(view, _("Select")).dimen)
            tap(coverRect(view, 2))
            tap(coverRect(view, 3))
            -- 移出书架 asks first, over the washed shelf
            local refreshes, restore = spyRefreshes()
            tap(find(fm, "eink/shelf.remove").dimen)
            restore()
            local layer = topWidget()
            assert.are.equal(require("ui/widget/confirmlayer"), getmetatable(layer).__index)
            assert.are.equal(T(N_("Remove 1 book from the shelf? The file stays on the device.",
                "Remove %1 books from the shelf? The files stay on the device.", 2), 2), layer.text)
            assert.are.same({ type = "ui", region = layer:getRefreshRegion(), requested = true }, refreshes[1])
            -- 取消 changes nothing: still selecting the same two books
            tap(find(layer, _("Cancel")).dimen)
            assert.are.equal(fm, topWidget())
            assert.are.same(before, names(view.shown))
            assert.is_nil(G_reader_settings:readSetting("shelf_removed"))
            assert.is_truthy(find(view, selectedTitle(2)))
            assert.is_true(framed(view, 2) and framed(view, 3))
            -- confirmed: hidden from the shelf, the files stay, and selection mode ends
            tap(find(fm, "eink/shelf.remove").dimen)
            tap(find(topWidget(), C_("Shelf", "Remove")).dimen)
            assert.is_nil(view.selected)
            assert.are.equal(_("Shelf"), titleText(view))
            assert.is_truthy(find(fm, "eink/shelf.bold"))
            assert.are.equal(count - 2, #view.shown)
            assert.is_nil(find(view, title(2)))
            assert.is_nil(find(view, title(3)))
            for i = 2, 3 do
                assert.are.equal("file", lfs.attributes(bookPath(i), "mode"))
            end
            -- written to the settings file at once, as the next start reads it (not only when KOReader quits)
            local on_disk = require("luasettings"):open(G_reader_settings.file):readSetting("shelf_removed")
            assert.is_truthy(on_disk[bookPath(2)])
            assert.is_truthy(on_disk[bookPath(3)])
            assert.are.equal(T(N_("Removed 1 book from the shelf. The file stays on the device.",
                "Removed %1 books from the shelf. The files stay on the device.", 2), 2), toastText())
            closeToasts()
            -- still hidden the next time
            fm:onClose()
            fm, view = openShelf(home)
            assert.are.equal(count - 2, #view.shown)
            assert.is_nil(find(view, title(2)))
            -- one book: asked by its title; a tap on the washed page cancels too
            tap(find(view, _("Select")).dimen)
            tap(coverRect(view, 5))
            tap(find(fm, "eink/shelf.remove").dimen)
            assert.are.equal(T(_("Remove “%1” from the shelf? The file stays on the device."), title(5)), topWidget().text)
            gesture("tap", math.floor(Screen:getWidth() / 2), dp(40))
            assert.are.equal(fm, topWidget())
            assert.is_truthy(find(view, title(5)))
            assert.is_truthy(find(view, selectedTitle(1)))
            tap(find(fm, "eink/shelf.remove").dimen)
            tap(find(topWidget(), C_("Shelf", "Remove")).dimen)
            assert.is_nil(find(view, title(5)))
            assert.are.equal(T(_("Removed from shelf. The file is still in %1"),
                filemanagerutil.abbreviate(home)), toastText())
            closeToasts()
            fm:onClose()
        end)

        it("marks the selected books 读完, 在读 or 搁置, saved with each book", function()
            local ok, err = pcall(function()
                local fm, view = openShelf(home)
                assert.are.equal(count, view.counts.new)
                tap(find(view, _("Select")).dimen)
                tap(coverRect(view, 1))
                tap(coverRect(view, 2))
                tap(find(fm, "eink/mark").dimen)
                local layer = topWidget()
                assert.are.equal(require("ui/widget/confirmlayer"), getmetatable(layer).__index)
                assert.are.equal(T(N_("Mark 1 book as", "Mark %1 books as", 2), 2), layer.text)
                local labels = { C_("Status of single book", "Finished"), C_("Status of single book", "Reading"),
                    C_("Status of single book", "On hold"), _("Cancel") }
                local y = 0
                for __, label in ipairs(labels) do
                    local row = find(layer, label)
                    assert.is_truthy(row, label)
                    assert.is_true(row.dimen.y > y) -- in this order
                    y = row.dimen.y
                end
                -- 取消 changes nothing
                tap(find(layer, _("Cancel")).dimen)
                assert.are.equal(fm, topWidget())
                assert.is_false(DocSettings:hasSidecarFile(bookPath(1)))
                assert.is_truthy(find(view, selectedTitle(2)))
                -- 读完: both get the tag, and selection mode ends
                tap(find(fm, "eink/mark").dimen)
                tap(find(topWidget(), C_("Status of single book", "Finished")).dimen)
                assert.is_nil(view.selected)
                assert.is_truthy(find(fm, "eink/shelf.bold"))
                assert.are.same({ all = count, reading = 0, new = count - 2, complete = 2, abandoned = 0 }, view.counts)
                local finished = C_("Status of single book", "Finished")
                for i = 1, 2 do
                    local cell = find(view, title(i))
                    assert.is_truthy(find(cell, finished) or find(cell, util.splitToChars(finished)[1]))
                    assert.are.equal("complete", DocSettings:open(bookPath(i)):readSetting("summary").status)
                end
                assert.are.equal(T(N_("Marked 1 book as %2", "Marked %1 books as %2", 2), 2, finished), toastText())
                closeToasts()
                -- kept with the books: the next time, and under the 读完 filter
                fm:onClose()
                require("ui/widget/booklist").book_info_cache = {}
                fm, view = openShelf(home)
                assert.are.equal(2, view.counts.complete)
                -- one book, asked by its title: 搁置, then 在读
                local cover = coverRect(view, 1)
                gesture("hold", cover.x + dp(10), cover.y + dp(10))
                tap(find(fm, "eink/mark").dimen)
                assert.are.equal(T(_("Mark “%1” as"), title(1)), topWidget().text)
                tap(find(topWidget(), C_("Status of single book", "On hold")).dimen)
                closeToasts()
                assert.are.equal("abandoned", DocSettings:open(bookPath(1)):readSetting("summary").status)
                assert.are.same({ all = count, reading = 0, new = count - 2, complete = 1, abandoned = 1 }, view.counts)
                tap(view.title_button.dimen)
                tap(find(topWidget(), C_("Status of group of books", "On hold")).dimen)
                assert.are.same({ "s01.txt" }, names(view.shown))
                tap(find(view, _("Select")).dimen)
                tap(find(view, _("Select all")).dimen)
                tap(find(fm, "eink/mark").dimen)
                tap(find(topWidget(), C_("Status of single book", "Reading")).dimen)
                closeToasts()
                assert.are.equal("reading", DocSettings:open(bookPath(1)):readSetting("summary").status)
                -- out of the 搁置 filter now
                assert.are.same({}, view.shown)
                fm:onClose()
            end)
            for i = 1, 2 do
                DocSettings:open(bookPath(i)):purge()
                require("ui/widget/booklist").resetBookInfoCache(bookPath(i))
            end
            G_reader_settings:delSetting("shelf_filter")
            assert(ok, err)
        end)

        it("keeps both title rows apart and 44dp to tap at the largest interface font size", function()
            local Font = require("ui/font")
            local saved = G_reader_settings:readSetting("ui_font_scale")
            Font:setUIScale(1.35)
            local ok, err = pcall(function()
                local fm, view = openShelf(home)
                local touch, screen_w = dp(44), Screen:getWidth()
                local row = view:titleRect()
                local title, import, select = view.title_button, view.import_button, view.select_button
                assert.is_true(title.dimen.x + title.dimen.w < import.dimen.x)
                assert.is_true(import.dimen.x + import.dimen.w < select.dimen.x)
                assert.are.equal(screen_w - dp(22), select.dimen.x + select.dimen.w)
                tap(select.dimen)
                tap(find(view, _("Select all")).dimen)
                -- the longest labels: 取消全选 and the count of the whole shelf
                local all, cancel = find(view, _("Deselect all")), find(view, _("Cancel"))
                assert.is_truthy(find(view, selectedTitle(count)))
                for __, target in ipairs{ all, cancel, find(fm, "eink/shelf.remove"), find(fm, "eink/mark") } do
                    assert.is_true(target.dimen.w >= touch and target.dimen.h >= touch)
                end
                assert.is_true(all.dimen.y >= row.y and all.dimen.y + all.dimen.h <= row.y + row.h)
                -- the count is whole, and (centered on the screen) clear of both
                local heading = find(view, selectedTitle(count))
                local w = heading:getSize().w
                assert.is_false(heading:isTruncated())
                assert.is_true((screen_w - w) / 2 > all.dimen.x + all.dimen.w)
                assert.is_true((screen_w + w) / 2 < cancel.dimen.x)
                fm:onClose()
            end)
            Font:setUIScale(1)
            if saved == nil then G_reader_settings:delSetting("ui_font_scale") end
            assert(ok, err)
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
            -- on 文件 (from 我) the file browser takes the page keys, as before, and the capsule turns its pages
            tap(find(fm.me_view, _("Files")).dimen)
            assert.are.equal("files", fm.current_tab)
            local fc_page = fm.file_chooser.page
            press("RPgFwd")
            assert.are.equal(fc_page + 1, fm.file_chooser.page)
            assert.are.equal(fm.file_chooser.page, capsule(fm).page)
            tap(capsule(fm).prev_rect)
            assert.are.equal(fc_page, fm.file_chooser.page)
            assert.are.equal(view.pages, view.page)
            -- back to 我, then on 书架, on the page it was left
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
                assert.is_nil(view.selected)
                -- what shows of it is the book: a long press selects it
                gesture("hold", x, band.y - dp(10))
                assert.are.equal(fm, topWidget())
                assert.is_truthy(find(view, T(NC_("Shelf", "1 book selected", "%1 books selected", 1), 1)))
                assert.are.same({ next_book }, view:selectedBooks())
                tap(find(view, _("Cancel")).dimen)
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

        it("repaints the title row when indexing ends under the filter menu, which only repaints itself on closing", function()
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
                -- the filter menu is over part of the shelf
                tap(view.title_button.dimen)
                local menu = topWidget()
                assert.are_not.equal(fm, menu)
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
                restore()
                assert.is_nil(view.extracting)
                -- the title row was repainted without the progress, under the menu
                local title_repainted = false
                assert.is_true(#refreshes > 0)
                for __, r in ipairs(refreshes) do
                    assert.are.equal("ui", r.type)
                    if r.requested and r.region:contains(view:titleRect()) then title_repainted = true end
                end
                assert.is_true(title_repainted)
                -- a tap beside the menu closes it
                gesture("tap", Screen:getWidth() - dp(10), view.dimen.h - dp(10))
                assert.are.equal(fm, topWidget())
                assert.is_nil(find(view, progress))
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
