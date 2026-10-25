-- FFI adapter for openURL in device/sdl/iosbridge: SDL3's own SDL_OpenURL (UIApplication open on
-- UIKit), so there is no Swift for links. base's SDL3_h does not declare it.
local ffi = require("ffi")
require("ffi/SDL3_h")

pcall(ffi.cdef, "bool SDL_OpenURL(const char *url);")

local SDL = require("ffi/util").loadSDL3()

return {
    openURL = function(url)
        if SDL.SDL_OpenURL(url) then return true end
        return nil, ffi.string(SDL.SDL_GetError())
    end,
}
