--[[--
"More" panel of the e-ink redesign (see DESIGN.md, Panels), opened from the
reader toolbar's top bar: book information, tap zones, note export, reading
statistics and the reorganized settings. Also holds the tap zone overlay,
which the settings preview too (apps/settings/einksettings).

Each entry closes the toolbar and its panel ("ui" on their rects) before
opening its target.

@usage
    toolbar:showPanel("more", ReaderMorePanel:new{ toolbar = toolbar })
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Palette = require("ui/palette")
local Panel = require("ui/widget/panel")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")
local C_ = _.pgettext

local function text(str, face, color, max_width)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width }
end

local Tile = InputContainer:extend{
    icon = nil,
    label = nil,
    width = nil,
    enabled = true,
    callback = nil,
}

function Tile:init()
    local h = Screen:scaleBySize(84)
    local bw = Size.border.default
    local icon_size = Screen:scaleBySize(24)
    self.dimen = Geom:new{ w = self.width, h = h }
    local icon = IconWidget:new{ icon = self.icon, width = icon_size, height = icon_size, alpha = true }
    icon.dim = not self.enabled or nil
    self[1] = FrameContainer:new{
        bordersize = bw, padding = 0, radius = Screen:scaleBySize(12),
        color = Palette.rule, background = Palette.paper,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width - 2 * bw, h = h - 2 * bw },
            VerticalGroup:new{
                icon,
                VerticalSpan:new{ width = Screen:scaleBySize(8) },
                text(self.label, "ui_label", self.enabled and Palette.ink or Palette.ink_3, self.width - 2 * bw),
            },
        },
    }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function Tile:onTapSelect()
    if self.enabled then
        self.callback()
    end
    return true
end

-- Tap zone overlay: draws ReaderToolbar:getTapLayout(), a tap anywhere closes it.
local TapZones = InputContainer:extend{
    layout = nil,
}

function TapZones:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local margin = Screen:scaleBySize(6)
    local bw = Size.border.thick
    local names = {
        backward = C_("Tap zones", "Previous page"),
        forward = C_("Tap zones", "Next page"),
        toolbar = C_("Tap zones", "Toolbar"),
        none = _("Page turn taps off"),
    }
    local thirds_hints = { _("Tap the left third"), _("Tap the middle"), _("Tap the right third") }
    self.zones = {}
    -- drawn in reverse so that the zone that wins a tap is on top
    for i = #self.layout, 1, -1 do
        local z = self.layout[i]
        local x, y = math.floor(z[1] * sw), math.floor(z[2] * sh)
        local w, h = math.floor(z[3] * sw), math.floor(z[4] * sh)
        local hint
        if math.abs(z[3] - 1/3) < 0.01 and z[4] == 1 then
            hint = thirds_hints[math.floor(z[1] * 3 + 0.5) + 1]
        end
        local inner = Geom:new{ w = w - 2 * (margin + bw), h = h - 2 * (margin + bw) }
        local label = VerticalGroup:new{ text(names[z[5]], "ui_title", Palette.ink, inner.w) }
        if hint then
            table.insert(label, VerticalSpan:new{ width = Screen:scaleBySize(4) })
            table.insert(label, text(hint, "ui_caption", Palette.ink_2, inner.w))
        end
        table.insert(self.zones, { x = x, y = y, widget = FrameContainer:new{
            margin = margin, padding = 0, bordersize = bw, radius = Screen:scaleBySize(8),
            color = Palette.ink, background = Palette.paper,
            CenterContainer:new{ dimen = inner, label },
        } })
    end
    self.ges_events.TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.TapClose = { { Device.input.group.Back } }
    end
end

function TapZones:paintTo(bb, x, y)
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Palette.paper)
    for _, z in ipairs(self.zones) do
        z.widget:paintTo(bb, x + z.x, y + z.y)
    end
end

function TapZones:onTapClose()
    UIManager:close(self, "ui", self.dimen)
    return true
end

local ReaderMorePanel = Panel:extend{
    toolbar = nil, -- ReaderToolbar
}

ReaderMorePanel.TapZones = TapZones

function ReaderMorePanel:init()
    self.content = self:buildContent()
    Panel.init(self)
end

function ReaderMorePanel:buildContent()
    local toolbar = self.toolbar
    local ui = toolbar.ui
    local w = Panel.getContentWidth()
    local gap = Screen:scaleBySize(8)
    local tile_w = math.floor((w - 2 * gap) / 3)
    local function go(fn)
        return function()
            toolbar:hideToolbar()
            fn()
        end
    end
    local tiles = {
        { "eink/info", _("Book information"), true, function() ui.bookinfo:onShowBookInfo() end },
        { "eink/zones", _("Tap zones"), Device:isTouchDevice(), function()
            local zones = TapZones:new{ layout = toolbar:getTapLayout() }
            UIManager:show(zones, "ui", zones.dimen)
        end },
        { "eink/export", _("Export notes"), ui.exporter ~= nil and ui.exporter:isReadyToExport(), function() ui.exporter:onExportCurrentNotes() end },
        { "eink/stats", _("Reading statistics"), ui.statistics ~= nil, function() ui.statistics:onShowReaderProgress() end },
        { "eink/refresh", _("Refresh and ghosting"), true, function() ui:handleEvent(Event:new("ShowEinkSettings", "refresh")) end },
        { "eink/sliders", _("All settings"), true, function() ui:handleEvent(Event:new("ShowEinkSettings")) end },
    }
    local group = VerticalGroup:new{ align = "left" }
    local row
    for i, t in ipairs(tiles) do
        if i % 3 == 1 then
            if row then
                table.insert(group, row)
                table.insert(group, VerticalSpan:new{ width = gap })
            end
            row = HorizontalGroup:new{}
        else
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
        table.insert(row, Tile:new{ icon = t[1], label = t[2], enabled = t[3], width = tile_w, callback = go(t[4]) })
    end
    table.insert(group, row)
    return group
end

return ReaderMorePanel
