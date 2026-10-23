--[[--
What is left of the old contents drawer: the pieces other pages still share. The drawer itself is gone: the
contents moved to the full-screen contents page (apps/reader/modules/readertocpage), the bookmarks and notes
to the notes page (apps/reader/modules/readernotespage).

    TocDrawer.paginate(items, max_h) -- measured rows split into pages (the contents page, settings, 我)
    TocDrawer.Swatch -- a highlight style swatch

and the measured note rows of the 我 tab's all-notes page (apps/shelf/meview): noteMetrics(), headerItem(),
emptyItem() and noteItem() measure them, without rendering; groupHeader(), emptyState() and buildNoteRow()
build them.
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local util = require("util")
local Screen = Device.screen
local _ = require("gettext")

local dp = function(v) return Screen:scaleBySize(v) end

local function text(str, face, color, max_width, bold)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width, bold = bold }
end

-- Line height of a TextBoxWidget in `face` (see TextBoxWidget:init).
local function lineHeight(face, line_height)
    return math.floor((1 + (line_height or 0.3)) * Font:getFace(face).size + 0.5)
end

local function textSize(str, face, bold)
    local widget = TextWidget:new{ text = str, face = Font:getFace(face), bold = bold }
    local size = widget:getSize()
    widget:free()
    return size
end

-- Lines `str` needs at `width`, at most max_lines, estimated from its unwrapped width (nothing is rendered).
local function lineCount(str, face, width, max_lines, bold)
    return math.max(1, math.min(max_lines, math.ceil(textSize(str, face, bold).w / width)))
end

-- Wrapped text; with `lines`, exactly that tall, with an ellipsis when it needs more.
local function textBox(str, face, width, lines, opts)
    local args = { text = str, face = Font:getFace(face), width = width, fgcolor = Palette.ink, bgcolor = Palette.paper }
    for k, v in pairs(opts or {}) do args[k] = v end
    if lines then
        args.height = lines * lineHeight(face, args.line_height)
        args.height_overflow_show_ellipsis = true
    end
    return TextBoxWidget:new(args)
end

local function rule(w, color)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = dp(1) }, background = color }
end

-- First characters of a string, whitespace collapsed.
local function snippet(str, max_chars)
    str = util.trim(((str or ""):gsub("%s+", " ")))
    local chars = util.splitToChars(str)
    if #chars > max_chars then
        return table.concat(chars, "", 1, max_chars) .. "…"
    end
    return str
end

--- Highlight style swatch (18 × 10dp), drawn only from an annotation's drawer string, so styles
-- added later (wave) show without their drawing code: lighten (marker), underscore (line),
-- strikeout, invert and wave; anything else is drawn as the marker.
local Swatch = Widget:extend{
    drawer = nil,
}

function Swatch:init()
    self.dimen = Geom:new{ w = dp(18), h = dp(10) }
end

function Swatch:paintTo(bb, x, y)
    local w, h = self.dimen.w, self.dimen.h
    local line = dp(2)
    if self.drawer == "underscore" then
        bb:paintRect(x, y + h - line, w, line, Palette.ink)
    elseif self.drawer == "strikeout" then
        bb:paintRect(x, y + math.floor((h - line) / 2), w, line, Palette.ink)
    elseif self.drawer == "invert" then
        bb:paintRect(x, y, w, h, Palette.ink)
    elseif self.drawer == "wave" then
        local amp, period, thick = dp(1.5), dp(6), math.max(1, dp(1.3))
        local base = y + h - thick - amp
        for i = 0, w - 1 do
            local dy = math.floor(amp * math.sin(2 * math.pi * i / period) + 0.5)
            bb:paintRect(x + i, base - dy, 1, thick, Palette.ink)
        end
    else
        bb:paintRect(x, y, w, h, Palette.mark)
    end
end

-- A list item: content over a divider; tappable when it has a callback.
local ListRow = InputContainer:extend{
    callback = nil,
    is_header = false,
}

function ListRow:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ w = size.w, h = size.h }
    if self.callback then
        self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
end

function ListRow:onTapSelect()
    self.callback()
    return true
end

local TocDrawer = {}

--[[--
Splits measured rows into pages that fit `max_h`.
@tparam table items array of { h = height, is_header = bool }
@treturn table array of pages, each an array of item indexes
A group header that would end a page moves to the next one; a row taller than a page gets one of its own.
]]
function TocDrawer.paginate(items, max_h)
    local pages, page, used = {}, {}, 0
    for i, item in ipairs(items) do
        if #page > 0 and used + item.h > max_h then
            local last = page[#page]
            if items[last].is_header and #page > 1 then
                table.remove(page)
                table.insert(pages, page)
                page, used = { last }, items[last].h
            else
                table.insert(pages, page)
                page, used = {}, 0
            end
        end
        table.insert(page, i)
        used = used + item.h
    end
    if #page > 0 then
        table.insert(pages, page)
    end
    return pages
end

-- A list row `h` tall: content (vertically centered) over a rule-gray divider.
local function row(w, h, content, callback)
    return ListRow:new{
        callback = callback,
        VerticalGroup:new{
            LeftContainer:new{ dimen = Geom:new{ w = w, h = h - dp(1) }, content },
            rule(w, Palette.rule),
        },
    }
end

local function date(item)
    return (item.datetime or ""):sub(1, 10)
end

--[[--
Measured rows of note lists (the 我 tab's all-notes page): a group header, a note (a highlight with its thought, or
a bookmark) with its date, and an empty state. Build them with TocDrawer.groupHeader, TocDrawer.buildNoteRow and TocDrawer.emptyState,
`w` wide. `metrics` (TocDrawer.noteMetrics()) holds the sizes every row shares: measure it once per list.
]]
function TocDrawer.noteMetrics()
    return {
        excerpt_h = lineHeight("ui_excerpt", 0.6),
        label_h = lineHeight("ui_label_large"),
        caption_h = textSize("0", "ui_caption").h,
        thought_w = textSize(_("Thought"), "ui_label_large", true).w + dp(4),
    }
end

function TocDrawer.headerItem(title, metrics)
    return { kind = "header", is_header = true, title = title, h = dp(18) + metrics.caption_h + dp(6) + dp(1) }
end

function TocDrawer.emptyItem(title, hint)
    return { kind = "empty", h = 0, title = title, hint = hint }
end

-- What a bookmark's row reads: the note written on it, else its chapter, else 书签.
local function bookmarkText(item)
    if item.note and item.note ~= "" then return item.note end
    if item.chapter and item.chapter ~= "" then return item.chapter end
    -- @translators A bookmark among the notes of all books, when it has neither a note nor a chapter.
    return _("Bookmark")
end

--- Measured row of a note, `w` wide: a highlight (with a drawer, and maybe a thought), or a bookmark.
function TocDrawer.noteItem(w, item, metrics)
    local excerpt = snippet(item.drawer and item.text or bookmarkText(item), 400)
    local lines = lineCount(excerpt, "ui_excerpt", w - dp(24), 3)
    local note = item.drawer and item.note and item.note ~= "" and snippet(item.note, 200)
    local note_lines = note and lineCount(note, "ui_label_large", w - metrics.thought_w, 2) or 0
    return {
        kind = "note", item = item, excerpt = excerpt, lines = lines, note = note, note_lines = note_lines,
        h = lines * metrics.excerpt_h + (note and dp(6) + note_lines * metrics.label_h or 0)
            + dp(4) + metrics.caption_h + 2 * dp(12) + dp(1),
    }
end

function TocDrawer.emptyState(w, it)
    local group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = dp(40) },
        text(it.title, "ui_body", Palette.ink, w, true),
    }
    if it.hint then
        table.insert(group, VerticalSpan:new{ width = dp(4) })
        table.insert(group, textBox(it.hint, "ui_label_large", w - dp(16), nil, { alignment = "center", fgcolor = Palette.ink_2 }))
    end
    return ListRow:new{ CenterContainer:new{ dimen = Geom:new{ w = w, h = group:getSize().h }, group } }
end

function TocDrawer.groupHeader(w, it)
    return ListRow:new{
        is_header = true,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = dp(18) },
            text(it.title, "ui_caption", Palette.ink_2, w),
            VerticalSpan:new{ width = dp(6) },
            rule(w, Palette.ink),
        },
    }
end

--- A note row (style swatch or bookmark, excerpt, thought, date) from TocDrawer.noteItem; `callback` on tap.
function TocDrawer.buildNoteRow(w, it, callback)
    local swatch_w = dp(24)
    local content = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            align = "top",
            LeftContainer:new{
                dimen = Geom:new{ w = swatch_w, h = lineHeight("ui_excerpt", 0.6) },
                it.item.drawer and Swatch:new{ drawer = it.item.drawer }
                    or IconWidget:new{ icon = "eink/bookmark", width = dp(16), height = dp(16), alpha = true },
            },
            textBox(it.excerpt, "ui_excerpt", w - swatch_w, it.lines, { line_height = 0.6 }),
        },
    }
    if it.note then
        local label = text(_("Thought"), "ui_label_large", Palette.ink, nil, true)
        local gap = dp(4)
        table.insert(content, VerticalSpan:new{ width = dp(6) })
        table.insert(content, HorizontalGroup:new{
            align = "top",
            label,
            HorizontalSpan:new{ width = gap },
            textBox(it.note, "ui_label_large", w - label:getSize().w - gap, it.note_lines),
        })
    end
    table.insert(content, VerticalSpan:new{ width = dp(4) })
    table.insert(content, text(date(it.item), "ui_caption", Palette.ink_2, w))
    local r = row(w, it.h, content, callback)
    r.note = it.item
    return r
end

TocDrawer.Swatch = Swatch

return TocDrawer
