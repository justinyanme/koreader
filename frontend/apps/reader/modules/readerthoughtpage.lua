-- Local thought cards and detail, after 07-selection-and-lookup/08 and 09.
-- The cards wash the reader; detail uses a paper page. Both repaint with "ui"
-- because the wash changes gray levels. Long thoughts paginate without truncation.
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmLayer = require("ui/widget/confirmlayer")
local EinkControls = require("ui/widget/einkcontrols")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local FullscreenPage = require("ui/widget/fullscreenpage")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext

local function dp(n) return Screen:scaleBySize(n) end

local ThoughtPage = FullscreenPage:extend{
    ui = nil,
    item = nil, -- the annotation itself: indexes can change when other notes change
    detail = false,
    stop_events_propagation = true,
}

function ThoughtPage:init()
    FullscreenPage.init(self)
    self.covers_fullscreen = false
    self.alpha = Palette.wash.a / 0xFF -- asks UIManager to repaint the reader before washing it again
    self:build()
end

local function text(str, width, role, height)
    return TextBoxWidget:new{
        text = str or "", face = Font:getFace(role or "ui_body"), fgcolor = Palette.ink,
        width = width, height = height, height_adjust = true,
        height_overflow_show_ellipsis = height ~= nil,
    }
end

local function card(content)
    return FrameContainer:new{
        padding = dp(20), radius = dp(14), bordersize = dp(0.94),
        color = Palette.ink, background = Palette.paper, content,
    }
end

function ThoughtPage:buildContent(rect)
    local width = self.detail and rect.w - 2 * dp(22) or math.min(dp(416), rect.w - 2 * dp(22))
    local padding = dp(20) + dp(0.94)
    local inner = self.detail and width or width - 2 * padding
    local quote = text(util.cleanupSelectedText(self.item.text), inner, "ui_body", dp(70))
    local quote_link = ShelfWidgets.Tappable:new{
        callback = function() self:jump() end,
        self.detail and CenterContainer:new{
            dimen = Geom:new{ w = inner, h = math.max(dp(44), quote:getSize().h) }, quote,
        } or card(quote),
    }
    local column = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = dp(32) } }
    local footer = VerticalGroup:new{ align = "left" }
    if not self.detail then
        table.insert(column, quote_link)
        table.insert(column, VerticalSpan:new{ width = dp(12) })
    else
        table.insert(footer, VerticalSpan:new{ width = dp(16) })
        table.insert(footer, LineWidget:new{ dimen = Geom:new{ w = width, h = dp(0.94) }, background = Palette.rule })
        table.insert(footer, VerticalSpan:new{ width = dp(12) })
        table.insert(footer, quote_link)
        table.insert(footer, VerticalSpan:new{ width = dp(12) })
        table.insert(footer, ShelfWidgets.Tappable:new{
            callback = function() self:jump() end,
            HorizontalGroup:new{
                self:buildCover(), HorizontalSpan:new{ width = dp(16) },
                VerticalGroup:new{
                    align = "left",
                    text(self.ui.doc_props.display_title, width - dp(58), "ui_title", dp(48)),
                    text(self.ui.doc_props.authors, width - dp(58), "ui_label", dp(24)),
                },
            },
        })
        table.insert(footer, VerticalSpan:new{ width = dp(16) })
        table.insert(footer, text(_("Only visible to you"), width, "ui_label"))
        table.insert(footer, ShelfWidgets.Tappable:new{
            callback = function() self:confirmDelete() end,
            CenterContainer:new{
                dimen = Geom:new{ w = width, h = dp(44) },
                text(C_("Thought editor", "Delete note"), width, "ui_label"),
            },
        })
    end
    local heading = text(_("Thought"), inner, "ui_title")
    local note_h = math.max(dp(44), rect.h - column:getSize().h - footer:getSize().h
        - heading:getSize().h - dp(12 + 16) - (self.detail and 0 or 2 * padding))
    local note = TextBoxWidget:new{
        text = self.item.note, face = Font:getFace("ui_body"), fgcolor = Palette.ink,
        width = inner, height = note_h, height_adjust = true,
        virtual_line_num = (self.page - 1) * (self.lines_per_page or 1) + 1,
    }
    self.lines_per_page = note.lines_per_page
    local pages = math.max(1, math.ceil(#note.vertical_string_list / note.lines_per_page))
    local body = VerticalGroup:new{
        align = "left", heading, VerticalSpan:new{ width = dp(12) }, note,
    }
    if not self.detail then
        table.insert(column, ShelfWidgets.Tappable:new{
            callback = function() self:showDetail() end, card(body),
        })
    else
        table.insert(column, body)
        table.insert(column, footer)
    end
    column:resetLayout()
    self.content = HorizontalGroup:new{
        HorizontalSpan:new{ width = math.floor((rect.w - width) / 2) }, column,
    }
    return self.content, pages
end

-- The detail's cover is 42 × 60dp in reference 09, smaller than the notes overview.
function ThoughtPage:buildCover()
    if self.cover == nil then
        self.cover = self.ui.bookinfo and self.ui.bookinfo:getCoverImage(self.ui.document) or false
    end
    local props = self.ui.doc_props
    return ShelfWidgets.cover({ title = props.display_title, authors = props.authors }, dp(42), dp(60),
        self.cover or nil, true)
end

function ThoughtPage:buildBarParts()
    return nil, { EinkControls.PillButton:new{
        text = C_("Highlight bubble", "Edit note"), face = Font:getFace("ui_label"), height = dp(44),
        callback = function() self:edit() end,
    } }
end

function ThoughtPage:paintTo(bb, x, y)
    if self.detail then
        return FullscreenPage.paintTo(self, bb, x, y)
    end
    ConfirmLayer.wash(bb, x, y, self.dimen.w, self.dimen.h)
    -- Leave the reader visible through the empty space between the cards and the bar.
    self.content:paintTo(bb, x, y)
    bb:paintRect(x, y + self.content_rect.h, self.dimen.w, self.bar:getSize().h, Palette.paper)
    self.bar:paintTo(bb, x, y + self.content_rect.h)
end

function ThoughtPage:showDetail()
    self.detail, self.covers_fullscreen, self.page, self.lines_per_page = true, true, 1, nil
    self.alpha = nil
    self:build()
    UIManager:setDirty(self, "ui", self.dimen)
end

function ThoughtPage:edit()
    local index = util.arrayContains(self.ui.annotation.annotations, self.item)
    if not index then return self:goBack() end
    self.ui.highlight:showNoteSheet(index, function()
        if self.closed then return end
        if not self.item.note or not util.arrayContains(self.ui.annotation.annotations, self.item) then
            return self:goBack()
        end
        self.page, self.lines_per_page = 1, nil
        self:build()
        UIManager:setDirty(self, "ui", self.dimen)
    end)
end

function ThoughtPage:confirmDelete()
    self.confirm = ConfirmLayer:new{
        text = C_("Thought editor", "Delete this note?"),
        actions = { { text = _("Delete"), callback = function()
            local index = util.arrayContains(self.ui.annotation.annotations, self.item)
            if index then self.ui.highlight:setNote(index, "") end
            self:goBack()
        end } },
        on_close = function() self.confirm = nil end,
    }
    UIManager:show(self.confirm, "ui", self.confirm:getRefreshRegion())
end

function ThoughtPage:jump()
    self:goBack()
    self.ui.link:addCurrentLocationToStack()
    self.ui.bookmark:gotoBookmark(self.item.page, self.item.pos0)
end

function ThoughtPage:onCloseWidget()
    if self.confirm then self.confirm:onClose() end
    if self.on_close then self.on_close() end
    self[1]:free()
    if self.cover then self.cover:free() end
end

return ThoughtPage
