--[[--
Small controls of the e-ink redesign (see DESIGN.md, Components): a pill
button, a tick stepper and a toggle. They only use @{ui.palette} colors and
the ui_* font roles, and leave refreshing to their owner.

@usage
    local EinkControls = require("ui/widget/einkcontrols")
    local button = EinkControls.PillButton:new{ text = _("Next chapter"), callback = ... }
]]

local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Palette = require("ui/palette")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local Screen = require("device").screen

local function tapEvents(dimen)
    return { TapSelect = { GestureRange:new{ ges = "tap", range = dimen } } }
end

--- Pill button: 1.5dp ink outline, or ink fill when `solid`. Shows `text` or an `icon` from resources/icons.
local PillButton = InputContainer:extend{
    text = nil,
    icon = nil,
    icon_size = Screen:scaleBySize(18),
    callback = nil,
    enabled = true,
    solid = false,
    width = nil, -- defaults to the label width plus 16dp padding
    height = Screen:scaleBySize(40),
}

function PillButton:init()
    local fg = not self.enabled and Palette.ink_3 or self.solid and Palette.paper or Palette.ink
    local label
    if self.icon then
        label = IconWidget:new{ icon = self.icon, width = self.icon_size, height = self.icon_size, alpha = true }
        if not self.enabled then label.dim = true end
    else
        label = TextWidget:new{ text = self.text, face = Font:getFace("ui_label_large"), fgcolor = fg }
    end
    local bw = Size.border.button
    local w = self.width or label:getSize().w + 2 * (Screen:scaleBySize(16) + bw)
    self.dimen = Geom:new{ w = w, h = self.height }
    self[1] = FrameContainer:new{
        bordersize = bw,
        padding = 0,
        radius = math.floor(self.height / 2),
        color = self.enabled and Palette.ink or Palette.rule,
        background = self.solid and Palette.ink or Palette.paper,
        CenterContainer:new{
            dimen = Geom:new{ w = w - 2 * bw, h = self.height - 2 * bw },
            label,
        },
    }
    self.ges_events = tapEvents(self.dimen)
end

function PillButton:onTapSelect()
    if self.enabled and self.callback then
        self.callback()
    end
    return true
end

--- Tick track: a 1.5dp ink line with `count` hollow dots; dots before `value` are filled, the current one is a 16dp dot.
local TickTrack = InputContainer:extend{
    count = 9,
    value = 1, -- 1-based
    width = nil,
    height = Screen:scaleBySize(38),
    on_change = nil, -- function(value)
}

function TickTrack:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.inset = Screen:scaleBySize(6) + Screen:scaleBySize(8) -- track padding + half the current dot
    self.ges_events = tapEvents(self.dimen)
end

function TickTrack:tickX(i)
    if self.count < 2 then return math.floor(self.width / 2) end
    return self.inset + math.floor((self.width - 2 * self.inset) * (i - 1) / (self.count - 1) + 0.5)
end

function TickTrack:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local mid = y + math.floor(self.height / 2)
    local line = Size.border.button
    bb:paintRect(x + Screen:scaleBySize(6), mid - math.floor(line / 2), self.width - 2 * Screen:scaleBySize(6), line, Palette.ink)
    local dot = Screen:scaleBySize(3.5)
    local current = Screen:scaleBySize(8)
    for i = 1, self.count do
        local cx = x + self:tickX(i)
        if i == self.value then
            bb:paintCircle(cx, mid, current, Palette.ink)
        else
            bb:paintCircle(cx, mid, dot, Palette.ink)
            if i > self.value then
                bb:paintCircle(cx, mid, dot - line, Palette.paper)
            end
        end
    end
end

function TickTrack:onTapSelect(_, ges)
    local best, best_d
    for i = 1, self.count do
        local d = math.abs(ges.pos.x - (self.dimen.x + self:tickX(i)))
        if not best_d or d < best_d then best, best_d = i, d end
    end
    if best ~= self.value and self.on_change then
        self.on_change(best)
    end
    return true
end

--- Stepper: minus pill, tick track, plus pill (44 × 38dp buttons, 8dp gaps).
local TickStepper = HorizontalGroup:extend{
    count = 9,
    value = 1,
    width = nil,
    on_change = nil, -- function(value)
    minus_icon = "eink/minus",
    plus_icon = "eink/plus",
}

function TickStepper:init()
    local bw, bh, gap = Screen:scaleBySize(44), Screen:scaleBySize(38), Screen:scaleBySize(8)
    local set = function(v) if self.on_change then self.on_change(v) end end
    self[1] = PillButton:new{
        icon = self.minus_icon, width = bw, height = bh, enabled = self.value > 1,
        callback = function() set(self.value - 1) end,
    }
    self[2] = HorizontalSpan:new{ width = gap }
    self[3] = TickTrack:new{
        count = self.count, value = self.value, width = self.width - 2 * (bw + gap), height = bh, on_change = set,
    }
    self[4] = HorizontalSpan:new{ width = gap }
    self[5] = PillButton:new{
        icon = self.plus_icon, width = bw, height = bh, enabled = self.value < self.count,
        callback = function() set(self.value + 1) end,
    }
end

--- Toggle: 42 × 26dp pill. Off: ink outline and ink knob. On: ink fill and paper knob.
local Toggle = InputContainer:extend{
    checked = false,
    callback = nil, -- function(new_checked)
    enabled = true,
}

function Toggle:init()
    self.dimen = Geom:new{ w = Screen:scaleBySize(42), h = Screen:scaleBySize(26) }
    self.ges_events = tapEvents(self.dimen)
end

function Toggle:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local w, h = self.dimen.w, self.dimen.h
    local r = math.floor(h / 2)
    local ink = self.enabled and Palette.ink or Palette.ink_3
    if self.checked then
        bb:paintRoundedRect(x, y, w, h, ink, r)
    else
        bb:paintRoundedRect(x, y, w, h, Palette.paper, r)
        bb:paintBorder(x, y, w, h, Size.border.button, ink, r, true)
    end
    local knob = Screen:scaleBySize(8)
    local inset = Screen:scaleBySize(4) + knob
    local cx = self.checked and x + w - inset or x + inset
    bb:paintCircle(cx, y + r, knob, self.checked and Palette.paper or ink)
end

function Toggle:onTapSelect()
    if not self.enabled then return true end
    self.checked = not self.checked
    if self.callback then
        self.callback(self.checked)
    end
    return true
end

return {
    PillButton = PillButton,
    TickTrack = TickTrack,
    TickStepper = TickStepper,
    Toggle = Toggle,
}
