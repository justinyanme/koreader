--[[--
Bottom sheet of the e-ink redesign (see DESIGN.md, Bottom sheet): a paper plane
with a 1dp ink border and 16dp top corners, bleeding past the screen edges, with
a 54dp header (bold title and close button) above the caller's content.

The rest of the screen is a transparent scrim: a tap there closes the sheet.
Showing, updating and closing only refresh the sheet's own rect ("ui").

@usage
    local sheet = BottomSheet:new{
        title = _("Progress"),
        content = VerticalGroup:new{ ... }, -- at most BottomSheet:getContentWidth() wide
        on_close = function() ... end,
    }
    UIManager:show(sheet, "ui", sheet:getRefreshRegion())
]]

local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconButton = require("ui/widget/iconbutton")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Palette = require("ui/palette")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local BottomSheet = InputContainer:extend{
    title = nil,
    content = nil, -- widget
    on_close = nil, -- function, called once the sheet is closed
    on_back = nil, -- function; when set, the header starts with a back button
    close_on_scrim = true,
}

function BottomSheet.getContentWidth()
    return Screen:getWidth() - 2 * Screen:scaleBySize(24)
end

function BottomSheet:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events.TapScrim = { GestureRange:new{ ges = "tap", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:build()
end

function BottomSheet:build()
    local gutter = Screen:scaleBySize(24)
    local close_size = Screen:scaleBySize(24)
    local close_pad = Screen:scaleBySize(10)
    local content_w = self.getContentWidth()
    local back_w = self.on_back and close_size + close_pad or 0
    local title_w = content_w - close_size - close_pad - back_w
    local title = TextWidget:new{
        text = self.title or "",
        face = Font:getFace("ui_title"),
        fgcolor = Palette.ink,
        max_width = title_w,
    }
    local header = HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = title_w, h = Screen:scaleBySize(54) },
            title,
        },
        IconButton:new{
            icon = "eink/close",
            width = close_size,
            height = close_size,
            padding_left = close_pad,
            padding_right = 0,
            allow_flash = false,
            callback = function() self:onClose() end,
        },
    }
    if self.on_back then
        table.insert(header, 1, IconButton:new{
            icon = "eink/back",
            width = close_size,
            height = close_size,
            padding_left = 0,
            padding_right = close_pad,
            allow_flash = false,
            callback = function() self.on_back() end,
        })
    end
    local radius = Screen:scaleBySize(16)
    local border = Screen:scaleBySize(1)
    self.frame = FrameContainer:new{
        bordersize = border,
        color = Palette.ink,
        background = Palette.paper,
        radius = radius,
        padding = 0,
        padding_left = gutter,
        padding_right = gutter,
        -- bottom corners sit below the screen edge, so only the top ones show
        padding_bottom = Screen:scaleBySize(20) + radius,
        VerticalGroup:new{
            align = "left",
            header,
            self.content or VerticalSpan:new{ width = 0 },
        },
    }
    local size = self.frame:getSize()
    local max_h = math.floor(Screen:getHeight() * 0.84) + radius + border
    self.sheet_y = Screen:getHeight() + radius + border - math.min(size.h, max_h)
end

--- The on-screen rect of the sheet: what show, update and close refresh.
function BottomSheet:getRefreshRegion()
    return Geom:new{ x = 0, y = self.sheet_y, w = Screen:getWidth(), h = Screen:getHeight() - self.sheet_y }
end

--- Replaces the content and refreshes the union of the old and new sheet rects.
function BottomSheet:setContent(content)
    local old = self:getRefreshRegion()
    if self.content and self.content ~= content then
        self.content:free()
    end
    self.content = content
    self:build()
    local new = self:getRefreshRegion()
    if new.y == old.y then
        UIManager:setDirty(self, "ui", new)
    else
        -- the page below must repaint where a taller sheet used to be
        UIManager:setDirty("all", "ui", old:combine(new))
    end
end

function BottomSheet:paintTo(bb, x, y)
    self.frame:paintTo(bb, x - Screen:scaleBySize(1), y + self.sheet_y)
end

function BottomSheet:propagateEvent(event)
    return self.frame:handleEvent(event)
end

function BottomSheet:onTapScrim(_, ges)
    if ges.pos.y < self.sheet_y and self.close_on_scrim then
        self:onClose()
    end
    return true
end

function BottomSheet:onClose()
    UIManager:close(self, "ui", self:getRefreshRegion())
    if self.on_close then
        self.on_close()
    end
    return true
end

function BottomSheet:onCloseWidget()
    self.frame:free()
end

return BottomSheet
