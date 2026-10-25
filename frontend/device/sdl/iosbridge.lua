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
    A failed snapshot's error is "timeout" (no data within timeout), "background"
    (background time ran out while it ran; reported once the app is active again,
    "downloading" until then), or the system's text.
downloadCancel(handle) -> true | nil, error
    Cancels/releases the job and removes its temporary file, including partial
    files after failure. Safe to repeat. Lua moves a successful file before release.

backgroundBegin() -> handle | nil, error
    Acquires short background time, without promising a duration. nil means no
    time was granted; saving must still proceed. Native event watchers may have
    acquired the handle before Lua receives the lifecycle event. Claim that same
    handle even if it expired before delivery, so backgroundExpired sees expiry.
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

pickFilesStart{extensions} -> true | nil, error
    Presents the system document picker over SDL's view controller: multiple selection, as copies
    (asCopy), of files with one of the extensions (no dot; "fb2.zip" counts as its last part).
    One picker at a time: "busy" while one shows.
pickFilesPoll() -> snapshot | nil, error
    snapshot = {state, paths, errors, error}. state is "idle", "pending", "picked", "cancelled" or
    "failed"; a final state is returned once, then "idle". paths are the system's copies, which Lua
    moves or removes. errors maps a file name to why it could not be copied (not downloaded from
    its cloud, say); error explains "failed".
memoryAvailable() -> bytes | nil, error
    How much more the app may allocate before the system's per-process limit.
    Without such a limit (the simulator), the physical memory. No margin applied.

openURL(url) -> true | nil, error
    Hands url to the system (SDL_OpenURL); the app may move to the background.
shareStart(paths) -> handle | nil, error
    Presents the system share sheet for an array of absolute file paths. One sheet
    at a time; the native side keeps no reference to the files after dismissal.
sharePoll(handle) -> state | nil, error
    state is "presenting", "completed", "cancelled" or "failed"; terminal states
    are sticky. Lua removes the shared files once a terminal state is reached.

keychainAvailable = true only when the three Keychain operations are implemented.
keychainGet(key) -> string | nil, error
    Missing entries return nil, "not_found"; other failures are distinct.
keychainSet(key, value) -> true | nil, error
keychainDelete(key) -> true | nil, error
    Delete succeeds for an absent entry. Values are byte strings, including empty
    strings. Keys are opaque references, never credentials. Native storage uses
    generic passwords, AfterFirstUnlockThisDeviceOnly, without synchronization.
    Errors contain only numeric OSStatus; no credential or system error text.
accessibilitySet{generation, pixel_width, screen_changed, elements} -> true | nil, error
    Replaces the VoiceOver elements over SDL's view (device/sdl/iosaccessibility). elements, in
    VoiceOver order: {x, y, w, h, label, value, adjustable}, rects in screen pixels of a screen
    pixel_width wide. screen_changed: a new screen rather than a change on the same one.
accessibilityPoll() -> {{generation, index, action}} | nil, error
    The activations since the last poll, oldest first: index of the element (from 1) in the set of
    that generation, action "activate", "increment" or "decrement". The overlay wakes the input wait
    with an SDL user event when it queues one; it never calls Lua.
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
        pickFilesStart = unsupported,
        pickFilesPoll = unsupported,
        memoryAvailable = unsupported,
        openURL = unsupported,
        shareStart = unsupported,
        sharePoll = unsupported,


        keychainAvailable = false,
        keychainGet = unsupported,
        keychainSet = unsupported,
        keychainDelete = unsupported,
        accessibilitySet = unsupported,
        accessibilityPoll = unsupported,
    }
end

--- The production bridge on iOS: the defaults above, with each feature's FFI adapter laid over
-- them. An adapter is device/sdl/iosnative/<feature>.lua returning a table of the functions it
-- implements, so tickets wiring different features never edit the same file.
Bridge.features = { "safearea", "brightness", "links", "share", "files", "background", "download", "keychain", "keyboard", "memory", "accessibility" }

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
