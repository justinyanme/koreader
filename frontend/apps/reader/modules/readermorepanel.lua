--[[--
"更多" panel of the e-ink redesign (see DESIGN.md, Panels and Confirm layer), opened
from the reader toolbar's top bar: KOReader's capabilities that WeChat Read lacks,
as the rows of a confirm layer's band without a question, right above the bottom
bar. Both bars stay; the page between them is washed and takes no touches.

- 亮度与色温: the brightness panel, in place of this one
- 书籍详情: KOReader's book status page, with the reader's own rating and review
- 导出笔记: exports the book's notes, or shows where formats are chosen when none is;
  faded while the book has no notes, left out without the exporter plugin
- 点击区域: the tap zones, drawn over the page until a tap
- 阅读统计: the statistics plugin's reading progress, left out without the plugin
- 全部设置（原版）: the original menu
- 取消: closes the panel; the bars stay

Each other row closes the panel and the bars ("ui" on their rects) before opening
its target, and closing that comes back to the page; so does a tap on the washed
page. 刷新与残影 is not here: it stays in 设置 → 屏幕 (ui/elements/eink_settings_order).
Also holds the tap zone overlay, which the settings preview too (apps/settings/einksettings).

The wash pales what is painted under it as it is painted. That is the page as last
drawn: the bars repaint alone only where they already covered it, and the list
reaches higher than any panel it replaces (with the bookmark toggle, the page
repaints too). Closing it uncovers the page, which repaints.

@usage
    toolbar:showPanel("more", ReaderMorePanel:new{ toolbar = toolbar })
]]

local BookStatusWidget = require("ui/widget/bookstatuswidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmLayer = require("ui/widget/confirmlayer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Palette = require("ui/palette")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")
local C_ = _.pgettext

local function text(str, face, color, max_width)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width }
end

-- Tap zone overlay: draws ReaderToolbar:getTapLayout(), a tap anywhere closes it.
local TapZones = InputContainer:extend{
    layout = nil,
}

function TapZones:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local margin = Screen:scaleBySize(6)
    local bw = Size.border.default -- an ink outline, as on cards
    local names = {
        backward = C_("Tap zones", "Previous page"),
        forward = C_("Tap zones", "Next page"),
        toolbar = C_("Tap zones", "Toolbar"),
        none = _("Page turn taps off"),
    }
    local thirds_hints = { _("Tap the left third"), _("Tap the middle"), _("Tap the right third") }
    self.zones = {}
    -- drawn in reverse so that the zone that wins a tap is on top
    for i = #self.layout, 1, -1 do
        local z = self.layout[i]
        local x, y = math.floor(z[1] * sw), math.floor(z[2] * sh)
        local w, h = math.floor(z[3] * sw), math.floor(z[4] * sh)
        local hint
        if math.abs(z[3] - 1/3) < 0.01 and z[4] == 1 then
            hint = thirds_hints[math.floor(z[1] * 3 + 0.5) + 1]
        end
        local inner = Geom:new{ w = w - 2 * (margin + bw), h = h - 2 * (margin + bw) }
        local label = VerticalGroup:new{ text(names[z[5]], "ui_title", Palette.ink, inner.w) }
        if hint then
            table.insert(label, VerticalSpan:new{ width = Screen:scaleBySize(4) })
            -- ink: pencil gray is only for placeholders and the open-book hint (DESIGN.md, Colors)
            table.insert(label, text(hint, "ui_caption", Palette.ink, inner.w))
        end
        table.insert(self.zones, { x = x, y = y, widget = FrameContainer:new{
            margin = margin, padding = 0, bordersize = bw, radius = Screen:scaleBySize(8),
            color = Palette.ink, background = Palette.paper,
            CenterContainer:new{ dimen = inner, label },
        } })
    end
    self.ges_events.TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.TapClose = { { Device.input.group.Back } }
    end
end

function TapZones:paintTo(bb, x, y)
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Palette.paper)
    for _, z in ipairs(self.zones) do
        z.widget:paintTo(bb, x + z.x, y + z.y)
    end
end

function TapZones:onTapClose()
    UIManager:close(self, "ui", self.dimen)
    return true
end

-- Shown like a ui/widget/panel by ReaderToolbar, which sets `bottom_y` and `show_parent` (its ToolbarBars).
local ReaderMorePanel = InputContainer:extend{
    toolbar = nil, -- ReaderToolbar
    hide_top_bar = false,
    on_close = nil,
    bottom_y = nil,
    show_parent = nil,
}

ReaderMorePanel.TapZones = TapZones

function ReaderMorePanel:init()
    local toolbar = self.toolbar
    local ui = toolbar.ui
    local function go(fn)
        return function()
            toolbar:hideToolbar()
            fn()
        end
    end
    local rows = {
        -- the bars have no brightness entry (WeChat Read's have none): its panel takes this one's place
        { text = _("Brightness and warmth"), callback = function() toolbar:openPanel("brightness") end },
        { text = _("Book details"), callback = go(function()
            -- KOReader's book status page, which flashes on closing elsewhere: only opening a book, going back to
            -- the shelf and night mode may (DESIGN.md, Refresh mapping)
            UIManager:show(BookStatusWidget:new{ ui = ui, close_refresh = "ui" }, "ui")
        end) },
    }
    local exporter = ui.exporter
    if exporter then
        table.insert(rows, { text = _("Export notes"), callback = exporter:isDocReady() and go(function()
            if exporter:isReady() then
                exporter:onExportCurrentNotes()
            else
                -- no format or service chosen yet: where the exporter's settings live
                toolbar:showOriginalMenuTab("appbar.tools")
            end
        end) or nil })
    end
    table.insert(rows, { text = _("Tap zones"), callback = go(function()
        local zones = TapZones:new{ layout = toolbar:getTapLayout() }
        UIManager:show(zones, "ui", zones.dimen)
    end) })
    if ui.statistics then
        table.insert(rows, { text = _("Reading statistics"), callback = go(function()
            ui.statistics:onShowReaderProgress()
        end) })
    end
    table.insert(rows, { text = _("All settings (original)"), callback = go(function()
        ui:handleEvent(Event:new("ShowOriginalMenu"))
    end) })
    table.insert(rows, { text = _("Cancel"), callback = function() toolbar:closePanel() end })
    self[1] = ConfirmLayer.buildBand(nil, rows)
    self.band_h = self[1]:getSize().h
    self.dimen = Geom:new{ w = Screen:getWidth(), h = self.band_h }
    self.ges_events.TapWash = { GestureRange:new{ ges = "tap", range = function() return self:getWashRect() end } }
end

--- The on-screen rect of the panel, while it shows: the washed page from under the top bar, and the band.
function ReaderMorePanel:getRefreshRegion()
    local bars = self.show_parent
    local top = bars.show_top and bars.top_rect.h or 0
    return Geom:new{ x = 0, y = top, w = Screen:getWidth(), h = self.bottom_y - top }
end

function ReaderMorePanel:getWashRect()
    local rect = self:getRefreshRegion()
    rect.h = rect.h - self.band_h
    return rect
end

function ReaderMorePanel:paintTo(bb, x, y)
    local wash = self:getWashRect()
    ConfirmLayer.wash(bb, x, y, wash.w, wash.h)
    bb:paintRect(x, y + wash.h, wash.w, self.band_h, Palette.paper)
    self[1]:paintTo(bb, x, y + wash.h)
end

-- A tap on the washed page closes the panel and the bars, without turning the page.
function ReaderMorePanel:onTapWash()
    self.toolbar:hideToolbar()
    return true
end

return ReaderMorePanel
