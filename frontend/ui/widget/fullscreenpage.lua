--[[--
Full-screen page of the e-ink redesign, after WeChat Read's list pages (settings, contents, notes):
a paper page with an optional title band on top, the content, and the bottom bar
(@{ui.widget.einkcontrols}.BottomBar) with the back arrow on the left and the page capsule on
the right. Lists are paginated, never scrolled.

A page extends it and implements buildContent(rect), which returns the widget of `self.page`,
fitting `rect`, and the number of pages. Its init sets `title` (the band exists only if there is
one by then), calls FullscreenPage.init(), sets up its own state, then calls build(), which puts
the page together; goToPage() turns pages. The back arrow and the Back key call goBack(), which
closes the page unless overridden.

Showing and closing the page repaint it whole, and turning a page repaints the content and the
bar (`body_rect`), all with "ui". Taps never reach what is under the page. A swipe west or north,
or a page-forward key, turns to the next page; east or south, or a page-back key, to the previous one.

@usage
    local NotesPage = FullscreenPage:extend{ title = _("Notes") }
    function NotesPage:init()
        FullscreenPage.init(self)
        self.notes = ...
        self:build()
    end
    function NotesPage:buildContent(rect) ... return list, page_count end
    local page = NotesPage:new{}
    UIManager:show(page, "ui", page.dimen)
]]

local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Palette = require("ui/palette")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local GUTTER = Screen:scaleBySize(24)

local FullscreenPage = InputContainer:extend{
    title = nil, -- shown in the title band; without one at init, the page has no band
    title_align = "center", -- or "left"
    page = 1,
    page_count = 1,
}
FullscreenPage.TITLE_H = Screen:scaleBySize(56)

function FullscreenPage:init()
    local w, h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    self.covers_fullscreen = true
    local title_h = self.title and FullscreenPage.TITLE_H or 0
    self.title_rect = Geom:new{ x = 0, y = 0, w = w, h = title_h }
    self.content_rect = Geom:new{ x = 0, y = title_h, w = w, h = h - title_h - EinkControls.BottomBar.height }
    self.body_rect = Geom:new{ x = 0, y = title_h, w = w, h = h - title_h }
    self.ges_events.TapBlock = { GestureRange:new{ ges = "tap", range = self.dimen } }
    self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.Back = { { Device.input.group.Back } }
        self.key_events.NextPage = { { Device.input.group.PgFwd } }
        self.key_events.PrevPage = { { Device.input.group.PgBack } }
    end
end

--- Returns the widget of page `self.page` fitting `rect`, and the number of pages; clamps `self.page` first.
function FullscreenPage:buildContent(rect) -- luacheck: ignore 212
    return VerticalGroup:new{}, 1
end

function FullscreenPage:buildTitle()
    local rect = self.title_rect
    local title = TextWidget:new{
        text = self.title, face = Font:getFace("ui_title"), bold = true, fgcolor = Palette.ink,
        max_width = rect.w - 2 * GUTTER,
    }
    if self.title_align == "left" then
        return LeftContainer:new{
            dimen = Geom:new{ w = rect.w, h = rect.h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, title },
        }
    end
    return CenterContainer:new{ dimen = Geom:new{ w = rect.w, h = rect.h }, title }
end

--- (Re)builds the page around buildContent().
function FullscreenPage:build()
    local content, page_count = self:buildContent(self.content_rect)
    self.page_count = page_count
    local column = VerticalGroup:new{ align = "left" }
    if self.title_rect.h > 0 then
        table.insert(column, self:buildTitle())
    end
    table.insert(column, content)
    table.insert(column, VerticalSpan:new{ width = math.max(0, self.content_rect.h - content:getSize().h) })
    self.bar = EinkControls.BottomBar:new{
        width = self.dimen.w, page = self.page, pages = page_count,
        on_change = function(page) self:goToPage(page) end,
        on_back = function() self:goBack() end,
    }
    table.insert(column, self.bar)
    if self[1] then
        self[1]:free()
    end
    self[1] = FrameContainer:new{ bordersize = 0, padding = 0, background = Palette.paper, column }
end

function FullscreenPage:goToPage(page)
    if page == self.page or page < 1 or page > self.page_count then return end
    self.page = page
    self:build()
    UIManager:setDirty(self, "ui", self.body_rect)
end

--- The back arrow and the Back key: closes the page.
function FullscreenPage:goBack()
    UIManager:close(self, "ui", self.dimen)
end

function FullscreenPage:onBack()
    self:goBack()
    return true
end

function FullscreenPage:onNextPage()
    self:goToPage(self.page + 1)
    return true
end

function FullscreenPage:onPrevPage()
    self:goToPage(self.page - 1)
    return true
end

function FullscreenPage:onSwipe(_, ges)
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" or direction == "north" then
        self:goToPage(self.page + 1)
    elseif direction == "east" or direction == "south" then
        self:goToPage(self.page - 1)
    end
    return true
end

function FullscreenPage:onTapBlock()
    return true
end

return FullscreenPage
