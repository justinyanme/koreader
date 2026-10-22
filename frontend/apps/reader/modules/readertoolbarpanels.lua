--[[--
Panels opened from the reader toolbar: progress, brightness and more (see the
prototype's progressSheet, lightSheet and moreSheet). Each returns a BottomSheet.
Changing a value re-renders the sheet with a "ui" refresh of its own rect;
page jumps refresh the page through the reader as usual ("partial").
]]

local BottomSheet = require("ui/widget/bottomsheet")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext

local Panels = {}

local function text(str, face, color, max_width)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width }
end

local function rule(color)
    return LineWidget:new{ dimen = Geom:new{ w = BottomSheet.getContentWidth(), h = Screen:scaleBySize(1) }, background = color }
end

-- A full-width tappable row: label on the left, an optional widget (chevron, toggle) on the right.
local Row = InputContainer:extend{
    label = nil, -- widget
    right = nil, -- widget
    height = nil,
    callback = nil,
}

function Row:init()
    local w = BottomSheet.getContentWidth()
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

function Row:onTapSelect()
    self.callback()
    return true
end

-- Labelled control row of the sheet ("srow"): gray label column, then the control.
local LABEL_W = Screen:scaleBySize(64)
local function controlRow(label, control)
    return HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = LABEL_W, h = Screen:scaleBySize(52) },
            text(label, "ui_label", Palette.ink_2, LABEL_W),
        },
        control,
    }
end

------------------------------------------------------------------------
-- Progress

-- Position track: 1.5dp ink line, chapter ticks, filled up to the current page, round knob.
local ProgressTrack = InputContainer:extend{
    width = nil,
    page = 1,
    page_count = 1,
    ticks = nil, -- array of chapter start pages
    on_jump = nil, -- function(page)
}

function ProgressTrack:init()
    self.dimen = Geom:new{ w = self.width, h = Screen:scaleBySize(44) }
    self.knob_radius = Screen:scaleBySize(11)
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

-- The knob's radius is kept free at both ends so that it is never clipped.
function ProgressTrack:xOf(page)
    local r = self.knob_radius
    return r + math.floor((page - 1) / math.max(1, self.page_count - 1) * (self.width - 2 * r) + 0.5)
end

function ProgressTrack:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local mid = y + math.floor(self.dimen.h / 2)
    local line = Size.border.button
    bb:paintRect(x, mid - math.floor(line / 2), self.width, line, Palette.ink)
    local tick_h = Screen:scaleBySize(20)
    for _, page in ipairs(self.ticks) do
        if page > 1 then
            bb:paintRect(x + self:xOf(page), mid - tick_h / 2, line, tick_h, Palette.ink)
        end
    end
    local pos = self:xOf(self.page)
    local bar_h = Screen:scaleBySize(6)
    bb:paintRoundedRect(x, mid - bar_h / 2, pos, bar_h, Palette.ink, bar_h / 2)
    local r = self.knob_radius
    bb:paintCircle(x + pos, mid, r, Palette.ink)
    bb:paintCircle(x + pos, mid, r - Size.border.thick, Palette.paper)
end

function ProgressTrack:onTapSelect(_, ges)
    local fx = (ges.pos.x - self.dimen.x - self.knob_radius) / (self.width - 2 * self.knob_radius)
    local page = math.max(1, math.min(self.page_count, math.floor(fx * self.page_count) + 1))
    if page ~= self.page then
        self.on_jump(page)
    end
    return true
end

local function locationPage(ui, location)
    if ui.rolling then
        return location.xpointer and ui.document:getPageFromXPointer(location.xpointer)
    end
    return location[1] and location[1].page
end

local function chapterStart(toc, page)
    if toc:isChapterStart(page) then return page end
    return toc:getPreviousChapter(page)
end

local function progressContent(toolbar)
    local ui = toolbar.ui
    local toc = ui.toc
    local w = BottomSheet.getContentWidth()
    local page = ui:getCurrentPage()
    local page_count = ui.document:getPageCount()
    local refresh = function() toolbar.sheet:setContent(progressContent(toolbar)) end
    local jump = function(target)
        ui.link:addCurrentLocationToStack()
        ui:handleEvent(Event:new("GotoPage", target))
        refresh()
    end

    local function chapterTitle(p)
        local title = toc:getTocTitleByPage(p)
        return title ~= "" and title or ui.doc_props.display_title
    end
    local chapter = chapterTitle(page)
    local pages_done = toc:getChapterPagesDone(page)
    local chapter_pages = toc:getChapterPageCount(page)
    local percent = math.floor(page / page_count * 100)
    local where
    if pages_done and chapter_pages then
        where = T(_("Chapter page %1 / %2 · Book %3%"), pages_done + 1, chapter_pages, percent)
    else
        where = T(_("Page %1 / %2 · Book %3%"), page, page_count, percent)
    end

    local current_start = chapterStart(toc, page)
    local prev = current_start and toc:getPreviousChapter(current_start)
    local next = toc:getNextChapter(page)
    local button_w = math.floor((w - Screen:scaleBySize(10)) / 2)
    local group = VerticalGroup:new{
        align = "left",
        text(chapter, "ui_body", Palette.ink, w),
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        text(where, "ui_caption", Palette.ink_2, w),
        VerticalSpan:new{ width = Screen:scaleBySize(16) },
        ProgressTrack:new{
            width = w, page = page, page_count = page_count,
            ticks = toc:getTocTicks(1) or {}, on_jump = jump, -- top-level chapters only
        },
        VerticalSpan:new{ width = Screen:scaleBySize(18) },
        HorizontalGroup:new{
            EinkControls.PillButton:new{
                text = _("Previous chapter"), width = button_w, enabled = prev ~= nil,
                callback = function() jump(prev) end,
            },
            HorizontalSpan:new{ width = w - 2 * button_w },
            EinkControls.PillButton:new{
                text = _("Next chapter"), width = button_w, enabled = next ~= nil,
                callback = function() jump(next) end,
            },
        },
    }
    local stack = ui.link.location_stack
    local last = stack and stack[#stack]
    local last_page = last and locationPage(ui, last)
    if last_page then
        local last_done = toc:getChapterPagesDone(last_page)
        local chev = Screen:scaleBySize(18)
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(10) })
        table.insert(group, rule(Palette.rule))
        table.insert(group, Row:new{
            height = Screen:scaleBySize(48),
            label = text(T(_("Return to last position: %1, page %2"),
                           chapterTitle(last_page), (last_done or last_page - 1) + 1),
                         "ui_label_large", Palette.ink, w - chev),
            right = IconWidget:new{ icon = "eink/chev", width = chev, height = chev, alpha = true },
            callback = function()
                ui.link:onGoBackLink()
                refresh()
            end,
        })
    end
    return group
end

function Panels.progress(toolbar)
    return BottomSheet:new{
        title = _("Progress"),
        content = progressContent(toolbar),
        on_close = function() toolbar.sheet = nil end,
    }
end

------------------------------------------------------------------------
-- Brightness

local TICKS = 9

local function toTick(value, min, max)
    return math.floor((value - min) / (max - min) * (TICKS - 1) + 0.5) + 1
end

local function fromTick(tick, min, max)
    return min + math.floor((tick - 1) / (TICKS - 1) * (max - min) + 0.5)
end

local function toggleRow(toolbar, label, checked, callback)
    local toggle = EinkControls.Toggle:new{ checked = checked }
    toggle.callback = function(v)
        UIManager:setDirty(toolbar.sheet, "fast", toggle.dimen)
        callback(v)
    end
    return VerticalGroup:new{
        rule(Palette.rule),
        Row:new{
            height = Screen:scaleBySize(52) - Screen:scaleBySize(1),
            label = text(label, "ui_label_large", Palette.ink, BottomSheet.getContentWidth() - toggle:getSize().w),
            right = toggle,
        },
    }
end

local function brightnessContent(toolbar)
    local ui = toolbar.ui
    local powerd = Device:getPowerDevice()
    local w = BottomSheet.getContentWidth()
    local refresh = function() toolbar.sheet:setContent(brightnessContent(toolbar)) end
    local group = VerticalGroup:new{ align = "left" }
    if Device:hasFrontlight() then
        local intensity = powerd:isFrontlightOn() and powerd:frontlightIntensity() or powerd.fl_min
        table.insert(group, controlRow(T(_("Brightness %1%"), math.floor(intensity / powerd.fl_max * 100 + 0.5)),
            EinkControls.TickStepper:new{
                count = TICKS, width = w - LABEL_W,
                value = toTick(intensity, powerd.fl_min, powerd.fl_max),
                on_change = function(tick)
                    ui:handleEvent(Event:new("SetFlIntensity", fromTick(tick, powerd.fl_min, powerd.fl_max)))
                    refresh()
                end,
            }))
    end
    if Device:hasNaturalLight() then
        local warmth = powerd:toNativeWarmth(powerd:frontlightWarmth())
        local min, max = powerd.fl_warmth_min, powerd.fl_warmth_max
        table.insert(group, controlRow(T(_("Warmth %1"), warmth),
            EinkControls.TickStepper:new{
                count = TICKS, width = w - LABEL_W,
                value = toTick(warmth, min, max),
                on_change = function(tick)
                    ui:handleEvent(Event:new("SetFlWarmth", fromTick(tick, min, max)))
                    refresh()
                end,
            }))
    end
    -- Without natural light the plugin is "auto night mode" and would flip night mode on its own.
    local autowarmth = Device:hasNaturalLight() and ui.autowarmth
    if autowarmth then
        table.insert(group, toggleRow(toolbar, _("Adjust warmth automatically by time"), autowarmth.activate ~= 0,
            function(on)
                autowarmth:onAutoWarmthMode(on and 2 or 0) -- 2: fixed schedule, needs no location
                refresh() -- warmth and night mode may have changed with it
            end))
    end
    table.insert(group, toggleRow(toolbar, _("Night mode (white on black)"), G_reader_settings:isTrue("night_mode"),
        function()
            ui:handleEvent(Event:new("ToggleNightMode")) -- full refresh, the only one
        end))
    return group
end

function Panels.brightness(toolbar)
    return BottomSheet:new{
        title = _("Brightness"),
        content = brightnessContent(toolbar),
        on_close = function() toolbar.sheet = nil end,
    }
end

------------------------------------------------------------------------
-- More

local Tile = InputContainer:extend{
    icon = nil,
    label = nil,
    width = nil,
    enabled = true,
    callback = nil,
}

function Tile:init()
    local h = Screen:scaleBySize(84)
    local bw = Size.border.default
    local icon_size = Screen:scaleBySize(24)
    self.dimen = Geom:new{ w = self.width, h = h }
    local icon = IconWidget:new{ icon = self.icon, width = icon_size, height = icon_size, alpha = true }
    icon.dim = not self.enabled or nil
    self[1] = FrameContainer:new{
        bordersize = bw, padding = 0, radius = Screen:scaleBySize(12),
        color = Palette.rule, background = Palette.paper,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width - 2 * bw, h = h - 2 * bw },
            VerticalGroup:new{
                icon,
                VerticalSpan:new{ width = Screen:scaleBySize(8) },
                text(self.label, "ui_label", self.enabled and Palette.ink or Palette.ink_3, self.width - 2 * bw),
            },
        },
    }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function Tile:onTapSelect()
    if self.enabled then
        self.callback()
    end
    return true
end

-- Tap zone overlay: draws ReaderToolbar:getTapLayout(), a tap anywhere closes it.
local TapZones = InputContainer:extend{
    layout = nil,
}

function TapZones:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local margin = Screen:scaleBySize(6)
    local bw = Size.border.thick
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
            table.insert(label, text(hint, "ui_caption", Palette.ink_2, inner.w))
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

local function moreContent(toolbar, sheet)
    local ui = toolbar.ui
    local w = BottomSheet.getContentWidth()
    local gap = Screen:scaleBySize(8)
    local tile_w = math.floor((w - 2 * gap) / 3)
    -- Each tile closes the sheet ("ui" on its rect) before opening its target.
    local function go(fn)
        return function()
            sheet:onClose()
            fn()
        end
    end
    local tiles = {
        { "eink/info", _("Book information"), true, function() ui.bookinfo:onShowBookInfo() end },
        { "eink/zones", _("Tap zones"), Device:isTouchDevice(), function()
            local zones = TapZones:new{ layout = toolbar:getTapLayout() }
            UIManager:show(zones, "ui", zones.dimen)
        end },
        { "eink/export", _("Export notes"), ui.exporter ~= nil and ui.exporter:isReadyToExport(), function() ui.exporter:onExportCurrentNotes() end },
        { "eink/stats", _("Reading statistics"), ui.statistics ~= nil, function() ui.statistics:onShowReaderProgress() end },
        -- Until the reorganized settings (#12) exist: the original menu, on its settings tab.
        { "eink/refresh", _("Refresh and ghosting"), true, function() toolbar:showOriginalMenuTab("appbar.settings") end },
        { "eink/sliders", _("All settings"), true, function() ui:handleEvent(Event:new("ShowOriginalMenu")) end },
    }
    local group = VerticalGroup:new{ align = "left" }
    local row
    for i, t in ipairs(tiles) do
        if i % 3 == 1 then
            if row then
                table.insert(group, row)
                table.insert(group, VerticalSpan:new{ width = gap })
            end
            row = HorizontalGroup:new{}
        else
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
        table.insert(row, Tile:new{ icon = t[1], label = t[2], enabled = t[3], width = tile_w, callback = go(t[4]) })
    end
    table.insert(group, row)
    return group
end

function Panels.more(toolbar)
    local sheet = BottomSheet:new{
        title = _("More"),
        on_close = function() toolbar.sheet = nil end,
    }
    sheet.content = moreContent(toolbar, sheet)
    sheet:build()
    return sheet
end

return Panels
