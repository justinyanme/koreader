local BasePowerD = require("device/generic/powerd")
local SDL = require("ffi/SDL3")

local SDLPowerD = BasePowerD:new{
    -- these values are just used on the emulator
    hw_intensity = 50,
    fl_min = 0,
    fl_max = 100,
    fl_warmth = 50,
    fl_warmth_min = 0,
    fl_warmth_max = 100,
}

-- Only iOS has a native bridge: its brightness is the system's, on the same 0..100 scale.
-- A failing bridge leaves the emulated value in place rather than raising.
function SDLPowerD:frontlightIntensityHW()
    local bridge = self.device and self.device.bridge
    if bridge then
        local value, err = bridge.brightnessGet()
        if value then
            self.hw_intensity = value
        else
            require("logger").warn("SDLPowerD: brightnessGet failed:", err)
        end
    end
    return self.hw_intensity
end

function SDLPowerD:setIntensityHW(intensity)
    require("logger").info("set brightness to", intensity)
    self.hw_intensity = intensity or self.hw_intensity
    local bridge = self.device and self.device.bridge
    if bridge then
        local ok, err = bridge.brightnessSet(self.hw_intensity)
        if not ok then require("logger").warn("SDLPowerD: brightnessSet failed:", err) end
    end
    self:_decideFrontlightState()
end

function SDLPowerD:frontlightWarmthHW()
    return self.fl_warmth
end

function SDLPowerD:getCapacityHW()
    local _, _, _, percent = SDL.getPowerInfo()
    -- -1 looks a bit odd compared to 0
    if percent == -1 then return 0 end
    return percent
end

function SDLPowerD:isChargingHW()
    local ok, charging = SDL.getPowerInfo()
    if ok then return charging end
    return false
end

function SDLPowerD:beforeSuspend()
    -- Inhibit user input and emit the Suspend event.
    self.device:_beforeSuspend()
end

function SDLPowerD:afterResume()
    self:invalidateCapacityCache()

    -- Restore user input and emit the Resume event.
    self.device:_afterResume()
end

return SDLPowerD
