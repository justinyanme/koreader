--[[--
进度面板 of the e-ink redesign (see DESIGN.md, Panels), opened from the reader
toolbar's "Progress": the chapter and position, a position track with chapter
ticks, previous/next chapter, and a way back to the last position.

Changing the position re-lays out the page as a page turn does ("partial");
the panel then re-renders with a "ui" refresh of its own rect.

@usage
    toolbar:showPanel("progress", ReaderProgressPanel:new{ toolbar = toolbar })
]]

local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local Panel = require("ui/widget/panel")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local function text(str, face, color, max_width)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width }
end

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

local ReaderProgressPanel = Panel:extend{
    toolbar = nil, -- ReaderToolbar
}

function ReaderProgressPanel:jump(target)
    local ui = self.toolbar.ui
    ui.link:addCurrentLocationToStack()
    ui:handleEvent(Event:new("GotoPage", target))
    self:refresh()
end

function ReaderProgressPanel:buildContent()
    local ui = self.toolbar.ui
    local toc = ui.toc
    local w = Panel.getContentWidth()
    local page = ui:getCurrentPage()
    local page_count = ui.document:getPageCount()

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
            ticks = toc:getTocTicks(1) or {}, on_jump = function(p) self:jump(p) end, -- top-level chapters only
        },
        VerticalSpan:new{ width = Screen:scaleBySize(18) },
        HorizontalGroup:new{
            EinkControls.PillButton:new{
                text = _("Previous chapter"), width = button_w, enabled = prev ~= nil,
                callback = function() self:jump(prev) end,
            },
            HorizontalSpan:new{ width = w - 2 * button_w },
            EinkControls.PillButton:new{
                text = _("Next chapter"), width = button_w, enabled = next ~= nil,
                callback = function() self:jump(next) end,
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
        table.insert(group, LineWidget:new{ dimen = Geom:new{ w = w, h = Screen:scaleBySize(1) }, background = Palette.rule })
        table.insert(group, Panel.Row:new{
            height = Screen:scaleBySize(48),
            label = text(T(_("Return to last position: %1, page %2"),
                           chapterTitle(last_page), (last_done or last_page - 1) + 1),
                         "ui_label_large", Palette.ink, w - chev),
            right = IconWidget:new{ icon = "eink/chev", width = chev, height = chev, alpha = true },
            callback = function()
                ui.link:onGoBackLink()
                self:refresh()
            end,
        })
    end
    return group
end

return ReaderProgressPanel
