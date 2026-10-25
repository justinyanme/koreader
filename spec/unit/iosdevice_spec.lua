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

    it("keeps each device's window and bridge state separate", function()
        local first = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new() }
        local second = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new() }
        first.window.width = 390
        assert.are_not.equal(390, second.window.width)
        first.bridge.brightnessSet(75)
        assert.are.equal(75, first.bridge.brightnessGet())
        assert.are.equal(50, second.bridge.brightnessGet())
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
                    if ({ zh_CN = true, zh_TW = true, de = true, en_GB = true,
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
            } do
                preferred = { { case[1], case[2] } }
                assert.are.equal(case[3], Locale.resolveLanguage(nil), case[1])
            end
        end)

        it("honors preference order and falls back to English when none is supported", function()
            preferred = { { "xx", "XX" }, { "de", "AT" }, { "zh", "CN" } }
            assert.are.equal("de", Locale.resolveLanguage(nil))
            preferred = { { "xx", "XX" } }
            assert.are.equal("C", Locale.resolveLanguage(nil))
            preferred = {}
            assert.are.equal("C", Locale.resolveLanguage(nil))
        end)

        it("preserves explicit language and KO_RTL overrides without persisting the system default", function()
            local saved_language = G_reader_settings:readSetting("language")
            preferred = { { "zh", "CN" } }
            for _, override in ipairs{ "C", "de", "ar", "" } do
                assert.are.equal(override, Locale.resolveLanguage(override))
            end
            assert.are.equal(saved_language, G_reader_settings:readSetting("language"))
            assert.are.equal("zh_CN", Locale.resolveLanguage(nil))
            assert.are.equal(saved_language, G_reader_settings:readSetting("language"))
        end)

        it("leaves Desktop and Emulator startup language selection alone", function()
            preferred = { { "zh", "CN" } }
            platform = "Linux"
            assert.is_nil(Locale.resolveLanguage(nil))
        end)
    end)
end)
