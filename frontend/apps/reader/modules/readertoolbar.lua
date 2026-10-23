--[[--
Reader toolbar of the e-ink redesign (see DESIGN.md, Reader toolbars).

Replaces the reader menu (apps/replacements reader_menu slot): a tap in the
middle third of the page shows a top bar (back, bookmark, search, more) and a
bottom bar (contents, progress, brightness, font); taps on the left and right
thirds turn pages. The original menu stays reachable through "ShowOriginalMenu",
menu search, and on devices without a touch screen.

Showing or hiding the toolbar only refreshes the two bars ("ui").
]]

local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
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

-- Full-screen, transparent apart from the two bars: a tap outside them closes the toolbar.
local ToolbarBars = InputContainer:extend{
    toolbar = nil,
    top = nil, -- widget
    bottom = nil, -- widget
}

function ToolbarBars:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.top_rect = Geom:new{ x = 0, y = 0, w = sw, h = self.top:getSize().h }
    local bottom_h = self.bottom:getSize().h
    self.bottom_rect = Geom:new{ x = 0, y = sh - bottom_h, w = sw, h = bottom_h }
    self[1] = self.top
    self[2] = self.bottom
    self.ges_events.TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
end

function ToolbarBars:paintTo(bb, x, y)
    self.top:paintTo(bb, x, y)
    self.bottom:paintTo(bb, x, y + self.bottom_rect.y)
end

function ToolbarBars:onTapOutside(_, ges)
    if not self.top_rect:contains(ges.pos) and not self.bottom_rect:contains(ges.pos) then
        self.toolbar:hideToolbar()
    end
    return true
end

function ToolbarBars:onClose()
    self.toolbar:hideToolbar()
    return true
end

local ReaderToolbar = ReaderMenu:extend{
    bars = nil, -- ToolbarBars while shown
    sheet = nil, -- BottomSheet of an open panel
    drawer = nil, -- the contents page while shown, or the old drawer that its 书签 opens
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
    self:closeSheet(true)
    self:closeDrawer()
    if self.menu_container then
        self:onCloseReaderMenu()
        ReaderMenu.onShowMenu(self)
    end
    self:initGesListener()
end

function ReaderToolbar:onCloseWidget()
    self:hideToolbar(true)
    self:closeSheet(true)
    self:closeDrawer()
end

--- The contents page (目录页) takes over "ShowToc", from the toolbar and gestures alike;
-- the original table of contents stays in the original menu, which calls ReaderToc directly.
function ReaderToolbar:onShowToc()
    if not Device:isTouchDevice() then return end -- no D-pad navigation here: ReaderToc handles it
    self:hideToolbar(true)
    self:closeSheet(true)
    self:closeDrawer()
    self.drawer = require("apps/reader/modules/readertocpage"):new{
        ui = self.ui,
        on_close = function() self.drawer = nil end,
        on_bookmarks = function() self:showBookmarks() end,
    }
    UIManager:show(self.drawer, "ui", self.drawer.dimen)
    return true
end

--- The old drawer's bookmarks (and notes): where the contents page's 书签 goes until the notes page.
function ReaderToolbar:showBookmarks()
    self:closeDrawer()
    self.drawer = require("apps/reader/modules/readertocdrawer"):new{
        ui = self.ui,
        on_close = function() self.drawer = nil end,
    }
    UIManager:show(self.drawer, "ui", self.drawer.panel_rect)
end

--- The reorganized settings (apps/settings/einksettings), on an optional group or row id.
function ReaderToolbar:onShowEinkSettings(target)
    self:hideToolbar(true)
    self:closeSheet(true)
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

function ReaderToolbar:buildBars()
    local sw = Screen:getWidth()
    local top_h, bottom_h = Screen:scaleBySize(56), Screen:scaleBySize(76)
    local rule = Screen:scaleBySize(1)
    local icon_size = Screen:scaleBySize(24)
    local pad = Screen:scaleBySize(10) -- 44dp touch targets
    local function iconButton(icon, callback)
        return IconButton:new{
            icon = icon, width = icon_size, height = icon_size, padding = pad,
            allow_flash = false, callback = callback,
        }
    end
    self.bookmark_button = iconButton(self:bookmarkIcon(), function() self:toggleBookmark() end)
    local buttons_w = 4 * (icon_size + 2 * pad)
    local side = Screen:scaleBySize(8)
    local top = FrameContainer:new{
        bordersize = 0, padding = 0, background = Palette.paper,
        VerticalGroup:new{
            CenterContainer:new{
                dimen = Geom:new{ w = sw, h = top_h - rule },
                HorizontalGroup:new{
                    iconButton("eink/back", function() self:backToShelf() end),
                    HorizontalSpan:new{ width = sw - 2 * side - buttons_w },
                    self.bookmark_button,
                    iconButton("eink/search", function() self:runAction("search") end),
                    iconButton("eink/more", function() self:openPanel("more") end),
                },
            },
            LineWidget:new{ dimen = Geom:new{ w = sw, h = rule }, background = Palette.ink },
        },
    }
    local cell_w = math.floor(sw / 4)
    local function cell(icon, text, callback)
        return ToolbarCell:new{ icon = icon, text = text, width = cell_w, height = bottom_h - rule, callback = callback }
    end
    local bottom = FrameContainer:new{
        bordersize = 0, padding = 0, background = Palette.paper,
        VerticalGroup:new{
            LineWidget:new{ dimen = Geom:new{ w = sw, h = rule }, background = Palette.ink },
            CenterContainer:new{
                dimen = Geom:new{ w = sw, h = bottom_h - rule },
                HorizontalGroup:new{
                    cell("eink/toc", C_("Reader toolbar", "Contents"), function() self:runAction("toc") end),
                    cell("eink/progress", _("Progress"), function() self:openPanel("progress") end),
                    cell("eink/light", _("Brightness"), function() self:openPanel("brightness") end),
                    cell("eink/font", _("Font"), function() self:runAction("font") end),
                },
            },
        },
    }
    return ToolbarBars:new{ toolbar = self, top = top, bottom = bottom }
end

function ReaderToolbar:showToolbar()
    if self.bars then return true end
    self:closeSheet()
    self.bars = self:buildBars()
    UIManager:show(self.bars) -- no refresh of its own: only the two bars below
    UIManager:setDirty(nil, "ui", self.bars.top_rect)
    UIManager:setDirty(nil, "ui", self.bars.bottom_rect)
    return true
end

--- Hides the toolbar. With `refresh_top_only`, only the top bar is refreshed (a sheet covers the bottom one).
function ReaderToolbar:hideToolbar(no_refresh, refresh_top_only)
    local bars = self.bars
    if not bars then return end
    self.bars = nil
    self.bookmark_button = nil
    UIManager:close(bars)
    if not no_refresh then
        UIManager:setDirty(nil, "ui", bars.top_rect)
        if not refresh_top_only then
            UIManager:setDirty(nil, "ui", bars.bottom_rect)
        end
    end
end

function ReaderToolbar:bookmarkIcon()
    return self.ui.bookmark:isPageBookmarked() and "eink/bookmark-on" or "eink/bookmark"
end

function ReaderToolbar:toggleBookmark()
    self.ui.bookmark:onToggleBookmark() -- also refreshes the dog-ear
    local button = self.bookmark_button
    if button then
        local rect = button.dimen:copy()
        button:setIcon(self:bookmarkIcon())
        button.dimen.x, button.dimen.y = rect.x, rect.y
        UIManager:setDirty(self.bars, "fast", rect)
    end
end

function ReaderToolbar:backToShelf()
    self:hideToolbar(true)
    local file = self.ui.document.file
    self.ui:onClose()
    self.ui:showFileManager(file)
end

--- Toolbar entries that open existing UI. "toc" and "font" are the entry points #8 and #5 take over.
function ReaderToolbar:runAction(action)
    self:hideToolbar()
    if action == "toc" then
        self.ui:handleEvent(Event:new("ShowToc"))
    elseif action == "font" then
        self.ui:handleEvent(Event:new("ShowConfigMenu"))
    elseif action == "search" then
        self.ui.search:onShowFulltextSearchInput()
    end
end

--- Opens a panel ("progress", "brightness", "more") in a bottom sheet, replacing the toolbar.
function ReaderToolbar:openPanel(name)
    self:hideToolbar(false, true)
    self:closeSheet(true)
    self.sheet = require("apps/reader/modules/readertoolbarpanels")[name](self)
    UIManager:show(self.sheet, "ui", self.sheet:getRefreshRegion())
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

function ReaderToolbar:closeSheet(no_refresh)
    local sheet = self.sheet
    if not sheet then return end
    self.sheet = nil
    sheet.on_close = nil
    if no_refresh then
        UIManager:close(sheet)
    else
        sheet:onClose()
    end
end

return ReaderToolbar
