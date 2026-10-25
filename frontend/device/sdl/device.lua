local Event = require("ui/event")
local Geom = require("ui/geometry")
local Gamepad = require("device/sdl/gamepad")
local Generic = require("device/generic/device")
local Key = require("device/key")
local UIManager
local SDL = require("ffi/SDL3")
local ffi = require("ffi")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")

-- SDL computes WM_CLASS on X11/Wayland based on process's binary name.
-- Some desktop environments rely on WM_CLASS to name the app and/or to assign the proper icon.
if jit.os == "Linux" or jit.os == "BSD" or jit.os == "POSIX" then
    if not os.getenv("SDL_VIDEO_WAYLAND_WMCLASS") then ffi.C.setenv("SDL_VIDEO_WAYLAND_WMCLASS", "KOReader", 1) end
    if not os.getenv("SDL_VIDEO_X11_WMCLASS") then ffi.C.setenv("SDL_VIDEO_X11_WMCLASS", "KOReader", 1) end
end

local function yes() return true end
local function no() return false end
local function hasExternalKeyboard(self) return self._keyboard_connected == true end
local function notOSX() return jit.os ~= "OSX" end

local function isUrl(s)
    return type(s) == "string" and s:match("*?://")
end

local function isCommand(s)
    return os.execute("command -v "..s.." >/dev/null") == 0
end

local function runCommand(command)
    return os.execute(command) == 0
end

local function getDesktopDicts()
    local t = {
        { "Goldendict", "Goldendict", false, "goldendict" },
    }
    -- apple dict is always present in osx
    if jit.os == "OSX" then
        table.insert(t, 1, { "Apple", "AppleDict", false, "dict://" })
    end
    return t
end

local function getLinkOpener()
    if jit.os == "Linux" and isCommand("xdg-open") then
        return true, "xdg-open"
    elseif jit.os == "OSX" and isCommand("open") then
        return true, "open"
    end
    return false
end

-- Probe desktop applications only when a device with external lookup support
-- actually requests them. Loading the iOS variant must never invoke a shell.
local external
local function getExternal()
    if not external then
        external = require("device/thirdparty"):new{
            dicts = getDesktopDicts(),
            check = function(self, app)
                return (isUrl(app) and getLinkOpener()) or isCommand(app)
            end,
        }
    end
    return external
end

local Device = Generic:extend{
    model = "SDL",
    isSDL = yes,
    home_dir = os.getenv("XDG_DOCUMENTS_DIR") or os.getenv("HOME"),
    hasBattery = SDL.getPowerInfo,
    hasKeyboard = yes,
    hasKeys = yes,
    hasSymKey = os.getenv("DISABLE_TOUCH") == "1" and yes or no,
    hasDPad = yes,
    useDPadAsActionKeys = os.getenv("DISABLE_TOUCH") == "1" and yes or no,
    supportsGamepad = yes,
    hasWifiToggle = no,
    hasSeamlessWifiToggle = no,
    isTouchDevice = yes,
    isDefaultFullscreen = no,
    needsScreenRefreshAfterResume = no,
    hasColorScreen = yes,
    hasEinkScreen = no,
    hasSystemFonts = yes,
    canSuspend = no,
    canStandby = no,
    startTextInput = SDL.startTextInput,
    stopTextInput = SDL.stopTextInput,
    canOpenLink = getLinkOpener,
    openLink = function(self, link)
        local enabled, tool = getLinkOpener()
        if not enabled or not tool or not link or type(link) ~= "string" then return end
        return runCommand(util.shell_escape{tool, link})
    end,
    canExternalDictLookup = yes,
    getExternalDictLookupList = function() return getExternal().dicts end,
    doExternalDictLookup = function(self, text, method, callback)
        local external = getExternal()
        external.when_back_callback = callback
        local ok, app = external:checkMethod("dict", method)
        if app then
            if isUrl(app) and getLinkOpener() then
                ok = self:openLink(app..text)
            elseif isCommand(app) then
                ok = runCommand(util.shell_escape{app, text} .. " &")
            end
        end
        if ok and external.when_back_callback then
            external.when_back_callback()
            external.when_back_callback = nil
        end
    end,
}

function Device:hasKeyboardTextInput()
    return true
end

local AppImage = Device:extend{
    model = "AppImage",
    hasOTAUpdates = yes,
    isDesktop = yes,
}

function AppImage:otaModel()
    local arch = jit.arch
    local model
    if arch == "arm64" then
        model = "appimage-aarch64"
    elseif arch == "arm" then
        model = "appimage-armhf"
    elseif arch == "x64" then
        model = "appimage-x86_64"
    end
    return model, "link"
end

local Desktop = Device:extend{
    isDesktop = yes,
    canRestart = notOSX,
    hasExitOptions = notOSX,
}

local Flatpak = Device:extend{
    model = "Flatpak",
    isDesktop = yes,
    canExternalDictLookup = no,
}

local Emulator = Device:extend{
    model = "Emulator",
    isEmulator = yes,
    hasBattery = yes,
    hasEinkScreen = yes,
    hasFrontlight = yes,
    hasNaturalLight = yes,
    hasNaturalLightApi = yes,
    hasWifiToggle = yes,
    -- Not really, Device:reboot & Device:powerOff are not implemented, so we just exit ;).
    canPowerOff = yes,
    canReboot = yes,
    -- NOTE: Via simulateSuspend
    canSuspend = yes,
    canStandby = no,
}

local UbuntuTouch = Device:extend{
    model = "UbuntuTouch",
    hasFrontlight = yes,
    isDefaultFullscreen = yes,
}

local IOS = Device:extend{
    model = "iOS",
    isIOS = yes,
    minimum_touch_size = 44,
    isDesktop = no,
    isEmulator = no,
    hasFrontlight = yes,
    hasNaturalLight = no,
    hasKeys = hasExternalKeyboard,
    hasDPad = no,
    hasKeyboard = hasExternalKeyboard,
    canShowMenuShortcuts = no,
    hasSymKey = no,
    useDPadAsActionKeys = no,
    supportsGamepad = no,
    hasOTAUpdates = no,
    canForkProcesses = no,
    canRestart = no,
    hasExitOptions = no,
    isDefaultFullscreen = yes,
    canOpenLink = no,
    openLink = no,
    canExternalDictLookup = no,
    getExternalDictLookupList = function() return {} end,
    doExternalDictLookup = function() end,
    hasSandboxedHome = yes,
    canImportFiles = yes,
    importFile = function(folder) require("apps/shelf/bookimport").pick(folder) end,
}

function IOS:getUpdateInstructions()
    return _("To update it, install the new build from TestFlight.")
end

--- Moves what the system left in its inboxes into the home folder: "Open with" while the app was not
-- running (SDL's drop event comes before SDL is initialized, and is lost), and leftovers.
function IOS:sweepImports()
    local inboxes = require("device/sdl/iosstorage").inboxes(self.container)
    return require("apps/shelf/bookimport").sweep(inboxes, self.home_dir)
end

local is_tablet
local function isTablet()
    if is_tablet == nil then
        local ok, result = pcall(function()
            ffi.cdef("bool SDL_IsTablet(void);")
            return SDL.SDL.SDL_IsTablet()
        end)
        is_tablet = ok and result or false
    end
    return is_tablet
end

--- 导入's 从电脑传书 (Q30, Q43): the Files app's folder and Finder's file sharing.
function IOS:getTransferInstructions()
    -- @translators %1 is iPhone or iPad. "On My iPhone" and Just Reader are the folder names the Files app shows; Files is the tab of the device's window in Finder.
    return T(_("In the Files app, put books in On My %1 › Just Reader. From a Mac, connect the %1, select it in Finder, then drag books onto Just Reader in the Files tab."),
        isTablet() and "iPad" or "iPhone")
end

-- SDL window dimensions are points on iOS; framebuffer dimensions are pixels.
-- T0 measured 3 pixels/point on iPhone and 2 on iPad. Derive the ratio rather
-- than identifying models, and keep this policy on this screen instance only.
function IOS:setupScreen()
    local screen = self.screen
    self.pixel_ratio = screen.screen_size.w / self.window.width
    self.display_dpi = 160 * self.pixel_ratio -- dp ruler, not physical panel PPI
    screen:setDPI(self.display_dpi)
    local function pointsToPixels(_, dp)
        return math.ceil(dp * self.pixel_ratio)
    end
    screen.scaleBySize = pointsToPixels
    screen.scaleByDPI = pointsToPixels

    local insets, err = self.bridge.safeAreaInsets()
    if not insets then
        logger.warn("iOS safe area unavailable:", err)
        insets = { top = 0, right = 0, bottom = 0, left = 0 }
    end
    -- Round inward so fractional point edges never expose an unsafe pixel.
    local left = math.ceil(insets.left * self.pixel_ratio)
    local top = math.ceil(insets.top * self.pixel_ratio)
    local right = math.floor(screen.screen_size.w - insets.right * self.pixel_ratio)
    local bottom = math.floor(screen.screen_size.h - insets.bottom * self.pixel_ratio)
    self.viewport = Geom:new{ x = left, y = top, w = right - left, h = bottom - top }
end

function IOS:setScreenDPI()
    -- A saved e-ink DPI override must not shrink iOS's point-sized controls.
    Generic.setScreenDPI(self, self.display_dpi)
end

function IOS:resizeWindow(w, h)
    self.screen:resize(w, h)
    self.window.width, self.window.height = SDL.win_w, SDL.win_h
    -- resize returns a full buffer, with the previous viewport released. Keep
    -- screen_size physical: framebuffer coordinate translation depends on it.
    local full_size = self.screen:getSize()
    self.screen.screen_size.w, self.screen.screen_size.h = full_size.w, full_size.h
    self:setupScreen()
    self.screen:setViewport(self.viewport)
    self.viewport_touch_offset.x = -self.viewport.x
    self.viewport_touch_offset.y = -self.viewport.y
    self:notifyScreenResize()
end

function Device:resizeWindow(w, h)
    self.screen:resize(w, h)
    self.window.width, self.window.height = w, h
    local size = self.screen:getSize()
    self.screen.screen_size.w, self.screen.screen_size.h = size.w, size.h
    self:notifyScreenResize()
end

function Device:notifyScreenResize()
    local new_size = self.screen:getSize()
    logger.dbg("Resizing screen to", new_size)
    -- ReaderRolling's SetDimensions handler retains internal history across
    -- reflow, restoring the same text position for resize and safe-area changes.
    UIManager:broadcastEvent(Event:new("SetDimensions", new_size))
    UIManager:broadcastEvent(Event:new("ScreenResize", new_size))
    UIManager:broadcastEvent(Event:new("RedrawCurrentPage"))
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then
        FileManager.instance:reinit(FileManager.instance.path, FileManager.instance.focused_file)
    end
    UIManager:setDirty("all", "ui")
end

function Device:init()
    -- allows to set a viewport via environment variable
    -- syntax is Lua table syntax, e.g. EMULATE_READER_VIEWPORT="{x=10,w=550,y=5,h=790}"
    local viewport = os.getenv("EMULATE_READER_VIEWPORT")
    if viewport then
        self.viewport = require("ui/geometry"):new(loadstring("return " .. viewport)())
    end

    local touchless = os.getenv("DISABLE_TOUCH") == "1"
    if touchless then
        self.isTouchDevice = no
    end

    local portrait = os.getenv("EMULATE_READER_FORCE_PORTRAIT")
    if portrait then
        self.isAlwaysPortrait = yes
    end

    self.hasClipboard = yes
    self.screen = require("ffi/framebuffer_SDL3"):new{
        device = self,
        debug = logger.dbg,
        w = self.window.width,
        h = self.window.height,
        x = self.window.left,
        y = self.window.top,
        is_always_portrait = self.isAlwaysPortrait(),
    }
    -- Pickup the updated window sizes if they were enforced in S.open (we'll get the coordinates via the initial SDL_WINDOWEVENT_MOVED)...
    self.window.width = self.screen.w
    self.window.height = self.screen.h
    if self:isIOS() then self:setupScreen() end
    self.powerd = require("device/sdl/powerd"):new{device = self}

    local ok, re = pcall(self.screen.setWindowIcon, self.screen, "resources/koreader.png")
    if not ok then logger.warn(re) end

    local function makeKeyPressEvent(keycode)
        if not keycode then
            return nil
        end
        return Event:new("KeyPress", Key:new(keycode, {}))
    end

    local function dispatchGamepadAxisMotion(axis, value, event_time)
        local axis_ev = {
            axis = axis,
            value = value,
            time = event_time,
        }
        if not UIManager:broadcastEvent(Event:new("GamepadAxisMotion", axis_ev)) then
            local key_ev = makeKeyPressEvent(Gamepad:getAxisKeyName(axis, value))
            if key_ev then
                UIManager:sendEvent(key_ev)
            end
        end
    end

    local function unscheduleAxisRepeat(clear_state)
        if self._axis_repeat_action then
            UIManager:unschedule(self._axis_repeat_action)
            self._axis_repeat_action = nil
        end
        if clear_state ~= false then
            Gamepad:clearRepeatingAxis()
        end
    end

    local function scheduleAxisRepeat(axis, delay_s)
        unscheduleAxisRepeat(false)
        Gamepad:setRepeatingAxis(axis)
        self._axis_repeat_action = function()
            local axis_ev = Gamepad:getHeldAxisEvent()
            if not axis_ev then
                Gamepad:clearRepeatingAxis()
                self._axis_repeat_action = nil
                return
            end
            dispatchGamepadAxisMotion(axis_ev.axis, axis_ev.value, time.now())
            UIManager:scheduleIn(Gamepad.axis_repeat_interval_s, self._axis_repeat_action)
        end
        UIManager:scheduleIn(delay_s, self._axis_repeat_action)
    end

    self.input = require("device/input"):new{
        device = self,
        event_map = dofile("frontend/device/sdl/event_map_sdl2.lua"),
        handleSdlEv = function(device_input, ev)
            if self.handleLifecycleEvent and self:handleLifecycleEvent(ev.code) then return end
            if ev.code == SDL.SDL.SDL_EVENT_MOUSE_WHEEL and (ev.value.integer_x ~= 0 or ev.value.integer_y ~= 0) then
                local pos = Geom:new{
                    x = 0,
                    y = 0,
                    w = 0, h = 0,
                }

                local fake_ges = {
                    ges = "pan",
                    distance = 200,
                    relative = {
                        x = 50 * ev.value.integer_x,
                        y = 100 * ev.value.integer_y,
                    },
                    pos = pos,
                    time = time.timeval(ev.time),
                    mousewheel_direction = ev.value.integer_y,
                    direction = ev.value.integer_y > 0 and "south" or "north"
                }
                local fake_ges_release = {
                    ges = "pan_release",
                    distance = fake_ges.distance,
                    relative = fake_ges.relative,
                    pos = pos,
                    time = time.timeval(ev.time),
                    from_mousewheel = true,
                }
                local fake_pan_ev = Event:new("Pan", nil, fake_ges)
                local fake_release_ev = Event:new("Gesture", fake_ges_release)
                UIManager:sendEvent(fake_pan_ev)
                UIManager:sendEvent(fake_release_ev)
            elseif ev.code == SDL.SDL.SDL_EVENT_DROP_FILE then
                local dropped_file_path = ev.value
                if dropped_file_path and dropped_file_path ~= "" then
                    if self:hasSandboxedHome() then -- "Open with": the system's copy goes into the home folder first
                        require("apps/shelf/bookimport").open(dropped_file_path, self.home_dir)
                    else
                        local ReaderUI = require("apps/reader/readerui")
                        ReaderUI:doShowReader(dropped_file_path)
                    end
                end
            elseif ev.code == SDL.SDL.SDL_EVENT_WINDOW_RESIZED then
                self:resizeWindow(ev.value.data1, ev.value.data2)
            elseif self:isIOS() and (ev.code == SDL.SDL.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED
                or ev.code == SDL.SDL.SDL_EVENT_WINDOW_SAFE_AREA_CHANGED) then
                -- Pixel-size event payloads are pixels, not SDL window points.
                self:resizeWindow()
            elseif ev.code == SDL.SDL.SDL_EVENT_WINDOW_MOVED then
                self.window.left = ev.value.data1
                self.window.top = ev.value.data2
            elseif ev.code == SDL.SDL.SDL_EVENT_GAMEPAD_AXIS_MOTION then
                local should_process = Gamepad:shouldProcessAxisMotion(ev.value.axis, ev.value.value)
                local held_direction = Gamepad:getHeldDirection(ev.value.axis)

                if not held_direction then
                    if Gamepad.repeating_axis == ev.value.axis then
                        unscheduleAxisRepeat()
                    end
                    return
                end

                if should_process then
                    scheduleAxisRepeat(ev.value.axis, Gamepad.axis_repeat_delay_s)
                    dispatchGamepadAxisMotion(ev.value.axis, ev.value.value, time.timeval(ev.time))
                end
                return
            elseif ev.code == SDL.SDL.SDL_EVENT_GAMEPAD_BUTTON_DOWN then
                -- Broadcast for plugins; if not handled, emit default key events
                if not UIManager:broadcastEvent(Event:new("GamepadButtonDown", ev.value)) then
                    return makeKeyPressEvent(Gamepad:getButtonKeyName(ev.value.button))
                end
            elseif ev.code == SDL.SDL.SDL_EVENT_GAMEPAD_BUTTON_UP then
                UIManager:broadcastEvent(Event:new("GamepadButtonUp", ev.value))
            elseif ev.code == SDL.SDL.SDL_EVENT_TEXT_INPUT then
                UIManager:sendEvent(Event:new("TextInput", tostring(ev.value)))
            end
        end,
    }

    self.keyboard_layout = dofile("frontend/device/sdl/keyboard_layout.lua")

    if self.input.gameControllerRumble(0, 0, 0) then
        self.isHapticFeedbackEnabled = yes
        self.performHapticFeedback = function(type)
            self.input.gameControllerRumble()
        end
    end

    if portrait then
        self.input:registerEventAdjustHook(
            self.input.adjustTouchSwitchAxesAndMirrorX,
            (self.screen:getScreenWidth() - 1)
        )
    end

    Generic.init(self)
end

function IOS:updateKeyboardState()
    local connected = self.bridge.keyboardConnected()
    if connected == nil or connected == self:hasKeys() then return end
    self._keyboard_connected = connected
    if not connected then
        -- A removed keyboard may never send the releases for keys held at unplug.
        local modifiers = {}
        for key in pairs(self.input.modifiers) do modifiers[key] = false end
        self.input.modifiers = modifiers
        self.input.last_repeat_time = nil
        self.input.keyboard_toggle_tapped = nil
    end
    if UIManager then
        -- Like the externalkeyboard plugin, update static bindings before live widgets.
        require("ui/widget/inputtext").initInputEvents()
        UIManager:broadcastEvent(Event:new(
            connected and "PhysicalKeyboardConnected" or "PhysicalKeyboardDisconnected"))
    end
    return true
end

function IOS:initKeyboard()
    self:updateKeyboardState()
    local backend = self.input.input
    local function afterWait(...)
        local has_input_timer = self.input.timer_callbacks and self.input.timer_callbacks[1]
        if self:updateKeyboardState() and not has_input_timer
            and select(1, ...) == false and select(2, ...) == ffi.C.EINTR then
            -- Let UIManager paint changes requested by the hotplug handlers
            -- before blocking again. Do not discard input batches or errors.
            -- With a gesture timer pending, ETIME would incorrectly tell Input
            -- that its requested polling deadline has already elapsed.
            return false, ffi.C.ETIME, select(3, ...)
        end
        return ...
    end
    -- Keep this wrapper on the iOS instance. In particular, do not replace the
    -- shared ffi/input_SDL3 waitForEvent used by Desktop and Emulator.
    self.input.input = setmetatable({
        waitForEvent = function(...)
            -- Check even when SDL reports EINTR for an event discarded by the
            -- Lua adapter (keyboard hotplug, window focus). No extra wakeups.
            return afterWait(backend.waitForEvent(...))
        end,
    }, { __index = backend })
end

--- memavailable, memtotal for util.calcFreeMem: 85% of the headroom, the Linux MemAvailable margin.
-- No total: Cache:memoryPressureCheck stays off; releasing caches is left to B5's memory warnings.
function IOS:freeMemory()
    local available = self.bridge.memoryAvailable()
    if available then
        return math.floor(available * 0.85), nil
    end
    return nil, nil
end

function IOS:init()
    -- The storage layout (device/sdl/iosstorage) first: nothing may read the home folder before it.
    self.container = os.getenv("HOME")
    self.home_dir = require("device/sdl/iosstorage").setup(G_reader_settings, self.container)
    -- Before anything sizes a cache (DocCache sizes itself when first required).
    util.freeMemProvider = function() return self:freeMemory() end
    Device.init(self)
    -- SDL must be initialized before querying its keyboard state.
    self:initKeyboard()
end

function Device:setDateTime(year, month, day, hour, min, sec)
    if hour == nil or min == nil then return true end
    local command
    if year and month and day then
        command = string.format("date -s '%d-%d-%d %d:%d:%d'", year, month, day, hour, min, sec)
    else
        command = string.format("date -s '%d:%d'",hour, min)
    end
    if os.execute(command) == 0 then
        os.execute('hwclock -u -w')
        return true
    else
        return false
    end
end

function Device:isAlwaysFullscreen()
    -- return true on embedded devices, which should default to fullscreen
    return self:isDefaultFullscreen()
end

function Device:toggleFullscreen()
    local current_mode = self.fullscreen or self:isDefaultFullscreen()
    local new_mode = not current_mode
    local ok, err = SDL.setWindowFullscreen(new_mode)
    if not ok then
        logger.warn("Unable to toggle fullscreen mode to", new_mode, "\n", err)
    else
        self.fullscreen = new_mode
    end
end

function Device:UIManagerReady(uimgr)
    UIManager = uimgr
end

function IOS:UIManagerReady(uimgr)
    Device.UIManagerReady(self, uimgr)
    self.lifecycle = require("device/sdl/ioslifecycle").new(self, uimgr)
end

function IOS:handleLifecycleEvent(code)
    return self.lifecycle and self.lifecycle:handle(code) or false
end

function IOS:scheduleSettingsSave(reader)
    if self.lifecycle then self.lifecycle:changed(reader) end
end

function IOS:cancelPendingSettingsSave(reader)
    if self.lifecycle then self.lifecycle:cancel(reader) end
end

function Device:setEventHandlers(uimgr)
    if not self:canSuspend() then
        -- If we can't suspend, we have no business even trying to, as we may not have overloaded `Device:simulateResume`.
        -- Instead, rely on the Generic Suspend/Resume handlers.
        return
    end

    UIManager.event_handlers.Suspend = function()
        self:simulateSuspend()
    end
    UIManager.event_handlers.Resume = function()
        self:simulateResume()
    end
    UIManager.event_handlers.PowerRelease = function()
        -- Resume if we were suspended
        if self.screen_saver_mode then
            if self.screen_saver_lock then
                UIManager.event_handlers.Suspend()
            else
                UIManager.event_handlers.Resume()
            end
        else
            UIManager.event_handlers.Suspend()
        end
    end
end

function Device:initNetworkManager(NetworkMgr)
    function NetworkMgr:isWifiOn() return true end
    function NetworkMgr:isConnected()
        if not Device:hasWifiToggle() then
            -- NOTE: This is necessary so as not to confuse NetworkMghr's beforeWifiAction framework.
            --       c.f., the default implementation in `NetworkMgr` itself for more details.
            return true
        end
        -- Pull the default gateway first, so we don't even try to ping anything if there isn't one...
        local default_gw = Device:getDefaultRoute()
        if not default_gw then
            return false
        end
        return 0 == os.execute("ping -c1 -w2 " .. default_gw .. " > /dev/null")
    end
end

function Emulator:supportsScreensaver() return true end

function Emulator:simulateSuspend()
    local Screensaver = require("ui/screensaver")
    Screensaver:setup()
    Screensaver:show()

    self.powerd:beforeSuspend()
end

function Emulator:simulateResume()
    local Screensaver = require("ui/screensaver")
    Screensaver:close()

    self.powerd:afterResume()
end

-- fake network manager for the emulator
function Emulator:initNetworkManager(NetworkMgr)
    local connectionChangedEvent = function(complete_callback)
        if G_reader_settings:nilOrTrue("emulator_fake_wifi_connected") then
            UIManager:broadcastEvent(Event:new("NetworkConnected"))
        else
            UIManager:broadcastEvent(Event:new("NetworkDisconnected"))
        end
        if complete_callback then
            complete_callback()
        end
    end
    function NetworkMgr:turnOffWifi(complete_callback)
        G_reader_settings:flipNilOrTrue("emulator_fake_wifi_connected")
        UIManager:scheduleIn(2, connectionChangedEvent, complete_callback)
    end
    function NetworkMgr:turnOnWifi(complete_callback)
        G_reader_settings:flipNilOrTrue("emulator_fake_wifi_connected")
        UIManager:scheduleIn(2, connectionChangedEvent, complete_callback)
    end
    function NetworkMgr:isWifiOn()
        return G_reader_settings:nilOrTrue("emulator_fake_wifi_connected")
    end
    NetworkMgr.isConnected = NetworkMgr.isWifiOn
end

-------------- device probe ------------
-- Seam C: production and specs use the same selection path. Construction does not
-- open a window; callers can initialize the returned device with :init().
function Device:createVariant(options)
    options = options or {}
    local platform = options.platform or SDL.getPlatform()
    local variant
    if platform == "iOS" then
        variant = IOS
    elseif os.getenv("APPIMAGE") then
        variant = AppImage
    elseif os.getenv("FLATPAK") then
        variant = Flatpak
    elseif os.getenv("KO_MULTIUSER") then
        variant = Desktop
    elseif os.getenv("UBUNTU_APPLICATION_ISOLATION") then
        variant = UbuntuTouch
    else
        variant = Emulator
    end
    local device = variant:extend{
        window = G_reader_settings:readSetting("sdl_window", {}),
    }
    if variant == Desktop then device.model = platform end
    if variant == IOS then
        device.bridge = options.native_bridge or require("device/sdl/iosbridge").native()
    end
    return device
end

return Device:createVariant()
