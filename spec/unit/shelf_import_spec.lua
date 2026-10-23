-- 导入 and the two ways to 文件 (导入, 我), driven from the shelf home with a temporary home folder and the
-- real OPDS and calibre plugins.
describe("Shelf home, 导入 and 文件", function()
    local DataStorage, Event, FileManager, Geom, ImportPage, Key, LuaSettings, ReaderUI, Replacements, UIManager, Screen
    local BookSourceView, filemanagerutil, ffiUtil, lfs, T, _, C_
    local home, tmp, opds_settings, saved_settings
    local cleanup_files = {}

    local function dp(n) return Screen:scaleBySize(n) end

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function isShown(class)
        for __, w in ipairs(UIManager._window_stack) do
            if getmetatable(w.widget).__index == class then return true end
        end
        return false
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
    end

    -- the text of every TextWidget/TextBoxWidget under `widget`
    local function texts(widget, out)
        out = out or {}
        if type(widget) ~= "table" then return out end
        if widget.text and widget.face then table.insert(out, widget.text) end
        for __, child in ipairs(widget) do texts(child, out) end
        return out
    end

    local function contains(list, value)
        for __, v in ipairs(list) do
            if v == value then return true end
        end
        return false
    end

    -- Input is sent the way it arrives, and the screen is repainted after it, as before the next input.
    local function gesture(ges, x, y)
        UIManager:sendEvent(Event:new("Gesture", { ges = ges, pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
        UIManager:forceRePaint()
    end

    local function tap(rect)
        gesture("tap", rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2))
    end

    local function press(key_name)
        UIManager:sendEvent(Event:new("KeyPress", Key:new(key_name, {})))
        UIManager:forceRePaint()
    end

    -- the refreshes asked for: with setDirty, and by closing a widget
    local function spyRefreshes()
        local refreshes = {}
        local orig_setDirty, orig_refresh = UIManager.setDirty, UIManager._refresh
        UIManager.setDirty = function(self, widget, refreshtype, region, ...)
            if refreshtype then table.insert(refreshes, { type = refreshtype, region = region }) end
            return orig_setDirty(self, widget, refreshtype, region, ...)
        end
        UIManager._refresh = function(self, refreshtype, region, ...)
            if refreshtype then table.insert(refreshes, { type = refreshtype, region = region }) end
            return orig_refresh(self, refreshtype, region, ...)
        end
        return refreshes, function()
            UIManager.setDirty, UIManager._refresh = orig_setDirty, orig_refresh
        end
    end

    local function assertWholeScreenUi(refreshes)
        local screen, whole = Screen:getSize(), false
        assert.is_true(#refreshes > 0)
        for __, r in ipairs(refreshes) do
            assert.are.equal("ui", r.type)
            if r.region.x == 0 and r.region.y == 0 and r.region.w == screen.w and r.region.h == screen.h then
                whole = true
            end
        end
        assert.is_true(whole)
    end

    -- some refreshes were asked for, all "ui", and each of `rects` lies in one of them
    local function assertUiCovering(refreshes, rects)
        assert.is_true(#refreshes > 0)
        for __, r in ipairs(refreshes) do assert.are.equal("ui", r.type) end
        for __, rect in ipairs(rects) do
            local covered = false
            for i = 1, #refreshes do
                local region = refreshes[i].region
                if region and region:contains(rect) then covered = true end
            end
            assert.is_true(covered, tostring(rect))
        end
    end

    local function addFile(name, source)
        local path = home .. "/" .. name
        lfs.mkdir((path:match("^(.*)/")))
        ffiUtil.copyFile("spec/front/unit/data/" .. source, path)
        table.insert(cleanup_files, path)
        return path
    end

    local function openShelf()
        FileManager:showFiles(home)
        UIManager:forceRePaint()
        local fm = FileManager.instance
        fm.opds.settings_file = opds_settings
        fm.opds.settings = nil
        return fm, fm.shelf_view
    end

    --- Opens 导入 from the shelf's title row.
    local function openImport(fm)
        tap(fm.shelf_view.import_button.dimen)
        local page = topWidget()
        assert.are.equal(ImportPage, getmetatable(page).__index)
        return page
    end

    -- the bottom band of the file manager
    local function band(fm)
        return fm.layout_group[2][1]
    end

    local function closeAll()
        while UIManager._window_stack[2] do
            UIManager:close(topWidget())
        end
        if FileManager.instance then FileManager.instance:onClose() end
        UIManager:forceRePaint()
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("opds.koplugin")
        load_plugin("calibre.koplugin")
        package.path = "plugins/opds.koplugin/?.lua;" .. package.path
        require("document/canvascontext"):init(require("device"))
        DataStorage = require("datastorage")
        Event = require("ui/event")
        FileManager = require("apps/filemanager/filemanager")
        Geom = require("ui/geometry")
        Key = require("device/key")
        LuaSettings = require("luasettings")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        filemanagerutil = require("apps/filemanager/filemanagerutil")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        T = ffiUtil.template
        _ = require("gettext")
        C_ = _.pgettext
        require("apps/shelf/shelffilemanager") -- registers the replacements
        ImportPage = require("apps/shelf/importpage")
        BookSourceView = require("apps/opds/booksourceview")

        saved_settings = {}
        for __, key in ipairs{ "home_dir", "lastdir", "shelf_removed", "shelf_filter", "back_in_filemanager" } do
            saved_settings[key] = G_reader_settings:readSetting(key)
            G_reader_settings:delSetting(key)
        end
        tmp = ffiUtil.realpath(DataStorage:getDataDir()) .. "/shelf_import_spec"
        ffiUtil.purgeDir(tmp)
        lfs.mkdir(tmp)
        home = tmp .. "/home"
        lfs.mkdir(home)
        G_reader_settings:saveSetting("home_dir", home)
        addFile("juliet.epub", "juliet.epub")
        addFile("sub/leaves.epub", "leaves.epub")
        -- no 书源 added yet: the 书源 page opens on its source list, with nothing to fetch
        opds_settings = tmp .. "/opds.lua"
        local s = LuaSettings:open(opds_settings)
        s:saveSetting("servers", {})
        s:flush()
    end)

    teardown(function()
        closeAll()
        for __, path in ipairs(cleanup_files) do
            require("readhistory"):removeItemByPath(path)
        end
        for key, value in pairs(saved_settings) do
            G_reader_settings:saveSetting(key, value)
        end
        Replacements.filemanager = nil
        Replacements.opds_catalog = nil
        ffiUtil.purgeDir(tmp)
        disable_plugins()
    end)

    after_each(closeAll)

    it("opens from 导入 at the right of the title row: a card of the three routes over a circled ×", function()
        local fm, view = openShelf()
        local screen = Screen:getSize()
        -- 导入 ends at the right gutter, level with the 书架 title, with its circled plus
        local button = view.import_button
        assert.is_truthy(find(button, C_("Shelf", "Import")))
        assert.is_truthy(find(button, "eink/plus.circle"))
        assert.are.equal(screen.w - dp(22), button.dimen.x + button.dimen.w)
        assert.are.equal(view.title_button.dimen.y, button.dimen.y)
        assert.is_true(button.dimen.h >= dp(44))
        local refreshes, restore = spyRefreshes()
        local page = openImport(fm)
        restore()
        assertWholeScreenUi(refreshes)

        -- the routes, each with its tile; the real home folder is named
        local shown = texts(page)
        for __, str in ipairs{ _("Browse device files"), _("Download from book sources"), _("Transfer from a computer"),
                _("Files"), C_("Import page", "Book sources"), _("Calibre wireless connection"),
                T(_("Home folder: %1"), home) } do
            assert.is_true(contains(shown, str), str)
        end
        -- the 57dp × centered 44dp from the bottom, the card (at most 458dp wide) centered in the space above it
        local card = page.card.dimen
        assert.is_true(card.w <= dp(458))
        assert.is_true(math.abs(card.x + card.w / 2 - screen.w / 2) <= 1)
        local close = page.close_button.dimen
        assert.are.equal(dp(57), close.w)
        assert.is_true(math.abs(close.x + close.w / 2 - screen.w / 2) <= 1)
        assert.are.equal(screen.h - dp(44), close.y + close.h)
        local above = close.y - dp(34)
        assert.is_true(card.y + card.h <= above)
        assert.is_true(math.abs(card.y - (above - card.y - card.h)) <= 1)
        -- every tile is a big enough target, inside the card
        for __, label in ipairs{ _("Files"), C_("Import page", "Book sources"), _("Calibre wireless connection") } do
            local tile = find(page, label)
            assert.is_true(tile.dimen.h >= dp(44), label)
            assert.is_true(tile.dimen.x > card.x and tile.dimen.x + tile.dimen.w < card.x + card.w, label)
        end

        -- a tap outside the card and the × is the page's own, and changes nothing: here, over the shelf's 书源 tab
        local sources_tab = find(fm, "eink/compass").dimen
        assert.is_true(page:handleEvent(Event:new("Gesture", { ges = "tap",
            pos = Geom:new{ x = sources_tab.x + math.floor(sources_tab.w / 2), y = sources_tab.y + 1, w = 0, h = 0 } })))
        UIManager:forceRePaint()
        assert.are.equal(page, topWidget())
        assert.is_false(isShown(BookSourceView))
        -- the × goes back to the shelf with a ui refresh of the whole screen; so does Back
        refreshes, restore = spyRefreshes()
        tap(close)
        restore()
        assert.are.equal(fm, topWidget())
        assertWholeScreenUi(refreshes)
        openImport(fm)
        press("Back")
        assert.are.equal(fm, topWidget())
        assert.are.equal("shelf", fm.current_tab)
    end)

    it("names only the routes it has: without the OPDS and calibre plugins, USB alone", function()
        local fm = openShelf()
        local opds, calibre = fm.opds, fm.calibre
        fm.opds, fm.calibre = nil, nil
        local page = openImport(fm)
        fm.opds, fm.calibre = opds, calibre
        local shown = texts(page)
        assert.is_true(contains(shown, _("Browse device files")))
        assert.is_false(contains(shown, _("Download from book sources")))
        assert.is_false(contains(shown, C_("Import page", "Book sources")))
        assert.is_true(contains(shown, _("Copy books into the home folder over USB.")))
        assert.is_false(contains(shown, _("Calibre wireless connection")))
        assert.is_true(contains(shown, T(_("Home folder: %1"), home)))
    end)

    it("takes 文件 and comes back: the back arrow, or Back at the home folder, returns to 导入, then × to 书架", function()
        local fm = openShelf()
        local page = openImport(fm)
        local refreshes, restore = spyRefreshes()
        tap(find(page, _("Files")).dimen)
        restore()
        -- 文件 in the content area, the back arrow in place of the tab icons; one ui refresh covers the screen
        assert.are.equal(fm, topWidget())
        assert.are.equal("files", fm.current_tab)
        assert.are.equal(fm.files_ui, fm.content[1])
        assert.is_truthy(band(fm).back)
        assert.is_nil(find(fm, "eink/shelf.bold"))
        assertUiCovering(refreshes, { fm.content_dimen, fm.tabbar_dimen })
        -- the file browser works as before: into a folder, and Back goes up to home
        fm.file_chooser:changeToPath(home)
        UIManager:forceRePaint()
        tap(find(fm.files_ui, "sub").dimen)
        assert.are.equal(home .. "/sub", fm.file_chooser.path)
        assert.are.equal("files", fm.current_tab)
        press("Back")
        assert.are.equal(home, fm.file_chooser.path)
        assert.are.equal("files", fm.current_tab)
        -- Back at the home folder leaves 文件 for 导入, over the shelf
        press("Back")
        assert.are.equal("shelf", fm.current_tab)
        assert.are.equal(fm.shelf_view, fm.content[1])
        page = topWidget()
        assert.are.equal(ImportPage, getmetatable(page).__index)
        -- and the back arrow does the same
        tap(find(page, _("Files")).dimen)
        assert.are.equal("files", fm.current_tab)
        tap(band(fm).back.dimen)
        assert.are.equal("shelf", fm.current_tab)
        page = topWidget()
        assert.are.equal(ImportPage, getmetatable(page).__index)
        tap(page.close_button.dimen)
        assert.are.equal(fm, topWidget())
        assert.is_truthy(find(fm, "eink/shelf.bold"))
        -- with Back set to go to the parent folder, it goes past home, and leaves 文件 at "/"
        G_reader_settings:saveSetting("back_in_filemanager", "parent_folder")
        fm:openFiles()
        fm.file_chooser:changeToPath(home)
        press("Back")
        assert.are.equal(tmp, fm.file_chooser.path)
        fm.file_chooser:changeToPath("/")
        press("Back")
        assert.are.equal("shelf", fm.current_tab)
        G_reader_settings:delSetting("back_in_filemanager")
    end)

    it("goes back from 文件 to 导入 without rebuilding the shelf under it, and brings the shelf up to date on closing", function()
        local fm, view = openShelf()
        local leaves = home .. "/sub/leaves.epub"
        local function status()
            for __, book in ipairs(view.books) do
                if book.file == leaves then return book.status end
            end
        end
        assert.are.equal("new", status())
        local page = openImport(fm)
        tap(find(page, _("Files")).dimen)
        -- a status set in 文件, from a book's sheet
        fm.file_chooser:changeToPath(home .. "/sub")
        UIManager:forceRePaint()
        local row = find(fm.files_ui, "leaves.epub")
        gesture("hold", row.dimen.x + dp(10), row.dimen.y + dp(10))
        tap(find(topWidget(), _("Mark as finished")).dimen)
        local updates = 0
        local orig_update = view.update
        view.update = function(...)
            updates = updates + 1
            return orig_update(...)
        end
        local ok, err = pcall(function()
            tap(band(fm).back.dimen)
            assert.are.equal(ImportPage, getmetatable(topWidget()).__index)
            assert.are.equal(fm.shelf_view, fm.content[1])
            assert.are.equal(0, updates)
            tap(topWidget().close_button.dimen)
            fastforward_ui_events() -- the UI loop: due tasks, then the repaint
            assert.are.equal(1, updates)
            assert.are.equal("complete", status())
        end)
        view.update = nil
        assert(ok, err)
    end)

    it("takes 书源 over it, and leaving 书源 comes back to it", function()
        local fm = openShelf()
        local page = openImport(fm)
        tap(find(page, C_("Import page", "Book sources")).dimen)
        local sources = topWidget()
        assert.are.equal(BookSourceView, getmetatable(sources).__index)
        assert.are.equal("manage", sources:top().kind)
        assert.is_true(isShown(ImportPage))
        local refreshes, restore = spyRefreshes()
        press("Back")
        restore()
        assert.are.equal(page, topWidget())
        assertWholeScreenUi(refreshes)
        tap(page.close_button.dimen)
        assert.are.equal(fm, topWidget())
    end)

    it("starts calibre's wireless connection from its tile, or says it is connected", function()
        local PathChooser = require("ui/widget/pathchooser")
        local Notification = require("ui/widget/notification")
        local CalibreWireless = package.loaded["wireless"]
        local saved_inbox = G_reader_settings:readSetting("inbox_dir")
        G_reader_settings:delSetting("inbox_dir")
        local ok, err = pcall(function()
            local fm = openShelf()
            local page = openImport(fm)
            -- the plugin's own flow: with no folder for its books yet, it asks for one first, over the page
            tap(find(page, _("Calibre wireless connection")).dimen)
            assert.are.equal(PathChooser, getmetatable(topWidget()).__index)
            assert.is_true(isShown(ImportPage))
            UIManager:close(topWidget())
            UIManager:forceRePaint()
            assert.are.equal(page, topWidget())
            -- connected already: a toast says so, and nothing else opens
            CalibreWireless.calibre_socket = {}
            tap(find(page, _("Calibre wireless connection")).dimen)
            assert.is_true(isShown(Notification))
            assert.is_false(isShown(PathChooser))
            CalibreWireless.calibre_socket = nil
        end)
        CalibreWireless.calibre_socket = nil
        G_reader_settings:saveSetting("inbox_dir", saved_inbox)
        assert(ok, err)
    end)

    it("closes at once, and rescans the home folder after the shelf is repainted, redrawing only what changed", function()
        local Shelf = require("apps/shelf/shelf")
        local fm, view = openShelf()
        fastforward_ui_events()
        local count = #view.shown
        local page = openImport(fm)
        -- the order of things as the UI loop runs them on the device
        local order = {}
        local orig_repaint, orig_scan = UIManager._repaint, Shelf.scan
        UIManager._repaint = function(...)
            if #order == 0 or order[#order] ~= "repaint" then table.insert(order, "repaint") end
            return orig_repaint(...)
        end
        Shelf.scan = function(...)
            table.insert(order, "scan")
            return orig_scan(...)
        end
        local ok, err = pcall(function()
            -- nothing came in: the shelf shows again, is walked after that repaint, and nothing else is redrawn
            local close = page.close_button.dimen
            local refreshes, restore = spyRefreshes()
            UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = close.x + 5, y = close.y + 5, w = 0, h = 0 } }))
            assert.are.equal(fm, topWidget())
            assert.are.same({ "repaint" }, order) -- drawn before the tap's handler returns
            fastforward_ui_events() -- the UI loop: due tasks, then the repaint
            restore()
            assert.are.same({ "repaint", "scan", "repaint" }, order)
            assert.are.equal(1, #refreshes) -- the close, of the whole screen
            assertUiCovering(refreshes, { Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } })
            assert.are.equal(count, #view.shown)
        end)
        UIManager._repaint, Shelf.scan = orig_repaint, orig_scan
        assert(ok, err)
    end)

    it("shows books that came in while it was open once it closes", function()
        local fm, view = openShelf()
        local count = #view.shown
        local page = openImport(fm)
        -- as copied over USB or sent by calibre
        local path = addFile("arrived.epub", "juliet.epub")
        tap(page.close_button.dimen)
        assert.are.equal(count, #view.shown) -- not walked yet: the shelf shows again first
        local refreshes, restore = spyRefreshes()
        fastforward_ui_events() -- the UI loop: due tasks, then the repaint
        restore()
        -- the grid and the band are redrawn, nothing above
        assertUiCovering(refreshes, { view:gridRect() })
        for __, r in ipairs(refreshes) do assert.is_true(r.region.y >= view:gridRect().y) end
        assert.are.equal(count + 1, #view.shown)
        local found = false
        for __, book in ipairs(view.shown) do
            if book.file == path then found = true end
        end
        assert.is_true(found)
        os.remove(path)
    end)

    it("goes with the file manager when a book opens from a route over it", function()
        local fm = openShelf()
        openImport(fm)
        -- as 书源 does when a downloaded cover is tapped: it closes itself, then opens the book
        filemanagerutil.openFile(fm, home .. "/juliet.epub")
        fastforward_ui_events()
        local reader = ReaderUI.instance
        assert.is_truthy(reader)
        assert.is_false(isShown(ImportPage))
        reader:onClose()
        ReaderUI.instance = nil
    end)

    it("puts its × beside the card in landscape, where the card is too tall to sit above it", function()
        local fm = openShelf()
        local rotation = Screen:getRotationMode()
        fm:onSetRotationMode(rotation == 0 and 1 or 0)
        fm = FileManager.instance
        UIManager:forceRePaint()
        local ok, err = pcall(function()
            local screen = Screen:getSize()
            assert.is_true(screen.w > screen.h)
            local page = openImport(fm)
            local card, close = page.card.dimen, page.close_button.dimen
            assert.is_true(card.y >= 0 and card.y + card.h <= screen.h)
            assert.are.equal(card.x + card.w + dp(34), close.x)
            assert.is_true(close.x + close.w <= screen.w)
            assert.are.equal(card.y + card.h, close.y + close.h)
            tap(close)
            assert.are.equal(fm, topWidget())
        end)
        FileManager.instance:onSetRotationMode(rotation)
        assert(ok, err)
    end)

    it("opens 文件 from 我 on the folder its row names, and its back arrow returns to 我", function()
        local fm = openShelf()
        tap(find(fm, "eink/user").dimen)
        assert.are.equal("me", fm.current_tab)
        -- the row between 生词本 and 同步与传书, naming the folder 文件 opens on
        local row = find(fm.me_view, _("Files"))
        assert.is_truthy(row)
        assert.is_true(contains(texts(row), home))
        local refreshes, restore = spyRefreshes()
        tap(row.dimen)
        restore()
        assert.are.equal("files", fm.current_tab)
        assert.are.equal(fm.files_ui, fm.content[1])
        assert.are.equal(home, fm.file_chooser.path)
        assertUiCovering(refreshes, { fm.content_dimen, fm.tabbar_dimen })
        tap(find(fm.files_ui, "sub").dimen)
        tap(band(fm).back.dimen)
        assert.are.equal("me", fm.current_tab)
        assert.are.equal(fm.me_view, fm.content[1])
        assert.is_truthy(find(fm, "eink/user.bold"))
        -- left in a subfolder: the row names it, and 文件 opens there again
        row = find(fm.me_view, _("Files"))
        assert.is_true(contains(texts(row), home .. "/sub"))
        tap(row.dimen)
        assert.are.equal(home .. "/sub", fm.file_chooser.path)
    end)
end)
