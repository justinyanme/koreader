-- Seam C: real iOS device initialization and input dispatch, with a fake bridge
-- and an offscreen framebuffer in place of the SDL window. Q46: do not run here.
describe("iOS point ruler and safe viewport (seam C)", function()
    local BB, Device, FakeBridge, FB, SDL, factory, UIManager, IosStorage
    local device, screen, insets, window_w, window_h, scale, events
    local saved_settings, saved_window, saved_sdl, resizes

    setup(function()
        require("commonrequire")
        BB = require("ffi/blitbuffer")
        Device = require("device/sdl/device")
        FakeBridge = require("iosbridge")
        FB = require("ffi/framebuffer")
        SDL = require("ffi/SDL3")
        factory = require("ffi/framebuffer_SDL3")
        IosStorage = require("device/sdl/iosstorage")
        -- Initialize its device callback before each case installs a fake.
        -- Otherwise the first FileManager require can overwrite that fake.
        UIManager = require("ui/uimanager")
    end)

    before_each(function()
        saved_settings = {}
        for _, key in ipairs{ "night_mode", "screen_dpi", "closed_rotation_mode" } do
            saved_settings[key] = G_reader_settings:readSetting(key)
            G_reader_settings:delSetting(key)
        end
        saved_window = { SDL.win_w, SDL.win_h }
        saved_sdl = SDL.SDL
        window_w, window_h, scale = 440, 956, 3
        insets = { top = 62, right = 0, bottom = 34, left = 0 }
        events, resizes = {}, 0
        SDL.SDL = setmetatable({
            SDL_GetWindowSize = function(_, w, h) w[0], h[0] = window_w, window_h; return true end,
            SDL_GetCurrentRenderOutputSize = function(_, w, h)
                w[0], h[0] = window_w * scale, window_h * scale
                return true
            end,
        }, { __index = saved_sdl })
        local bridge = FakeBridge.new()
        bridge.safeAreaInsets = function() return insets end
        -- Storage migration has its own spec; layout initialization must not
        -- read or migrate the host HOME when it enters B3's IOS:init.
        stub(IosStorage, "setup", function() return "spec/front/unit/data" end)
        device = Device:createVariant{ platform = "iOS", native_bridge = bridge }
        device.window = { width = window_w, height = window_h }
        stub(factory, "new", function()
            screen = FB:new{ device = device, bb = BB.new(window_w * scale, window_h * scale, BB.TYPE_BBRGB32),
                w = window_w, h = window_h }
            -- Models the B1-followup framebuffer contract: resize owns and releases
            -- the old full buffer and its view, then returns a fresh full buffer.
            function screen:resize(w, h)
                resizes = resizes + 1
                local rotation = self.bb:getRotation()
                self.bb:free()
                if self.full_bb then self.full_bb:free() end
                self.full_bb, self.viewport = nil, nil
                self.bb = BB.new(window_w * scale, window_h * scale, BB.TYPE_BBRGB32)
                self.bb:setRotation(rotation)
                SDL.win_w, SDL.win_h = w or window_w, h or window_h
            end
            return screen
        end)
        stub(SDL, "gameControllerRumble", function() return false end)
        device:UIManagerReady{
            broadcastEvent = function(_, ev) table.insert(events, ev.handler) end,
            setDirty = function() end,
        }
        device:init()
    end)

    after_each(function()
        IosStorage.setup:revert()
        factory.new:revert()
        SDL.gameControllerRumble:revert()
        device:UIManagerReady(UIManager)
        screen.bb:free()
        if screen.full_bb then screen.full_bb:free() end
        for _, key in ipairs{ "night_mode", "screen_dpi", "closed_rotation_mode" } do
            G_reader_settings:saveSetting(key, saved_settings[key])
        end
        SDL.win_w, SDL.win_h = saved_window[1], saved_window[2]
        SDL.SDL = saved_sdl
    end)

    local function dispatch(code)
        device.input:handleSdlEv{ code = code, value = { data1 = window_w, data2 = window_h } }
    end

    it("makes 44dp exactly 44pt on iPhone, unaffected by a legacy DPI override", function()
        assert.are.equal(132, screen:scaleBySize(44))
        assert.are.equal(132, screen:scaleByDPI(44))
        assert.are.equal(480, device.display_dpi)
        device:setScreenDPI(160)
        assert.are.equal(132, screen:scaleBySize(44))
        assert.are.equal(480, screen:getDPI())
        assert.are.same({ w = 1320, h = 2580 }, screen:getRawSize())
        assert.are.same({ x = 0, y = 186, w = 1320, h = 2580 }, device.viewport)
        assert.are.same({ w = 1320, h = 2868 }, screen.screen_size)
    end)

    it("uses the same resize notifications for iPad pixels, rotation and inset-only changes", function()
        scale, window_w, window_h = 2, 834, 1210
        insets = { top = 0, right = 0, bottom = 20, left = 0 }
        dispatch(SDL.SDL.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED)
        assert.are.equal(88, screen:scaleBySize(44))
        assert.are.equal(320, screen:getDPI())
        assert.are.same({ w = 1668, h = 2380 }, screen:getRawSize())
        window_w, window_h = 1210, 834
        dispatch(SDL.SDL.SDL_EVENT_WINDOW_RESIZED)
        insets.top = 24
        dispatch(SDL.SDL.SDL_EVENT_WINDOW_SAFE_AREA_CHANGED)
        assert.are.same({ w = 2420, h = 1580 }, screen:getRawSize())
        assert.are.same({ "onSetDimensions", "onScreenResize", "onRedrawCurrentPage",
            "onSetDimensions", "onScreenResize", "onRedrawCurrentPage",
            "onSetDimensions", "onScreenResize", "onRedrawCurrentPage" }, events)
    end)

    it("ignores duplicate startup events and rebuilds once per physical geometry change", function()
        local FileManager = require("apps/filemanager/filemanager")
        local saved_instance, reinitializations = FileManager.instance, 0
        FileManager.instance = { reinit = function() reinitializations = reinitializations + 1 end }
        local ok, err = pcall(function()
            local sequence = { SDL.SDL.SDL_EVENT_WINDOW_RESIZED, SDL.SDL.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
                SDL.SDL.SDL_EVENT_WINDOW_SAFE_AREA_CHANGED }
            for _, event in ipairs(sequence) do dispatch(event) end
            assert.are.equal(0, resizes)
            assert.are.same({}, events)
            assert.are.equal(0, reinitializations)

            window_w, window_h = 956, 440
            insets = { top = 0, right = 62, bottom = 21, left = 62 }
            for _, event in ipairs(sequence) do dispatch(event) end
            assert.are.equal(1, resizes)
            assert.are.same({ "onSetDimensions", "onScreenResize", "onRedrawCurrentPage" }, events)
            assert.are.equal(1, reinitializations)
        end)
        FileManager.instance = saved_instance
        assert(ok, err)
    end)

    it("rebuilds when only render pixels change, then ignores equivalent safe-area events", function()
        scale = 2
        dispatch(SDL.SDL.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED)
        dispatch(SDL.SDL.SDL_EVENT_WINDOW_SAFE_AREA_CHANGED)
        assert.are.equal(1, resizes)
        assert.are.same({ w = 880, h = 1912 }, screen.screen_size)
        assert.are.equal(88, screen:scaleBySize(44))
        assert.are.same({ x = 0, y = 124, w = 880, h = 1720 }, device.viewport)
    end)

    it("updates the point ruler when window points change with identical pixel geometry", function()
        window_w, window_h, scale = 880, 1912, 1.5
        insets = { top = 124, right = 0, bottom = 68, left = 0 }
        dispatch(SDL.SDL.SDL_EVENT_WINDOW_RESIZED)
        assert.are.equal(1, resizes)
        assert.are.same({ w = 1320, h = 2868 }, screen.screen_size)
        assert.are.same({ x = 0, y = 186, w = 1320, h = 2580 }, device.viewport)
        assert.are.equal(66, screen:scaleBySize(44))
    end)

    it("reapplies an Emulator viewport after resize and retains its touch translation and software rotation", function()
        local emulator = Device:createVariant{ platform = "Linux" }
        emulator.screen, emulator.input = screen, device.input
        emulator.window = {}
        emulator.viewport = require("ui/geometry"):new{ x = 10, y = 5, w = 550, h = 790 }
        -- Reuse the real Generic.init hook installed above, with the fixed
        -- viewport's offset rather than the iPhone's inset.
        device.viewport_touch_offset.x, device.viewport_touch_offset.y = -10, -5
        scale = 1
        for rotation = 0, 1 do
            screen.bb:setRotation(rotation)
            screen.full_bb:setRotation(rotation)
            window_w, window_h = 600 + rotation * 200, 800 + rotation * 200
            emulator:resizeWindow(window_w, window_h)
            assert.are.same({ w = window_w, h = window_h }, screen.screen_size)
            assert.are.same(emulator.viewport, screen.viewport)
            assert.are.same(rotation == 0 and { w = 550, h = 790 } or { w = 790, h = 550 }, screen:getRawSize())
            assert.are.equal(rotation, screen.bb:getRotation())
            assert.are.equal(rotation, screen.full_bb:getRotation())
            local C = require("ffi").C
            for _, position in ipairs{ { C.ABS_MT_POSITION_X, 20, 10 }, { C.ABS_MT_POSITION_Y, 20, 15 } } do
                local ev = { type = C.EV_ABS, code = position[1], value = position[2] }
                emulator.input:eventAdjustHook(ev)
                assert.are.equal(position[3], ev.value)
            end
        end
    end)

    it("translates touch once using the current insets, including an initially zero inset", function()
        local C = require("ffi").C
        for _, top in ipairs{ 0, 10, 20, 0, 30 } do
            insets.top = top
            dispatch(SDL.SDL.SDL_EVENT_WINDOW_SAFE_AREA_CHANGED)
            local ev = { type = C.EV_ABS, code = C.ABS_MT_POSITION_Y, value = 300 }
            device.input:eventAdjustHook(ev)
            assert.are.equal(300 - top * scale, ev.value)
        end
    end)

    it("keeps the physical point ruler and safe rectangle after a saved software rotation", function()
        screen:setRotationMode(screen.DEVICE_ROTATED_CLOCKWISE)
        local rotation = screen.bb:getRotation()
        for index, event in ipairs{ SDL.SDL.SDL_EVENT_WINDOW_SAFE_AREA_CHANGED, SDL.SDL.SDL_EVENT_WINDOW_RESIZED } do
            insets.top = 62 - index -- force a rebuild rather than the unchanged-geometry fast path
            dispatch(event)
            assert.are.equal(132, screen:scaleBySize(44))
            assert.are.equal(480, screen:getDPI())
            assert.are.same({ w = 1320, h = 2868 }, screen.screen_size)
            local height = 2868 - (insets.top + 34) * 3
            assert.are.same({ x = 0, y = insets.top * 3, w = 1320, h = height }, device.viewport)
            assert.are.same({ w = height, h = 1320 }, screen:getRawSize())
            assert.are.equal(rotation, screen.bb:getRotation())
            assert.are.equal(rotation, screen.full_bb:getRotation())
        end
        assert.are.equal(2, resizes)
    end)

    it("uses current window points when an older resize payload is still queued", function()
        window_w, window_h = 956, 440
        insets = { top = 0, right = 62, bottom = 21, left = 62 }
        device.input:handleSdlEv{ code = SDL.SDL.SDL_EVENT_WINDOW_RESIZED,
            value = { data1 = 440, data2 = 956 } }
        assert.are.equal(132, screen:scaleBySize(44))
        assert.are.same({ x = 186, y = 0, w = 2496, h = 1257 }, device.viewport)
    end)

    it("keeps the full buffer white outside the viewport and inverts it with night mode", function()
        assert.are.equal(255, screen.full_bb:getPixel(0, 0):getColor8().a)
        screen:toggleNightMode()
        assert.are.equal(0, screen.full_bb:getPixelP(0, 0)[0]:getColor8().a)
        assert.are.equal(1, screen.full_bb:getInverse())
    end)

    it("maps SDL's safe rectangle to window-coordinate insets without applying pixel scale", function()
        local real_sdl, real_window = SDL.SDL, SDL.screen
        SDL.screen = true -- the fake SDL boundary never dereferences a window
        SDL.SDL = {
            SDL_GetWindowSafeArea = function(_, rect)
                rect[0].x, rect[0].y, rect[0].w, rect[0].h = 62, 0, 832, 419
                return true
            end,
            SDL_GetWindowSize = function(_, w, h) w[0], h[0] = 956, 440; return true end,
        }
        local ok, err = pcall(function()
            local bridge = require("device/sdl/iosbridge").native()
            assert.are.same({ top = 0, right = 62, bottom = 21, left = 62 }, bridge.safeAreaInsets())
        end)
        SDL.SDL, SDL.screen = real_sdl, real_window
        assert(ok, err)
    end)
end)
