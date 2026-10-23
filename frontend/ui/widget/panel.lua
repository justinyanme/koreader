--[[--
Panel of the e-ink redesign (see DESIGN.md, Panels): a paper band between the
page and the reader's bottom bar, with a 1dp rule-gray top edge and square
corners. It has no title bar and no close button: the reader toolbar hosts it
with the bottom bar still showing, and the top bar too unless `hide_top_bar`
is set (the typeset panel, as in WeChat Read). The toolbar switches it in
place and closes it (see ReaderToolbar:showPanel()).

A panel with `on_back` is nested: opened from another panel, such as the
typeset panel's layout options (DESIGN.md's paragraph panel). The toolbar
then hides the top bar and shows only a back arrow in the bottom bar. The expanded
font panel also sets `hide_bottom_bar`, reaching the screen edge with its own collapse button.

A panel either gets its `content`, or builds it in `buildContent()`, which
`refresh()` calls again after a change.

Updating the content only refreshes the panel's rect ("ui"), or the union of
its old and new rects, with the page under them, when its height changes.

@usage
    local panel = Panel:new{
        content = VerticalGroup:new{ ... }, -- at most Panel.getContentWidth() wide
    }
    ui.menu:showPanel("progress", panel)
    panel:setContent(VerticalGroup:new{ ... })

    local MyPanel = Panel:extend{}
    function MyPanel:buildContent() return VerticalGroup:new{ ... } end
]]

local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Palette = require("ui/palette")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local GUTTER = Screen:scaleBySize(22)

local Panel = InputContainer:extend{
    content = nil, -- widget
    on_back = nil, -- function: leaves this nested panel for the one it was opened from
    hide_top_bar = false, -- the toolbar hides its top bar while this panel shows
    hide_bottom_bar = false, -- the expanded font panel reaches the screen's bottom edge
    padding_top = Screen:scaleBySize(16),
    on_close = nil, -- function, called once the panel is closed
    -- set by the toolbar while the panel shows
    bottom_y = nil, -- the panel sits right above this line
    show_parent = nil, -- the window that paints the panel
}

function Panel.getContentWidth()
    return Screen:getWidth() - 2 * GUTTER
end

function Panel:init()
    if self.buildContent then
        self.content = self:buildContent()
    end
    self:build()
end

function Panel:build()
    self.rule = Size.border.default
    self[1] = FrameContainer:new{
        bordersize = 0,
        background = Palette.paper,
        padding = 0,
        padding_left = GUTTER,
        padding_right = GUTTER,
        padding_top = self.padding_top,
        padding_bottom = Screen:scaleBySize(20),
        self.content or VerticalSpan:new{ width = 0 },
    }
    self.dimen = Geom:new{ w = Screen:getWidth(), h = self.rule + self[1]:getSize().h }
end

--- The on-screen rect of the panel, while it shows.
function Panel:getRefreshRegion()
    return Geom:new{ x = 0, y = self.bottom_y - self.dimen.h, w = self.dimen.w, h = self.dimen.h }
end

--- Rebuilds the content with buildContent(), after a change.
function Panel:refresh()
    self:setContent(self:buildContent())
end

--- Replaces the content. While the panel shows, refreshes its rect, or the union of the old and new rects.
function Panel:setContent(content)
    local old = self.bottom_y and self:getRefreshRegion()
    if self.content and self.content ~= content then
        self.content:free()
    end
    self.content = content
    self:build()
    if not old then return end
    local new = self:getRefreshRegion()
    if new.h == old.h then
        UIManager:setDirty(self.show_parent, "ui", new)
    else
        -- the page must repaint where a taller panel used to be
        UIManager:setDirty("all", "ui", old:combine(new))
    end
end

function Panel:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.rule, Palette.rule)
    self[1]:paintTo(bb, x, y + self.rule)
end

------------------------------------------------------------------------

--- A full-width tappable row of a panel: label on the left, an optional widget (chevron, toggle) on the right.
Panel.Row = InputContainer:extend{
    label = nil, -- widget
    right = nil, -- widget
    height = nil,
    callback = nil,
}

function Panel.Row:init()
    local w = Panel.getContentWidth()
    local right_w = self.right and self.right:getSize().w or 0
    self.dimen = Geom:new{ w = w, h = self.height }
    self[1] = HorizontalGroup:new{
        LeftContainer:new{ dimen = Geom:new{ w = w - right_w, h = self.height }, self.label },
        self.right,
    }
    if self.callback then
        self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
end

function Panel.Row:onTapSelect()
    self.callback()
    return true
end

return Panel
