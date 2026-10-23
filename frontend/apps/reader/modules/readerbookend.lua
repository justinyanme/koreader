-- The page after the last body page (Q01-Q04). Its position stays in the document;
-- a backward turn returns to that page, and a jump from the toolbars dismisses this one.
local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FinishedBooks = require("finishedbooks")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local FullscreenPage = require("ui/widget/fullscreenpage")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local Toast = require("ui/widget/toast")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")
local T = require("ffi/util").template

local function dp(n) return Screen:scaleBySize(n) end

local function text(str, role, width)
    return TextWidget:new{ text = str, face = Font:getFace(role), fgcolor = Palette.ink, max_width = width }
end

local BookEnd = FullscreenPage:extend{}

function BookEnd:init()
    FullscreenPage.init(self)
    self.stats = self.ui.statistics and self.ui.statistics:getStatsBookStatus()
    if Device:hasKeys() then
        self.key_events.ShowMenu = Device:hasFewKeys() and { { { "Menu", "Right" } } } or { { "Menu" } }
    end
    self:build()
end

local function shortDate(timestamp)
    return T(_.pgettext("Book end date", "%1/%2"), tonumber(os.date("%m", timestamp)), tonumber(os.date("%d", timestamp)))
end

local function statText(str, size, width, bold)
    return TextWidget:new{
        text = str, face = Font:getFace("ui_label", size), bold = bold, padding = 0,
        fgcolor = Palette.ink, max_width = width,
    }
end

function BookEnd:buildStatistics(width)
    local stats = self.stats
    local minutes = stats and math.floor(stats.time / 60)
    local started, last_read
    if stats and stats.first_read then
        started = T(_("Started reading on %1"), shortDate(stats.first_read))
    end
    if stats and stats.last_read then
        local date = os.date("%Y-%m-%d", stats.last_read)
        local yesterday = os.date("*t")
        yesterday.day = yesterday.day - 1
        local label = date == os.date("%Y-%m-%d") and _("Today")
            or date == os.date("%Y-%m-%d", os.time(yesterday)) and _("Yesterday")
            or shortDate(stats.last_read)
        last_read = T(_("Last read · %1"), label)
    end
    local count = #self.ui.annotation.annotations
    local values = {
        { _.pgettext("Book end", "Total reading time"), minutes, _.pgettext("Time", "min"), started },
        { _("Reading days"), stats and stats.days, _.npgettext("Book end unit", "day", "days", stats and stats.days or 0), last_read },
        { _.pgettext("Book end", "Thoughts and notes"), count, _.npgettext("Book end unit", "note", "notes", count), count > 0 and _("A book full of highlights") or nil },
    }
    local pad = dp(20)
    local inner_w = width - 2 * (pad + Size.border.default)
    local widths = { math.floor(inner_w * 0.44), math.floor(inner_w * 0.41) }
    widths[3] = inner_w - widths[1] - widths[2]
    local row = HorizontalGroup:new{ align = "top" }
    for i, value in ipairs(values) do
        local cell_w = widths[i]
        local number = HorizontalGroup:new{
            align = "bottom", statText(value[2] and tostring(value[2]) or "—", 18, cell_w, true),
        }
        if value[2] then
            table.insert(number, statText(value[3], 11, cell_w, true))
        end
        local caption = value[4] and statText(value[4], 10, cell_w - (i == 3 and dp(9) or 0))
        if i == 3 and caption then
            caption = HorizontalGroup:new{
                caption, IconWidget:new{ icon = "eink/chev", width = dp(9), height = dp(9), alpha = true, dim = true },
            }
        end
        local content = VerticalGroup:new{
            align = "left", statText(value[1], 11, cell_w, true),
            VerticalSpan:new{ width = dp(3) }, number,
            VerticalSpan:new{ width = dp(2) },
            LeftContainer:new{ dimen = Geom:new{ w = cell_w, h = dp(14) }, caption or VerticalSpan:new{ width = dp(14) } },
        }
        local cell = LeftContainer:new{ dimen = Geom:new{ w = cell_w, h = dp(90) }, content }
        if i == 3 then
            cell = InputContainer:new{ dimen = cell.dimen:copy(), cell }
            cell.ges_events.Notes = { GestureRange:new{ ges = "tap", range = cell.dimen } }
            cell.onNotes = function() self.ui:handleEvent(Event:new("ShowNotes")) return true end
            self.notes_button = cell
        end
        table.insert(row, cell)
    end
    return FrameContainer:new{
        padding = 0, padding_left = pad, padding_right = pad,
        bordersize = Size.border.default, radius = dp(16), color = Palette.ink, row,
    }
end

-- 读完的第 N 本, filling the inner circle of `size` as in the reference: the template's first line small, 18% down,
-- over its number large, just below the middle, between the rest of that line small.
local function finishedEmblem(number, size)
    -- @translators The emblem of a finished book, numbering it among the books marked finished; Chinese: 读完的第\n%1本. The first line is shown small, the number (%1) large and the words beside it small.
    local template = _.pgettext("Book end", "Finished book\nNo. %1")
    local caption, line = template:match("^(.-)\n(.*)$")
    if not caption then caption, line = "", template end
    local before, after = line:match("^(.-)%%1(.*)$")
    if not before then before, after = line, "" end
    local function row(number_size)
        local digits = TextWidget:new{
            text = tostring(number), face = Font:getFace("ui_headword", number_size), padding = 0, fgcolor = Palette.ink,
        }
        local function word(str)
            local widget = statText(str, math.floor(number_size * 0.45), nil, true)
            return VerticalGroup:new{ VerticalSpan:new{ width = digits:getBaseline() - widget:getBaseline() }, widget }
        end
        local group = HorizontalGroup:new{ align = "top" }
        if before ~= "" then table.insert(group, word(before)) end
        table.insert(group, digits)
        if after ~= "" then table.insert(group, word(after)) end
        return group, digits
    end
    local max_w = size - dp(28)
    local number_size = math.floor(62 * size / dp(128)) -- smaller in a smaller circle (landscape)
    local number_row, digits = row(number_size)
    if number_row:getSize().w > max_w then
        number_size = math.floor(number_size * max_w / number_row:getSize().w)
        number_row:free()
        number_row, digits = row(number_size)
    end
    local label = statText(caption, 11, max_w, true)
    local label_top = math.floor(size * 0.185 - label:getSize().h / 2)
    -- Lining figures are about 0.7em high, so their middle is 0.35em above the baseline.
    local row_top = math.floor(size / 2 + dp(6) + 0.35 * digits.face.size) - digits:getBaseline()
    return CenterContainer:new{
        dimen = Geom:new{ w = size, h = size }, ignore = "height",
        VerticalGroup:new{
            align = "center", VerticalSpan:new{ width = label_top }, label,
            VerticalSpan:new{ width = math.max(0, row_top - label_top - label:getSize().h) }, number_row,
        },
    }
end

-- Whether the book was marked or unmarked finished since the page was built; book details does it
-- without a reader event.
function BookEnd:finishedChanged()
    local summary = self.ui.doc_settings:readSetting("summary")
    return self.finished ~= (summary.status == "complete") or self.finished_time ~= summary.finished_time
end

function BookEnd:build()
    local sw, sh = self.dimen.w, self.dimen.h
    local width = math.min(dp(460), sw - 2 * dp(24))
    -- The finished number is counted for the status shown, not again when notes or rotation rebuild the page.
    if self:finishedChanged() then
        local summary = self.ui.doc_settings:readSetting("summary")
        self.finished, self.finished_time = summary.status == "complete", summary.finished_time
        self.finished_number = FinishedBooks.number(self.ui.document.file, summary)
    end
    local finished = self.finished
    local column = VerticalGroup:new{ align = "center" }
    local function at(y, widget)
        table.insert(column, VerticalSpan:new{ width = math.max(0, y - column:getSize().h) })
        table.insert(column, widget)
        column:resetLayout()
    end
    at(math.floor(sh * 0.065), TextWidget:new{
        text = finished and _.pgettext("Book end", "Finished") or _("The End"),
        face = Font:getFace("ui_headword", 20), max_width = width,
    })
    local diameter = math.min(dp(128), math.floor(sh * 0.18))
    local inner = diameter - 2 * Size.border.default
    local emblem
    if self.finished_number then
        emblem = finishedEmblem(self.finished_number, inner)
    else
        -- @translators The single word in the circular book-end emblem; Chinese: 完.
        emblem = TextWidget:new{ text = _.pgettext("Book end", "End"), face = Font:getFace("ui_headword", 90) }
        local size = math.min(90, math.floor(90 * (diameter - dp(16)) / emblem:getSize().w))
        emblem:free()
        emblem = TextWidget:new{ text = _.pgettext("Book end", "End"), face = Font:getFace("ui_headword", size) }
    end
    self.emblem = FrameContainer:new{
        bordersize = Size.border.default, padding = 0, radius = math.floor(diameter / 2), color = Palette.ink_3,
        CenterContainer:new{ dimen = Geom:new{ w = inner, h = inner }, emblem },
    }
    at(math.floor(sh * 0.122), self.emblem)
    self.mark_button = nil
    if not finished then
        local label = text(_.pgettext("Book end", "Mark as finished"), "ui_label_large", width)
        self.mark_button = InputContainer:new{ dimen = Geom:new{ w = width, h = dp(44) } }
        self.mark_button[1] = CenterContainer:new{
            dimen = self.mark_button.dimen:copy(),
            VerticalGroup:new{
                align = "center", label,
                LineWidget:new{ dimen = Geom:new{ w = label:getSize().w, h = Size.border.default }, background = Palette.ink },
            },
        }
        self.mark_button.ges_events.Mark = { GestureRange:new{ ges = "tap", range = self.mark_button.dimen } }
        self.mark_button.onMark = function() self:markFinished() return true end
        at(math.floor(sh * 0.275), self.mark_button)
    end

    at(math.floor(sh * 0.368), self:buildStatistics(width))
    self.state_rect = Geom:new{ x = math.floor((sw - width) / 2), w = width, h = column:getSize().h }
    self.exit_button = Button:new{
        text = _("Exit reading"), width = width, height = dp(44), radius = dp(12),
        text_font_face = "ui_title", text_font_size = Font.sizemap.ui_title, allow_flash = false,
        callback = function() self.status:openFileBrowser() end,
    }
    at(math.max(column:getSize().h + dp(16), sh - dp(74)), self.exit_button)
    if self[1] then self[1]:free() end
    self[1] = FrameContainer:new{
        bordersize = 0, padding = 0, background = Palette.paper,
        CenterContainer:new{ dimen = self.dimen:copy(), ignore = "height", column },
    }
end

function BookEnd:refresh()
    self:build()
    UIManager:setDirty(self, "ui", self.state_rect)
end

-- Book details changes the same summary without a reader event; read it back when uncovered.
function BookEnd:paintTo(bb, x, y)
    if self:finishedChanged() then
        self:refresh()
    end
    FullscreenPage.paintTo(self, bb, x, y)
end

function BookEnd:markFinished()
    local summary = self.ui.doc_settings:readSetting("summary")
    local old_status, old_modified, old_finished = summary.status, summary.modified, summary.finished_time
    self.status:markBook(true)
    if not self.ui.doc_settings:flush() then
        summary.status, summary.modified, summary.finished_time = old_status, old_modified, old_finished
        BookList.setBookInfoCacheProperty(self.ui.document.file, "status", old_status)
        UIManager:show(Toast:new{ text = _("Could not save the book status.") })
        return
    end
    self:refresh()
end

function BookEnd:onShowMenu()
    return self.ui.menu:onShowMenu()
end

function BookEnd:goBack()
    self.status:closeBookEnd()
end

function BookEnd:onNextPage()
    return true
end

function BookEnd:onPrevPage()
    self:goBack()
    return true
end

function BookEnd:onTapBlock(_, ges)
    local menu = self.ui.menu
    -- The original ReaderMenu, still supported without the toolbar replacement, has no tap layout.
    local layout = menu.getTapLayout and menu:getTapLayout() or {
        { 0, 0, 1/3, 1, "backward" }, { 1/3, 0, 1/3, 1, "toolbar" }, { 2/3, 0, 1/3, 1, "forward" },
    }
    local x, y = ges.pos.x / self.dimen.w, ges.pos.y / self.dimen.h
    for _, zone in ipairs(layout) do
        if x >= zone[1] and x < zone[1] + zone[3] and y >= zone[2] and y < zone[2] + zone[4] then
            if zone[5] == "backward" then self:goBack()
            elseif zone[5] == "toolbar" then menu:onShowMenu() end
            break
        end
    end
    return true
end

function BookEnd:onSwipe(_, ges)
    if ges.direction == "north" then
        self.ui.menu:onShowMenu()
    else
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        local backward = self.ui.view.inverse_reading_order and "west" or "east"
        if direction == backward or direction == "south" then
            self:goBack()
        elseif direction ~= "west" and direction ~= "east" then
            return false -- let the reader's screenshot action take diagonal swipes
        end
    end
    return true
end

BookEnd.onCloseWidget = BookEnd.free

return BookEnd
