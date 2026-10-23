--[[--
Open-book hint of the reader toolbar (see DESIGN.md, Reader toolbars): "↑ Swipe up to show the toolbar"
in pencil gray, centered on the footer line, as in WeChat Read (15-supplement/10-open-book-toolbar-hint.png).

ReaderToolbar shows it each time a book opens, as a view module: it is part of the page and stays through
page turns, until the toolbar first shows or TIMEOUT seconds have passed, and never comes back for that
book until it opens again. It lays a paper ground under itself, over whatever a customized footer centers
on its line, and the footer paints it again when it repaints alone (its refreshes on resume, frontlight or
charging changes).

@usage
    ui.view:registerViewModule("toolbar_hint", ReaderToolbarHint:new{})
]]

local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local Palette = require("ui/palette")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen
local _ = require("gettext")

local ReaderToolbarHint = Widget:extend{
    -- set by ReaderView:registerViewModule()
    view = nil,
    ui = nil,
    shown = true, -- false once dismissed
    dimen = nil, -- where it was last painted
    paints_over_footer = true, -- so that ReaderFooter paints it again when it repaints itself alone
}

ReaderToolbarHint.TIMEOUT = 60 -- seconds: "about a minute" (DECISIONS.md, B05)

function ReaderToolbarHint:init()
    local arrow = Screen:scaleBySize(18)
    self.content = HorizontalGroup:new{
        align = "center",
        IconWidget:new{ icon = "eink/swipe-up", width = arrow, height = arrow, alpha = true },
        HorizontalSpan:new{ width = Screen:scaleBySize(2) },
        TextWidget:new{ text = _("Swipe up to show the toolbar"), face = Font:getFace("ui_micro"), fgcolor = Palette.ink_2 },
    }
end

function ReaderToolbarHint:paintTo(bb, x, y)
    if not self.shown then return end
    local size = self.content:getSize()
    local pad = Screen:scaleBySize(8)
    -- the footer's text sits in the middle of a band of its height, above its bottom padding; the reference's
    -- hint sits a little higher than the time and page beside it
    local footer = self.view.footer
    local center_y = Screen:getHeight() - footer.bottom_padding - math.floor(footer.height / 2) - Screen:scaleBySize(3)
    self.dimen = Geom:new{
        x = math.floor((Screen:getWidth() - size.w) / 2) - pad,
        y = math.min(center_y - math.floor(size.h / 2), Screen:getHeight() - size.h),
        w = size.w + 2 * pad,
        h = size.h,
    }
    bb:paintRect(x + self.dimen.x, y + self.dimen.y, self.dimen.w, self.dimen.h, Palette.paper)
    self.content:paintTo(bb, x + self.dimen.x + pad, y + self.dimen.y)
end

function ReaderToolbarHint:free()
    self.content:free()
end

return ReaderToolbarHint
