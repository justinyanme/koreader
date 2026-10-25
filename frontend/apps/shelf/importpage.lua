--[[--
导入 (CONTEXT.md), after WeChat Read's import page (15-supplement/02-import-instructions.png): one card with a
section per way of putting books into the home folder, and a circled × centered under it. The reference's
WeChat routes are replaced by KOReader's own: 浏览设备文件 (to 文件), 从书源下载 (to 书源, with the OPDS
plugin only) and 从电脑传书 (USB, or calibre's wireless connection with its plugin), which names the real home
folder. Each section ends with a gray tile, where the reference has its illustration, that takes the route.
Where the home folder is the app's sandbox (iOS), the first route is the system's document picker instead, which
copies books in (apps/shelf/bookimport), and the device says how to transfer books from a computer.

The page copies nothing itself. 书源 opens over it, so leaving 书源 comes back here; 文件 shows in the file
manager under it, so the page closes and shows again when 文件 is left. The calibre tile starts the plugin's
wireless connection, which reports its own progress. Showing and closing repaint the whole screen with "ui".
Closing rescans the home folder once the shelf shows again, so the shelf lists what came into it
meanwhile (over USB, say); the grid is only redrawn if that changed it.
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
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Notification = require("ui/widget/notification")
local Palette = require("ui/palette")
local Shelf = require("apps/shelf/shelf")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext

local function dp(n) return Screen:scaleBySize(n) end

-- as measured on the reference
local CARD_W = dp(458) -- at most
local MARGIN = dp(24) -- the least space beside the card
local PADDING = dp(20)
local RADIUS = dp(19)
local SECTION_GAP = dp(24)
local TILE_H = dp(56)
local TILE_RADIUS = dp(12) -- DESIGN.md's choice radius; the reference's illustrations are about 10dp
local CLOSE_D = dp(57)
local CLOSE_GAP = dp(34) -- the least space between the card and the ×
local CLOSE_BOTTOM = dp(44) -- under the ×

local ImportPage = InputContainer:extend{
    ui = nil, -- the file manager
}

--- Shows the page over the file manager `fm`.
function ImportPage.show(fm)
    local page = ImportPage:new{ ui = fm }
    UIManager:show(page, "ui", page.dimen)
    return page
end

function ImportPage:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    self.ges_events = {
        TapBlock = { GestureRange:new{ ges = "tap", range = self.dimen } }, -- nothing reaches the shelf below
    }
    if Device:hasKeys() then
        self.key_events.Back = { { Device.input.group.Back } }
    end
    self:build()
end

--- The routes, each { title, text, path, tile = { icon, text, callback } }; path and tile are optional.
function ImportPage:routes()
    local fm = self.ui
    local sandboxed = Device:hasSandboxedHome()
    local routes = {
        sandboxed and {
            title = _("Import from Files"),
            text = _("Pick books in the Files app, including iCloud Drive. They're copied into the home folder."),
            tile = { icon = "eink/folder", text = _("Choose files"),
                callback = function() Device.importFile(Shelf.homeDir()) end },
        } or {
            title = _("Browse device files"),
            text = _("Find books in any folder on the device, then open them or copy them into the home folder."),
            tile = { icon = "eink/folder", text = _("Files"), callback = function() self:openFiles() end },
        },
    }
    if fm.opds then
        table.insert(routes, {
            title = _("Download from book sources"),
            text = _("Download books from the OPDS sources you added. By default they go into the home folder."),
            tile = { icon = "eink/compass", text = C_("Import page", "Book sources"),
                callback = function() fm:switchTab("sources") end },
        })
    end
    local computer = {
        title = _("Transfer from a computer"),
        text = _("Copy books into the home folder over USB."),
        path = Shelf.homeDir(),
    }
    if sandboxed then
        computer.text, computer.path = Device:getTransferInstructions(), nil
    elseif fm.calibre then
        computer.text = _("Copy books into the home folder over USB, or send them from calibre wirelessly.")
    end
    if fm.calibre then
        computer.tile = { icon = "eink/computer", text = _("Calibre wireless connection"),
            callback = function() self:connectCalibre() end }
    end
    table.insert(routes, computer)
    return routes
end

--- A route's tint tile: an icon, the route's name, and a chevron at the right.
function ImportPage:buildTile(tile, w)
    local inset, icon_size, gap, chev_size = dp(16), dp(24), dp(12), dp(18)
    local label_w = w - 2 * inset - icon_size - gap - chev_size - dp(8)
    return ShelfWidgets.Tappable:new{
        callback = tile.callback,
        FrameContainer:new{
            bordersize = 0,
            padding = 0,
            radius = TILE_RADIUS,
            background = Palette.tint,
            LeftContainer:new{
                dimen = Geom:new{ w = w, h = TILE_H },
                HorizontalGroup:new{
                    align = "center",
                    HorizontalSpan:new{ width = inset },
                    IconWidget:new{ icon = tile.icon, width = icon_size, height = icon_size, alpha = true },
                    HorizontalSpan:new{ width = gap },
                    LeftContainer:new{
                        dimen = Geom:new{ w = label_w + dp(8), h = TILE_H },
                        TextWidget:new{ text = tile.text, face = Font:getFace("ui_title"), fgcolor = Palette.ink,
                            max_width = label_w },
                    },
                    -- in ink: dim lightens its whole rect, which shows as a box on the tint
                    IconWidget:new{ icon = "eink/chev", width = chev_size, height = chev_size, alpha = true },
                },
            },
        },
    }
end

-- A route: the headline, what to do, the home folder where it matters, and the tile.
function ImportPage:buildSection(route, w)
    local body = Font:getFace("ui_body", 16)
    local section = VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = route.title, face = Font:getFace("ui_headline", 20), fgcolor = Palette.ink, max_width = w },
        VerticalSpan:new{ width = dp(6) },
        TextBoxWidget:new{ text = route.text, face = body, fgcolor = Palette.ink, width = w },
    }
    if route.path then
        table.insert(section, VerticalSpan:new{ width = dp(4) })
        table.insert(section, TextBoxWidget:new{ text = T(_("Home folder: %1"), BD.dirpath(route.path)), face = body,
            bold = true, fgcolor = Palette.ink, width = w })
    end
    if route.tile then
        table.insert(section, VerticalSpan:new{ width = dp(14) })
        table.insert(section, self:buildTile(route.tile, w))
    end
    return section
end

function ImportPage:buildClose()
    local border = Size.border.button
    self.close_button = ShelfWidgets.Tappable:new{
        callback = function() self:close() end,
        FrameContainer:new{
            bordersize = border,
            color = Palette.ink,
            background = Palette.paper,
            radius = math.floor(CLOSE_D / 2),
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = CLOSE_D - 2 * border, h = CLOSE_D - 2 * border },
                IconWidget:new{ icon = "eink/close", width = dp(28), height = dp(28), alpha = true },
            },
        },
    }
    return self.close_button
end

--- The × centered 44dp from the bottom, as in the reference, and the card centered in the space above it;
-- where the card is too tall for that (landscape), the × sits beside it instead.
function ImportPage:build()
    local screen_w, screen_h = self.dimen.w, self.dimen.h
    local column_h = screen_h - CLOSE_BOTTOM - CLOSE_D - CLOSE_GAP -- the most the card can take above the ×
    local function buildCard(card_w)
        local inner_w = card_w - 2 * (PADDING + Size.border.default)
        local sections = VerticalGroup:new{ align = "left" }
        for i, route in ipairs(self:routes()) do
            if i > 1 then table.insert(sections, VerticalSpan:new{ width = SECTION_GAP }) end
            table.insert(sections, self:buildSection(route, inner_w))
        end
        return FrameContainer:new{
            bordersize = Size.border.default,
            color = Palette.ink,
            background = Palette.paper,
            radius = RADIUS,
            padding = PADDING,
            sections,
        }
    end
    local card = buildCard(math.min(CARD_W, screen_w - 2 * MARGIN))
    local layout
    local card_h = card:getSize().h
    if card_h <= column_h then
        local top = math.floor((column_h - card_h) / 2)
        layout = VerticalGroup:new{
            VerticalSpan:new{ width = top },
            CenterContainer:new{ dimen = Geom:new{ w = screen_w, h = card_h }, card },
            VerticalSpan:new{ width = column_h - top - card_h + CLOSE_GAP },
            CenterContainer:new{ dimen = Geom:new{ w = screen_w, h = CLOSE_D }, self:buildClose() },
        }
    else
        card:free()
        card = buildCard(math.min(CARD_W, screen_w - 2 * MARGIN - CLOSE_GAP - CLOSE_D))
        local close = self:buildClose()
        layout = CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = screen_h },
            HorizontalGroup:new{ align = "bottom", card, HorizontalSpan:new{ width = CLOSE_GAP }, close },
        }
    end
    self.card = card
    if self[1] then self[1]:free() end
    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        background = Palette.paper,
        width = screen_w,
        height = screen_h,
        layout,
    }
end

-- Closes the page with no refresh, for what shows next to repaint the screen.
function ImportPage:dismiss()
    if self.closed then return end
    self.closed = true
    UIManager:close(self)
end

--- The × and Back: back to the shelf, rescanned for what came in while the page was open.
function ImportPage:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui", self.dimen)
    -- the shelf on screen first: walking a large home folder (all of the shared storage, on Android) takes a
    -- while. Tasks run before the repaint, even tickAfterNext's with a coarse clock, so it is drawn now.
    UIManager:forceRePaint()
    local fm = self.ui
    UIManager:nextTick(function()
        if UIManager:isWidgetShown(fm) then
            fm.shelf_view:rescan()
        end
    end)
end

--- The calibre tile: starts the plugin's wireless connection, which shows its own progress and errors (and
-- asks for the folder books go to, the first time); connected already, says so.
function ImportPage:connectCalibre()
    local wireless = package.loaded["wireless"] -- the plugin's connection, as 我 → 同步与传书 reads it
    if wireless and wireless.calibre_socket then
        UIManager:show(Notification:new{ text = _("Connected") })
        return
    end
    self.ui:handleEvent(Event:new("StartWirelessConnection"))
end

--- 浏览设备文件: 文件 shows under the page, which shows again when 文件 is left.
function ImportPage:openFiles()
    local fm = self.ui
    self:dismiss() -- 文件 repaints the content and the band: the whole screen
    fm:openFiles(function() ImportPage.show(fm) end)
end

function ImportPage:onBack()
    self:close()
    return true
end

function ImportPage:onTapBlock()
    return true
end

-- A book opening from 书源 over the page closes the file manager under it: go with it.
function ImportPage:onShowingReader()
    self:dismiss()
end

return ImportPage
