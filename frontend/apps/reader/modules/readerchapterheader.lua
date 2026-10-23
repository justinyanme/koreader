--[[--
Page header of the e-ink redesign (see DESIGN.md, Layout: reading page): a
circled ‹ and the current chapter title, drawn in the top margin of reflowable
books, as in WeChat Read (00-entry/02-book-open.png): 11dp serif ink, centered
in the top margin and aligned with the text.

crengine's own header (the alt status bar) has no chapter-only mode, so this is
a view module painted over the page. It is skipped whenever the top margin is
too small to hold it with a gap above and below, so it never overlaps the text.
It is part of the page and repaints with it.
]]

local Font = require("ui/font")
local IconWidget = require("ui/widget/iconwidget")
local Palette = require("ui/palette")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen

local ReaderChapterHeader = Widget:extend{
    -- set by ReaderView:registerViewModule()
    view = nil,
    ui = nil,
}

ReaderChapterHeader.FACE = "NotoSerif-Regular.ttf" -- CJK titles fall back to Noto Sans CJK SC
ReaderChapterHeader.SIZE = 11
ReaderChapterHeader.GAP = 4 -- dp, minimum above the header and between it and the text
ReaderChapterHeader.ICON = 12 -- dp, the circled ‹ before the title
ReaderChapterHeader.ICON_GAP = 4 -- dp

function ReaderChapterHeader:getTitle()
    local title = self.ui.toc:getTocTitleOfCurrentPage()
    if not title or title == "" then
        title = self.ui.doc_props and self.ui.doc_props.display_title
    end
    return title
end

-- Mirrors when ReaderFlipping:paintTo() draws an icon for reflowable books.
function ReaderChapterHeader:flippingIconShown()
    local ui = self.ui
    local highlight = ui.highlight
    if highlight and (highlight.select_mode or highlight.long_hold_reached) then return true end
    return ui.rolling.rendering_state ~= nil and self.view.flipping:getRollingRenderingStateIconWidget() ~= nil
end

function ReaderChapterHeader:paintTo(bb, x, y)
    local ui = self.ui
    if not ui.rolling or not ui.document or self.view.view_mode ~= "page"
            or ui.document.configurable.status_line == 0 then -- crengine's top status bar has the room
        return
    end
    local title = self:getTitle()
    if not title or title == "" then return end
    local margins = ui.document:getPageMargins()
    local left = margins.left
    if self:flippingIconShown() then
        -- ReaderFlipping's icon (re-rendering, selection) sits in the top left corner: start after it
        left = math.max(left, Screen:scaleBySize(36 + self.GAP)) -- its icons are 32 or 36dp
    end
    local icon_size = Screen:scaleBySize(self.ICON)
    local text_x = left + icon_size + Screen:scaleBySize(self.ICON_GAP)
    local width = Screen:getWidth() - text_x - margins.right
    local widget = TextWidget:new{
        text = title,
        face = Font:getFace(self.FACE, self.SIZE),
        fgcolor = Palette.ink,
        max_width = width,
    }
    local text_h = widget:getSize().h
    local h = math.max(text_h, icon_size)
    local top = math.floor((margins.top - h) / 2)
    if width > 0 and top >= Screen:scaleBySize(self.GAP) then
        local icon = IconWidget:new{ icon = "eink/chapter", width = icon_size, height = icon_size, alpha = true }
        icon:paintTo(bb, x + left, y + top + math.floor((h - icon_size) / 2))
        icon:free()
        widget:paintTo(bb, x + text_x, y + top + math.floor((h - text_h) / 2))
    end
    widget:free()
end

return ReaderChapterHeader
