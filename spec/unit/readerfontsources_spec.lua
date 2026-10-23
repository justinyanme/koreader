describe("Reading fonts from the user's fonts folder", function()
    local ffiUtil, lfs, home

    setup(function()
        require("commonrequire")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        home = require("datastorage"):getFullDataDir() .. "/font_sources"
        require("util").makePath(home .. "/fonts")
        require("util").makePath(home .. "/bundled")
        -- FreeSerif is available only from the user folder; the other bundled faces remain real font files.
        require("util").findFiles("./fonts", function(path, name)
            if name:match("%.ttf$") or name:match("%.otf$") then
                local dir = name == "FreeSerif.ttf" and "/fonts/" or "/bundled/"
                assert(lfs.link(ffiUtil.realpath(path), home .. dir .. name, true))
            end
        end)
    end)

    teardown(function() ffiUtil.purgeDir(home) end)

    local function readWithFonts(opt_out)
        -- Font discovery is once per process, just as after a device restart.
        local result_path = home .. "/result"
        local pid = ffiUtil.runInSubProcess(function()
            local ok, err = xpcall(function()
                disable_plugins()
                local Device = require("device")
                local CanvasContext = require("document/canvascontext")
                local FontList = require("fontlist")
                -- commonrequire has scanned UI fonts; supply the isolated filesystem before opening the first book.
                FontList.fontlist, FontList.fontnames, FontList.fontinfo = {}, {}, {}
                FontList.fontdir = home .. "/bundled"
                FontList.cachedir = home .. "/cache"
                local old_home = Device.home_dir
                Device.home_dir = home
                local android = stub(Device, "isAndroid", function() return true end)
                local canvas_android = stub(CanvasContext, "isAndroid", function() return true end)
                local system_fonts = stub(CanvasContext, "hasSystemFonts", function() return true end)
                if opt_out then G_reader_settings:saveSetting("system_fonts", false) end
                G_reader_settings:saveSetting("last_migration_date", 20260804)
                dofile("frontend/ui/data/onetime_migration.lua")
                local dirs = require("ui/elements/font_settings"):getPath()
                for _, dir in ipairs{ "/system/fonts", "/product/fonts", "/system_ext/fonts" } do
                    assert.are.equal(not opt_out, dirs:find(dir, 1, true) ~= nil)
                end
                FontList:getFontList()
                android:revert()
                canvas_android:revert()
                system_fonts:revert()
                Device.home_dir = old_home

                local ReaderUI = require("apps/reader/readerui")
                local UIManager = require("ui/uimanager")
                local Event = require("ui/event")
                local Geom = require("ui/geometry")
                local Replacements = require("apps/replacements")
                Replacements.reader_menu = require("apps/reader/modules/readertoolbar")
                Replacements.reader_config = require("apps/reader/modules/readertypesetpanel")
                local sample = "spec/front/unit/data/juliet.epub"
                require("docsettings"):open(sample):purge()
                local function open()
                    local ui = ReaderUI:new{
                        dimen = Device.screen:getSize(),
                        document = require("document/documentregistry"):openDocument(sample),
                    }
                    UIManager:show(ui)
                    ui:handleEvent(Event:new("ShowConfigMenu"))
                    UIManager:forceRePaint()
                    return ui
                end
                local function close(ui)
                    ui:closeDocument()
                    UIManager:close(ui)
                    ui:onClose()
                end
                local function find(widget, predicate)
                    if type(widget) ~= "table" then return end
                    if predicate(widget) then return widget end
                    for _, child in ipairs(widget) do
                        local found = find(child, predicate)
                        if found then return found end
                    end
                    if rawget(widget, "content") then return find(widget.content, predicate) end
                end
                local cre = require("document/credocument"):engineInit()
                local available = cre.getFontFaces()
                local get_filename = cre.getFontFaceFilenameAndFaceIndex
                local decorative = { "AndroidClock", "Emoji", "Symbol", "Dancing Script", "Coming Soon", "Cutive Mono" }
                for _, face in ipairs(decorative) do table.insert(available, face) end
                stub(cre, "getFontFaces", function() return require("util").tableDeepCopy(available) end)
                stub(cre, "getFontFaceFilenameAndFaceIndex", function(face, ...)
                    if require("util").arrayContains(decorative, face) then return get_filename("FreeSans") end
                    return get_filename(face, ...)
                end)
                local ui = open()
                local names = {}
                find(ui.config.panel, function(w)
                    if w.name and w.callback then table.insert(names, w.name) end
                    return false
                end)
                assert.are.equal("System font", names[1])
                assert.are.equal("FreeSerif", names[2])
                assert.is_true(require("util").arrayContains(names, "FreeSerif") < require("util").arrayContains(names, "FreeSans"))
                for _, face in ipairs(decorative) do
                    assert.is_false(require("util").arrayContains(names, face))
                    assert.is_truthy(require("util").arrayContains(available, face))
                    local listed = false
                    for _, item in ipairs(ui.font.face_table) do
                        if item.menu_item_id == face then listed = true end
                    end
                    assert.is_true(listed)
                end
                local card = find(ui.config.panel, function(w) return w.name == "FreeSerif" and w.callback end)
                assert.is_truthy(card)
                local name = find(card, function(w) return w.text == "FreeSerif" end)
                assert.are.equal(home .. "/fonts/FreeSerif.ttf", name.face.realname)
                local xpointer = ui.document:getXPointer()
                UIManager:sendEvent(Event:new("Gesture", {
                    ges = "tap", pos = Geom:new{ x = card.dimen.x + card.dimen.w / 2, y = card.dimen.y + card.dimen.h / 2 },
                }))
                for __ = 1, 3 do UIManager:_checkTasks() end
                UIManager:forceRePaint()
                assert.are.equal(ui.document:getCurrentPage(), ui.document:getPageFromXPointer(xpointer))
                assert.are.equal("FreeSerif", ui.font.font_face)
                assert.are.equal("FreeSerif", ui.document:getFontFace())
                assert.are.equal(not opt_out, G_reader_settings:readSetting("system_fonts"))
                assert.is_true(G_reader_settings:readSetting("cre_fonts_explicitly_selected").FreeSerif)
                close(ui)
                ui = open()
                assert.are.equal("FreeSerif", ui.font.font_face)
                assert.are.equal("FreeSerif", ui.document:getFontFace())
                card = find(ui.config.panel, function(w) return w.name == "FreeSerif" and w.callback end)
                assert.is_true(card.selected)
                local reordered = {}
                find(ui.config.panel, function(w)
                    if w.name and w.callback then table.insert(reordered, w.name) end
                    return false
                end)
                assert.are.equal("FreeSerif", reordered[2])
                card = find(ui.config.panel, function(w) return w.name == "Noto Serif" and w.callback end)
                UIManager:sendEvent(Event:new("Gesture", {
                    ges = "tap", pos = Geom:new{ x = card.dimen.x + card.dimen.w / 2, y = card.dimen.y + card.dimen.h / 2 },
                }))
                UIManager:forceRePaint()
                reordered = {}
                find(ui.config.panel, function(w)
                    if w.name and w.callback then table.insert(reordered, w.name) end
                    return false
                end)
                assert.are.same({ "System font", "Noto Serif", "FreeSerif" }, { reordered[1], reordered[2], reordered[3] })
                assert.are.equal("Noto Serif", ui.document:getFontFace())
                for _, item in ipairs(ui.font:getFontSettingsTable()) do
                    if item.text == "Sort fonts by recently selected" then item.hold_callback() end
                end
                local confirm = UIManager._window_stack[#UIManager._window_stack].widget
                assert.are.equal("Clear", confirm.ok_text)
                confirm.ok_callback()
                UIManager:close(confirm)
                assert.is_nil(G_reader_settings:readSetting("cre_fonts_explicitly_selected"))
                close(ui)
                ui = open()
                reordered = {}
                find(ui.config.panel, function(w)
                    if w.name and w.callback then table.insert(reordered, w.name) end
                    return false
                end)
                assert.are.equal("FreeSerif", reordered[2])
                close(ui)
            end, debug.traceback)
            local result = assert(io.open(result_path, "w"))
            result:write(ok and "ok" or tostring(err))
            result:close()
        end)
        assert.is_truthy(pid)
        ffiUtil.isSubProcessDone(pid, true)
        local result = assert(io.open(result_path))
        local outcome = result:read("*a")
        result:close()
        os.remove(result_path)
        assert.are.equal("ok", outcome)
    end

    it("should discover user fonts and enable Android system fonts on first use", function()
        readWithFonts(false)
    end)

    it("should keep user fonts selectable when system fonts were explicitly disabled", function()
        readWithFonts(true)
    end)
    it("should prefer Simplified Chinese sans faces across Android system directories without caching the choice", function()
        local FontList = require("fontlist")
        local cre = require("document/credocument"):engineInit()
        local faces = { "A Serif CJK TC", "B Sans CJK JP", "C Serif CJK SC", "Noto Sans CJK SC", "DroidSansFallback" }
        local paths = {
            "/system/fonts/tc.ttf", "/system_ext/fonts/jp.ttf", "/product/fonts/serif-sc.ttf",
            "/product/fonts/sans-sc.ttf", "/system_ext/fonts/fallback.ttf",
        }
        local original_info = FontList.fontinfo
        FontList.fontinfo = {}
        for _, path in ipairs(paths) do FontList.fontinfo[path] = { { has_chinese = true } } end
        local list = stub(cre, "getFontFaces", function() return faces end)
        local filenames = stub(cre, "getFontFaceFilenameAndFaceIndex", function(face)
            return paths[require("util").arrayContains(faces, face)], 0
        end)
        local ok, err = pcall(function()
            assert.are.equal("Noto Sans CJK SC", FontList:getSystemFontFace())
            paths[4] = "/user/fonts/sans-sc.ttf"
            assert.are.equal("DroidSansFallback", FontList:getSystemFontFace())
            paths[5] = "/user/fonts/fallback.ttf"
            assert.are.equal("C Serif CJK SC", FontList:getSystemFontFace())
            paths[3] = "/user/fonts/serif-sc.ttf"
            paths[1] = "/user/fonts/tc.ttf"
            assert.are.equal("B Sans CJK JP", FontList:getSystemFontFace())
        end)
        filenames:revert()
        list:revert()
        FontList.fontinfo = original_info
        assert(ok, err)
    end)

end)
