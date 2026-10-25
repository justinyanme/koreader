-- FFI adapter for the share sheet in device/sdl/iosbridge (Swift: Bridge/Share.swift).
local ffi = require("ffi")

ffi.cdef[[
int ko_ios_share_start(const char **paths, int count);
int ko_ios_share_poll(int handle);
]]

local C = ffi.C
-- Must match ShareState in Share.swift.
local states = { [0] = "presenting", "completed", "cancelled", "failed" }

return {
    shareStart = function(paths)
        local array = ffi.new("const char *[?]", #paths)
        for i, path in ipairs(paths) do array[i - 1] = path end
        local handle = C.ko_ios_share_start(array, #paths)
        if handle <= 0 then return nil, "share sheet not presented" end
        return handle
    end,
    sharePoll = function(handle)
        local state = states[C.ko_ios_share_poll(handle)]
        if not state then return nil, "unknown share" end
        return state
    end,
}
