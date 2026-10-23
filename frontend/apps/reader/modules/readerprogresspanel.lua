--[[--
进度面板 of the e-ink redesign (see DESIGN.md, Panels), opened from the reader
toolbar's "Progress": three reading statistics, and a capsule track with chapter
arrows.

Dragging the track's knob only previews: the knob and the position figure
follow the finger ("ui" refreshes of those two), and the page moves once, on
release. A jump that has to wait for the book's layout (pending after a
typesetting change) first covers the page with 加载中….

The first jump from the panel keeps the position it left, the 原进度, until the
reader goes back to it or the bars close: later jumps keep it. A gray dot marks
it on the track (only a mark: a tap there is a tap on the track), and an outline
pill ‹ 返回原进度 just above the panel goes back to it and closes the panel and
the bars. While a drag goes on without one, the dot marks where the reader is.

Changing the position re-lays out the page as a page turn does ("partial");
the panel then re-renders with a "ui" refresh of its own rect.

@usage
    toolbar:showPanel("progress", ReaderProgressPanel:new{ toolbar = toolbar })
]]

local Device = require("device")
local CenterContainer = require("ui/widget/container/centercontainer")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
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
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext

-- The 原进度 of each toolbar: { location = a ReaderLink location, bars = the ToolbarBars it was kept in }.
-- It lapses when those bars close.
local origins = setmetatable({}, { __mode = "k" })

-- The chapter targets occupy the ends of the capsule; the knob travels between them.
local ProgressTrack = InputContainer:extend{
    width = nil,
    page = 1,
    page_count = 1,
    previous_chapter = nil,
    next_chapter = nil,
    origin_page = nil, -- the page of the 原进度, marked by a gray dot
    on_jump = nil, -- function(page)
    on_preview = nil, -- function(page): the page under the finger while dragging, nil once it lifts
    -- while dragging, and once let go until the jump lands
    preview_page = nil, -- the page the knob shows
    held = false, -- whether the finger is still down
    hold_pos = nil, -- where the last hold started, on the track or not
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
    -- A drag goes on wherever the finger goes once it started on the track, so its moves and its lift
    -- are matched anywhere; each handler checks where the drag started.
    local pan_rate = Screen.low_pan_rate and 2.0 or 5.0
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldStart = { GestureRange:new{ ges = "hold" } },
        DragMove = {
            GestureRange:new{ ges = "pan", rate = pan_rate },
            GestureRange:new{ ges = "hold_pan", rate = pan_rate },
        },
        DragRelease = {
            GestureRange:new{ ges = "pan_release" },
            GestureRange:new{ ges = "hold_release" },
        },
        DragSwipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
end

function ProgressTrack:xOf(page)
    return self.inset + math.floor((page - 1) / math.max(1, self.page_count - 1) * (self.width - 2 * self.inset) + 0.5)
end

-- The page at screen abscissa `x`, past the ends included.
function ProgressTrack:pageAt(x)
    local fraction = (x - self.dimen.x - self.inset) / (self.width - 2 * self.inset)
    return math.max(1, math.min(self.page_count, math.floor(fraction * (self.page_count - 1) + 1.5)))
end

function ProgressTrack:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local mid = y + math.floor(self.dimen.h / 2)
    local r = self.knob_radius
    local pos = self:xOf(self.preview_page or self.page)
    local track_h = Screen:scaleBySize(35)
    local track_r = math.floor(track_h / 2)
    bb:paintRoundedRect(x, mid - track_r, self.width, track_h, Palette.mark, track_r)
    bb:paintRoundedRect(x, mid - track_r, pos + track_r, track_h, Palette.ink, track_r)
    local origin = self.origin_page or (self.preview_page and self.page)
    if origin then
        local dot = self:xOf(origin)
        if dot > pos then
            -- on the gray part, an ink outline keeps it visible
            bb:paintCircle(x + dot, mid, r, Palette.ink)
            bb:paintCircle(x + dot, mid, r - Size.border.default, Palette.mark)
        else
            bb:paintCircle(x + dot, mid, r, Palette.mark)
        end
    end
    if self.held then
        -- an ink knob in a paper ring
        bb:paintCircle(x + pos, mid, r, Palette.paper)
        bb:paintCircle(x + pos, mid, r - Size.border.button, Palette.ink)
    else
        bb:paintCircle(x + pos, mid, r, Palette.ink)
        bb:paintCircle(x + pos, mid, r - Size.border.button, Palette.paper)
    end
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
        target = self:pageAt(ges.pos.x)
    end
    if target and target ~= self.page then
        self.on_jump(target)
    end
    return true
end

local function sideways(ges)
    return ges.direction ~= "north" and ges.direction ~= "south"
end

-- Forgets a drag whose finger lifted where the track did not see it (a window on top took the release).
function ProgressTrack:dropDrag()
    if self.held or self.preview_page then
        self.held = false
        self.preview_page = nil
        self.on_preview(nil)
    end
end

-- Notes where a hold starts, without taking it: its release is a tap only if it started on the track.
function ProgressTrack:onHoldStart(_, ges)
    self.hold_pos = ges.pos
end

-- A move that started on the track, and not straight up or down, drags the knob. A move that started
-- elsewhere is another gesture: any drag left over is over.
function ProgressTrack:onDragMove(_, ges)
    if not (ges.start_pos and self.dimen:contains(ges.start_pos)) then
        self:dropDrag()
        return
    end
    if not self.held then
        if not sideways(ges) then return end
        self.held = true
    end
    local page = self:pageAt(ges.pos.x)
    if page ~= self.preview_page then
        self.preview_page = page
        self.on_preview(page)
    end
    return true
end

-- The finger lifts: the jump, if it moved the knob off the page. A hold on the track that did not drag is a tap.
function ProgressTrack:onDragRelease(_, ges)
    if self.held then
        return self:release(ges.pos.x)
    end
    if ges.ges == "hold_release" then
        local start = ges.start_pos or self.hold_pos
        self.hold_pos = nil
        if start and self.dimen:contains(start) and self.dimen:contains(ges.pos) then
            return self:onTapSelect(nil, ges)
        end
    end
end

-- A quick drag ends as a swipe, reported from where it started.
function ProgressTrack:onDragSwipe(_, ges)
    if self.held or sideways(ges) then
        return self:release(ges.end_pos.x)
    end
end

function ProgressTrack:free()
    self.held = false
    self.preview_page = nil
    self.hold_pos = nil
    InputContainer.free(self)
end

-- The knob rests where it was let go while the page jumps there (the panel then shows the page reached).
function ProgressTrack:release(x)
    local target = self:pageAt(x)
    self.held = false
    if target ~= self.page then
        self.preview_page = target
        self.on_jump(target)
    else
        self.preview_page = nil
        self.on_preview(nil)
    end
    return true
end

------------------------------------------------------------------------

-- One of the three statistics: a figure and its unit over a caption, tappable with `callback`.
local Statistic = InputContainer:extend{
    value = nil,
    unit = nil,
    label = nil,
    width = nil,
    callback = nil,
}

function Statistic:init()
    local unit = TextWidget:new{
        text = self.unit, face = Font:getFace("ui_label"), bold = true,
        fgcolor = Palette.ink, max_width = math.floor(self.width / 2),
    }
    self.figure = TextWidget:new{
        text = self.value, face = Font:getFace("ui_headline", 24), bold = true,
        fgcolor = Palette.ink, max_width = self.width - unit:getSize().w,
    }
    self.figure_row = HorizontalGroup:new{ align = "bottom", self.figure, unit }
    self.content = VerticalGroup:new{
        self.figure_row,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        TextWidget:new{
            text = self.label or "", face = Font:getFace("ui_label"), bold = true,
            fgcolor = Palette.ink, max_width = self.width,
        },
    }
    self.dimen = Geom:new{ w = self.width, h = math.max(Screen:scaleBySize(48), self.content:getSize().h) }
    self[1] = CenterContainer:new{ dimen = self.dimen:copy(), self.content }
    if self.callback then
        self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
end

--- Shows another figure in place.
function Statistic:setValue(value)
    self.figure:setText(value)
    self.figure_row:resetLayout()
    self.content:resetLayout()
end

function Statistic:onTapSelect()
    self.callback()
    return true
end

------------------------------------------------------------------------

-- ‹ 返回原进度: an outline pill with a chevron (as tall as the paragraph pill), in a 44dp tall touch target.
local ReturnPill = InputContainer:extend{
    callback = nil,
    pill_height = Screen:scaleBySize(29),
}

function ReturnPill:init()
    local h = self.pill_height
    local bw = Size.border.default
    local chev = Screen:scaleBySize(14)
    local pad = Screen:scaleBySize(10)
    local label = HorizontalGroup:new{
        align = "center",
        IconWidget:new{ icon = "eink/chev", width = chev, height = chev, alpha = true, rotation_angle = 180 },
        HorizontalSpan:new{ width = Screen:scaleBySize(3) },
        TextWidget:new{ text = _("Back to original position"), face = Font:getFace("ui_label"), fgcolor = Palette.ink, padding = 0 },
    }
    local w = label:getSize().w + 2 * (pad + bw)
    self.dimen = Geom:new{ w = w, h = Screen:scaleBySize(44) }
    self[1] = CenterContainer:new{
        dimen = self.dimen:copy(),
        FrameContainer:new{
            bordersize = bw, padding = 0, radius = math.floor(h / 2),
            color = Palette.ink, background = Palette.paper,
            CenterContainer:new{ dimen = Geom:new{ w = w - 2 * bw, h = h - 2 * bw }, label },
        },
    }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function ReturnPill:onTapSelect()
    self.callback()
    return true
end

------------------------------------------------------------------------

-- The position within the current flow (the whole book without hidden flows): page and pages.
local function flowPosition(document, page)
    if document:hasHiddenFlows() then
        return document:getPageNumberInFlow(page), document:getTotalPagesInFlow(document:getPageFlow(page))
    end
    return page, document:getPageCount()
end

local function percentOf(document, page)
    local current, total = flowPosition(document, page)
    return math.floor(current / total * 100)
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

-- Whether a jump waits for the book's layout: after a typesetting change, partial rendering (KOReader's
-- default) lays a reflowable book out again only where it is shown until its background rendering is done
-- and the book reloaded, so a jump lays out the target's chapter before it can show it. Once the background
-- rendering is ready, the reload waits for the reader to be idle: jumps don't wait for it.
local function jumpWaitsForLayout(ui)
    local rolling = ui.rolling
    if not rolling then return false end
    local state, states = rolling.rendering_state, rolling.RENDERING_STATE
    return state == states.PARTIALLY_RERENDERED or state == states.FULL_RENDERING_IN_BACKGROUND
        or state == states.RELOADING_DOCUMENT
end

-- The gap between the bottom of the 返回原进度 pill and the panel's top edge, as measured on the Leaf5.
local PILL_GAP = Screen:scaleBySize(26)

local ReaderProgressPanel = Panel:extend{
    toolbar = nil, -- ReaderToolbar
    -- built with the content
    position = nil, -- the position's Statistic
    track = nil, -- ProgressTrack
    pill = nil, -- ReturnPill, while there is a 原进度
    pill_rect = nil, -- where the pill shows, if the last paint showed it
}

ReaderProgressPanel.onAnnotationsModified = Panel.refresh

--- The 原进度 (a ReaderLink location) while the bars it was kept in show.
function ReaderProgressPanel:getOrigin()
    local origin = origins[self.toolbar]
    return origin and origin.bars == self.toolbar.bars and origin.location or nil
end

function ReaderProgressPanel:jump(target)
    local ui = self.toolbar.ui
    -- kept once the jump is done: one that fails leaves neither
    local origin = not self:getOrigin() and ui.link:getCurrentLocation()
    local left = ui.link:getCurrentLocation()
    local loading, loading_rect
    if jumpWaitsForLayout(ui) then
        loading, loading_rect = self:showLoading()
    end
    local ok, err = pcall(ui.handleEvent, ui, Event:new("GotoPage", target))
    if loading then
        -- the page takes its place once laid out, with the jump's own repaint; without a jump, the page as it was
        if ok then
            UIManager:close(loading)
        else
            UIManager:close(loading, "ui", loading_rect)
        end
    end
    if not ok then
        error(err, 0)
    end
    if origin then
        origins[self.toolbar] = { location = origin, bars = self.toolbar.bars }
    end
    ui.link:addCurrentLocationToStack(left)
    self:refresh()
end

--- Covers the page between the bars with 加载中… (centered on the screen, as in WeChat Read), until the next
-- repaint; the knob let go shows at rest meanwhile. Returns the cover and the rect it covers.
function ReaderProgressPanel:showLoading()
    local bars = self.show_parent
    local top = bars.show_top and bars.top_rect.h or 0
    local rect = Geom:new{ x = 0, y = top, w = Screen:getWidth(), h = self:getRefreshRegion().y - top }
    local label = TextWidget:new{ text = _("Loading…"), face = Font:getFace("ui_label"), bold = true, fgcolor = Palette.ink }
    local label_h = label:getSize().h
    local above = math.floor(Screen:getHeight() / 2) - top - math.floor(label_h / 2)
    local cover = FrameContainer:new{
        bordersize = 0, padding = 0, background = Palette.paper,
        width = rect.w, height = rect.h,
        VerticalGroup:new{
            VerticalSpan:new{ width = math.max(0, math.min(rect.h - label_h, above)) },
            CenterContainer:new{ dimen = Geom:new{ w = rect.w, h = label_h }, label },
        },
    }
    UIManager:setDirty(bars, "ui", self.track.dimen)
    UIManager:show(cover, "ui", rect, rect.x, rect.y)
    UIManager:forceRePaint() -- before the jump keeps the reader busy
    return cover, rect
end

--- Goes back to the 原进度, closing the panel and the bars.
function ReaderProgressPanel:returnToOrigin()
    local toolbar = self.toolbar
    local location = self:getOrigin()
    origins[toolbar] = nil
    toolbar:hideToolbar()
    toolbar.ui.link:addCurrentLocationToStack()
    toolbar.ui:handleEvent(Event:new("RestoreBookLocation", location))
end

--- Shows the page under the finger while the knob is dragged (`page`), or the current one again (nil).
function ReaderProgressPanel:preview(page)
    local document = self.toolbar.ui.document
    self.position:setValue(tostring(percentOf(document, page or self.track.page)))
    UIManager:setDirty(self.show_parent, "ui", self.position.dimen)
    UIManager:setDirty(self.show_parent, "ui", self.track.dimen)
end

function ReaderProgressPanel:buildContent()
    local ui = self.toolbar.ui
    local toc = ui.toc
    local w = Panel.getContentWidth()
    local page = ui:getCurrentPage()
    local page_count = ui.document:getPageCount()

    local current_page, total_pages = flowPosition(ui.document, page)
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
    local origin = self:getOrigin()
    local current_start = chapterStart(toc, page)
    self.position = Statistic:new{
        value = tostring(percentOf(ui.document, page)), unit = "%", label = estimate, width = column_w,
    }
    self.track = ProgressTrack:new{
        width = w, page = page, page_count = page_count,
        previous_chapter = current_start and toc:getPreviousChapter(current_start),
        next_chapter = toc:getNextChapter(page),
        origin_page = origin and locationPage(ui, origin),
        on_jump = function(p) self:jump(p) end,
        on_preview = function(p) self:preview(p) end,
    }
    if self.pill then
        self.pill:free()
    end
    self.pill = origin and ReturnPill:new{ callback = function() self:returnToOrigin() end }
    local content = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            self.position,
            divider(),
            Statistic:new{ value = duration, unit = unit, label = _("Reading time"), width = column_w },
            divider(),
            Statistic:new{
                value = tostring(count), unit = " " .. N_("item", "items", count), label = C_("Notes page", "Notes"),
                width = w - 2 * column_w - 2 * rule,
                callback = function() ui:handleEvent(Event:new("ShowNotes")) end,
            },
        },
        VerticalSpan:new{ width = Screen:scaleBySize(20) },
        self.track,
    }
    if ui.autoturn then
        table.insert(content, VerticalSpan:new{ width = Screen:scaleBySize(20) })
        table.insert(content, require("apps/reader/modules/readerautoturn").Button:new{
            text = ui.autoturn:_enabled() and _("Autoturn settings") or _("Start autoturn"),
            width = w, height = Screen:scaleBySize(35), bordersize = Size.border.default,
            face = Font:getFace("ui_label"),
            callback = function()
                self.toolbar:hideToolbar()
                if ui.autoturn:_enabled() then
                    ui.autoturn:showSettings()
                else
                    ui.autoturn:start()
                end
            end,
        })
    end
    return content
end

function ReaderProgressPanel:build()
    Panel.build(self)
    self[2] = self.pill -- painted above the panel, see paintTo(); receives its taps as a child
end

function ReaderProgressPanel:paintTo(bb, x, y)
    Panel.paintTo(self, bb, x, y)
    local pill = self.pill
    self.pill_rect = nil
    if pill then
        local size = pill:getSize()
        local pill_h = pill.pill_height
        pill:paintTo(bb, x + math.floor((self.dimen.w - size.w) / 2),
            y - PILL_GAP - pill_h - math.floor((size.h - pill_h) / 2))
        self.pill_rect = pill.dimen:copy()
    end
end

function ReaderProgressPanel:free()
    -- the page shows again where the pill was painted, whether the bars close or switch panels
    if self.pill_rect then
        UIManager:setDirty(self.toolbar.view.dialog, "ui", self.pill_rect)
        self.pill_rect = nil
    end
    Panel.free(self)
end

return ReaderProgressPanel
