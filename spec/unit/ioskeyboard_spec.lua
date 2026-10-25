-- ReaderUI (seam A) with an iOS device and fake bridge (seam C). Only the
-- platform input source is replaced; SDL key mapping and dispatch stay real.
describe("iOS external keyboard in the reader (seams A and C)", function()
    local Device, SDLDevice, FakeBridge, Input, UIManager, Event, Geom, time, C
    local ReaderUI, DocumentRegistry, DocSettings, Replacements, Screen
    local ios, bridge, pending, interrupted, ui, saved_reader_menu
    local capabilities = { "hasKeys", "hasKeyboard", "hasDPad", "hasFewKeys", "useDPadAsActionKeys", "canShowMenuShortcuts" }

    setup(function()
        require("commonrequire")
        disable_plugins()
        Device = require("device")
        SDLDevice = require("device/sdl/device")
        FakeBridge = require("iosbridge")
        Input = require("device/input")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        time = require("ui/time")
        C = require("ffi").C
        ReaderUI = require("apps/reader/readerui")
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        Replacements = require("apps/replacements")
        Screen = Device.screen
    end)

    before_each(function()
        bridge = FakeBridge.new()
        ios = SDLDevice:createVariant{ platform = "iOS", native_bridge = bridge }
        ios.screen = Screen
        ios.input = Input:new{
            device = ios,
            event_map = dofile("frontend/device/sdl/event_map_sdl2.lua"),
            input = {
                waitForEvent = function()
                    if interrupted then
                        interrupted = false
                        return false, C.EINTR
                    end
                    local batch = pending
                    pending = nil
                    if batch then return true, batch end
                    return false, C.ETIME
                end,
            },
        }
        -- Reader modules capture the process Device singleton. Expose the
        -- seam-C variant's capabilities there, retaining the offscreen screen.
        for _, capability in ipairs(capabilities) do
            stub(Device, capability, function() return ios[capability](ios) end)
        end
        ios:initKeyboard()
        ios:UIManagerReady(UIManager)
        -- Other specs may already have populated FocusManager's static maps
        -- with the emulator's keys; model a touch-only iOS startup here.
        local focus = require("ui/widget/focusmanager"):new{}
        focus:onPhysicalKeyboardDisconnected()
        saved_reader_menu = Replacements.reader_menu
        Replacements.reader_menu = require("apps/reader/modules/readertoolbar")
    end)

    after_each(function()
        if ui then
            ui.menu:hideToolbar()
            ui:onClose()
            ui = nil
        end
        pending, interrupted = nil, nil
        -- Restore static widget bindings too, as when a keyboard is removed.
        bridge.setKeyboardConnected(false)
        ios:updateKeyboardState()
        for _, capability in ipairs(capabilities) do Device[capability]:revert() end
        require("ui/widget/inputtext").initInputEvents()
        local focus = require("ui/widget/focusmanager"):new{}
        focus:onPhysicalKeyboardConnected()
        Replacements.reader_menu = saved_reader_menu
    end)

    local function openReader(file)
        DocSettings:open(file):purge()
        ui = ReaderUI:new{ dimen = Screen:getSize(), document = DocumentRegistry:openDocument(file) }
        UIManager:show(ui)
        UIManager:forceRePaint()
    end

    local function pump(batch)
        pending = batch
        interrupted = batch == nil
        local now = time.now()
        local events = ios.input:waitEvent(now, now)
        for _, event in ipairs(events or {}) do UIManager:handleInputEvent(event) end
    end

    local function key(code)
        pump{
            { type = C.EV_KEY, code = code, value = 1 },
            { type = C.EV_KEY, code = code, value = 0 },
        }
    end

    local function tap(x, y)
        UIManager:sendEvent(Event:new("Gesture", {
            ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 },
        }))
    end

    for _, connected in ipairs{ false, true } do
        it("does not reserve menu shortcut boxes with a keyboard at startup: " .. tostring(connected), function()
            bridge.setKeyboardConnected(connected)
            pump()
            -- Load the class with the startup capabilities, without replacing
            -- the cached Menu module used by other specs and reader widgets.
            local StartupMenu = dofile("frontend/ui/widget/menu.lua")
            local menu = StartupMenu:new{ item_table = { { text = "Chapter 1" } } }
            finally(function() menu:free() end)
            assert.is_false(menu.is_enable_shortcut)
            assert.is_nil(menu.key_events.SelectByShortCut)
        end)
    end

    for _, file in ipairs{ "spec/front/unit/data/juliet.epub", "spec/front/unit/data/sample.pdf" } do
        it("handles the first arrow after hotplug, reconnects, and preserves touch after unplug: " .. file, function()
            openReader(file)
            local first = ui:getCurrentPage()
            key(1073741903) -- Right, while no hardware keyboard is connected.
            assert.are.equal(first, ui:getCurrentPage())

            bridge.setKeyboardConnected(true)
            key(1073741903) -- The very first Right must register bindings before dispatch.
            assert.are.equal(first + 1, ui:getCurrentPage())
            key(1073741904) -- Left
            assert.are.equal(first, ui:getCurrentPage())

            bridge.setKeyboardConnected(false)
            pump() -- Discarded SDL hotplug/focus event: EINTR, then the ordinary timeout.
            key(1073741903)
            assert.are.equal(first, ui:getCurrentPage())
            tap(Screen:getWidth() - 10, Screen:getHeight() / 2)
            assert.are.equal(first + 1, ui:getCurrentPage())

            bridge.setKeyboardConnected(true)
            key(1073741903)
            assert.are.equal(first + 2, ui:getCurrentPage())
        end)
    end

    it("lets the first Esc close a panel opened before keyboard connection, then closes the toolbar", function()
        openReader("spec/front/unit/data/juliet.epub")
        ui.menu:openPanel("progress")
        local bars = ui.menu.bars
        assert.is_truthy(ui.menu.panel)
        bridge.setKeyboardConnected(true)
        key(27) -- SDL Escape maps to Back.
        assert.is_nil(ui.menu.panel)
        assert.are.equal(bars, ui.menu.bars)
        key(27)
        assert.is_nil(ui.menu.bars)
    end)

    it("removes and restores Esc on the same open toolbar across disconnect and reconnect", function()
        openReader("spec/front/unit/data/juliet.epub")
        bridge.setKeyboardConnected(true)
        pump()
        ui.menu:showToolbar()
        local bars = ui.menu.bars
        bridge.setKeyboardConnected(false)
        key(27)
        assert.are.equal(bars, ui.menu.bars)
        bridge.setKeyboardConnected(true)
        key(27)
        assert.is_nil(ui.menu.bars)
    end)
end)
