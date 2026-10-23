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
local RightContainer = require("ui/widget/container/rightcontainer")
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

-- Keep the reference's small capsules, with at least a 44dp touch target around them.
local QuickButton = EinkControls.PillButton:extend{}

function QuickButton:init()
    EinkControls.PillButton.init(self)
    self.touch_dimen = Geom:new{
        w = math.max(self.dimen.w, Screen:scaleBySize(44)),
        h = math.max(self.dimen.h, Screen:scaleBySize(44)),
    }
    self.ges_events.TapSelect[1].range = self.touch_dimen
end

function QuickButton:paintTo(bb, x, y)
    self.touch_dimen.x = x - math.floor((self.touch_dimen.w - self.dimen.w) / 2)
    self.touch_dimen.y = y - math.floor((self.touch_dimen.h - self.dimen.h) / 2)
    InputContainer.paintTo(self, bb, x, y)
end

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
    self.touch_dimen = self.dimen:copy()
    self.touch_dimen.h = Screen:scaleBySize(44)
    self.touch_dimen.y = self.dimen.y - math.floor((self.touch_dimen.h - h) / 2)
    local border = Size.border.default
    self[1] = FrameContainer:new{
        bordersize = border, color = Palette.rule, background = Palette.paper,
        radius = math.floor(h / 2), padding = 0,
        CenterContainer:new{ dimen = Geom:new{ w = w - 2 * border, h = h - 2 * border }, label },
    }
end

function Pill:paintTo(bb, x, y)
    if not self.autoturn:isActive() or self.autoturn.suspended then return end
    self[1]:paintTo(bb, x + self.dimen.x, y + self.dimen.y)
end

------------------------------------------------------------------------

local Guide = InputContainer:extend{ autoturn = nil }

function Guide:reset()
    self.lines = {}
    self.needs_baselines = true
    local ui = self.autoturn.ui
    local text = ui.document:getTextFromPositions({ x = 0, y = 0 }, { x = Screen:getWidth(), y = Screen:getHeight() }, true)
    local column_w = Screen:getWidth() / ui.document:getVisiblePageCount()
    for _, box in ipairs(text and text.sboxes or {}) do
        -- Superscripts and inline images can give one visual line different segment heights.
        local column = math.floor(box.x / column_w)
        local last = self.lines[#self.lines]
        local bottom = box.y + box.h
        local overlap = last and math.min(last.bottom, bottom) - math.max(last.top, box.y) or 0
        if last and last.column == column and overlap > math.min(last.bottom - last.top, box.h) / 2 then
            local right = math.max(last.rect.x + last.rect.w, box.x + box.w)
            last.rect.x = math.min(last.rect.x, box.x)
            last.rect.w = right - last.rect.x
            last.top = math.min(last.top, box.y)
            last.bottom = math.max(last.bottom, bottom)
            table.insert(last.segments, box)
        else
            table.insert(self.lines, { top = box.y, bottom = bottom, column = column, segments = { box }, rect = Geom:new{
                x = box.x, y = box.y + box.h - 1, w = box.w, h = Size.border.default,
            } })
        end
    end
    for i = #self.lines, 1, -1 do
        if self.lines[i].top < 0 or self.lines[i].bottom > Screen:getHeight() then
            table.remove(self.lines, i)
        end
    end
end

function Guide:setLine(index)
    local rect = index and self.lines[index] and self.lines[index].rect
    if rect == self.rect then return end
    local old = self.rect
    self.rect = rect
    -- Restore the old strip from the reader, then draw only the new strip.
    if old then UIManager:setDirty(self.autoturn.ui.view.dialog, "fast", old) end
    if rect then
        UIManager:setDirty(self.autoturn.ui.view.dialog, function() return "fast", rect end)
    end
end

function Guide:paintTo(bb, x, y)
    if self.rect then
        if self.needs_baselines then
            local view = self.autoturn.ui.view
            for _, line in ipairs(self.lines) do
                local saved_y
                for _, box in ipairs(line.segments) do
                    local top = view.highlight.line_tops and view.highlight.line_tops[box.y .. ":" .. box.h]
                    if top then saved_y = math.max(saved_y or top, top) end
                end
                -- Saved underlines are already painted here; only measure lines without them.
                line.rect.y = saved_y or view:underlineY(bb, {{
                    x = line.rect.x, y = line.top, w = line.rect.w, h = line.bottom - line.top,
                }})
                line.rect.y = math.min(line.rect.y, Screen:getHeight() - line.rect.h)
            end
            self.needs_baselines = false
        end
        bb:paintRect(x + self.rect.x, y + self.rect.y, self.rect.w, self.rect.h, Palette.ink)
    end
end

------------------------------------------------------------------------

-- DECISIONS F03: fixed seconds per page, not scrolling distance.
local speeds = {
    { rate = 1, seconds = 60 }, { rate = 1.5, seconds = 40 }, { rate = 2, seconds = 30 },
    { rate = 3, seconds = 20 }, { rate = 4, seconds = 15 },
}
local SpeedScale = InputContainer:extend{ autoturn = nil, width = nil, on_change = nil }

function SpeedScale:init()
    self.dimen = Geom:new{ w = self.width, h = Screen:scaleBySize(50) }
    -- Leave room for the end captions on narrow screens too.
    self.inset = math.min(Screen:scaleBySize(120), math.floor(self.width / 5))
    self.ges_events = { TapSpeed = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    local diameter = math.floor(Screen:scaleBySize(34) * Font:getUIScale())
    for i, speed in ipairs(speeds) do
        self[i] = QuickButton:new{
            text = string.format("%.1f", speed.rate), face = Font:getFace("ui_body", 16),
            width = diameter, height = diameter, bordersize = 0,
            callback = function() self:select(i) end,
        }
    end
    self[6] = TextWidget:new{ text = _.pgettext("Autoturn speed", "Slow"), face = Font:getFace("ui_label"), fgcolor = Palette.ink }
    self[7] = TextWidget:new{ text = _.pgettext("Autoturn speed", "Fast"), face = Font:getFace("ui_label"), fgcolor = Palette.ink }
end

function SpeedScale:speedX(i)
    return self.inset + (speeds[i].rate - 1) / 3 * (self.width - 2 * self.inset)
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
        if i <= 5 and self.autoturn.autoturn_sec == speeds[i].seconds and self.autoturn.autoturn_distance == 1 then
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
    self.autoturn:setInterval(speeds[i].seconds, 1, true)
    self.on_change()
end

------------------------------------------------------------------------

local GuideToggle = InputContainer:extend{ autoturn = nil, width = nil }

function GuideToggle:init()
    local label = TextWidget:new{
        text = _("Reading guide"), face = Font:getFace("ui_label"), fgcolor = Palette.ink, max_width = self.width,
    }
    self.toggle = EinkControls.Toggle:new{
        checked = self.autoturn.guide_enabled, width = Screen:scaleBySize(34), height = Screen:scaleBySize(17),
        callback = function(checked)
            self.autoturn.guide_enabled = checked
            G_reader_settings:saveSetting("autoturn_reading_guide", checked)
            self.autoturn:_resetGuide()
            UIManager:setDirty(self.autoturn.settings, "fast", self.touch_dimen)
        end,
    }
    self.dimen = Geom:new{ w = label:getSize().w + Screen:scaleBySize(42), h = Screen:scaleBySize(35) }
    self[1] = CenterContainer:new{
        dimen = self.dimen:copy(),
        HorizontalGroup:new{ label, HorizontalSpan:new{ width = Screen:scaleBySize(8) }, self.toggle },
    }
    self.touch_dimen = Geom:new{ w = self.dimen.w, h = Screen:scaleBySize(44) }
    self.ges_events = { TapGuide = { GestureRange:new{ ges = "tap", range = self.touch_dimen } } }
end

function GuideToggle:paintTo(bb, x, y)
    self.touch_dimen.x = x
    self.touch_dimen.y = y - math.floor((self.touch_dimen.h - self.dimen.h) / 2)
    InputContainer.paintTo(self, bb, x, y)
end

function GuideToggle:onTapGuide()
    return self.toggle:onTapSelect()
end

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
    header_content.dimen = Geom:new{ w = w, h = row_h }
    if autoturn.ui.rolling then
        header_content[#header_content + 1] = RightContainer:new{
            dimen = Geom:new{ w = w, h = row_h },
            GuideToggle:new{
                autoturn = autoturn,
                width = math.max(0, math.floor((w - title:getSize().w) / 2) - Screen:scaleBySize(50)),
            },
        }
    end
    local header = OverlapGroup:new(header_content)
    local panel = Panel:new{
        content = VerticalGroup:new{
            header,
            VerticalSpan:new{ width = Screen:scaleBySize(5) },
            SpeedScale:new{ autoturn = autoturn, width = w, on_change = function()
                UIManager:setDirty(self, "ui", self.panel:getRefreshRegion())
            end },
            VerticalSpan:new{ width = Screen:scaleBySize(13) },
            QuickButton:new{
                text = _("Stop autoturn"), width = w, height = Screen:scaleBySize(35), bordersize = Size.border.default,
                face = Font:getFace("ui_label"), callback = function() autoturn:stop(); self:close() end,
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
    self.autoturn:_resetGuide() -- CloseWidget runs before the settings leave the window stack.
end

Settings.onClose = Settings.close

function Settings:onCloseWidget()
    self.autoturn.settings = nil
    self:free()
    self.autoturn:_start(true)
end

return { Button = QuickButton, Pill = Pill, Settings = Settings, Guide = Guide }
