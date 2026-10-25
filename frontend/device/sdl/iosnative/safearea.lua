-- Seam C adapter: SDL already queries UIKit's safe area on its main thread.
-- Keep these values in window coordinates; the device owns pixel conversion.
local ffi = require("ffi")
local SDL = require("ffi/SDL3")

ffi.cdef[[bool SDL_GetWindowSafeArea(SDL_Window *window, SDL_Rect *rect);]]

return {
    safeAreaInsets = function()
        if SDL.screen == nil then return nil, "no SDL window" end
        local rect = ffi.new("SDL_Rect[1]")
        local w, h = ffi.new("int[1]"), ffi.new("int[1]")
        if not SDL.SDL.SDL_GetWindowSafeArea(SDL.screen, rect)
            or not SDL.SDL.SDL_GetWindowSize(SDL.screen, w, h) then
            return nil, ffi.string(SDL.SDL.SDL_GetError())
        end
        return {
            top = tonumber(rect[0].y),
            right = tonumber(w[0] - rect[0].x - rect[0].w),
            bottom = tonumber(h[0] - rect[0].y - rect[0].h),
            left = tonumber(rect[0].x),
        }
    end,
}
