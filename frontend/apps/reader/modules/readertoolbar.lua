--[[--
Reader toolbar of the e-ink redesign (see DESIGN.md, Reader toolbars and Panels).

Replaces the reader menu (apps/replacements reader_menu slot): a swipe up, or a
tap in the middle third of the page, shows a top bar (its icons at the right:
bookmark, more) and a bottom bar (back, a short rule, then contents, notes,
progress, font); taps on the left and right thirds and sideways swipes turn
pages, and links and highlights keep their taps. The swipe up works anywhere on
a page, but only from the bottom edge in scroll mode, where swipes scroll, and
not when the original menu's "Activate menu" leaves out swipes. Each time a book
opens, a hint on the footer line tells about the swipe (see ReaderToolbarHint).
The original menu stays reachable through "ShowOriginalMenu", menu search, and
on devices without a touch screen.

Panels (progress, brightness, more, and the typeset panel of ReaderTypesetPanel)
open between the page and the bottom bar, which keeps showing and draws the open
panel's icon filled. The top bar stays too, except over the typeset panel, as in
WeChat Read. Another entry switches the panel
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
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconButton = require("ui/widget/iconbutton")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderToolbarHint = require("apps/reader/modules/readertoolbarhint")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen

-- Sizes from WeChat Read on the Leaf5 (01-reader-navigation/01-toolbars.png).
local TOP_H = Screen:scaleBySize(50)
local TOP_CELL_W = Screen:scaleBySize(76) -- the top bar's icons are 76dp apart, the last one 38dp from the edge
local BOTTOM_H = EinkControls.BottomBar.height -- as on full-screen pages
local BACK_W = Screen:scaleBySize(88) -- the back arrow's column, up to the short rule
local RULE_H = Screen:scaleBySize(25) -- the short rule after the back arrow
local ICON_SIZE = Screen:scaleBySize(28)

-- The original bottom menu's zones, where a swipe up shows the toolbar in scroll mode too.
local function bottomEdgeZones()
    return { G_defaults:readSetting("DTAP_ZONE_CONFIG"), G_defaults:readSetting("DTAP_ZONE_CONFIG_EXT") }
end

-- An entry of the bottom bar: an icon without a label.
local ToolbarCell = InputContainer:extend{
    icon = nil,
    width = nil,
    height = nil,
    callback = nil,
}

function ToolbarCell:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = CenterContainer:new{
        dimen = self.dimen:copy(),
        IconWidget:new{ icon = self.icon, width = ICON_SIZE, height = ICON_SIZE, alpha = true },
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

--- Lays the bars out around the toolbar's panel. The top bar hides over a panel that asks for it,
-- and over a nested panel, below which the bottom bar holds only a back arrow.
function ToolbarBars:layout()
    local panel = self.toolbar.panel
    local nested = panel ~= nil and panel.on_back ~= nil
    if self.bottom then
        self.bottom:free()
    end
    self.bottom = self.toolbar:buildBottomBar(not nested and self.toolbar.panel_name, nested)
    self.show_top = not (nested or panel and panel.hide_top_bar)
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
    drawer = nil, -- the full-screen page shown over the book: the contents page or the notes page
    notes_return = nil, -- filter of the notes list to reopen on Back after a card jump
    hint = nil, -- ReaderToolbarHint while the open-book hint shows
}

--- Registers the toolbar in its replacement slot and applies its footer defaults.
function ReaderToolbar.register()
    require("apps/replacements").reader_menu = ReaderToolbar
    ReaderToolbar.applyFooterDefaults()
end

-- The footer of the redesign's first round: chapter pages, book percentage, time and battery.
local FOOTER_V1 = {
    settings = {
        page_progress = false, pages_left = false, book_time_to_read = false, chapter_time_to_read = false,
        chapter_progress = true, percentage = true, time = true, battery = Device:hasBattery(),
        dynamic_filler = true, all_at_once = true, disable_progress_bar = true,
        item_prefix = "compact_items", items_separator = "none", text_font_size = 12,
    },
    order = { [0] = "off", "chapter_progress", "dynamic_filler", "percentage", "time", "battery" },
}

-- WeChat Read's footer (00-entry/02-book-open.png): the time at the left and the current page / pages at the
-- right, aligned with the text ("same as book margins"), in 11dp serif on a line centered 33dp above the bottom.
local FOOTER = {
    settings = {
        page_progress = true, time = true,
        pages_left = false, battery = false, percentage = false, book_time_to_read = false, chapter_time_to_read = false,
        dynamic_filler = true, all_at_once = true, disable_progress_bar = true, progress_margin = true, text_book_margins = true,
        item_prefix = "letters", items_separator = "none", -- "87 / 648", not compact items' "87/648"
        text_font_size = 11, text_font_face = "./fonts/noto/NotoSerif-Regular.ttf",
        container_bottom_padding = 26,
    },
    order = { [0] = "off", "time", "dynamic_filler", "page_progress" },
}

local function footerSettings(footer)
    local util = require("util")
    local settings = util.tableDeepCopy(require("apps/reader/modules/readerfooter").default_settings)
    for k, v in pairs(footer.settings) do
        settings[k] = v
    end
    settings.order = util.tableDeepCopy(footer.order)
    return settings
end

--- Reading page footer, as in WeChat Read: the time at the left, the current page / pages at the right.
-- Only replaces a footer the user never customized, i.e. absent or still equal to upstream's defaults
-- (the one-time migration saves the default footer on first start) or to the first round's.
function ReaderToolbar.applyFooterDefaults()
    local util = require("util")
    local footer = G_reader_settings:readSetting("footer")
    if footer == nil or util.tableEquals(footer, require("apps/reader/modules/readerfooter").default_settings)
            or util.tableEquals(footer, footerSettings(FOOTER_V1)) then
        G_reader_settings:saveSetting("footer", footerSettings(FOOTER))
    end
end

function ReaderToolbar:initGesListener()
    if not Device:isTouchDevice() then return end
    -- The tap and the swipe use the original menu's zone ids, which links, highlights and the gestures
    -- plugin's corners and edges keep priority over. They and the pans also take over the bottom edge,
    -- where the original bottom menu (or the typeset panel) would open.
    local function zone(z) return { ratio_x = z.x, ratio_y = z.y, ratio_w = z.w, ratio_h = z.h } end
    local edge, edge_ext = unpack(bottomEdgeZones())
    self.ui:registerTouchZones({
        {
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
        {
            id = "readermenu_swipe",
            ges = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            overrides = {
                "rolling_swipe",
                "paging_swipe",
                "readerconfigmenu_ext_swipe",
                "readerconfigmenu_swipe",
            },
            handler = function(ges) return self:onSwipePage(ges) end,
        },
        {
            id = "readertoolbar_bottom_pan",
            ges = "pan",
            screen_zone = zone(edge),
            overrides = {
                "rolling_pan",
                "paging_pan",
                "readerconfigmenu_pan",
            },
            handler = function(ges) return self:onPanBottomEdge(ges) end,
        },
        {
            id = "readertoolbar_bottom_ext_pan",
            ges = "pan",
            screen_zone = zone(edge_ext),
            overrides = {
                "readertoolbar_bottom_pan",
                "readerconfigmenu_ext_pan",
            },
            handler = function(ges) return self:onPanBottomEdge(ges) end,
        },
    })
end

function ReaderToolbar:onReaderReady()
    self:initGesListener()
    -- each time a book opens, but not when a setting reloads it, nor when swipes don't show the toolbar,
    -- nor without a footer line to sit on (the text may then reach the bottom)
    if Device:isTouchDevice() and not self.ui.reloading and self.activation_menu ~= "tap"
            and self.view.footer_visible then
        self:showHint()
    end
end

-- Hiding the footer takes the open-book hint with it, for good.
function ReaderToolbar:onReaderFooterVisibilityChange()
    if self.hint and not self.view.footer_visible then
        self:dismissHint(true)
    end
end

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

-- Whether a swipe up from `pos` shows the toolbar: anywhere on a page, but only from the bottom edge in scroll
-- mode (where the original bottom menu opened), never when "Activate menu" leaves out swipes, and not while
-- a fixed-layout book's page or bookmark flipping mode takes the swipes.
function ReaderToolbar:swipeUpShowsToolbar(pos)
    if self.activation_menu == "tap" then return false end
    local paging = self.ui.paging
    if paging and (paging.page_flipping_mode or paging.bookmark_flipping_mode) then return false end
    if self.view.view_mode == "scroll" or self.view.page_scroll then
        local fx, fy = pos.x / Screen:getWidth(), pos.y / Screen:getHeight()
        for _, z in ipairs(bottomEdgeZones()) do
            if fx >= z.x and fx < z.x + z.w and fy >= z.y and fy < z.y + z.h then
                return true
            end
        end
        return false
    end
    return true
end

function ReaderToolbar:onSwipePage(ges)
    if ges.direction == "north" and self:swipeUpShowsToolbar(ges.pos) then
        self.ui:handleEvent(Event:new("HandledAsSwipe")) -- cancel any pan scroll made
        return self:showToolbar()
    end
end

-- A swipe starts with pans: those going up from the bottom edge wait for it, instead of opening the bottom menu.
function ReaderToolbar:onPanBottomEdge(ges)
    if ges.direction == "north" and self:swipeUpShowsToolbar(ges.start_pos or ges.pos) then
        return true
    end
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
    self.notes_return = nil
    self:dismissHint()
    self:hideToolbar(true)
    self:closeDrawer()
end

--- The contents page (目录页) takes over "ShowToc", from the toolbar and gestures alike;
-- the original table of contents stays in the original menu, which calls ReaderToc directly.
function ReaderToolbar:onShowToc()
    if not Device:isTouchDevice() then return end -- no D-pad navigation here: ReaderToc handles it
    self.notes_return = nil
    self:hideToolbar(true) -- the page covers the bars
    self:closeDrawer()
    self.drawer = require("apps/reader/modules/readertocpage"):new{
        ui = self.ui,
        on_close = function() self.drawer = nil end,
        on_bookmarks = function() self.ui:handleEvent(Event:new("ShowNotes", "bookmarks")) end,
    }
    UIManager:show(self.drawer, "ui", self.drawer.dimen)
    return true
end

--- "ShowNotes" always opens all notes from the bottom bar, or bookmarks from the contents page's 书签.
-- Only Back after a card jump restores the previous filter and list page.
function ReaderToolbar:onShowNotes(filter)
    if not Device:isTouchDevice() then return end
    self.notes_return = nil
    self:hideToolbar(true) -- the page covers the bars
    self:closeDrawer()
    local page
    page = require("apps/reader/modules/readernotespage"):new{
        ui = self.ui,
        filter = filter,
        on_close = function()
            if self.drawer == page then self.drawer = nil end
        end,
        on_jump = function() self.notes_return = { filter = page.filter } end,
    }
    self.drawer = page
    UIManager:show(page, "ui", page.dimen)
    return true
end

function ReaderToolbar:onBack()
    if self.notes_return then
        return self:onShowNotes(self.notes_return.filter)
    end
end

--- The notes page shown follows the notes as they change (not consumed: other modules want it too).
function ReaderToolbar:onAnnotationsModified()
    if self.drawer and self.drawer.refresh then
        self.drawer:refresh()
    end
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

--- The top bar: its icons at the right, from left to right 书签 and 更多 (书架状态 goes between them,
-- future 繁简 and 手写 entries to their left; nothing holds their place).
function ReaderToolbar:buildTopBar()
    local sw = Screen:getWidth()
    local rule = Size.border.default
    local row_h = TOP_H - rule
    local function iconButton(icon, callback)
        local pad_h = math.floor((TOP_CELL_W - ICON_SIZE) / 2)
        local pad_v = math.floor((row_h - ICON_SIZE) / 2)
        return IconButton:new{
            icon = icon, width = ICON_SIZE, height = ICON_SIZE,
            padding_left = pad_h, padding_right = TOP_CELL_W - ICON_SIZE - pad_h,
            padding_top = pad_v, padding_bottom = row_h - ICON_SIZE - pad_v,
            allow_flash = false, callback = callback,
        }
    end
    self.bookmark_button = iconButton(self:bookmarkIcon(), function() self:toggleBookmark() end)
    return FrameContainer:new{
        bordersize = 0, padding = 0, background = Palette.paper,
        VerticalGroup:new{
            RightContainer:new{
                dimen = Geom:new{ w = sw, h = row_h },
                HorizontalGroup:new{
                    self.bookmark_button,
                    iconButton("eink/more", function() self:togglePanel("more") end),
                },
            },
            LineWidget:new{ dimen = Geom:new{ w = sw, h = rule }, background = Palette.rule },
        },
    }
end

--- The bottom bar: back (to the shelf), a short rule, then 目录, 笔记, 进度 and 字体 sharing the rest, with
-- the icon of the `active` panel's entry filled. There is no slot for 听. With `back_only`, it holds only
-- the back arrow of full-screen pages, which leaves a nested panel.
function ReaderToolbar:buildBottomBar(active, back_only)
    local sw = Screen:getWidth()
    local rule = Size.border.default
    local row_h = BOTTOM_H - rule
    local row
    if back_only then
        row = LeftContainer:new{
            dimen = Geom:new{ w = sw, h = row_h },
            EinkControls.BackArrow:new{ height = row_h, callback = function() self:goBack() end },
        }
    else
        local cell_w = math.floor((sw - BACK_W - rule) / 4)
        local function cell(icon, name, callback)
            return ToolbarCell:new{
                icon = name ~= nil and name == active and icon .. ".bold" or icon,
                width = cell_w, height = row_h, callback = callback,
            }
        end
        row = HorizontalGroup:new{
            align = "center",
            EinkControls.BackArrow:new{ width = BACK_W, height = row_h, callback = function() self:backToShelf() end },
            LineWidget:new{ dimen = Geom:new{ w = rule, h = RULE_H }, background = Palette.rule },
            cell("eink/toc", nil, function() self.ui:handleEvent(Event:new("ShowToc")) end),
            cell("eink/notes", nil, function() self.ui:handleEvent(Event:new("ShowNotes")) end),
            cell("eink/progress", "progress", function() self:togglePanel("progress") end),
            cell("eink/font", "font", function() self:togglePanel("font") end),
        }
    end
    return FrameContainer:new{
        bordersize = 0, padding = 0, background = Palette.paper,
        VerticalGroup:new{
            align = "left", -- what the cells' rounding leaves goes to the right
            LineWidget:new{ dimen = Geom:new{ w = sw, h = rule }, background = Palette.rule },
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

-- Shows the bars, around the panel if one is set. The first time, the open-book hint goes.
function ReaderToolbar:openBars()
    self.bars = ToolbarBars:new{ toolbar = self }
    local hint = self.hint
    if hint then
        -- under the bottom bar, it just isn't painted again
        self:dismissHint(not (hint.dimen and self.bars.bottom_rect:contains(hint.dimen)))
    end
    UIManager:show(self.bars) -- no refresh of its own: only the bars and the panel below
    if self.bars.show_top then
        UIManager:setDirty(nil, "ui", self.bars.top_rect)
    end
    UIManager:setDirty(nil, "ui", self.bars:getBandRect())
end

--- Shows the open-book hint on the footer line, for about a minute (ReaderToolbarHint.TIMEOUT).
function ReaderToolbar:showHint()
    self.hint = ReaderToolbarHint:new{}
    self.view:registerViewModule("toolbar_hint", self.hint) -- painted with the page, until dismissed
    self.hint_timeout = self.hint_timeout or function() self:dismissHint(true) end
    UIManager:scheduleIn(ReaderToolbarHint.TIMEOUT, self.hint_timeout)
end

--- Takes the open-book hint away for good; with `refresh`, repaints where it was ("fast").
function ReaderToolbar:dismissHint(refresh)
    local hint = self.hint
    if not hint then return end
    self.hint = nil
    UIManager:unschedule(self.hint_timeout)
    hint.shown = false -- it stays a view module, which paints nothing now
    hint:free()
    if refresh and hint.dimen then
        UIManager:setDirty(self.view.dialog, "fast", hint.dimen)
    end
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
-- with the bars it keeps. `name` is its entry ("progress", "brightness", "more" or "font").
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

--- "ShowToolbarPanel" opens a panel with the bars from elsewhere than its entry (another panel, a page,
-- a gesture): "progress", "brightness", "more" or "font".
function ReaderToolbar:onShowToolbarPanel(name)
    if not Device:isTouchDevice() then return end
    self:openPanel(name)
    return true
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
    if not button then return end -- no bars: nothing to do on every page turn or scroll step
    local icon = self:bookmarkIcon()
    if button.icon ~= icon then
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
