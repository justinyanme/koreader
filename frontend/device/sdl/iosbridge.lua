--[[--
iOS native bridge contract (seam C). Devices expose this table as Device.bridge.
All functions use dot calls, return Lua values, and are polled from Lua's main
thread. No callbacks enter Lua. FFI adapters belong to B4/B5/B6/B8; the default
implementation below returns nil, "unsupported" until those adapters are wired.

downloadStart{url, headers, path, timeout} -> handle | nil, error
    Starts one GET into a temporary file at path. headers is a string map;
    timeout is in seconds. Handles are opaque and independent for concurrent jobs.
downloadPoll(handle) -> snapshot | nil, error
    snapshot = {state, received, total, status, headers, path, error}. state is
    "pending", "downloading", "completed", "failed", or "cancelled"; received
    and total are bytes (total may be nil). status is the HTTP status, headers
    has lowercase keys. A 3xx is a completed response with headers.location:
    NEVER follow redirects or apply credential/URL policy here (ADR-0004).
    Completed snapshots remain readable until downloadCancel releases the handle.
downloadCancel(handle) -> true | nil, error
    Cancels/releases the job and removes its temporary file, including partial
    files after failure. Safe to repeat. Lua moves a successful file before release.

backgroundBegin() -> handle | nil, error
    Acquires short background time, without promising a duration. nil means no
    time was granted; saving must still proceed. Native event watchers may have
    acquired the handle before Lua receives the lifecycle event.
backgroundEnd(handle) -> true | nil, error
    Releases the handle; safe after expiry or repeated calls.
backgroundExpired(handle) -> boolean | nil, error
    Sticky expiry flag. The native expiry handler ends the task immediately,
    without entering Lua; Lua checks this flag between save steps.
backgroundSaveIncomplete() -> boolean | nil, error
backgroundSetSaveIncomplete(boolean) -> true | nil, error
    Sticky process-wide save flag, retained across foreground/background cycles.
    Lua marks it before saving and clears it only after completing required saves.

safeAreaInsets() -> {top, right, bottom, left} | nil, error
    Insets in SDL window coordinates. B4 converts them to its viewport; no dp or
    viewport policy belongs in this table.
brightnessGet() -> number | nil, error
brightnessSet(number) -> true | nil, error
    System brightness on the inclusive 0..100 scale used by PowerD.
keyboardConnected() -> boolean | nil, error
    Whether an external hardware keyboard is connected (SDL_HasKeyboard).
    Query after SDL input waits; the on-screen keyboard does not count.
--]]

local Bridge = {}

local function unsupported()
    return nil, "unsupported"
end

function Bridge.new()
    return {
        downloadStart = unsupported,
        downloadPoll = unsupported,
        downloadCancel = unsupported,
        backgroundBegin = unsupported,
        backgroundEnd = unsupported,
        backgroundExpired = unsupported,
        backgroundSaveIncomplete = unsupported,
        backgroundSetSaveIncomplete = unsupported,
        safeAreaInsets = unsupported,
        brightnessGet = unsupported,
        brightnessSet = unsupported,
        keyboardConnected = unsupported,
    }
end

--- The production bridge on iOS: the defaults above, with each feature's FFI adapter laid over
-- them. An adapter is device/sdl/iosnative/<feature>.lua returning a table of the functions it
-- implements, so tickets wiring different features never edit the same file.
Bridge.features = { "safearea", "brightness", "links", "share", "files", "background", "download", "keychain", "keyboard" }

function Bridge.native()
    local bridge = Bridge.new()
    for _, feature in ipairs(Bridge.features) do
        local name = "device/sdl/iosnative/" .. feature
        if package.searchpath(name, package.path) then
            for key, fn in pairs(require(name)) do bridge[key] = fn end
        end
    end
    return bridge
end

return Bridge
