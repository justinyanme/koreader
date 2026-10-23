-- The bookmark ribbon in WeChat Read (05-bookmarks/02-bookmark-added.png):
-- 17dp wide, 42dp tall, flush with the top and 25dp from the right edge.
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local ReaderToolbarDogear = WidgetContainer:extend{}

function ReaderToolbarDogear:init()
    self.icon = IconWidget:new{
        icon = "eink/bookmark-ribbon", alpha = true,
        width = Screen:scaleBySize(17), height = Screen:scaleBySize(42),
    }
    self[1] = RightContainer:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = self.icon.height },
        HorizontalGroup:new{
            self.icon,
            HorizontalSpan:new{ width = Screen:scaleBySize(25) },
        },
    }
end

function ReaderToolbarDogear:resetLayout()
    -- ReaderThumbnail also adjusts this container's width when rendering PDF page images.
    self[1].dimen.w = Screen:getWidth()
end

function ReaderToolbarDogear:getRefreshRegion()
    return self.icon.dimen
end

function ReaderToolbarDogear:onSetDogearVisibility(visible)
    self.view.dogear_visible = visible
    return true
end

return ReaderToolbarDogear
