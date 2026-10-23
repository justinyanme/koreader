--[[--
Selection popover of the e-ink redesign (see DESIGN.md, Selection popover), as
in WeChat Read: a paper card with a 1dp ink outline and 13dp corners, and an
outlined 16 × 8dp arrow pointing at the selection. In a row with icons, cells
show an icon over a short label and are 62dp wide at least, and a widget cell
keeps its widget; other rows are labels or widgets in 44dp cells. A cell can
also run a secondary action on a long-press. Rows are split by rule-gray lines.
It sits above the selection when there is room, below it otherwise, and 16dp
from the screen edges.

The rest of the screen is a transparent scrim: a tap there closes the popover.
The owner refreshes; getRefreshRegion() is the popover and its arrow.

@usage
    local bubble = SelectionBubble:new{
        rows = { {
            { icon = "eink/copy", text = _("Copy"), callback = ... },
            { icon = "eink/highlight-off", text = _("Delete"), callback = ..., hold_callback = ... },
            { widget = swatch, selected = true, callback = ... },
        } },
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
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local BubbleCell = InputContainer:extend{
    width = nil,
    height = nil,
    content = nil, -- widget
    selected = false,
    callback = nil,
    hold_callback = nil, -- a secondary action on a long-press
}

function BubbleCell:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = CenterContainer:new{ dimen = self.dimen:copy(), self.content }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    if self.hold_callback then
        self.ges_events.HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } }
    end
end

function BubbleCell:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    if self.selected then
        local inset = Screen:scaleBySize(5) -- clear of the card's outline
        bb:paintBorder(x + inset, y + inset, self.width - 2 * inset, self.height - 2 * inset,
            Screen:scaleBySize(2), Palette.ink, Screen:scaleBySize(8))
    end
end

function BubbleCell:onTapSelect()
    if self.callback then
        self.callback()
    end
    return true
end

function BubbleCell:onHoldSelect()
    self.hold_callback()
    return true
end

local SelectionBubble = InputContainer:extend{
    rows = nil, -- array of rows; a row is an array of { icon =, text = } or { widget = }, with selected =, callback =, hold_callback =
    anchor_rects = nil, -- screen rects of the selection
    tap_close_callback = nil, -- called when a tap outside the popover closes it
}

function SelectionBubble:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events.TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.border = Size.border.default
    self.edge = Screen:scaleBySize(16)
    local avail = Screen:getWidth() - 2 * self.edge - 2 * self.border
    -- every row spreads its cells over the widest row
    local contents, heights, bubble_w = {}, {}, 0
    for r, row in ipairs(self.rows) do
        local row_w
        contents[r], row_w, heights[r] = self:rowContents(row, math.floor(avail / #row))
        bubble_w = math.max(bubble_w, row_w)
    end
    bubble_w = math.min(bubble_w, avail)
    local vgroup = VerticalGroup:new{}
    for r, row in ipairs(self.rows) do
        if r > 1 then
            table.insert(vgroup, LineWidget:new{ background = Palette.rule, dimen = Geom:new{ w = bubble_w, h = self.border } })
        end
        local hgroup = HorizontalGroup:new{}
        for c, cell in ipairs(row) do
            local w = math.floor(bubble_w / #row)
            if c == #row then w = bubble_w - (#row - 1) * w end
            table.insert(hgroup, BubbleCell:new{
                width = w,
                height = heights[r],
                content = contents[r][c],
                selected = cell.selected,
                callback = cell.callback,
                hold_callback = cell.hold_callback,
            })
        end
        table.insert(vgroup, hgroup)
    end
    self.radius = Screen:scaleBySize(13)
    self.frame = FrameContainer:new{
        bordersize = self.border,
        color = Palette.ink,
        padding = 0,
        radius = self.radius,
        background = Palette.paper,
        vgroup,
    }
    self:place()
end

--- The contents of a row of cells at most max_cell_w wide, its natural width and its height.
-- With an icon in it, every cell of the row is as wide as the widest, and 62dp at least.
function SelectionBubble:rowContents(row, max_cell_w)
    local has_icon = false
    for _, cell in ipairs(row) do
        if cell.icon then has_icon = true end
    end
    local contents, row_w, height = {}, 0, Screen:scaleBySize(44)
    if has_icon then
        local pad = Screen:scaleBySize(6) -- 删除划线 still fits a 62dp cell, so it takes 划线's place exactly
        local icon_size = Screen:scaleBySize(28)
        local cell_w = Screen:scaleBySize(62)
        for c, cell in ipairs(row) do
            -- the label's line box already leaves room below it
            contents[c] = cell.widget or VerticalGroup:new{
                VerticalSpan:new{ width = Screen:scaleBySize(10) },
                cell.icon and IconWidget:new{ icon = cell.icon, width = icon_size, height = icon_size, alpha = true }
                    or VerticalSpan:new{ width = icon_size },
                VerticalSpan:new{ width = Screen:scaleBySize(3) },
                TextWidget:new{
                    text = cell.text,
                    face = Font:getFace("ui_caption"),
                    bold = true,
                    fgcolor = Palette.ink,
                    max_width = max_cell_w - 2 * pad,
                },
                VerticalSpan:new{ width = Screen:scaleBySize(5) },
            }
            local size = contents[c]:getSize()
            cell_w = math.max(cell_w, size.w + 2 * pad)
            height = math.max(height, size.h)
        end
        row_w = math.min(cell_w, max_cell_w) * #row
    else
        local cell_pad = Screen:scaleBySize(13)
        for c, cell in ipairs(row) do
            contents[c] = cell.widget or TextWidget:new{
                text = cell.text,
                face = Font:getFace("ui_label_large"),
                fgcolor = Palette.ink,
                max_width = max_cell_w - 2 * cell_pad,
            }
            row_w = row_w + contents[c]:getSize().w + 2 * cell_pad
        end
    end
    return contents, row_w, height
end

-- Above the selection if it fits, else below; 16dp from screen edges, the arrow pointing at the selection.
-- When neither fits (or there is no selection on screen), it overlays the selection, without an arrow.
function SelectionBubble:place()
    local size = self.frame:getSize()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local edge = self.edge
    local rects = self.anchor_rects or {}
    self.arrow_h = Screen:scaleBySize(8)
    local gap = self.arrow_h + Screen:scaleBySize(6)
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
    -- the arrow's base stays clear of the rounded corners
    local inset = self.radius + self.border + self.arrow_h
    self.arrow_x = math.max(self.bubble_rect.x + inset, math.min(self.bubble_rect.x + size.w - inset, mid))
end

--- The popover and its arrow: what show and close refresh.
function SelectionBubble:getRefreshRegion()
    local r = self.bubble_rect
    return Geom:new{ x = r.x, y = self.above and r.y or r.y - self.arrow_h, w = r.w, h = r.h + self.arrow_h }
end

function SelectionBubble:paintTo(bb, x, y)
    local r = self.bubble_rect
    self.frame:paintTo(bb, x + r.x, y + r.y)
    -- Outlined arrow, one row of pixels at a time from its tip, 45° sides: an ink triangle with a paper one
    -- inside, which also cuts the outline where the arrow meets the card.
    local h = self.arrow_h
    if h == 0 then return end
    local b = self.border
    local inner = math.floor(b * math.sqrt(2) + 0.5) -- vertical inset that makes 45° sides b thick
    local cx = x + self.arrow_x
    for i = 0, h + b - 1 do -- i: rows from the tip
        local row_y = self.above and y + r.y + r.h + h - 1 - i or y + r.y - h + i
        bb:paintRect(cx - i, row_y, 2 * i + 1, 1, Palette.ink)
        local half = i - inner
        if half >= 0 then
            bb:paintRect(cx - half, row_y, 2 * half + 1, 1, Palette.paper)
        end
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
