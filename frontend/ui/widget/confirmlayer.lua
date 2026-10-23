--[[--
Confirm layer of the e-ink redesign (see DESIGN.md, Confirm layer), as WeChat
Read asks before deleting or removing: the page behind turns pale (the wash), and
a paper band at the bottom, under a 2dp ink rule, holds a centered bold question,
then each action and Cancel as whole rows split by gray lines.

Every touch stops here: a tap on the pale page cancels, as does the Back key.
Showing and closing are "ui" over the whole screen, which the paling changes.
The page is paled while painting, so repaint the layer only with what is under it
(UIManager:setDirty("all", ...)), never alone.

The reader's 更多 panel (apps/reader/modules/readermorepanel) shows the same band
without a question, above the bottom bar: see ConfirmLayer.buildBand() and
ConfirmLayer.wash().

@usage
    local layer = ConfirmLayer:new{
        text = _("Delete this source?"),
        actions = { { text = _("Delete"), callback = function() ... end } },
    }
    UIManager:show(layer, "ui", layer:getRefreshRegion())
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local Screen = Device.screen
local _ = require("gettext")

local ActionRow = InputContainer:extend{
    width = nil,
    height = nil,
    text = nil, -- what the label reads
    label = nil, -- widget
    callback = nil, -- none on a faded row
}

function ActionRow:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = CenterContainer:new{ dimen = self.dimen:copy(), self.label }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function ActionRow:onTapSelect()
    if self.callback then
        self.callback()
    end
    return true
end

--- A row label: bold, and with two Chinese characters spaced apart (删 除, 取 消), as WeChat Read sets them.
local function rowLabel(text, color)
    local face = Font:getFace("ui_body")
    local chars = util.splitToChars(text)
    if #chars == 2 and util.isCJKChar(chars[1]) and util.isCJKChar(chars[2]) then
        return HorizontalGroup:new{
            TextWidget:new{ text = chars[1], face = face, bold = true, fgcolor = color },
            HorizontalSpan:new{ width = math.floor(face.size / 4) },
            TextWidget:new{ text = chars[2], face = face, bold = true, fgcolor = color },
        }
    end
    return TextWidget:new{ text = text, face = face, bold = true, fgcolor = color, max_width = Screen:getWidth() }
end

local ConfirmLayer = InputContainer:extend{
    text = nil, -- the question
    actions = nil, -- array of { text =, callback = }, shown above Cancel
    on_close = nil, -- function, called once the layer is closed, whichever way
    stop_events_propagation = true, -- holds, swipes and the rest never reach the page
}

function ConfirmLayer:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events.TapPage = { GestureRange:new{ ges = "tap", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    local rows = {}
    for _, action in ipairs(self.actions) do
        table.insert(rows, { text = action.text, callback = function()
            self:onClose()
            action.callback()
        end })
    end
    table.insert(rows, { text = _("Cancel"), callback = function() self:onClose() end })
    local band = ConfirmLayer.buildBand(self.text, rows)
    table.insert(band, VerticalSpan:new{ width = Screen:scaleBySize(20) })
    self[1] = band
    local band_h = band:getSize().h
    self.band_rect = Geom:new{ x = 0, y = sh - band_h, w = sw, h = band_h }
end

--- The paper band, screen-wide: the 2dp ink rule, a centered `question` (none for a list of actions), then a row
-- per entry of `rows`, { text =, callback = }, split by gray lines. A row without a callback is faded: a tap on it
-- does nothing.
function ConfirmLayer.buildBand(question, rows)
    local sw = Screen:getWidth()
    local band = VerticalGroup:new{
        LineWidget:new{ background = Palette.ink, dimen = Geom:new{ w = sw, h = Size.border.thick } },
    }
    if question then
        local gutter = Screen:scaleBySize(24)
        local text = TextBoxWidget:new{
            text = question,
            face = Font:getFace("ui_label_large"),
            bold = true,
            fgcolor = Palette.ink,
            alignment = "center",
            width = sw - 2 * gutter,
        }
        table.insert(band, CenterContainer:new{
            dimen = Geom:new{ w = sw, h = math.max(Screen:scaleBySize(53), text:getSize().h + 2 * Screen:scaleBySize(14)) },
            text,
        })
    end
    for i, row in ipairs(rows) do
        if question or i > 1 then -- without a question, the ink rule tops the first row
            table.insert(band, LineWidget:new{ background = Palette.rule, dimen = Geom:new{ w = sw, h = Size.border.default } })
        end
        table.insert(band, ActionRow:new{
            width = sw,
            height = Screen:scaleBySize(58),
            text = row.text,
            label = rowLabel(row.text, row.callback and Palette.ink or Palette.ink_3),
            callback = row.callback,
        })
    end
    return band
end

--- Pales what is painted in that rect: ink ends up as Palette.wash, paper stays paper (in night mode, the other
-- way round). Paint it only once over a freshly painted page.
function ConfirmLayer.wash(bb, x, y, w, h)
    bb:lightenRect(x, y, w, h, Palette.wash.a / 0xFF)
end

--- The whole screen: the page is paled under the band.
function ConfirmLayer:getRefreshRegion()
    return self.dimen:copy()
end

function ConfirmLayer:paintTo(bb, x, y)
    ConfirmLayer.wash(bb, x, y, self.dimen.w, self.band_rect.y)
    bb:paintRect(x, y + self.band_rect.y, self.band_rect.w, self.band_rect.h, Palette.paper)
    self[1]:paintTo(bb, x, y + self.band_rect.y)
end

function ConfirmLayer:onTapPage(_, ges)
    if ges.pos.y < self.band_rect.y then
        self:onClose()
    end
    return true
end

--- Closes the layer: after an action, on Cancel, a tap on the page or the Back key, or by its owner.
function ConfirmLayer:onClose()
    if self.closed then return true end
    self.closed = true
    UIManager:close(self, "ui", self:getRefreshRegion())
    if self.on_close then
        self.on_close()
    end
    return true
end

function ConfirmLayer:onCloseWidget()
    self[1]:free()
end

return ConfirmLayer
