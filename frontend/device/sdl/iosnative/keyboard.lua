-- SDL's UIKit backend already tracks GCKeyboard connection notifications.
-- Use its hardware-keyboard state; no UIKit bridge or FFI callback is needed.
local ffi = require("ffi")
local SDL = require("ffi/SDL3").SDL

ffi.cdef[[bool SDL_HasKeyboard(void);]]

return {
    keyboardConnected = function()
        return SDL.SDL_HasKeyboard()
    end,
}
