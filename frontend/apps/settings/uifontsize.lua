--[[--
The interface font size page of the e-ink redesign (see DESIGN.md, Typography; WeChat Read's
13-reading-preferences/03-interface-font-size.png), opened from the settings' row.

Five sizes, 小 / 默认 / 大 / 较大 / 特大, multiply the ui_* font roles by 0.9 / 1 / 1.1 / 1.2 / 1.35
(Font:setUIScale). The book's text, its pages and the DPI stay as they are.

A full-screen page (ui/widget/fullscreenpage): the title band, a heading and a note that the book's
text is sized in the reader, then near the bottom the size track between − and + circle buttons,
with the current size's name above its knob. A tap on the track picks the nearest size; − and + step
one size, and are gray at the ends. A change applies at once: the page is rebuilt with the new faces
and repainted above its bottom bar with "ui". Closing the page after a change sends "UIFontScaleChanged"
to every window, so the settings and the shelf under the page are rebuilt with the new faces before
they show again.
]]

local Event = require("ui/event")
local Font = require("ui/font")
local FullscreenPage = require("ui/widget/fullscreenpage")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Palette = require("ui/palette")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local _ = require("gettext")
local C_ = _.pgettext

local function dp(n) return Screen:scaleBySize(n) end

local GUTTER = dp(22)
local BUTTON = dp(33) -- the − and + circles
local TRACK_H = dp(33)
local KNOB = dp(31)
local GAP = dp(8) -- between a circle and the track
local TOUCH = dp(44)
local TRACK_Y = dp(42) -- the track's center, above the bottom bar
local LABEL_Y = dp(35) -- the size's name's center, above the track's center

local SCALES = { 0.9, 1, 1.1, 1.2, 1.35 }

local function sizeNames()
    return {
        C_("Interface font size", "Small"),
        _("Default"),
        C_("Interface font size", "Large"),
        C_("Interface font size", "Larger"),
        C_("Interface font size", "Largest"),
    }
end

--- The index (1 to `count`) whose `distance(i)` is the smallest.
local function nearest(count, distance)
    local best, best_d
    for i = 1, count do
        local d = distance(i)
        if not best_d or d < best_d then best, best_d = i, d end
    end
    return best
end

--- The step (1 to 5) nearest to the current scale.
local function currentStep()
    local scale = Font:getUIScale()
    return nearest(#SCALES, function(i) return math.abs(SCALES[i] - scale) end)
end

-- The size track with its − and + buttons, across `width` (gutters included); the track's center is
-- TRACK_Y above its bottom. The circles and the track take taps over at least 44dp.
local SizeControl = InputContainer:extend{
    width = nil,
    step = 1, -- 1-based
    names = nil, -- the steps' names
    on_change = nil, -- function(new_step)
}

function SizeControl:init()
    local count = #self.names
    self.minus_enabled, self.plus_enabled = self.step > 1, self.step < count
    local icon = dp(20)
    self.minus_icon = IconWidget:new{ icon = "eink/minus", width = icon, height = icon, alpha = true,
        dim = not self.minus_enabled or nil }
    self.plus_icon = IconWidget:new{ icon = "eink/plus", width = icon, height = icon, alpha = true,
        dim = not self.plus_enabled or nil }
    self.track_x = GUTTER + BUTTON + GAP
    self.track_w = self.width - 2 * self.track_x
    self.knob_x = self:stepX(self.step)
    -- the track's ends read 小 and 大, as in the reference, whatever the last step is called
    local function endLabel(text, step)
        local on_ink = self:stepX(step) < self.knob_x
        return TextWidget:new{ text = text, face = Font:getFace("ui_caption"), bold = true,
            fgcolor = on_ink and Palette.paper or Palette.ink, padding = 0 }
    end
    self.small_label = endLabel(C_("Interface font size", "Small"), 1)
    self.large_label = endLabel(C_("Interface font size", "Large"), count)
    self.name_label = TextWidget:new{ text = self.names[self.step], face = Font:getFace("ui_caption"), bold = true,
        fgcolor = Palette.ink, max_width = self.width - 2 * GUTTER, padding = 0 }
    local name_h = self.name_label:getSize().h
    self.dimen = Geom:new{ w = self.width, h = TRACK_Y + LABEL_Y + math.ceil(name_h / 2) }
    self.minus_rect = Geom:new{ w = TOUCH, h = TOUCH }
    self.plus_rect = Geom:new{ w = TOUCH, h = TOUCH }
    self.track_rect = Geom:new{ w = self.track_w, h = TOUCH }
    self.ges_events = {
        TapMinus = { GestureRange:new{ ges = "tap", range = self.minus_rect } },
        TapPlus = { GestureRange:new{ ges = "tap", range = self.plus_rect } },
        TapTrack = { GestureRange:new{ ges = "tap", range = self.track_rect } },
    }
end

--- The x of step `i`'s knob center, from the control's left edge; the knob stays inside the track.
function SizeControl:stepX(i)
    local r = math.floor(TRACK_H / 2)
    local count = #self.names
    return self.track_x + r + math.floor((self.track_w - 2 * r) * (i - 1) / (count - 1) + 0.5)
end

function SizeControl:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local cy = y + self.dimen.h - TRACK_Y
    local anti_alias = G_reader_settings:nilOrTrue("anti_alias_ui")
    local bw = Size.border.default
    local function circle(cx, enabled, icon, rect)
        local r = math.floor(BUTTON / 2)
        bb:paintBorder(cx - r, cy - r, BUTTON, BUTTON, bw, enabled and Palette.ink or Palette.rule, r, anti_alias)
        local icon_size = icon:getSize()
        icon:paintTo(bb, cx - math.floor(icon_size.w / 2), cy - math.floor(icon_size.h / 2))
        rect.x, rect.y = cx - math.floor(TOUCH / 2), cy - math.floor(TOUCH / 2)
    end
    circle(x + GUTTER + math.floor(BUTTON / 2), self.minus_enabled, self.minus_icon, self.minus_rect)
    circle(x + self.width - GUTTER - math.floor(BUTTON / 2), self.plus_enabled, self.plus_icon, self.plus_rect)
    -- the track: gray, ink from its round left end to the knob's center (none on the first step)
    local r = math.floor(TRACK_H / 2)
    local tx, ty, kx = x + self.track_x, cy - r, x + self.knob_x
    bb:paintRoundedRect(tx, ty, self.track_w, TRACK_H, Palette.mark, r)
    if self.step > 1 then
        bb:paintCircle(tx + r, ty + r, r, Palette.ink)
        bb:paintRect(tx + r, ty, kx - tx - r, TRACK_H, Palette.ink)
    end
    self.track_rect.x, self.track_rect.y = tx, cy - math.floor(TOUCH / 2)
    -- the end labels on the first and last steps, inside the track
    local inset = dp(8)
    for _, end_label in ipairs{ { self.small_label, 1 }, { self.large_label, #self.names } } do
        local label = end_label[1]
        local label_size = label:getSize()
        local lx = x + self:stepX(end_label[2]) - math.floor(label_size.w / 2)
        lx = math.max(tx + inset, math.min(lx, tx + self.track_w - inset - label_size.w))
        label:paintTo(bb, lx, cy - math.floor(label_size.h / 2))
    end
    -- the knob: a paper disc with an ink ring, 1.5dp as in the reference
    local knob_r = math.floor(KNOB / 2)
    bb:paintCircle(kx, cy, knob_r, Palette.ink)
    bb:paintCircle(kx, cy, knob_r - Size.border.button, Palette.paper)
    -- the step's name above the knob, kept inside the gutters
    local name_size = self.name_label:getSize()
    local nx = math.max(x + GUTTER, math.min(kx - math.floor(name_size.w / 2), x + self.width - GUTTER - name_size.w))
    self.name_label:paintTo(bb, nx, cy - LABEL_Y - math.floor(name_size.h / 2))
end

function SizeControl:change(step)
    if step ~= self.step and step >= 1 and step <= #self.names and self.on_change then
        self.on_change(step)
    end
end

function SizeControl:onTapMinus()
    self:change(self.step - 1)
    return true
end

function SizeControl:onTapPlus()
    self:change(self.step + 1)
    return true
end

function SizeControl:onTapTrack(_, ges)
    self:change(nearest(#self.names, function(i) return math.abs(ges.pos.x - (self.dimen.x + self:stepX(i))) end))
    return true
end

-- The icons and labels are painted by hand, not children: free them on rebuild and on close.
function SizeControl:free()
    for _, w in ipairs{ self.minus_icon, self.plus_icon, self.small_label, self.large_label, self.name_label } do
        w:free()
    end
end

SizeControl.onCloseWidget = SizeControl.free

local UIFontSize = FullscreenPage:extend{}

--- The current step's name, for the settings' row.
function UIFontSize.currentName()
    return sizeNames()[currentStep()]
end

function UIFontSize.show()
    local page = UIFontSize:new{}
    UIManager:show(page, "ui", page.dimen)
    return page
end

function UIFontSize:init()
    self.title = _("Interface font size")
    FullscreenPage.init(self)
    self.opened_scale = Font:getUIScale()
    -- what a change repaints: everything above the bottom bar, whose arrow and capsule have no text
    self.change_rect = Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.content_rect.y + self.content_rect.h }
    self:build()
end

function UIFontSize:buildContent(rect)
    local w = rect.w - 2 * GUTTER
    local function indented(widget)
        return HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, widget }
    end
    local intro = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = dp(8) },
        indented(TextBoxWidget:new{ text = _("Tap the slider to set the interface font size"),
            face = Font:getFace("ui_title"), bold = true, width = w }),
        indented(TextBoxWidget:new{ text = _("The size of a book's text is set in the reader, and this setting does not change it."),
            face = Font:getFace("ui_label"), width = w }),
    }
    self.control = SizeControl:new{
        width = rect.w,
        step = currentStep(),
        names = sizeNames(),
        on_change = function(step) self:setStep(step) end,
    }
    local free_h = rect.h - intro:getSize().h - self.control:getSize().h
    return VerticalGroup:new{
        align = "left",
        intro,
        VerticalSpan:new{ width = math.max(0, free_h) },
        self.control,
    }, 1
end

function UIFontSize:setStep(step)
    Font:setUIScale(SCALES[step])
    self:build()
    UIManager:setDirty(self, "ui", self.change_rect)
end

--- However the page closes, after a change the windows under it rebuild with the new faces before they are
-- repainted.
function UIFontSize:onCloseWidget()
    if Font:getUIScale() ~= self.opened_scale then
        self.opened_scale = Font:getUIScale()
        UIManager:broadcastEvent(Event:new("UIFontScaleChanged"))
    end
end

return UIFontSize
