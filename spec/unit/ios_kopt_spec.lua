describe("KOPT reflow on iOS (C5)", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    -- spec/front links to the repository's spec/, so its parent holds platform/.
    local symbols_path = "spec/front/../platform/ios/ffi-symbols.txt"

    setup(function()
        require("commonrequire")
        disable_plugins()
    end)

    it("exports every k2pdfopt and leptonica function the reflow path calls", function()
        local listed = {}
        for line in io.lines(symbols_path) do
            if line:sub(1, 1) ~= "#" then listed[line] = true end
        end
        local called = 0
        for _, module in ipairs({"ffi/koptcontext", "ffi/mupdf", "document/koptinterface"}) do
            local f = assert(io.open(assert(package.searchpath(module, package.path))))
            local source = f:read("*a")
            f:close()
            for lib, name in source:gmatch("([%w_]+)%.([%a_][%w_]*)%s*%(") do
                if lib == "k2pdfopt" or lib == "leptonica" then
                    called = called + 1
                    assert.is_true(listed[name] == true, name .. " (" .. module .. ") is missing from ffi-symbols.txt")
                end
            end
        end
        assert.is_true(called > 0)
    end)

    describe("with the iOS device's capabilities", function()
        local Device, DocumentRegistry, Event, Geom, KoptInterface, ReaderUI, UIManager
        local readerui, reflowed

        setup(function()
            Device = require("device")
            DocumentRegistry = require("document/documentregistry")
            Event = require("ui/event")
            Geom = require("ui/geometry")
            KoptInterface = require("document/koptinterface")
            ReaderUI = require("apps/reader/readerui")
            UIManager = require("ui/uimanager")
            local ios = require("device/sdl/device"):createVariant{
                platform = "iOS", native_bridge = require("iosbridge").new(),
            }
            stub(Device, "canForkProcesses", ios.canForkProcesses)
            stub(Device, "isTouchDevice", ios.isTouchDevice)
            local purgeDir = require("ffi/util").purgeDir
            local DocSettings = require("docsettings")
            purgeDir(DocSettings:getSidecarDir(sample_pdf))
            os.remove(DocSettings:getHistoryPath(sample_pdf))
            readerui = ReaderUI:new{
                dimen = Device.screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            local reflowPage = KoptInterface.reflowPage
            reflowed = 0
            stub(KoptInterface, "reflowPage", function(...)
                reflowed = reflowed + 1
                return reflowPage(...)
            end)
        end)

        teardown(function()
            KoptInterface.reflowPage:revert()
            readerui:closeDocument()
            readerui:onClose()
            Device.canForkProcesses:revert()
            Device.isTouchDevice:revert()
        end)

        local function findToggle(widget, name)
            if type(widget) ~= "table" then return end
            if widget.name == name and widget.toggle then return widget end
            for _, key in ipairs({"dialog_frame", "config_panel"}) do
                local found = widget[key] ~= widget and findToggle(widget[key], name)
                if found then return found end
            end
            for _, child in ipairs(widget) do
                local found = findToggle(child, name)
                if found then return found end
            end
        end

        it("shows the reflow toggle in the fixed-layout bottom bar and reflows when tapped", function()
            readerui:handleEvent(Event:new("ShowConfigMenu"))
            local dialog = readerui.config.config_dialog
            assert.is_truthy(dialog)
            for i, tab in ipairs(dialog.config_options) do
                for _, option in ipairs(tab.options) do
                    if option.name == "text_wrap" then dialog:onShowConfigPanel(i) end
                end
            end
            dialog = readerui.config.config_dialog
            local switch = findToggle(dialog, "text_wrap")
            assert.is_truthy(switch)
            assert.is_true(switch.enabled)
            local d = switch.dimen
            switch:onTapSelect(nil, { pos = Geom:new{ x = d.x + math.floor(d.w * 3 / 4), y = d.y + math.floor(d.h / 2), w = 0, h = 0 } })
            for __ = 1, 3 do UIManager:_checkTasks() end
            assert.are.equal(1, readerui.document.configurable.text_wrap)
            UIManager:forceRePaint()
            assert.is_true(reflowed > 0)
            readerui.config.config_dialog:closeDialog()
            readerui:handleEvent(Event:new("ToggleReflow"))
            assert.are.equal(0, readerui.document.configurable.text_wrap)
        end)
    end)
end)
