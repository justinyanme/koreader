-- Autoturn's running pill and quick settings (03-progress/02 and 03 in the Leaf5 references).
local CenterContainer = require("ui/widget/container/centercontainer")
local EinkControls = require("ui/widget/einkcontrols")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Palette = require("ui/palette")
local Panel = require("ui/widget/panel")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local _ = require("gettext")

local Pill = InputContainer:extend{ autoturn = nil, paints_over_footer = true }

function Pill:init()
    local icon = Screen:scaleBySize(16)
    local label = HorizontalGroup:new{
        IconWidget:new{ icon = "eink/autoturn", width = icon, height = icon, alpha = true },
        HorizontalSpan:new{ width = Screen:scaleBySize(5) },
        TextWidget:new{
            text = _("Autoturn settings"), face = Font:getFace("ui_label"), fgcolor = Palette.ink,
            max_width = Screen:getWidth() - Screen:scaleBySize(77) - icon,
        },
    }
    local h = Screen:scaleBySize(35)
    local w = math.min(Screen:getWidth() - Screen:scaleBySize(44), label:getSize().w + Screen:scaleBySize(28))
    self.dimen = Geom:new{ x = Screen:scaleBySize(27), y = Screen:getHeight() - Screen:scaleBySize(56), w = w, h = h }
    local border = Size.border.default
    self[1] = FrameContainer:new{
        bordersize = border, color = Palette.confirm_rule, background = Palette.paper,
        radius = math.floor(h / 2), padding = 0,
        CenterContainer:new{ dimen = Geom:new{ w = w - 2 * border, h = h - 2 * border }, label },
    }
end

function Pill:paintTo(bb, x, y)
    if not self.autoturn:_enabled() or self.autoturn.suspended then return end
    self[1]:paintTo(bb, x + self.dimen.x, y + self.dimen.y)
end

------------------------------------------------------------------------

local speeds = { 1, 1.5, 2, 3, 4 }
local seconds = { 60, 40, 30, 20, 15 } -- DECISIONS F03: fixed seconds per page, not scrolling distance
local SpeedScale = InputContainer:extend{ autoturn = nil, width = nil, on_change = nil }

function SpeedScale:init()
    self.dimen = Geom:new{ w = self.width, h = Screen:scaleBySize(50) }
    self.inset = Screen:scaleBySize(120)
    -- Leave room for the end captions on narrow screens too.
    self.inset = math.min(self.inset, math.floor(self.width / 5))
    self.ges_events = { TapSpeed = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    local diameter = math.floor(Screen:scaleBySize(34) * Font:getUIScale())
    for i, speed in ipairs(speeds) do
        self[i] = EinkControls.PillButton:new{
            text = string.format("%.1f", speed), face = Font:getFace("ui_body", 16),
            width = diameter, height = diameter, bordersize = 0,
            callback = function() self:select(i) end,
        }
    end
    self[6] = TextWidget:new{ text = _.pgettext("Autoturn speed", "Slow"), face = Font:getFace("ui_label"), fgcolor = Palette.ink }
    self[7] = TextWidget:new{ text = _.pgettext("Autoturn speed", "Fast"), face = Font:getFace("ui_label"), fgcolor = Palette.ink }
end

function SpeedScale:speedX(i)
    return self.inset + (speeds[i] - 1) / 3 * (self.width - 2 * self.inset)
end

function SpeedScale:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local mid = y + math.floor(self.dimen.h / 2)
    local radius = math.floor(self[1].dimen.w / 2)
    for tick = 0, 20 do
        local tx = Screen:scaleBySize(48) + tick / 20 * (self.width - Screen:scaleBySize(96))
        local near_label = false
        for i = 1, #speeds do
            if math.abs(tx - self:speedX(i)) < radius + Screen:scaleBySize(5) then near_label = true end
        end
        if not near_label then
            bb:paintRect(x + math.floor(tx), mid - Screen:scaleBySize(4), Size.border.default, Screen:scaleBySize(8), Palette.ink_3)
        end
    end
    for i, label in ipairs(self) do
        local size = label:getSize()
        local cx = i <= 5 and self:speedX(i) or i == 6 and size.w / 2 or self.width - size.w / 2
        label:paintTo(bb, x + math.floor(cx - size.w / 2), mid - math.floor(size.h / 2))
        if i <= 5 and self.autoturn.autoturn_sec == seconds[i] and self.autoturn.autoturn_distance == 1 then
            bb:paintBorder(x + math.floor(cx) - radius, mid - radius, 2 * radius, 2 * radius,
                Size.border.button, Palette.ink, radius, true)
        end
    end
end

function SpeedScale:onTapSpeed(_, ges)
    local closest, distance = 1, math.huge
    for i = 1, #speeds do
        local d = math.abs(ges.pos.x - self.dimen.x - self:speedX(i))
        if d < distance then closest, distance = i, d end
    end
    self:select(closest)
    return true
end

function SpeedScale:select(i)
    self.autoturn:setInterval(seconds[i], 1, true)
    self.on_change()
end

------------------------------------------------------------------------

local Settings = InputContainer:extend{ autoturn = nil }

function Settings:init()
    local autoturn = self.autoturn
    local w = Panel.getContentWidth()
    local row_h = Screen:scaleBySize(35)
    local fold = IconButton:new{
        icon = "eink/chev.up", icon_rotation_angle = 180,
        width = Screen:scaleBySize(20), height = Screen:scaleBySize(20), padding = Screen:scaleBySize(12),
        allow_flash = false, callback = function() self:close() end,
    }
    local title = TextWidget:new{ text = _("Automatic reading"), face = Font:getFace("ui_label"), bold = true, fgcolor = Palette.ink }
    local header_content = {
        CenterContainer:new{
            dimen = Geom:new{ w = w, h = row_h },
            title,
        },
        fold,
    }
    local header_h = row_h
    if self.autoturn.ui.rolling then
        local guide = HorizontalGroup:new{
            TextWidget:new{ text = _("Reading guide"), face = Font:getFace("ui_label"), fgcolor = Palette.ink_3 },
            HorizontalSpan:new{ width = Screen:scaleBySize(8) },
            -- shortcut: guide rendering belongs to #69; keep this switch disabled until that behavior exists.
            EinkControls.Toggle:new{ enabled = false, width = Screen:scaleBySize(34), height = Screen:scaleBySize(17) },
        }
        local guide_size = guide:getSize()
        local below = 2 * (guide_size.w + Screen:scaleBySize(8)) + title:getSize().w > w
        guide.overlap_offset = { w - guide_size.w, below and row_h or math.floor((row_h - guide_size.h) / 2) }
        if below then header_h = row_h + guide_size.h end
        table.insert(header_content, guide)
    end
    header_content.dimen = Geom:new{ w = w, h = header_h }
    local header = OverlapGroup:new(header_content)
    local panel = Panel:new{
        content = VerticalGroup:new{
            header,
            VerticalSpan:new{ width = Screen:scaleBySize(5) },
            SpeedScale:new{ autoturn = autoturn, width = w, on_change = function()
                UIManager:setDirty(self, "ui", self.panel:getRefreshRegion())
            end },
            VerticalSpan:new{ width = Screen:scaleBySize(13) },
            EinkControls.PillButton:new{
                text = _("Stop autoturn"), width = w, height = Screen:scaleBySize(35), bordersize = Size.border.default,
                face = Font:getFace("ui_label"), callback = function() self:close(); autoturn:stop() end,
            },
        },
        bottom_y = Screen:getHeight(), show_parent = self,
    }
    -- The standalone settings band leaves more space below its stop button than toolbar panels do.
    panel[1].padding_top = Screen:scaleBySize(12)
    panel[1].padding_bottom = Screen:scaleBySize(40)
    panel.dimen.h = panel.rule + panel[1]:getSize().h
    self.panel, self[1] = panel, panel
    self.dimen = Screen:getSize()
    self.ges_events = { TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    if require("device"):hasKeys() then
        self.key_events.Close = { { require("device").input.group.Back } }
    end
end

function Settings:paintTo(bb, x, y)
    self.panel:paintTo(bb, x, y + self.panel:getRefreshRegion().y)
end

function Settings:onTapOutside(_, ges)
    if not self.panel:getRefreshRegion():contains(ges.pos) then self:close() end
    return true
end

function Settings:close()
    UIManager:close(self, "ui", self.panel:getRefreshRegion())
end

Settings.onClose = Settings.close

function Settings:onCloseWidget()
    self.autoturn.settings = nil
    self:free()
end

return { Pill = Pill, Settings = Settings }
