describe("SDL device selection (seam C)", function()
    local SDLDevice, FakeBridge

    setup(function()
        require("commonrequire")
        SDLDevice = require("device/sdl/device")
        FakeBridge = require("iosbridge")
    end)

    it("constructs iOS with the Q8 capabilities and an injected native bridge", function()
        local bridge = FakeBridge.new()
        local device = SDLDevice:createVariant{ platform = "iOS", native_bridge = bridge }
        local expected = {
            isIOS = true, isSDL = true, isDesktop = false, isEmulator = false,
            hasEinkScreen = false, hasFrontlight = true, hasNaturalLight = false,
            hasNaturalLightApi = false, hasNaturalLightMixer = false,
            hasKeys = false, hasDPad = false, hasKeyboard = false, hasSymKey = false,
            canShowMenuShortcuts = false,
            supportsGamepad = false, useDPadAsActionKeys = false,
            hasWifiToggle = false, hasOTAUpdates = false, canRestart = false,
            hasExitOptions = false, isDefaultFullscreen = true, hasSystemFonts = true,
            canForkProcesses = false, canOpenLink = false, canExternalDictLookup = false,
            isTouchDevice = true, hasColorScreen = true,
        }
        for capability, value in pairs(expected) do
            assert.are.equal(value, device[capability](device), capability)
        end
        assert.are.equal("iOS", device.model)
        assert.are.equal(bridge, device.bridge)
    end)

    it("keeps each device's bridge state separate", function()
        local first = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new() }
        local second = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new() }
        first.bridge.brightnessSet(75)
        assert.are.equal(75, first.bridge.brightnessGet())
        assert.are.equal(50, second.bridge.brightnessGet())
    end)

    it("observes keyboard hotplug without changing the shared SDL input backend or its return values", function()
        local bridge = FakeBridge.new{ keyboard_connected = true }
        local device = SDLDevice:createVariant{ platform = "iOS", native_bridge = bridge }
        local other = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new() }
        local batch = { { type = 1, code = 27, value = 1 } }
        local arguments
        local backend = {
            waitForEvent = function(...)
                arguments = { n = select("#", ...), ... }
                return false, nil, batch, nil
            end,
            is_ffi = true,
        }
        local original_wait = backend.waitForEvent
        device.input = { input = backend, modifiers = { Shift = true, Ctrl = true },
            last_repeat_time = 42, keyboard_toggle_tapped = "Sym" }
        device:initKeyboard()
        assert.is_true(device:hasKeys())
        assert.is_true(device:hasKeyboard())
        assert.is_false(device:hasDPad())
        assert.is_true(device:isTouchDevice())
        assert.is_false(other:hasKeys())
        assert.are_not.equal(backend, device.input.input)
        assert.are.equal(original_wait, backend.waitForEvent)
        assert.is_true(device.input.input.is_ffi)

        bridge.setKeyboardConnected(false)
        local function capture(...)
            return { n = select("#", ...), ... }
        end
        local result = capture(device.input.input.waitForEvent(nil, 250))
        assert.are.same({ n = 2, [2] = 250 }, arguments)
        assert.are.same({ n = 4, [1] = false, [3] = batch }, result)
        assert.is_false(device:hasKeys())
        assert.is_false(device:hasKeyboard())
        assert.are.same({ Shift = false, Ctrl = false }, device.input.modifiers)
        assert.is_nil(device.input.last_repeat_time)
        assert.is_nil(device.input.keyboard_toggle_tapped)

        bridge.setKeyboardConnected(true)
        device.input.input.waitForEvent()
        assert.is_true(device:hasKeys())
        assert.is_true(device:hasKeyboard())
        assert.are.equal(original_wait, backend.waitForEvent)
    end)

    it("yields a UI tick for discarded hotplug events without dropping key batches or errors", function()
        local C = require("ffi").C
        local bridge = FakeBridge.new()
        local device = SDLDevice:createVariant{ platform = "iOS", native_bridge = bridge }
        local reply = { n = 2, false, C.EINTR }
        device.input = { modifiers = {}, input = {
            waitForEvent = function() return unpack(reply, 1, reply.n) end,
        } }
        device:initKeyboard()
        local function capture(...)
            return { n = select("#", ...), ... }
        end
        assert.are.same({ n = 2, false, C.EINTR }, capture(device.input.input.waitForEvent()))
        bridge.setKeyboardConnected(true)
        assert.are.same({ n = 2, false, C.ETIME }, capture(device.input.input.waitForEvent()))
        assert.are.same({ n = 2, false, C.EINTR }, capture(device.input.input.waitForEvent()))

        bridge.setKeyboardConnected(false)
        local batch = { { type = C.EV_KEY, code = 27, value = 1 } }
        reply = { n = 3, true, batch }
        assert.are.same({ n = 3, true, batch }, capture(device.input.input.waitForEvent()))
        bridge.setKeyboardConnected(true)
        reply = { n = 3, [2] = "poll failed" }
        assert.are.same({ n = 3, [2] = "poll failed" }, capture(device.input.input.waitForEvent()))

        device.input.timer_callbacks = { {} }
        bridge.setKeyboardConnected(false)
        reply = { n = 2, false, C.EINTR }
        -- A pending gesture timer must not be told its deadline elapsed early.
        assert.are.same({ n = 2, false, C.EINTR }, capture(device.input.input.waitForEvent()))
    end)

    it("keeps touch-only capabilities when keyboard detection is unsupported", function()
        local device = SDLDevice:createVariant{
            platform = "iOS", native_bridge = require("device/sdl/iosbridge").new(),
        }
        device.input = { input = { waitForEvent = function() return nil end } }
        device:initKeyboard()
        device.input.input.waitForEvent()
        assert.is_false(device:hasKeys())
        assert.is_false(device:hasKeyboard())
        assert.is_true(device:isTouchDevice())
    end)

    it("preserves successful SDL event batches and the shared backend used by non-iOS variants", function()
        local backend = require("ffi/input_SDL3")
        local original_wait = backend.waitForEvent
        local batch = { { type = 1, code = 27, value = 1 } }
        stub(backend, "waitForEvent", function() return true, batch end)
        local shared_wait = backend.waitForEvent
        local ok, err = pcall(function()
            local device = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new() }
            device.input = { input = backend }
            device:initKeyboard()
            local success, events = device.input.input.waitForEvent()
            assert.is_true(success)
            assert.are.equal(batch, events)
            assert.are.equal(shared_wait, require("ffi/input_SDL3").waitForEvent)
            local non_ios = SDLDevice:createVariant{ platform = "Linux" }
            assert.is_nil(non_ios.initKeyboard)
            assert.is_nil(non_ios.updateKeyboardState)
            assert.are.equal(shared_wait, backend.waitForEvent)
        end)
        backend.waitForEvent:revert()
        assert.are.equal(original_wait, backend.waitForEvent)
        assert(ok, err)
    end)

    it("uses SDL's platform name by default, before desktop environment hints", function()
        local SDL = require("ffi/SDL3")
        stub(SDL, "getPlatform", function() return "iOS" end)
        local ok, err = pcall(function()
            assert.is_true(SDLDevice:createVariant():isIOS())
        end)
        SDL.getPlatform:revert()
        assert(ok, err)
    end)

    it("loads the production iOS variant without probing desktop applications through a shell", function()
        local SDL = require("ffi/SDL3")
        stub(SDL, "getPlatform", function() return "iOS" end)
        stub(os, "execute", function() error("iOS must not execute desktop shell probes") end)
        local ok, err = pcall(function()
            local device = dofile("frontend/device/sdl/device.lua")
            assert.is_true(device:isIOS())
            assert.are.same({}, device:getExternalDictLookupList())
        end)
        SDL.getPlatform:revert()
        os.execute:revert()
        assert(ok, err)
    end)

    it("reports unsupported native operations until the FFI adapters are installed", function()
        local device = SDLDevice:createVariant{ platform = "iOS" }
        local result, err = device.bridge.downloadStart{ url = "https://example.org/book", path = "unused" }
        assert.is_nil(result)
        assert.are.equal("unsupported", err)
        result, err = device.bridge.safeAreaInsets()
        assert.is_nil(result)
        assert.are.equal("unsupported", err)
    end)

    it("exposes independent download handles and returns redirects to Lua without following them", function()
        local device = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new{
            responses = {
                ["https://books.example/book"] = {
                    { state = "downloading", received = 10, total = 100 },
                    { state = "completed", received = 100, total = 100, status = 200 },
                },
                ["https://books.example/redirect"] = {
                    { state = "completed", status = 302, headers = { location = "https://other.example/book" } },
                },
            },
        } }
        local first_path, redirect_path = os.tmpname(), os.tmpname()
        local bridge = device.bridge
        local first = bridge.downloadStart{ url = "https://books.example/book", path = first_path }
        local redirect = bridge.downloadStart{ url = "https://books.example/redirect", path = redirect_path }
        assert.are_not.equal(first, redirect)
        assert.are.same({ state = "downloading", received = 10, total = 100, path = first_path }, bridge.downloadPoll(first))
        assert.are.same({ state = "completed", status = 302, headers = { location = "https://other.example/book" },
            path = redirect_path }, bridge.downloadPoll(redirect))
        assert.is_true(bridge.downloadCancel(redirect))
        assert.is_true(bridge.downloadCancel(redirect))
        assert.is_nil(bridge.downloadPoll(redirect))
        assert.are.equal("completed", bridge.downloadPoll(first).state)
        bridge.downloadCancel(first)
    end)

    it("exposes sticky background expiry, unfinished saves, insets and brightness through the device", function()
        local device = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new{
            insets = { top = 59, right = 0, bottom = 34, left = 0 },
        } }
        local bridge = device.bridge
        local task = bridge.backgroundBegin()
        bridge.backgroundSetSaveIncomplete(true)
        assert.is_false(bridge.backgroundExpired(task))
        bridge.expireBackground(task)
        assert.is_true(bridge.backgroundExpired(task))
        assert.is_true(bridge.backgroundEnd(task))
        assert.is_true(bridge.backgroundExpired(task))
        assert.is_true(bridge.backgroundSaveIncomplete())
        bridge.backgroundSetSaveIncomplete(false)
        assert.is_false(bridge.backgroundSaveIncomplete())
        assert.are.same({ top = 59, right = 0, bottom = 34, left = 0 }, bridge.safeAreaInsets())
        bridge.brightnessSet(80)
        assert.are.equal(80, bridge.brightnessGet())
        local denied = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new{ background_unavailable = true } }
        assert.is_nil(denied.bridge.backgroundBegin())
        assert.is_false(denied.bridge.backgroundExpired(nil))
    end)

    it("leaves the Emulator and Desktop capability defaults unchanged", function()
        local original_getenv = os.getenv
        stub(os, "getenv", function(name)
            if name ~= "APPIMAGE" and name ~= "FLATPAK" and name ~= "KO_MULTIUSER"
                and name ~= "UBUNTU_APPLICATION_ISOLATION" then
                return original_getenv(name)
            end
        end)
        local ok, err = pcall(function()
            local emulator = SDLDevice:createVariant{ platform = "Linux" }
            assert.are.equal("Emulator", emulator.model)
            assert.is_true(emulator:isEmulator())
            assert.is_true(emulator:hasEinkScreen())
            assert.is_true(emulator:hasFrontlight())
            assert.is_true(emulator:hasNaturalLight())
            assert.is_true(emulator:hasKeyboard())
            assert.is_true(emulator:canShowMenuShortcuts())
            assert.is_true(emulator:canForkProcesses())
            assert.is_false(emulator:hasOTAUpdates())
            assert.is_false(emulator:isIOS())
            os.getenv.invokes(function(name)
                if name == "KO_MULTIUSER" then return "1" end
                return original_getenv(name)
            end)
            local desktop = SDLDevice:createVariant{ platform = "Linux" }
            assert.are.equal("Linux", desktop.model)
            assert.is_true(desktop:isDesktop())
            assert.is_false(desktop:isIOS())
            assert.is_false(desktop:hasEinkScreen())
            assert.is_false(desktop:hasFrontlight())
            assert.is_true(desktop:hasKeyboard())
            assert.is_true(desktop:canShowMenuShortcuts())
            assert.is_true(desktop:canForkProcesses())
            -- The actual SDL platform always wins over desktop packaging hints.
            assert.is_true(SDLDevice:createVariant{ platform = "iOS" }:isIOS())
        end)
        os.getenv:revert()
        assert(ok, err)
    end)

    describe("system language before gettext initialization", function()
        local ffi, ffiUtil, Locale, original_open
        local preferred, platform, allocations

        before_each(function()
            ffi = require("ffi")
            ffiUtil = require("ffi/util")
            Locale = require("device/sdl/locale")
            preferred, allocations, platform = {}, {}, "iOS"
            stub(ffiUtil, "loadSDL3", function()
                return {
                    SDL_GetPlatform = function() return platform end,
                    SDL_GetPreferredLocales = function(count)
                        count[0] = #preferred
                        local locales = ffi.new("SDL_Locale *[?]", #preferred + 1)
                        for i, pair in ipairs(preferred) do
                            local locale = ffi.new("SDL_Locale[1]")
                            locale[0].language, locale[0].country = pair[1], pair[2]
                            locales[i - 1] = locale
                            allocations[#allocations + 1] = locale
                        end
                        return locales
                    end,
                    SDL_free = function() end,
                }
            end)
            original_open = io.open
            -- Catalog presence is a filesystem boundary; no need to compile .mo fixtures.
            stub(io, "open", function(path, ...)
                local catalog = path:match("^l10n/(.-)/koreader%.mo$")
                if catalog then
                    if ({ zh_CN = true, zh_TW = true, de = true, en_GB = true, ar = true, he = true,
                        pt_BR = true, pt_PT = true, ko_KR = true, it_IT = true })[catalog] then
                        return { close = function() end }
                    end
                    return nil
                end
                return original_open(path, ...)
            end)
        end)

        after_each(function()
            ffiUtil.loadSDL3:revert()
            io.open:revert()
        end)

        it("maps simplified/traditional Chinese and regional locales to installed catalogs", function()
            for _, case in ipairs{
                { "zh-Hans", "SG", "zh_CN" }, { "zh-Hant", "CN", "zh_TW" },
                { "zh", "HK", "zh_TW" }, { "zh", "TW", "zh_TW" }, { "zh", "CN", "zh_CN" },
                { "de", "DE", "de" }, { "pt", "BR", "pt_BR" }, { "pt", nil, "pt_PT" },
                { "ko", "KR", "ko_KR" }, { "it", nil, "it_IT" }, { "en", "GB", "en_GB" },
                { "en", "US", "C" },
                { "ar", "SA", "ar" }, { "he", "IL", "he" },
            } do
                preferred = { { case[1], case[2] } }
                assert.are.equal(case[3], Locale.resolveLanguage(), case[1])
            end
        end)

        it("honors preference order and falls back to English when none is supported", function()
            preferred = { { "xx", "XX" }, { "de", "AT" }, { "zh", "CN" } }
            assert.are.equal("de", Locale.resolveLanguage())
            preferred = { { "xx", "XX" } }
            assert.are.equal("C", Locale.resolveLanguage())
            preferred = {}
            assert.are.equal("C", Locale.resolveLanguage())
        end)

        it("resolves the system default without persisting it", function()
            local saved_language = G_reader_settings:readSetting("language")
            preferred = { { "zh", "CN" } }
            assert.are.equal("zh_CN", Locale.resolveLanguage())
            assert.are.equal(saved_language, G_reader_settings:readSetting("language"))
        end)

        it("leaves Desktop and Emulator startup language selection alone", function()
            preferred = { { "zh", "CN" } }
            platform = "Linux"
            assert.is_nil(Locale.resolveLanguage())
        end)
    end)
end)
