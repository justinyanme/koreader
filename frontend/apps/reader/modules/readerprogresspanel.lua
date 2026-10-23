--[[--
进度面板 of the e-ink redesign (see DESIGN.md, Panels), opened from the reader
toolbar's "Progress": three reading statistics, a capsule track with chapter
arrows, and a way back to the last position.

Changing the position re-lays out the page as a page turn does ("partial");
the panel then re-renders with a "ui" refresh of its own rect.

@usage
    toolbar:showPanel("progress", ReaderProgressPanel:new{ toolbar = toolbar })
]]

local Device = require("device")
local CenterContainer = require("ui/widget/container/centercontainer")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
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
local C_ = _.pgettext
local N_ = _.ngettext

local function text(str, face, color, max_width)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width }
end

-- The chapter targets occupy the ends of the capsule; the knob travels between them.
local ProgressTrack = InputContainer:extend{
    width = nil,
    page = 1,
    page_count = 1,
    previous_chapter = nil,
    next_chapter = nil,
    on_jump = nil, -- function(page)
}

function ProgressTrack:init()
    self.dimen = Geom:new{ w = self.width, h = Screen:scaleBySize(44) }
    self.knob_radius = Screen:scaleBySize(16.5)
    self.end_width = Screen:scaleBySize(44)
    self.inset = self.end_width + self.knob_radius
    self[1] = TextWidget:new{
        text = "‹", face = Font:getFace("ui_body", 26),
        fgcolor = self.previous_chapter and Palette.paper or Palette.ink_3,
    }
    self[2] = TextWidget:new{
        text = "›", face = Font:getFace("ui_body", 26),
        fgcolor = self.next_chapter and Palette.ink or Palette.ink_3,
    }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function ProgressTrack:xOf(page)
    return self.inset + math.floor((page - 1) / math.max(1, self.page_count - 1) * (self.width - 2 * self.inset) + 0.5)
end

function ProgressTrack:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local mid = y + math.floor(self.dimen.h / 2)
    local r = self.knob_radius
    local pos = self:xOf(self.page)
    local track_h = Screen:scaleBySize(35)
    local track_r = math.floor(track_h / 2)
    bb:paintRoundedRect(x, mid - track_r, self.width, track_h, Palette.mark, track_r)
    bb:paintRoundedRect(x, mid - track_r, pos + track_r, track_h, Palette.ink, track_r)
    bb:paintCircle(x + pos, mid, r, Palette.ink)
    bb:paintCircle(x + pos, mid, r - Size.border.button, Palette.paper)
    for i, cx in ipairs{ x + r, x + self.width - r } do
        local size = self[i]:getSize()
        self[i]:paintTo(bb, cx - math.floor(size.w / 2), mid - math.floor(size.h / 2))
    end
end

function ProgressTrack:onTapSelect(_, ges)
    local x = ges.pos.x - self.dimen.x
    local target
    if x < self.end_width then
        target = self.previous_chapter
    elseif x > self.width - self.end_width then
        target = self.next_chapter
    else
        local fraction = (x - self.inset) / (self.width - 2 * self.inset)
        target = math.max(1, math.min(self.page_count, math.floor(fraction * (self.page_count - 1) + 1.5)))
    end
    if target and target ~= self.page then
        self.on_jump(target)
    end
    return true
end

local function statistic(value, unit, label, width, callback)
    local unit_widget = TextWidget:new{
        text = unit, face = Font:getFace("ui_label"), bold = true,
        fgcolor = Palette.ink, max_width = math.floor(width / 2),
    }
    local figure = TextWidget:new{
        text = value, face = Font:getFace("ui_headline", 24), bold = true,
        fgcolor = Palette.ink, max_width = width - unit_widget:getSize().w,
    }
    local content = VerticalGroup:new{
        HorizontalGroup:new{ align = "bottom", figure, unit_widget },
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        TextWidget:new{
            text = label or "", face = Font:getFace("ui_label"), bold = true,
            fgcolor = Palette.ink, max_width = width,
        },
    }
    local dimen = Geom:new{ w = width, h = math.max(Screen:scaleBySize(48), content:getSize().h) }
    local column = InputContainer:new{
        dimen = dimen,
        CenterContainer:new{ dimen = dimen:copy(), content },
    }
    if callback then
        column.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = dimen } } }
        column.onTapSelect = function() callback() return true end
    end
    return column
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

ReaderProgressPanel.onAnnotationsModified = Panel.refresh

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
    local current_page, total_pages = page, page_count
    if ui.document:hasHiddenFlows() then
        local flow = ui.document:getPageFlow(page)
        current_page = ui.document:getPageNumberInFlow(page)
        total_pages = ui.document:getTotalPagesInFlow(flow)
    end
    local percent = math.floor(current_page / total_pages * 100)
    local remaining_pages = total_pages - current_page
    local stats = ui.statistics
    local duration, unit, estimate = "—", "", nil
    if stats and stats:isEnabled() then
        -- Use per-page-capped saved time plus timed session visits, as the estimate and notes page do, not the raw lifetime sum.
        local minutes = math.floor(((stats.book_read_time or 0) + (stats.mem_read_time or 0)) / 60)
        duration = minutes < 60 and tostring(minutes) or string.format("%.1f", minutes / 60)
        unit = minutes < 60 and C_("Time", "min") or C_("Time", "h")
        local read_pages = (stats.book_read_pages or 0) + (stats.mem_read_pages or 0)
        -- The plugin seeds avg_time even for an unread book: only use measured page times.
        if remaining_pages > 0 and read_pages > 0 and stats.avg_time and stats.avg_time > 0 and stats.avg_time < math.huge then
            local hours = math.max(1, math.ceil(stats.avg_time * remaining_pages / 3600))
            estimate = T(N_("About 1 hour left", "About %1 hours left", hours), hours)
        end
    end
    local count = ui.annotation:getNumberOfAnnotations()
    local rule = Size.border.default
    local column_w = math.floor((w - 2 * rule) / 3)
    local function divider()
        return LineWidget:new{
            dimen = Geom:new{ w = rule, h = Screen:scaleBySize(40) }, background = Palette.confirm_rule,
        }
    end
    local current_start = chapterStart(toc, page)
    local prev = current_start and toc:getPreviousChapter(current_start)
    local next = toc:getNextChapter(page)
    local group = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            statistic(tostring(percent), "%", estimate, column_w),
            divider(),
            statistic(duration, unit, _("Reading time"), column_w),
            divider(),
            statistic(tostring(count), " " .. N_("item", "items", count), C_("Notes page", "Notes"),
                w - 2 * column_w - 2 * rule, function() ui:handleEvent(Event:new("ShowNotes")) end),
        },
        VerticalSpan:new{ width = Screen:scaleBySize(20) },
        ProgressTrack:new{
            width = w, page = page, page_count = page_count,
            previous_chapter = prev, next_chapter = next, on_jump = function(p) self:jump(p) end,
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
