describe("Files tab (FileManager replacement)", function()
    local DocSettings, Event, FileChooser, FileManager, Geom, Replacements, UIManager
    local ffiUtil, lfs, util, _
    local saved_settings
    local home

    local function find(widget, pred)
        if type(widget) ~= "table" then return end
        if pred(widget) then return widget end
        for _, child in ipairs(widget) do
            local found = find(child, pred)
            if found then return found end
        end
    end

    -- every text drawn by `widget`
    local function texts(widget, list)
        list = list or {}
        if type(widget) ~= "table" then return list end
        if type(widget.text) == "string" then table.insert(list, widget.text) end
        for _, child in ipairs(widget) do texts(child, list) end
        return list
    end

    local function has(list, text)
        for _, t in ipairs(list) do
            if t == text then return true end
        end
        return false
    end

    -- the innermost tappable region drawing `text`
    local function tappable(widget, text)
        local found
        find(widget, function(w)
            if w.callback and w.ges_events and find(w, function(c) return c.text == text end) then
                found = w
            end
        end)
        return found
    end

    local function gesture(ges, widget)
        UIManager:forceRePaint()
        local pos = Geom:new{ x = widget.dimen.x + math.floor(widget.dimen.w / 2), y = widget.dimen.y + math.floor(widget.dimen.h / 2), w = 0, h = 0 }
        UIManager:sendEvent(Event:new("Gesture", { ges = ges, pos = pos }))
    end

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function spyRefreshes()
        local refreshes = {}
        local orig = UIManager.setDirty
        UIManager.setDirty = function(self, widget, refreshtype, region, ...)
            if refreshtype then table.insert(refreshes, { type = refreshtype, region = region }) end
            return orig(self, widget, refreshtype, region, ...)
        end
        return refreshes, function() UIManager.setDirty = orig end
    end

    local function openFiles(path)
        FileManager:showFiles(home)
        local fm = FileManager.instance
        fm:switchTab("files")
        if path then fm.file_chooser:changeToPath(home .. "/" .. path) end
        UIManager:forceRePaint()
        return fm, fm.file_chooser
    end

    local function itemNames(fc)
        local names = {}
        for _, item in ipairs(fc.item_table) do
            table.insert(names, (item.path:gsub(".*/", "")))
        end
        return names
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocSettings = require("docsettings")
        Event = require("ui/event")
        FileChooser = require("ui/widget/filechooser")
        FileManager = require("apps/filemanager/filemanager")
        Geom = require("ui/geometry")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        util = require("util")
        _ = require("gettext")
        require("apps/shelf/shelffilemanager") -- registers the replacement
        saved_settings = {}
        for _, key in ipairs{ "home_dir", "lastdir", "shelf_removed", "collate", "reverse_collate", "collate_mixed" } do
            saved_settings[key] = G_reader_settings:readSetting(key)
            G_reader_settings:delSetting(key)
        end

        local DataStorage = require("datastorage")
        home = ffiUtil.realpath(DataStorage:getDataDir()) .. "/files_home"
        ffiUtil.purgeDir(home)
        for _, dir in ipairs{ "", "/sub", "/sub/deeper", "/sub/deeper/deepest", "/empty", "/many" } do
            lfs.mkdir(home .. dir)
        end
        local function copy(src, dst) ffiUtil.copyFile("spec/front/unit/data/" .. src, home .. "/" .. dst) end
        copy("juliet.epub", "a.epub")
        copy("leaves.epub", "sub/b.epub")
        copy("sample.pdf", "sub/c.pdf")
        copy("sample.txt", "sub/deeper/d.txt")
        for i = 1, 30 do
            copy("sample.txt", string.format("many/%02d.txt", i))
        end
        local doc_settings = DocSettings:open(home .. "/sub/b.epub")
        doc_settings:saveSetting("summary", { status = "reading" })
        doc_settings:saveSetting("percent_finished", 0.42)
        doc_settings:flush()
        G_reader_settings:saveSetting("home_dir", home)
    end)

    teardown(function()
        if FileManager.instance then FileManager.instance:onClose() end
        ffiUtil.purgeDir(home)
        for key, value in pairs(saved_settings) do
            G_reader_settings:saveSetting(key, value)
        end
        Replacements.filemanager = nil
    end)

    it("lists a subfolder: folders with their counts, then files with format, size and status", function()
        local fm, fc = openFiles("sub")
        assert.are.equal(home .. "/sub", fc.path)
        -- no "⬆ ../" row: the crumbs replace it
        assert.are.same({ "deeper", "b.epub", "c.pdf" }, itemNames(fc))
        local shown = texts(fc[1])
        for _, text in ipairs{ _("Files"), "deeper", "1 folder · 1 book", "b.epub", "EPUB", require("ffi/util").template(_("Read %1%"), 42),
                "c.pdf", "PDF", require("gettext").pgettext("Shelf book status", "New"),
                util.getFriendlySize(lfs.attributes(home .. "/sub/c.pdf", "size")) } do
            assert.is_true(has(shown, text), text)
        end
        fm:onClose()
    end)

    it("goes back up with the crumbs, and opens folders with a tap", function()
        local fm, fc = openFiles("sub/deeper/deepest")
        local crumbs = {}
        for _, text in ipairs(texts(fc[1][1][2])) do
            if text ~= " / " then table.insert(crumbs, text) end
        end
        assert.are.same({ "files_home", "sub", "deeper", "deepest" }, crumbs)
        gesture("tap", tappable(fc[1][1][2], "sub"))
        assert.are.equal(home .. "/sub", fc.path)
        gesture("tap", tappable(fc[1][1][2], "files_home"))
        assert.are.equal(home, fc.path)
        assert.are.equal("files", fm.current_tab)
        gesture("tap", tappable(fc[1], "sub"))
        assert.are.equal(home .. "/sub", fc.path)
        fm:onClose()
    end)

    it("explains how to add books in an empty folder", function()
        local fm, fc = openFiles("empty")
        assert.are.equal(0, #fc.item_table)
        local shown = texts(fc[1])
        assert.is_true(has(shown, _("This folder is empty")))
        assert.is_true(has(shown, _("Put books here over USB or with Calibre wireless connection.")))
        fm:onClose()
    end)

    it("pages long folders, and refreshes only the content area with ui", function()
        local fm, fc = openFiles()
        local refreshes, restore = spyRefreshes()
        gesture("tap", tappable(fc[1], "many"))
        assert.is_true(fc.page_num > 1)
        fm:onSwipeFM{ direction = "west", pos = Geom:new{ x = 10, y = 10, w = 0, h = 0 } }
        assert.are.equal(2, fc.page)
        fc:onFolderUp()
        restore()
        assert.is_true(#refreshes >= 3)
        for _, r in ipairs(refreshes) do
            assert.are.equal("ui", r.type)
            assert.is_true(r.region.y + r.region.h <= fm.content_dimen.h)
        end
        assert.are.equal(home, fc.path)
        fm:onClose()
    end)

    it("turns pages with the pager", function()
        local fm, fc = openFiles("many")
        local pager = fc[1][1][4]
        local next_button = find(pager, function(w) return w.callback and w.ges_events and w.dimen end)
        -- the first enabled button is "next" on page 1
        gesture("tap", next_button)
        assert.are.equal(2, fc.page)
        assert.is_false(has(texts(fc[1]), "01.txt"))
        fm:onClose()
    end)

    it("long-presses a book into the shelf's book sheet, with More for the original file dialog", function()
        local fm, fc = openFiles("sub")
        gesture("hold", tappable(fc[1], "b.epub"))
        local sheet = topWidget()
        local shown = texts(sheet)
        for _, text in ipairs{ _("Continue reading"), _("Book information"), _("Mark as finished"), _("Put on hold"),
                _("Remove from shelf"), _("More") } do
            assert.is_true(has(shown, text), text)
        end
        -- a status change refreshes the list
        gesture("tap", tappable(sheet, _("Mark as finished")))
        assert.is_true(has(texts(fc[1]), require("gettext").pgettext("Shelf book status", "Finished")))
        -- More: the original dialog (open with, rename, delete, select...)
        gesture("hold", tappable(fc[1], "b.epub"))
        gesture("tap", tappable(topWidget(), _("More")))
        assert.are.equal(fc.file_dialog, topWidget())
        assert.is_true(has(texts(fc.file_dialog), _("Open with…")))
        UIManager:close(fc.file_dialog)
        -- folders keep the original dialog
        gesture("hold", tappable(fc[1], "deeper"))
        assert.are.equal(fc.file_dialog, topWidget())
        assert.is_true(has(texts(fc.file_dialog), _("Set as HOME folder")))
        UIManager:close(fc.file_dialog)
        fm:onClose()
    end)

    it("keeps select mode: the title button turns into a check, and taps select files", function()
        local fm, fc = openFiles("sub")
        local function icon() return find(fc.title_row, function(w) return w.icon end).icon end
        assert.are.equal("eink/more", icon())
        fm:onToggleSelectMode()
        assert.are.equal("eink/check", icon())
        gesture("tap", tappable(fc[1], "c.pdf"))
        assert.is_true(fm.selected_files[home .. "/sub/c.pdf"])
        fm:onToggleSelectMode()
        assert.are.equal("eink/more", icon())
        fm:onClose()
    end)

    it("re-enters a folder that lists nothing with a focused path (Show folder of a gone file)", function()
        local fm, fc = openFiles()
        fc:changeToPath(home .. "/empty", home .. "/empty/gone.epub")
        UIManager:forceRePaint()
        assert.are.equal(home .. "/empty", fc.path)
        assert.is_true(has(texts(fc[1]), _("This folder is empty")))
        fm:onClose()
    end)

    it("goes up a folder with Back, and prompts to exit only at home, also from 书架", function()
        local fm, fc = openFiles("sub/deeper")
        fc:handleEvent(Event:new("Back"))
        assert.are.equal(home .. "/sub", fc.path)
        fc:handleEvent(Event:new("Back"))
        assert.are.equal(home, fc.path)
        local stack = #UIManager._window_stack
        fc:handleEvent(Event:new("Back"))
        assert.are.equal(home, fc.path)
        assert.are.equal(stack + 1, #UIManager._window_stack) -- "Exit KOReader?"
        UIManager:close(topWidget())
        -- on 书架, Back keeps its exit prompt even when the hidden browser is in a subfolder
        fc:changeToPath(home .. "/sub")
        fm:switchTab("shelf")
        fm:onBack()
        assert.are.equal(home .. "/sub", fc.path)
        assert.are.equal(stack + 1, #UIManager._window_stack)
        UIManager:close(topWidget())
        fm:onClose()
    end)

    it("shows crumbs from / outside home", function()
        local fm, fc = openFiles()
        assert.are.same({ { text = "/", path = "/" } }, fc:getCrumbs("/"))
        assert.are.same({ { text = "/", path = "/" }, { text = "usr", path = "/usr" }, { text = "bin", path = "/usr/bin" } },
            fc:getCrumbs("/usr/bin"))
        assert.are.same({ { text = "files_home", path = home }, { text = "sub", path = home .. "/sub" } },
            fc:getCrumbs(home .. "/sub"))
        fc:changeToPath("/")
        UIManager:forceRePaint()
        assert.are.equal("/", texts(fc[1][1][2])[1])
        fm:onClose()
    end)

    it("keeps the size column of file search results, which are built with the file browser's items", function()
        local fm, fc = openFiles()
        local path = home .. "/a.epub"
        local attr = lfs.attributes(path)
        local item = fc:getListItem(nil, "a.epub", path, attr, fc:getCollate())
        assert.are.equal(util.getFriendlySize(attr.size), item.mandatory)
        fm:onClose()
    end)

    it("refreshes only the title row when select mode toggles", function()
        local fm, fc = openFiles("sub")
        local refreshes, restore = spyRefreshes()
        fm:onToggleSelectMode()
        restore()
        local title_h = fc.title_row.dimen.h
        local found = false
        for _, r in ipairs(refreshes) do
            assert.are.equal("ui", r.type)
            assert.is_true(r.region.y + r.region.h <= fm.content_dimen.h)
            if r.region.h == title_h then found = true end
        end
        assert.is_true(found)
        fm:onToggleSelectMode()
        fm:onClose()
    end)

    it("stays on 文件 across a rotation, laid out for the new screen", function()
        local Screen = require("device").screen
        local fm, fc = openFiles("many")
        local rotation = Screen:getRotationMode()
        fm:onSetRotationMode(rotation == 0 and 1 or 0)
        local rotated = FileManager.instance
        assert.are.equal("files", rotated.current_tab)
        assert.are.equal(rotated.files_ui, rotated.content[1])
        assert.are.equal(home .. "/many", rotated.file_chooser.path)
        assert.are.equal(rotated.content_dimen.h, rotated.file_chooser.dimen.h)
        assert.are.equal(Screen:getWidth(), rotated.file_chooser.dimen.w)
        assert.is_not.equal(fc, rotated.file_chooser)
        rotated:onSetRotationMode(rotation)
        FileManager.instance:onClose()
    end)

    it("leaves the upstream file browser alone without the replacement", function()
        local registered = Replacements.filemanager
        Replacements.filemanager = nil
        FileManager:showFiles(home .. "/sub")
        local fc = FileManager.instance.file_chooser
        assert.are.equal(FileChooser, getmetatable(fc))
        assert.is_true(fc.item_table[1].is_go_up)
        FileManager.instance:onClose()
        Replacements.filemanager = registered
    end)
end)
