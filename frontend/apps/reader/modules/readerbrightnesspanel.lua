--[[--
Brightness panel of the e-ink redesign (see DESIGN.md, Panels), opened from the
reader toolbar: frontlight, warmth, automatic warmth and night mode.

Changing a value re-renders the panel with a "ui" refresh of its own rect;
toggles refresh only themselves ("fast"), and night mode flashes the whole
screen ("full"), the only flash.

@usage
    toolbar:showPanel("brightness", ReaderBrightnessPanel:new{ toolbar = toolbar })
]]

local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local Panel = require("ui/widget/panel")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local TICKS = 9
local LABEL_W = Screen:scaleBySize(64)

local function text(str, face, color, max_width)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width }
end

local function toTick(value, min, max)
    return math.floor((value - min) / (max - min) * (TICKS - 1) + 0.5) + 1
end

local function fromTick(tick, min, max)
    return min + math.floor((tick - 1) / (TICKS - 1) * (max - min) + 0.5)
end

-- Labelled control row ("srow"): gray label column, then the control.
local function controlRow(label, control)
    return HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = LABEL_W, h = Screen:scaleBySize(52) },
            text(label, "ui_label", Palette.ink_2, LABEL_W),
        },
        control,
    }
end

local ReaderBrightnessPanel = Panel:extend{
    toolbar = nil, -- ReaderToolbar
}

function ReaderBrightnessPanel:init()
    self.content = self:buildContent()
    Panel.init(self)
end

function ReaderBrightnessPanel:refresh()
    self:setContent(self:buildContent())
end

function ReaderBrightnessPanel:toggleRow(label, checked, callback)
    local toggle = EinkControls.Toggle:new{ checked = checked }
    toggle.callback = function(v)
        UIManager:setDirty(self.show_parent, "fast", toggle.dimen)
        callback(v)
    end
    local w = Panel.getContentWidth()
    return VerticalGroup:new{
        LineWidget:new{ dimen = Geom:new{ w = w, h = Screen:scaleBySize(1) }, background = Palette.rule },
        Panel.Row:new{
            height = Screen:scaleBySize(52) - Screen:scaleBySize(1),
            label = text(label, "ui_label_large", Palette.ink, w - toggle:getSize().w),
            right = toggle,
        },
    }
end

function ReaderBrightnessPanel:buildContent()
    local ui = self.toolbar.ui
    local powerd = Device:getPowerDevice()
    local w = Panel.getContentWidth()
    local group = VerticalGroup:new{ align = "left" }
    if Device:hasFrontlight() then
        local intensity = powerd:isFrontlightOn() and powerd:frontlightIntensity() or powerd.fl_min
        table.insert(group, controlRow(T(_("Brightness %1%"), math.floor(intensity / powerd.fl_max * 100 + 0.5)),
            EinkControls.TickStepper:new{
                count = TICKS, width = w - LABEL_W,
                value = toTick(intensity, powerd.fl_min, powerd.fl_max),
                on_change = function(tick)
                    ui:handleEvent(Event:new("SetFlIntensity", fromTick(tick, powerd.fl_min, powerd.fl_max)))
                    self:refresh()
                end,
            }))
    end
    if Device:hasNaturalLight() then
        local warmth = powerd:toNativeWarmth(powerd:frontlightWarmth())
        local min, max = powerd.fl_warmth_min, powerd.fl_warmth_max
        table.insert(group, controlRow(T(_("Warmth %1"), warmth),
            EinkControls.TickStepper:new{
                count = TICKS, width = w - LABEL_W,
                value = toTick(warmth, min, max),
                on_change = function(tick)
                    ui:handleEvent(Event:new("SetFlWarmth", fromTick(tick, min, max)))
                    self:refresh()
                end,
            }))
    end
    -- Without natural light the plugin is "auto night mode" and would flip night mode on its own.
    local autowarmth = Device:hasNaturalLight() and ui.autowarmth
    if autowarmth then
        table.insert(group, self:toggleRow(_("Adjust warmth automatically by time"), autowarmth.activate ~= 0,
            function(on)
                autowarmth:onAutoWarmthMode(on and 2 or 0) -- 2: fixed schedule, needs no location
                self:refresh() -- warmth and night mode may have changed with it
            end))
    end
    table.insert(group, self:toggleRow(_("Night mode (white on black)"), G_reader_settings:isTrue("night_mode"),
        function()
            ui:handleEvent(Event:new("ToggleNightMode")) -- full refresh, the only one
        end))
    return group
end

return ReaderBrightnessPanel
