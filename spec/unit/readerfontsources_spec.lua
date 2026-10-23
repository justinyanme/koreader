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
                local ui = open()
                local card = find(ui.config.panel, function(w) return w.name == "FreeSerif" and w.callback end)
                assert.is_truthy(card)
                local name = find(card, function(w) return w.text == "FreeSerif" end)
                assert.are.equal(home .. "/fonts/FreeSerif.ttf", name.face.realname)
                UIManager:sendEvent(Event:new("Gesture", {
                    ges = "tap", pos = Geom:new{ x = card.dimen.x + card.dimen.w / 2, y = card.dimen.y + card.dimen.h / 2 },
                }))
                UIManager:forceRePaint()
                assert.are.equal("FreeSerif", ui.font.font_face)
                assert.are.equal(not opt_out, G_reader_settings:readSetting("system_fonts"))
                close(ui)
                ui = open()
                assert.are.equal("FreeSerif", ui.font.font_face)
                card = find(ui.config.panel, function(w) return w.name == "FreeSerif" and w.callback end)
                assert.is_true(card.selected)
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
end)
