--[[--
Small controls of the e-ink redesign (see DESIGN.md, Components): a pill
button, a tick stepper, a toggle, a list pager, and the bottom bar of a full-screen page
with its page capsule. They only use @{ui.palette} colors and the ui_* font roles, and
leave refreshing to their owner.

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
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = require("device").screen
local _ = require("gettext")

local function tapEvents(dimen)
    return { TapSelect = { GestureRange:new{ ges = "tap", range = dimen } } }
end

--- Pill button: 1.5dp ink outline, or ink fill when `solid`. Shows `text` or an `icon` from resources/icons.
local PillButton = InputContainer:extend{
    text = nil,
    icon = nil,
    icon_size = Screen:scaleBySize(18),
    icon_rotation_angle = 0,
    callback = nil,
    enabled = true,
    solid = false,
    width = nil, -- defaults to the label width plus 16dp padding
    height = Screen:scaleBySize(40),
    bordersize = Size.border.button,
    face = nil, -- label face, defaults to ui_label_large
}

function PillButton:init()
    local fg = not self.enabled and Palette.ink_3 or self.solid and Palette.paper or Palette.ink
    local label
    if self.icon then
        label = IconWidget:new{
            icon = self.icon, width = self.icon_size, height = self.icon_size, alpha = true,
            rotation_angle = self.icon_rotation_angle,
        }
        if not self.enabled then label.dim = true end
    else
        label = TextWidget:new{ text = self.text, face = self.face or Font:getFace("ui_label_large"), fgcolor = fg }
    end
    local bw = self.bordersize
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
    on_step = nil, -- optional function(direction): handles the minus (-1) and plus (+1) buttons instead of on_change
    minus_icon = "eink/minus",
    plus_icon = "eink/plus",
}

function TickStepper:init()
    local bw, bh, gap = Screen:scaleBySize(44), Screen:scaleBySize(38), Screen:scaleBySize(8)
    local set = function(v) if self.on_change then self.on_change(v) end end
    local step = function(direction)
        if self.on_step then
            self.on_step(direction)
        else
            set(self.value + direction)
        end
    end
    self[1] = PillButton:new{
        icon = self.minus_icon, width = bw, height = bh, enabled = self.value > 1,
        callback = function() step(-1) end,
    }
    self[2] = HorizontalSpan:new{ width = gap }
    self[3] = TickTrack:new{
        count = self.count, value = self.value, width = self.width - 2 * (bw + gap), height = bh, on_change = set,
    }
    self[4] = HorizontalSpan:new{ width = gap }
    self[5] = PillButton:new{
        icon = self.plus_icon, width = bw, height = bh, enabled = self.value < self.count,
        callback = function() step(1) end,
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

--- Segmented control: 38dp pill with a 1.5dp ink outline, segments split by 1dp ink rules, the selected one ink-filled.
local Segmented = InputContainer:extend{
    labels = nil, -- array of strings
    value = nil, -- 1-based index of the selected segment, or nil
    width = nil,
    height = Screen:scaleBySize(38),
    on_change = nil, -- function(index)
}

function Segmented:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.seg_w = math.floor(self.width / #self.labels)
    self.texts = {}
    for i, label in ipairs(self.labels) do
        self.texts[i] = TextWidget:new{
            text = label,
            face = Font:getFace("ui_label_large"),
            fgcolor = i == self.value and Palette.paper or Palette.ink,
            max_width = self.seg_w - Screen:scaleBySize(8),
        }
    end
    self.ges_events = tapEvents(self.dimen)
end

function Segmented:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local w, h, n, seg_w = self.width, self.height, #self.labels, self.seg_w
    local r = math.floor(h / 2)
    bb:paintRoundedRect(x, y, w, h, Palette.paper, r)
    local v = self.value
    if v then
        local sx = x + (v - 1) * seg_w
        local sw = v == n and w - (v - 1) * seg_w or seg_w
        if n == 1 then
            bb:paintRoundedRect(x, y, w, h, Palette.ink, r)
        elseif v == 1 then
            -- round the outer end only: paint past the inner edge, then restore the neighbour
            bb:paintRoundedRect(sx, y, sw + r, h, Palette.ink, r)
            bb:paintRect(sx + sw, y, r, h, Palette.paper)
        elseif v == n then
            bb:paintRoundedRect(sx - r, y, sw + r, h, Palette.ink, r)
            bb:paintRect(sx - r, y, r, h, Palette.paper)
        else
            bb:paintRect(sx, y, sw, h, Palette.ink)
        end
    end
    for i = 1, n - 1 do
        bb:paintRect(x + i * seg_w, y, Size.border.default, h, Palette.ink)
    end
    bb:paintBorder(x, y, w, h, Size.border.button, Palette.ink, r, true)
    for i, t in ipairs(self.texts) do
        local size = t:getSize()
        t:paintTo(bb, x + (i - 1) * seg_w + math.floor((seg_w - size.w) / 2), y + math.floor((h - size.h) / 2))
    end
end

function Segmented:onTapSelect(_, ges)
    local i = math.min(#self.labels, math.floor((ges.pos.x - self.dimen.x) / self.seg_w) + 1)
    if i >= 1 and i ~= self.value and self.on_change then
        self.on_change(i)
    end
    return true
end

function Segmented:free()
    for _, t in ipairs(self.texts) do
        t:free()
    end
end

--- Pager band (44dp): back pill, "n / N", forward pill; 44 × 32dp pills with a 1dp border. Empty with one page.
-- `more`: the server has pages not fetched yet, so "n / …" with forward enabled; `loading`: both disabled, "Loading more…".
local Pager = HorizontalGroup:extend{
    page = 1,
    pages = 1,
    more = false,
    loading = false,
    width = nil,
    on_change = nil, -- function(new_page)
}

function Pager:init()
    local band = Geom:new{ w = self.width, h = Screen:scaleBySize(44) }
    if self.pages <= 1 and not self.more then
        self[1] = CenterContainer:new{ dimen = band, HorizontalSpan:new{ width = 0 } }
        return
    end
    local function button(delta, rotation)
        local target = self.page + delta
        return PillButton:new{
            icon = "eink/chev", icon_size = Screen:scaleBySize(16), icon_rotation_angle = rotation,
            width = Screen:scaleBySize(44), height = Screen:scaleBySize(32), bordersize = Size.border.default,
            enabled = not self.loading and target >= 1 and (target <= self.pages or self.more),
            callback = function() self.on_change(target) end,
        }
    end
    local gap = Screen:scaleBySize(14)
    local count = TextWidget:new{
        text = self.loading and _("Loading more…") or self.page .. " / " .. (self.more and "…" or self.pages),
        face = Font:getFace("ui_label"), fgcolor = Palette.ink,
    }
    self[1] = CenterContainer:new{
        dimen = band,
        HorizontalGroup:new{
            button(-1, 180),
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{
                dimen = Geom:new{ w = math.max(Screen:scaleBySize(54), count:getSize().w), h = band.h },
                count,
            },
            HorizontalSpan:new{ width = gap },
            button(1, 0),
        },
    }
end

--- Page capsule: a 132 × 42dp pill split by a 1dp rule into an up half (previous page) and a down half (next page),
-- each with its own 1.5dp outline. A half that can't turn has a rule-gray outline and a dimmed chevron, and ignores
-- taps; with one page the whole capsule is gray. Each half takes taps over `touch_h`, centered on the capsule.
local PageCapsule = InputContainer:extend{
    page = 1,
    pages = 1,
    on_change = nil, -- function(new_page)
    width = Screen:scaleBySize(132),
    height = Screen:scaleBySize(42),
    touch_h = nil, -- at least 44dp
}

function PageCapsule:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.half_w = math.floor(self.width / 2)
    self.prev_enabled = self.page > 1
    self.next_enabled = self.page < self.pages
    local size = Screen:scaleBySize(24)
    self.prev_icon = IconWidget:new{ icon = "eink/chev.up", width = size, height = size, alpha = true,
        dim = not self.prev_enabled or nil }
    self.next_icon = IconWidget:new{ icon = "eink/chev.up", width = size, height = size, alpha = true,
        rotation_angle = 180, dim = not self.next_enabled or nil }
    local touch_h = math.max(self.touch_h or 0, Screen:scaleBySize(44))
    self.prev_rect = Geom:new{ w = self.half_w, h = touch_h }
    self.next_rect = Geom:new{ w = self.width - self.half_w, h = touch_h }
    self.ges_events = {
        TapPrev = { GestureRange:new{ ges = "tap", range = self.prev_rect } },
        TapNext = { GestureRange:new{ ges = "tap", range = self.next_rect } },
    }
end

function PageCapsule:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local w, h, half = self.width, self.height, self.half_w
    local touch_y = y - math.floor((self.prev_rect.h - h) / 2)
    self.prev_rect.x, self.prev_rect.y = x, touch_y
    self.next_rect.x, self.next_rect.y = x + half, touch_y
    local r = math.floor(h / 2)
    local bw = Size.border.button
    local anti_alias = G_reader_settings:nilOrTrue("anti_alias_ui")
    bb:paintRoundedRect(x, y, w, h, Palette.paper, r)
    -- A half's outline: a full ring at its round end with the inner side wiped, then its straight top and bottom.
    local function outline(enabled, end_x, wipe_x, line_x, line_w)
        local color = enabled and Palette.ink or Palette.rule
        bb:paintBorder(end_x, y, h, h, bw, color, r, anti_alias)
        bb:paintRect(wipe_x, y + bw, h - r, h - 2 * bw, Palette.paper)
        bb:paintRect(line_x, y, line_w, bw, color)
        bb:paintRect(line_x, y + h - bw, line_w, bw, color)
    end
    outline(self.prev_enabled, x, x + r, x + r, half - r)
    outline(self.next_enabled, x + w - h, x + w - h, x + half, w - half - r)
    local any = self.prev_enabled or self.next_enabled
    bb:paintRect(x + half, y, Size.border.default, h, any and Palette.ink or Palette.rule)
    local size = self.prev_icon:getSize()
    local icon_y = y + math.floor((h - size.h) / 2)
    self.prev_icon:paintTo(bb, x + math.floor((half - size.w) / 2), icon_y)
    self.next_icon:paintTo(bb, x + half + math.floor((w - half - size.w) / 2), icon_y)
end

function PageCapsule:onTapPrev()
    if self.prev_enabled and self.on_change then
        self.on_change(self.page - 1)
    end
    return true
end

function PageCapsule:onTapNext()
    if self.next_enabled and self.on_change then
        self.on_change(self.page + 1)
    end
    return true
end

-- The icons are painted by hand, not children: free them on rebuild and on close.
function PageCapsule:free()
    self.prev_icon:free()
    self.next_icon:free()
end

PageCapsule.onCloseWidget = PageCapsule.free

--- The ← back arrow at the start of a bottom bar: a 24dp icon after the 24dp gutter, tappable over its whole cell.
local BackArrow = InputContainer:extend{
    width = Screen:scaleBySize(72),
    height = nil,
    callback = nil,
}

function BackArrow:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local size = Screen:scaleBySize(24)
    local gutter = Screen:scaleBySize(24)
    self[1] = HorizontalGroup:new{
        HorizontalSpan:new{ width = gutter },
        CenterContainer:new{
            dimen = Geom:new{ w = size, h = self.height },
            IconWidget:new{ icon = "eink/arrow.left", width = size, height = size, alpha = true },
        },
    }
    self.ges_events = tapEvents(self.dimen)
end

function BackArrow:onTapSelect()
    if self.callback then
        self.callback()
    end
    return true
end

--- Bottom bar of a full-screen page: 58dp under a 1dp rule-gray rule, the back arrow on the left and the page
-- capsule on the right, 8dp from the edge. `left` replaces the back arrow (the shelf's tabs); `actions` are
-- widgets set just left of the capsule (a pill button such as 书签). `back` and `capsule` are its parts.
local BottomBar = InputContainer:extend{
    width = nil,
    page = 1,
    pages = 1,
    on_change = nil, -- function(new_page)
    on_back = nil, -- function(), for the back arrow
    left = nil,
    actions = nil,
}
BottomBar.height = Screen:scaleBySize(58)

function BottomBar:init()
    local rule_h = Size.border.default
    local row_h = BottomBar.height - rule_h
    self.dimen = Geom:new{ w = self.width, h = BottomBar.height }
    if not self.left then
        self.back = BackArrow:new{ height = row_h, callback = self.on_back }
    end
    self.capsule = PageCapsule:new{ page = self.page, pages = self.pages, on_change = self.on_change, touch_h = row_h }
    local right = HorizontalGroup:new{ align = "center" }
    for _, action in ipairs(self.actions or {}) do
        table.insert(right, action)
        table.insert(right, HorizontalSpan:new{ width = Screen:scaleBySize(16) })
    end
    table.insert(right, self.capsule)
    table.insert(right, HorizontalSpan:new{ width = Screen:scaleBySize(8) })
    local left = self.left or self.back
    self[1] = VerticalGroup:new{
        LineWidget:new{ background = Palette.rule, dimen = Geom:new{ w = self.width, h = rule_h } },
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = row_h },
            HorizontalGroup:new{
                align = "center",
                left,
                HorizontalSpan:new{ width = self.width - left:getSize().w - right:getSize().w },
                right,
            },
        },
    }
end

return {
    BottomBar = BottomBar,
    PageCapsule = PageCapsule,
    Pager = Pager,
    PillButton = PillButton,
    TickTrack = TickTrack,
    TickStepper = TickStepper,
    Toggle = Toggle,
    Segmented = Segmented,
}
