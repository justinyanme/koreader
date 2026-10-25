-- FFI adapter for the brightness part of device/sdl/iosbridge (Swift: Bridge/Brightness.swift).
-- Native brightness is 0..1 on the window scene's screen; the bridge speaks PowerD's 0..100.
local ffi = require("ffi")

ffi.cdef[[
double ko_ios_brightness_get(void);
bool ko_ios_brightness_set(double value);
]]

local C = ffi.C

return {
    brightnessGet = function()
        local value = C.ko_ios_brightness_get()
        if value < 0 then return nil, "no screen" end
        return math.floor(value * 100 + 0.5)
    end,
    brightnessSet = function(value)
        if C.ko_ios_brightness_set(math.max(0, math.min(100, value)) / 100) then return true end
        return nil, "no screen"
    end,
}
