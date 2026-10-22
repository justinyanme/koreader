--[[--
Page header of the e-ink redesign (see DESIGN.md, Layout: reading page): the
current chapter title, drawn in the top margin of reflowable books.

crengine's own header (the alt status bar) has no chapter-only mode, so this is
a view module painted over the page. It sits at 14dp, aligned with the text,
and is skipped whenever the top margin is too small to hold it, so it never
overlaps the text. It is part of the page and repaints with it.
]]

local Font = require("ui/font")
local Palette = require("ui/palette")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen

local ReaderChapterHeader = Widget:extend{
    -- set by ReaderView:registerViewModule()
    view = nil,
    ui = nil,
}

ReaderChapterHeader.TOP = 14 -- dp
ReaderChapterHeader.GAP = 4 -- dp, minimum between the header and the text

function ReaderChapterHeader:getTitle()
    local title = self.ui.toc:getTocTitleOfCurrentPage()
    if not title or title == "" then
        title = self.ui.doc_props and self.ui.doc_props.display_title
    end
    return title
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
    local top = Screen:scaleBySize(self.TOP)
    local width = Screen:getWidth() - margins.left - margins.right
    local widget = TextWidget:new{
        text = title,
        face = Font:getFace("ui_caption"),
        fgcolor = Palette.ink_2,
        max_width = width,
    }
    if width > 0 and top + widget:getSize().h + Screen:scaleBySize(self.GAP) <= margins.top then
        widget:paintTo(bb, x + margins.left, y + top)
    end
    widget:free()
end

return ReaderChapterHeader
