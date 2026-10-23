--[[--
The interface font size page of the e-ink redesign (see DESIGN.md, Typography; WeChat Read's
13-reading-preferences/03-interface-font-size.png), opened from the settings' row.

Five sizes, 小 / 默认 / 大 / 较大 / 特大, multiply the ui_* font roles by 0.9 / 1 / 1.1 / 1.2 / 1.35
(Font:setUIScale). The book's text, its pages and the DPI stay as they are.

A full-screen page (ui/widget/fullscreenpage): the title band, a heading and a note that the book's
text is sized in the reader, then near the bottom the size track (EinkControls.Track, as on the
typeset panel, without step marks) between − and + circle buttons, with the current size's name above
its knob. A tap on the track picks the nearest size; − and + step
one size, and are gray at the ends. A change applies at once: the page is rebuilt with the new faces
and repainted above its bottom bar with "ui". Closing the page after a change sends "UIFontScaleChanged"
to every window, so the settings and the shelf under the page are rebuilt with the new faces before
they show again.
]]

local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local FullscreenPage = require("ui/widget/fullscreenpage")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local _ = require("gettext")
local C_ = _.pgettext

local function dp(n) return Screen:scaleBySize(n) end

local GUTTER = dp(22)
local TRACK_Y = dp(42) -- the track's center, above the bottom bar

local SCALES = Font.ui_scales

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
    -- the size track, its name above the knob; as in the reference, the knob runs to the track's ends and covers
    -- 小 or 大 there, and the track has no ticks
    local step = currentStep()
    self.control = EinkControls.Track:new{
        width = w,
        count = #SCALES,
        position = step,
        caption = sizeNames()[step],
        low = C_("Interface font size", "Small"),
        high = C_("Interface font size", "Large"),
        ticks = false,
        clear_ends = false,
        on_change = function(i) self:setStep(i) end,
        on_step = function(direction) self:setStep(step + direction) end,
    }
    local below = VerticalSpan:new{ width = TRACK_Y - math.floor(EinkControls.Track.height / 2) }
    local free_h = rect.h - intro:getSize().h - self.control:getSize().h - below:getSize().h
    return VerticalGroup:new{
        align = "left",
        intro,
        VerticalSpan:new{ width = math.max(0, free_h) },
        indented(self.control),
        below,
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
