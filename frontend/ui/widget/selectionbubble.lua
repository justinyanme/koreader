--[[--
Selection bubble of the e-ink redesign (see DESIGN.md, Selection bubble): a solid
ink bar with 10dp corners, rows of 44dp cells split by bubble-rule dividers, and
a 7dp arrow pointing at the selection. It sits above the selection when there is
room, below it otherwise.

The rest of the screen is a transparent scrim: a tap there closes the bubble.
The owner refreshes; getRefreshRegion() is the bubble and its arrow.

@usage
    local bubble = SelectionBubble:new{
        rows = { { { text = _("Copy"), callback = ... }, { widget = swatch, selected = true, callback = ... } } },
        anchor_rects = selection_screen_rects,
        tap_close_callback = function() ... end,
    }
    UIManager:show(bubble, "fast", bubble:getRefreshRegion())
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen

local BubbleCell = InputContainer:extend{
    width = nil,
    height = nil,
    content = nil, -- widget
    selected = false,
    callback = nil,
}

function BubbleCell:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = CenterContainer:new{ dimen = self.dimen:copy(), self.content }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function BubbleCell:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    if self.selected then
        local inset = Screen:scaleBySize(1)
        bb:paintBorder(x + inset, y + inset, self.width - 2 * inset, self.height - 2 * inset,
            Screen:scaleBySize(2), Palette.paper, Screen:scaleBySize(8))
    end
end

function BubbleCell:onTapSelect()
    if self.callback then
        self.callback()
    end
    return true
end

local SelectionBubble = InputContainer:extend{
    rows = nil, -- array of rows; a row is an array of { text = or widget =, selected = , callback = }
    anchor_rects = nil, -- screen rects of the selection
    tap_close_callback = nil, -- called when a tap outside the bubble closes it
    rule_color = Palette.bubble_rule, -- dividers; Palette.paper survives a black and white ("fast") refresh
}

function SelectionBubble:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events.TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    local cell_h = Screen:scaleBySize(44)
    local cell_pad = Screen:scaleBySize(13)
    local rule = Screen:scaleBySize(1)
    -- every row spreads its cells over the widest row
    local contents, bubble_w = {}, 0
    for r, row in ipairs(self.rows) do
        contents[r] = {}
        local row_w = 0
        for c, cell in ipairs(row) do
            contents[r][c] = cell.widget or TextWidget:new{
                text = cell.text,
                face = Font:getFace("ui_label_large"),
                fgcolor = Palette.paper,
            }
            row_w = row_w + contents[r][c]:getSize().w + 2 * cell_pad
        end
        bubble_w = math.max(bubble_w, row_w + (#row - 1) * rule)
    end
    local vgroup = VerticalGroup:new{}
    for r, row in ipairs(self.rows) do
        if r > 1 then
            table.insert(vgroup, LineWidget:new{ background = self.rule_color, dimen = Geom:new{ w = bubble_w, h = rule } })
        end
        local hgroup = HorizontalGroup:new{}
        local avail = bubble_w - (#row - 1) * rule
        for c, cell in ipairs(row) do
            if c > 1 then
                table.insert(hgroup, LineWidget:new{ background = self.rule_color, dimen = Geom:new{ w = rule, h = cell_h } })
            end
            local w = math.floor(avail / #row)
            if c == #row then w = avail - (#row - 1) * w end
            table.insert(hgroup, BubbleCell:new{
                width = w,
                height = cell_h,
                content = contents[r][c],
                selected = cell.selected,
                callback = cell.callback,
            })
        end
        table.insert(vgroup, hgroup)
    end
    self.frame = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        radius = Screen:scaleBySize(10),
        background = Palette.ink,
        vgroup,
    }
    self:place()
end

-- Same placement as the prototype: above the selection if it fits, else below; 10dp from screen edges.
-- When neither fits (or there is no selection on screen), it overlays the selection, without an arrow.
function SelectionBubble:place()
    local size = self.frame:getSize()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local edge, gap = Screen:scaleBySize(10), Screen:scaleBySize(10)
    local rects = self.anchor_rects or {}
    self.arrow_h = Screen:scaleBySize(7)
    local top0, bot0, anchor
    if #rects > 0 then
        top0, bot0 = math.huge, 0
        for _, r in ipairs(rects) do
            top0 = math.min(top0, r.y)
            bot0 = math.max(bot0, r.y + r.h)
        end
    end
    local y
    if top0 and top0 - gap - size.h >= edge then
        self.above, anchor, y = true, rects[1], top0 - gap - size.h
    elseif bot0 and bot0 + gap + size.h <= sh - edge then
        self.above, anchor, y = false, rects[#rects], bot0 + gap
    else
        self.above, self.arrow_h = true, 0
        y = math.max(edge, math.min(sh - size.h - edge, top0 or math.floor((sh - size.h) / 2)))
    end
    local mid = anchor and anchor.x + math.floor(anchor.w / 2) or math.floor(sw / 2)
    self.bubble_rect = Geom:new{
        x = math.max(edge, math.min(sw - size.w - edge, mid - math.floor(size.w / 2))),
        y = y,
        w = size.w,
        h = size.h,
    }
    local corner = Screen:scaleBySize(14)
    self.arrow_x = math.max(self.bubble_rect.x + corner, math.min(self.bubble_rect.x + size.w - corner, mid))
end

--- The bubble and its arrow: what show and close refresh.
function SelectionBubble:getRefreshRegion()
    local r = self.bubble_rect
    return Geom:new{ x = r.x, y = self.above and r.y or r.y - self.arrow_h, w = r.w, h = r.h + self.arrow_h }
end

function SelectionBubble:paintTo(bb, x, y)
    local r = self.bubble_rect
    self.frame:paintTo(bb, x + r.x, y + r.y)
    -- arrow, one row per pixel, base against the bubble
    for i = 0, self.arrow_h - 1 do
        local half = self.arrow_h - i
        local row_y = self.above and r.y + r.h + i or r.y - 1 - i
        bb:paintRect(x + self.arrow_x - half, y + row_y, 2 * half, 1, Palette.ink)
    end
end

function SelectionBubble:propagateEvent(event)
    return self.frame:handleEvent(event)
end

function SelectionBubble:onTapClose(_, ges)
    if not ges.pos:intersectWith(self.bubble_rect) then
        if self.tap_close_callback then
            self.tap_close_callback()
        end
    end
    return true
end

function SelectionBubble:onClose()
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function SelectionBubble:onCloseWidget()
    self.frame:free()
end

return SelectionBubble
