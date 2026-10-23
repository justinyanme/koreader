--[[--
Toast of the e-ink redesign (see DESIGN.md, Toast), as WeChat Read confirms a
copy: an ink rounded rectangle with paper text, centered over the lower part of
the page, that goes away by itself after a moment.

Like a Notification, whose toast handling this follows, it is a toast for
UIManager: any touch or key closes it and still reaches the page, so it is gone
before the popover a long-press brings up. It refreshes its own rect itself:
showing with "fast" (it is solid ink), closing with `close_refresh_type`, "fast"
by default, "ui" where the page under it is gray.

@usage
    UIManager:show(Toast:new{ text = _("Copied") })
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Palette = require("ui/palette")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local Toast = InputContainer:extend{
    text = nil,
    timeout = 2, -- seconds
    close_refresh_type = "fast",
    toast = true, -- stacked on top, never stops an event
}

function Toast:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local edge = Screen:scaleBySize(16)
    local pad = Screen:scaleBySize(18)
    local label = TextWidget:new{
        text = self.text,
        face = Font:getFace("ui_label"),
        fgcolor = Palette.paper,
        max_width = sw - 2 * (edge + pad),
    }
    -- as wide as in the reference (248dp) for a short text
    local w = math.min(sw - 2 * edge, math.max(Screen:scaleBySize(248), label:getSize().w + 2 * pad))
    local h = Screen:scaleBySize(47)
    -- its bottom 90dp above the screen's, as in the reference
    self.dimen = Geom:new{ x = math.floor((sw - w) / 2), y = sh - Screen:scaleBySize(90) - h, w = w, h = h }
    self.frame = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        radius = Screen:scaleBySize(8),
        background = Palette.ink,
        CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, label },
    }
end

function Toast:paintTo(bb, x, y)
    self.frame:paintTo(bb, x + self.dimen.x, y + self.dimen.y)
end

function Toast:onShow()
    UIManager:setDirty(self, "fast", self.dimen)
    if self.timeout then
        self._timeout_func = function()
            self._timeout_func = nil
            UIManager:close(self)
        end
        UIManager:scheduleIn(self.timeout, self._timeout_func)
    end
    return true
end

function Toast:onCloseWidget()
    if self._timeout_func then
        UIManager:unschedule(self._timeout_func)
        self._timeout_func = nil
    end
    UIManager:setDirty(nil, self.close_refresh_type, self.dimen)
    self.frame:free()
end

-- Any input closes it and goes on to the widget below.
function Toast:onGesture()
    UIManager:close(self)
    return false
end

function Toast:onKeyPress()
    UIManager:close(self)
    return false
end
Toast.onKeyRepeat = Toast.onKeyPress

-- Events InputContainer would otherwise handle, and stop, on the page's behalf
function Toast:onIgnoreTouchInput()
    return true
end
Toast.onResume = Toast.onIgnoreTouchInput
Toast.onPhysicalKeyboardDisconnected = Toast.onIgnoreTouchInput
Toast.onInput = Toast.onIgnoreTouchInput

return Toast
