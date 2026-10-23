-- WeChat Read's ribbon, with ReaderDogear's margin, header and view-mode handling.
local BD = require("ui/bidi")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ReaderDogear = require("apps/reader/modules/readerdogear")
local RightContainer = require("ui/widget/container/rightcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen

local ReaderToolbarDogear = ReaderDogear:extend{}

function ReaderToolbarDogear:init()
    self.dogear_min_size = Screen:scaleBySize(17)
    self.dogear_max_size = Screen:scaleBySize(42)
    self.dogear_y_offset = 0
    self:setupDogear()
end

function ReaderToolbarDogear:setupDogear(size)
    size = size or self.dogear_max_size
    if size == self.dogear_size then return end
    self.dogear_size = size
    if self[1] then self[1]:free() end
    self.icon = IconWidget:new{
        icon = "eink/bookmark-ribbon", alpha = true,
        width = math.floor(size * 17 / 42 + 0.5), height = size,
    }
    self.top_pad = VerticalSpan:new{ width = self.dogear_y_offset }
    self.vgroup = VerticalGroup:new{ self.top_pad, self.icon }
    local inset = HorizontalSpan:new{ width = Screen:scaleBySize(25) }
    local mirrored = BD.mirroredUILayout()
    self[1] = (mirrored and LeftContainer or RightContainer):new{
        allow_mirroring = false,
        dimen = Geom:new{ w = Screen:getWidth(), h = self.dogear_y_offset + size },
        HorizontalGroup:new{
            allow_mirroring = false,
            mirrored and inset or self.vgroup,
            mirrored and self.vgroup or inset,
        },
    }
end

function ReaderToolbarDogear:updateDogearOffset()
    ReaderDogear.updateDogearOffset(self)
    self[1][1]:resetLayout()
end

return ReaderToolbarDogear
