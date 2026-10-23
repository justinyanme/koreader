--[[--
Reader toolbar of the e-ink redesign (see DESIGN.md, Reader toolbars and Panels).

Replaces the reader menu (apps/replacements reader_menu slot): a tap in the
middle third of the page shows a top bar (back, bookmark, search, more) and a
bottom bar (contents, progress, brightness, font); taps on the left and right
thirds turn pages. The original menu stays reachable through "ShowOriginalMenu",
menu search, and on devices without a touch screen.

Panels (progress, brightness, more, and the typeset panel of ReaderTypesetPanel)
open between the page and the bottom bar, with both bars still showing; the
bottom bar draws the open panel's icon filled. Another entry switches the panel
in place, the open panel's own entry closes it, and a tap on the page closes the
panel and the bars without turning the page. Back leaves one layer at a time:
a nested panel opened from a panel (only a back arrow below, no top bar), the
panel, then the bars. What a panel opens elsewhere (book information, menus,
settings) closes the panel and the bars first.

Showing, switching or hiding the toolbar and its panel only refreshes their
rects ("ui"), with the page under what they no longer cover.
]]

local BD = require("ui/bidi")
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
local IconButton = require("ui/widget/iconbutton")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local ReaderMenu = require("apps/reader/modules/readermenu")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")
local C_ = _.pgettext

local ToolbarCell = InputContainer:extend{
    icon = nil,
    text = nil,
    width = nil,
    height = nil,
    callback = nil,
}

function ToolbarCell:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local icon_size = Screen:scaleBySize(24)
    self[1] = CenterContainer:new{
        dimen = self.dimen:copy(),
        VerticalGroup:new{
            IconWidget:new{ icon = self.icon, width = icon_size, height = icon_size, alpha = true },
            VerticalSpan:new{ width = Screen:scaleBySize(5) },
            TextWidget:new{ text = self.text, face = Font:getFace("ui_caption"), fgcolor = Palette.ink },
        },
    }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function ToolbarCell:onTapSelect()
    self.callback()
    return true
end

-- Full-screen window holding the two bars and the open panel, transparent elsewhere:
-- a tap on the page closes them all.
local ToolbarBars = InputContainer:extend{
    toolbar = nil,
}

function ToolbarBars:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.top = self.toolbar:buildTopBar()
    self.top_rect = Geom:new{ x = 0, y = 0, w = sw, h = self.top:getSize().h }
    self.ges_events.TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.ToolbarBack = { { Device.input.group.Back } }
    end
    self:layout()
end

--- Lays the bars out around the toolbar's panel. Below a nested panel,
-- the bottom bar holds only a back arrow and the top bar hides.
function ToolbarBars:layout()
    local panel = self.toolbar.panel
    local nested = panel ~= nil and panel.on_back ~= nil
    if self.bottom then
        self.bottom:free()
    end
    self.bottom = self.toolbar:buildBottomBar(not nested and self.toolbar.panel_name, nested)
    self.show_top = not nested
    local bottom_h = self.bottom:getSize().h
    self.bottom_rect = Geom:new{ x = 0, y = Screen:getHeight() - bottom_h, w = Screen:getWidth(), h = bottom_h }
    -- children receive events: the bars first
    for i = #self, 1, -1 do
        self[i] = nil
    end
    if self.show_top then
        table.insert(self, self.top)
    end
    table.insert(self, self.bottom)
    if panel then
        panel.bottom_y = self.bottom_rect.y
        panel.show_parent = self
        table.insert(self, panel)
    end
end

--- The rect of the panel, if any, and the bottom bar.
function ToolbarBars:getBandRect()
    local panel = self.toolbar.panel
    return panel and panel:getRefreshRegion():combine(self.bottom_rect) or self.bottom_rect
end

--- What a refresh compares: see ReaderToolbar:refreshBars().
function ToolbarBars:snapshot()
    return { band = self:getBandRect(), top = self.show_top }
end

function ToolbarBars:paintTo(bb, x, y)
    local panel = self.toolbar.panel
    if panel then
        panel:paintTo(bb, x, y + panel:getRefreshRegion().y)
    end
    if self.show_top then
        self.top:paintTo(bb, x, y)
    end
    self.bottom:paintTo(bb, x, y + self.bottom_rect.y)
end

function ToolbarBars:onTapOutside(_, ges)
    if not (self.show_top and self.top_rect:contains(ges.pos)) and not self:getBandRect():contains(ges.pos) then
        self.toolbar:hideToolbar()
    end
    return true
end

function ToolbarBars:onToolbarBack()
    self.toolbar:goBack()
    return true
end

local ReaderToolbar = ReaderMenu:extend{
    bars = nil, -- ToolbarBars while shown
    panel = nil, -- ui/widget/panel open between the page and the bottom bar
    panel_name = nil, -- the entry of that panel: "progress", "brightness", "more" or "font"
}

--- Registers the toolbar in its replacement slot and applies its footer defaults.
function ReaderToolbar.register()
    require("apps/replacements").reader_menu = ReaderToolbar
    ReaderToolbar.applyFooterDefaults()
end

--- Reading page footer: chapter pages, book percentage, time and battery.
-- Only replaces a footer the user never customized, i.e. absent or still equal to upstream's defaults
-- (the one-time migration saves the default footer on first start).
function ReaderToolbar.applyFooterDefaults()
    local util = require("util")
    local default_footer = require("apps/reader/modules/readerfooter").default_settings
    local footer = G_reader_settings:readSetting("footer")
    if footer == nil or util.tableEquals(footer, default_footer) then
        footer = util.tableDeepCopy(default_footer)
        for k, v in pairs{
            page_progress = false, pages_left = false, book_time_to_read = false, chapter_time_to_read = false,
            chapter_progress = true, percentage = true, time = true, battery = Device:hasBattery(),
            dynamic_filler = true, all_at_once = true, disable_progress_bar = true,
            item_prefix = "compact_items", items_separator = "none", text_font_size = 12,
        } do
            footer[k] = v
        end
        footer.order = { [0] = "off", "chapter_progress", "dynamic_filler", "percentage", "time", "battery" }
        G_reader_settings:saveSetting("footer", footer)
    end
end

function ReaderToolbar:initGesListener()
    if not Device:isTouchDevice() then return end
    self.ui:registerTouchZones({
        {
            -- Same id as the original menu zone, so that taps on links and highlights keep priority.
            id = "readermenu_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            overrides = {
                "tap_forward",
                "tap_backward",
                "readerfooter_tap",
                "readerconfigmenu_ext_tap",
                "readerconfigmenu_tap",
            },
            handler = function(ges) return self:onTapPage(ges) end,
        },
    })
end

ReaderToolbar.onReaderReady = ReaderToolbar.initGesListener

--[[--
Where taps go on the page, as screen-ratio rects: { x, y, w, h, kind } with kind
"backward", "forward", "toolbar" or "none" (page turn taps disabled), first match wins.
Default: thirds. Custom page turn zones keep their size; the toolbar gets the band
left between them, or the screen's center when they leave none.
]]
function ReaderToolbar:getTapLayout()
    local third = 1/3
    if G_reader_settings:isTrue("page_turns_disable_tap") then
        return { { 0, 0, third, 1, "none" }, { third, 0, third, 1, "toolbar" }, { 2 * third, 0, third, 1, "none" } }
    end
    if G_reader_settings:readSetting("page_turns_tap_zones", "default") == "default" then
        local left, right = "backward", "forward"
        if self.view.inverse_reading_order ~= BD.mirroredUILayout() then
            left, right = right, left
        end
        return { { 0, 0, third, 1, left }, { third, 0, third, 1, "toolbar" }, { 2 * third, 0, third, 1, right } }
    end
    local forward, backward = self.view:getTapZones()
    local function rect(z, kind) return { z.ratio_x, z.ratio_y, z.ratio_w, z.ratio_h, kind } end
    -- side by side (left_right) or stacked (top_bottom, bottom_top): the toolbar takes the gap
    local axis = forward.ratio_h == 1 and backward.ratio_h == 1 and 1 or 2
    local first, second = backward, forward
    if (axis == 1 and forward.ratio_x < backward.ratio_x) or (axis == 2 and forward.ratio_y < backward.ratio_y) then
        first, second = forward, backward
    end
    local gap_start, gap_end
    if axis == 1 then
        gap_start, gap_end = first.ratio_x + first.ratio_w, second.ratio_x
    else
        gap_start, gap_end = first.ratio_y + first.ratio_h, second.ratio_y
    end
    local toolbar
    if gap_end - gap_start > 0.01 then
        toolbar = axis == 1 and { gap_start, 0, gap_end - gap_start, 1, "toolbar" }
                             or { 0, gap_start, 1, gap_end - gap_start, "toolbar" }
    else
        -- zones covering the whole page: the toolbar keeps a center square on top of them
        return { { third, third, third, third, "toolbar" }, rect(backward, "backward"), rect(forward, "forward") }
    end
    return { rect(backward, "backward"), rect(forward, "forward"), toolbar }
end

function ReaderToolbar:onTapPage(ges)
    local fx, fy = ges.pos.x / Screen:getWidth(), ges.pos.y / Screen:getHeight()
    for _, z in ipairs(self:getTapLayout()) do
        if fx >= z[1] and fx < z[1] + z[3] and fy >= z[2] and fy < z[2] + z[4] then
            if z[5] == "toolbar" then
                return self:showToolbar()
            elseif z[5] == "none" then
                return true
            end
            return (self.ui.rolling or self.ui.paging):onGotoViewRel(z[5] == "forward" and 1 or -1)
        end
    end
    return self:showToolbar()
end

function ReaderToolbar:onTapShowMenu()
    return self:showToolbar()
end

function ReaderToolbar:onPressMenu()
    return self:showToolbar()
end

function ReaderToolbar:onShowMenu(tab_index, do_not_show)
    -- menu search and rebuilds want the original menu, and so do devices without touch (no D-pad navigation here)
    if do_not_show or not Device:isTouchDevice() then
        return ReaderMenu.onShowMenu(self, tab_index, do_not_show)
    end
    return self:showToolbar()
end

function ReaderToolbar:onSetDimensions(dimen)
    self:hideToolbar(true)
    self:closeDrawer()
    if self.menu_container then
        self:onCloseReaderMenu()
        ReaderMenu.onShowMenu(self)
    end
    self:initGesListener()
end

function ReaderToolbar:onCloseWidget()
    self:hideToolbar(true)
    self:closeDrawer()
end

--- The contents drawer (目录 / 书签 / 笔记) takes over "ShowToc", from the toolbar and gestures alike;
-- the original table of contents stays in the original menu, which calls ReaderToc directly.
function ReaderToolbar:onShowToc()
    if not Device:isTouchDevice() then return end -- no D-pad navigation here: ReaderToc handles it
    self:hideToolbar(true)
    self:closeDrawer()
    self.drawer = require("apps/reader/modules/readertocdrawer"):new{
        ui = self.ui,
        on_close = function() self.drawer = nil end,
    }
    UIManager:show(self.drawer, "ui", self.drawer.panel_rect)
    return true
end

--- The reorganized settings (apps/settings/einksettings), on an optional group or row id.
function ReaderToolbar:onShowEinkSettings(target)
    self:hideToolbar(true)
    self:closeDrawer()
    require("apps/settings/einksettings").show(self.ui, self, target)
    return true
end

function ReaderToolbar:closeDrawer()
    if self.drawer then
        UIManager:close(self.drawer)
        self.drawer = nil
    end
end

local BAR_PAD = Screen:scaleBySize(10) -- 44dp touch targets
local BAR_SIDE = Screen:scaleBySize(8)

local function iconButton(icon, callback)
    local icon_size = Screen:scaleBySize(24)
    return IconButton:new{
        icon = icon, width = icon_size, height = icon_size, padding = BAR_PAD,
        allow_flash = false, callback = callback,
    }
end

function ReaderToolbar:buildTopBar()
    local sw = Screen:getWidth()
    local top_h = Screen:scaleBySize(56)
    local rule = Screen:scaleBySize(1)
    self.bookmark_button = iconButton(self:bookmarkIcon(), function() self:toggleBookmark() end)
    local buttons_w = 4 * (Screen:scaleBySize(24) + 2 * BAR_PAD)
    return FrameContainer:new{
        bordersize = 0, padding = 0, background = Palette.paper,
        VerticalGroup:new{
            CenterContainer:new{
                dimen = Geom:new{ w = sw, h = top_h - rule },
                HorizontalGroup:new{
                    iconButton("eink/back", function() self:backToShelf() end),
                    HorizontalSpan:new{ width = sw - 2 * BAR_SIDE - buttons_w },
                    self.bookmark_button,
                    iconButton("eink/search", function() self:runAction("search") end),
                    iconButton("eink/more", function() self:togglePanel("more") end),
                },
            },
            LineWidget:new{ dimen = Geom:new{ w = sw, h = rule }, background = Palette.ink },
        },
    }
end

--- The bottom bar, with the icon of the `active` panel's entry filled;
-- with `back_only`, it holds only the back arrow of full-screen pages (below a nested panel).
function ReaderToolbar:buildBottomBar(active, back_only)
    local sw = Screen:getWidth()
    local bottom_h = Screen:scaleBySize(76)
    local rule = Screen:scaleBySize(1)
    local row
    if back_only then
        row = LeftContainer:new{
            dimen = Geom:new{ w = sw, h = bottom_h - rule },
            EinkControls.BackArrow:new{ height = bottom_h - rule, callback = function() self:goBack() end },
        }
    else
        local cell_w = math.floor(sw / 4)
        local function cell(icon, text, name, callback)
            return ToolbarCell:new{
                icon = name ~= nil and name == active and icon .. ".bold" or icon, text = text,
                width = cell_w, height = bottom_h - rule, callback = callback,
            }
        end
        row = CenterContainer:new{
            dimen = Geom:new{ w = sw, h = bottom_h - rule },
            HorizontalGroup:new{
                cell("eink/toc", C_("Reader toolbar", "Contents"), nil, function() self:runAction("toc") end),
                cell("eink/progress", _("Progress"), "progress", function() self:togglePanel("progress") end),
                cell("eink/light", _("Brightness"), "brightness", function() self:togglePanel("brightness") end),
                cell("eink/font", _("Font"), "font", function() self:togglePanel("font") end),
            },
        }
    end
    return FrameContainer:new{
        bordersize = 0, padding = 0, background = Palette.paper,
        VerticalGroup:new{
            LineWidget:new{ dimen = Geom:new{ w = sw, h = rule }, background = Palette.ink },
            row,
        },
    }
end

function ReaderToolbar:showToolbar()
    if not self.bars then
        self:openBars()
    end
    return true
end

-- Shows the bars, around the panel if one is set.
function ReaderToolbar:openBars()
    self.bars = ToolbarBars:new{ toolbar = self }
    UIManager:show(self.bars) -- no refresh of its own: only the bars and the panel below
    if self.bars.show_top then
        UIManager:setDirty(nil, "ui", self.bars.top_rect)
    end
    UIManager:setDirty(nil, "ui", self.bars:getBandRect())
end

--- Hides the toolbar and its panel.
function ReaderToolbar:hideToolbar(no_refresh)
    local bars = self.bars
    if not bars then return end
    local snapshot = bars:snapshot()
    self.bars = nil
    self.bookmark_button = nil
    UIManager:close(bars)
    self:dropPanel()
    bars.top:free()
    bars.bottom:free()
    if not no_refresh then
        if snapshot.top then
            UIManager:setDirty(nil, "ui", bars.top_rect)
        end
        UIManager:setDirty(nil, "ui", snapshot.band)
    end
end

--- Shows `panel` (a ui/widget/panel) between the page and the bottom bar, in place of the open one,
-- with both bars. `name` is its entry ("progress", "brightness", "more" or "font").
function ReaderToolbar:showPanel(name, panel)
    local bars = self.bars
    local before = bars and bars:snapshot()
    self:dropPanel()
    self.panel, self.panel_name = panel, name
    if not bars then
        return self:openBars()
    end
    bars:layout()
    self:refreshBars(before)
end

--- Closes the open panel; the bars stay.
function ReaderToolbar:closePanel()
    local bars = self.bars
    if not (bars and self.panel) then return end
    local before = bars:snapshot()
    self:dropPanel()
    bars:layout()
    self:refreshBars(before)
end

--- Opens the panel of an entry, or closes it when it is the open one.
function ReaderToolbar:togglePanel(name)
    if self.panel_name == name then
        self:closePanel()
    else
        self:openPanel(name)
    end
end

--- Opens the panel of an entry: "progress", "brightness", "more" (apps/reader/modules/readertoolbarpanels)
-- or "font", the typeset panel, which shows itself on "ShowConfigMenu".
function ReaderToolbar:openPanel(name)
    if name == "font" then
        local config = self.ui.config
        if not (config.usesPanel and config:usesPanel()) then
            self:hideToolbar() -- fixed-layout books keep the original bottom bar
        end
        self.ui:handleEvent(Event:new("ShowConfigMenu"))
        return
    end
    self:showPanel(name, require("apps/reader/modules/readertoolbarpanels")[name](self))
end

--- Back leaves one layer at a time: a nested panel, the panel, then the bars.
function ReaderToolbar:goBack()
    local panel = self.panel
    if panel and panel.on_back then
        panel.on_back()
    elseif panel then
        self:closePanel()
    else
        self:hideToolbar()
    end
end

-- Forgets the open panel and tells its owner, without refreshing.
function ReaderToolbar:dropPanel()
    local panel = self.panel
    if not panel then return end
    self.panel, self.panel_name = nil, nil
    panel:free()
    if panel.on_close then
        panel.on_close()
    end
end

-- Refreshes what changed in the bars since `before` (a ToolbarBars:snapshot()): the band of the panel and
-- the bottom bar, and the top bar if it came or went. The page repaints where nothing covers it anymore.
function ReaderToolbar:refreshBars(before)
    local bars = self.bars
    local band = bars:getBandRect()
    local uncovered = before.band.y < band.y or (before.top and not bars.show_top)
    local target = uncovered and "all" or bars
    if before.top ~= bars.show_top then
        UIManager:setDirty(target, "ui", bars.top_rect)
    end
    UIManager:setDirty(target, "ui", before.band:combine(band))
end

function ReaderToolbar:bookmarkIcon()
    return self.ui.bookmark:isPageBookmarked() and "eink/bookmark-on" or "eink/bookmark"
end

function ReaderToolbar:toggleBookmark()
    self.ui.bookmark:onToggleBookmark() -- also refreshes the dog-ear
    self:updateBookmarkButton()
end

-- Shows whether the current page has a bookmark ("fast" on the button only, when that changed).
function ReaderToolbar:updateBookmarkButton()
    local button = self.bookmark_button
    local icon = self:bookmarkIcon()
    if button and button.icon ~= icon then
        local rect = button.dimen:copy()
        button:setIcon(icon)
        button.dimen.x, button.dimen.y = rect.x, rect.y
        UIManager:setDirty(self.bars, "fast", rect)
    end
end

-- The page can change under the bars (a panel's jumps, a reflow).
ReaderToolbar.onPageUpdate = ReaderToolbar.updateBookmarkButton
ReaderToolbar.onPosUpdate = ReaderToolbar.updateBookmarkButton

function ReaderToolbar:backToShelf()
    self:hideToolbar(true)
    local file = self.ui.document.file
    self.ui:onClose()
    self.ui:showFileManager(file)
end

--- Toolbar entries that open existing UI. "toc" is the entry point #8 takes over.
function ReaderToolbar:runAction(action)
    self:hideToolbar()
    if action == "toc" then
        self.ui:handleEvent(Event:new("ShowToc"))
    elseif action == "search" then
        self.ui.search:onShowFulltextSearchInput()
    end
end

--- Opens the original menu on the tab with this icon.
function ReaderToolbar:showOriginalMenuTab(icon)
    if self.tab_item_table == nil then
        self:setUpdateItemTable()
    end
    for i, tab in ipairs(self.tab_item_table) do
        if tab.icon == icon then
            return self:onShowOriginalMenu(i)
        end
    end
    return self:onShowOriginalMenu()
end

return ReaderToolbar
