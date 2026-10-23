--[[--
Notes page of the e-ink redesign (笔记页, see DESIGN.md, Other pages): every note of the book (highlights,
thoughts and bookmarks) on a full-screen page (ui/widget/fullscreenpage), after WeChat Read's
06-notes/01-notes-list.png, 02-notes-next-page.png and 06-empty-notes-completed-book.png, and
05-bookmarks/04-bookmark-in-notes.png and 05-bookmarks-and-highlights-filter.png.

Opened by "ShowNotes" (ReaderToolbar): the toolbar's 笔记 lists every note, the contents page's 书签 (and the
search page's) only the bookmarks, when the book has any. In the title band, 笔记, and 仅显示书签 at the right
while the book has bookmarks: a toggle, its bookmark icon filled while only the bookmarks are listed. On the
first page, the overview card: the book title, → 已读到 x% · 共 N 条笔记, ↗ 时长 N 分钟 (with the statistics
plugin only) and the cover. N counts every note (ReaderAnnotation:getNumberOfAnnotations()), whatever is
listed. Then the notes in book order, under their chapters, one card each: a type disc (the highlight's own
style on an A, a thought, a bookmark) and up to three lines of text: the highlighted text, the thought (over
the text it is on), or the text the bookmarked page starts with. A book without notes gets a card saying what
can be kept here. The column of cards is 416dp wide and centered, as on the Leaf5.

Lists are paginated, never scrolled; a heading never ends a page, and a page past the first starts under a
rule, as the reference's scrolled list does. Cards are measured as they are built (TextBoxWidget wraps the
real text), and only up to the page shown: pages are laid out as the reader turns to them. The page reopens
on the page left (with the same filter, or the last page when there are fewer now), and follows the notes as they change while it is
shown (refresh(), which ReaderToolbar calls on "AnnotationsModified").

A tap on a card goes to its note, with the location stack keeping the position left, as the contents page
does. A highlight or a thought gets the jump focus there: its text marked in marker gray for a moment
(JumpFocus, a view module), which saves nothing and leaves the highlight as it is. A bookmark has no text to
mark: its page is enough.

Opening and closing repaint the page, turning a page repaints the content and the bar, 仅显示书签 and a change
of the notes the whole page (all "ui"). A jump closes the page with the reader's "partial", which the jump's
own repaint joins; the jump focus leaves with "ui" over the lines it marked.
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local FullscreenPage = require("ui/widget/fullscreenpage")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local ReaderView = require("apps/reader/modules/readerview")
local RenderImage = require("ui/renderimage")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Tappable = ShelfWidgets.Tappable
local util = require("util")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext

local function dp(v) return Screen:scaleBySize(v) end

-- Sizes from WeChat Read on the Leaf5 (06-notes/01-notes-list.png).
local COLUMN_W = dp(416) -- the cards' column, centered
local GUTTER = dp(22) -- at least, on each side of the column
local PAGE_TOP = dp(12) -- from the title band to the first card
local BOTTOM_GAP = dp(13) -- at least, from the last card to the bar
local CARD_R = dp(14)
local CARD_BORDER = dp(0.94) -- 2px on the Leaf5, as in the reference (1dp rounds up to 3px), like the lookup cards
local CARD_PAD_X = dp(20)
local CARD_PAD_Y = dp(18)
local CARD_GAP = dp(13)
local DISC = dp(25) -- the type disc
local DISC_GAP = dp(15) -- from the disc to the text
local HEADING_H = dp(56) -- from the card before a chapter heading to the card after it
local HEADING_CENTER = dp(32) -- the heading's middle, from the top of its band
local COVER_W, COVER_H = dp(64), dp(91)
local OVERVIEW_TEXT_TOP = dp(4) -- the title's line box, from the top of the cover
local OVERVIEW_LINE_GAP = dp(2) -- the lines are 27 and 24dp apart, as measured
local OVERVIEW_ICON = dp(16)
local EMPTY_H = dp(111)
local QUOTE_BAR = dp(2) -- before the text a thought is on
local QUOTE_GAP = dp(8)
local EXCERPT_SIZE = 18 -- the Excerpt role, in the UI sans
local HEADLINE_SIZE = 18 -- the Headline role: the page title, the book title and the chapter headings
local TEXT_LINE = 0.4 -- line height in em: 25dp lines at 18dp, as measured
local TEXT_LINES = 3
local QUOTE_LINES = 2
local FOCUS_SECONDS = 1.5 -- how long the jump focus stays
local FOCUS_DARKEN = 1 - Palette.mark.a / 0xFF -- darkens paper to marker gray, and leaves ink as it is

local function text(str, face, size, color, max_width, bold)
    return TextWidget:new{
        text = str, face = Font:getFace(face, size), fgcolor = color or Palette.ink, max_width = max_width, bold = bold,
    }
end

local function icon(name, size)
    return IconWidget:new{ icon = name, width = size, height = size, alpha = true }
end

-- The chapter a note is filed under, or the book's title: a book without contents stores "" (ReaderHighlight, and
-- ReaderAnnotation for old bookmarks), others nothing.
local function chapterOf(item, ui)
    if item.chapter == nil or item.chapter == "" then
        return ui.doc_props.display_title
    end
    return item.chapter
end

-- First characters of a string, whitespace collapsed: enough for the lines a card shows.
local function snippet(str, max_chars)
    str = util.trim(((str or ""):gsub("%s+", " ")))
    local chars = util.splitToChars(str)
    if #chars > max_chars then
        return table.concat(chars, "", 1, max_chars)
    end
    return str
end

--- The type disc: a 25dp ink ring around the note's type: a bookmark, a thought, or an A carrying the
-- highlight's own style (a line under it, a marker behind it, a wave, a strikeout, or inverted).
local TypeDisc = Widget:extend{
    kind = nil, -- "highlight", "thought" or "bookmark"
    drawer = nil, -- a highlight's style
}

function TypeDisc:init()
    self.dimen = Geom:new{ w = DISC, h = DISC }
    if self.kind == "bookmark" then
        self.glyph = icon("eink/bookmark", dp(15))
    elseif self.kind == "thought" then
        self.glyph = icon("eink/thought", dp(15))
    else
        self.glyph = IconWidget:new{ icon = "eink/glyph.a", width = dp(16), height = dp(16), alpha = true,
            invert = self.drawer == "invert" or nil }
    end
end

function TypeDisc:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local anti_alias = G_reader_settings:nilOrTrue("anti_alias_ui")
    bb:paintBorder(x, y, DISC, DISC, Size.border.default, Palette.ink, math.floor(DISC / 2), anti_alias)
    local size = self.glyph:getSize()
    local gx = x + math.floor((DISC - size.w) / 2)
    if self.kind ~= "highlight" then
        self.glyph:paintTo(bb, gx, y + math.floor((DISC - size.h) / 2))
        return
    end
    -- the A sits a little high, over where its line goes (as in eink/highlight)
    local gy = y + math.floor((DISC - size.h) / 2) - dp(1)
    local line_x, line_w = gx + math.floor(size.w * 5.5 / 24), math.floor(size.w * 13 / 24)
    local thick = math.max(1, math.floor(size.h * 2 / 24 + 0.5))
    if self.drawer == "lighten" then
        bb:paintRect(gx + math.floor(size.w * 4 / 24), gy + math.floor(size.h * 1.5 / 24),
            math.floor(size.w * 16 / 24), math.floor(size.h * 17 / 24), Palette.mark)
    elseif self.drawer == "invert" then
        bb:paintRect(gx, gy, size.w, size.h, Palette.ink)
    end
    self.glyph:paintTo(bb, gx, gy)
    if self.drawer == "wave" then
        ReaderView.paintWave(bb, line_x, gy + size.h + dp(1), line_w, Palette.ink)
    elseif self.drawer == "strikeout" then
        bb:paintRect(line_x, gy + math.floor(size.h * 10 / 24), line_w, thick, Palette.ink)
    elseif self.drawer ~= "lighten" and self.drawer ~= "invert" then -- the line, and any other style
        bb:paintRect(line_x, gy + math.floor(size.h * 20.5 / 24), line_w, thick, Palette.ink)
    end
end

function TypeDisc:free()
    self.glyph:free()
end

TypeDisc.onCloseWidget = TypeDisc.free

--[[--
The jump focus: the text of the note jumped to, marked in marker gray for a moment. A view module, drawn with the
page (so the jump's repaint shows it) and only where the text is on the screen; nothing is saved. It is also a
module of the reader, for its events: a page turn drops the mark (the turn repaints the page without it), and so
does the reader closing, whose timer goes with it.
]]
local JumpFocus = Widget:extend{
    item = nil, -- the highlight marked, while it is
}

--- Marks `item`'s text in the reader `ui` for a moment.
function JumpFocus.show(ui, item)
    local focus = ui.view.view_modules.notes_jump_focus
    if not focus then
        focus = JumpFocus:new{}
        ui.view:registerViewModule("notes_jump_focus", focus)
        ui:registerModule(nil, focus)
    end
    focus:stop()
    focus.item = item
    focus.clear = function() focus:finish() end
    UIManager:scheduleIn(FOCUS_SECONDS, focus.clear)
end

--- Where the mark is on the screen: nothing when the text is on another page, or when nothing is marked.
function JumpFocus:rects()
    local rects = {}
    local item = self.item
    if not item then return rects end
    local document, view = self.ui.document, self.view
    if self.ui.rolling then
        -- as ReaderView does for highlights: the boxes only for text in view, which they are costly to get
        local top = document:getCurrentPos()
        local bottom = top + self.ui.dimen.h * ((view.view_mode == "page" and document:getVisiblePageCount() > 1) and 2 or 1)
        if document:getPosFromXPointer(item.pos0) <= bottom and document:getPosFromXPointer(item.pos1) >= top then
            for _, box in ipairs(document:getScreenBoxesFromPositions(item.pos0, item.pos1, true) or {}) do
                if box.h ~= 0 then
                    table.insert(rects, box)
                end
            end
        end
    else
        for _, page in ipairs(view:getCurrentPageList()) do
            if page == item.pos0.page then
                for _, box in ipairs(document:getPageBoxesFromPositions(page, item.pos0, item.pos1) or {}) do
                    local rect = view:pageToScreenTransform(page, box)
                    if rect then
                        table.insert(rects, rect)
                    end
                end
            end
        end
    end
    return rects
end

function JumpFocus:paintTo(bb, x, y)
    for _, rect in ipairs(self:rects()) do
        bb:darkenRect(x + rect.x, y + rect.y, rect.w, rect.h, FOCUS_DARKEN)
    end
end

--- Drops the mark and its timer, without a repaint of its own. (Returns nothing: the reader's other modules get
-- the event too.)
function JumpFocus:stop()
    if self.clear then
        UIManager:unschedule(self.clear)
        self.clear = nil
    end
    self.item = nil
end

JumpFocus.onPageUpdate = JumpFocus.stop
JumpFocus.onPosUpdate = JumpFocus.stop -- scroll mode
JumpFocus.onCloseWidget = JumpFocus.stop

--- The mark goes, repainting what it covered (nothing when the text is no longer on the screen).
function JumpFocus:finish()
    self.clear = nil
    local region
    for _, rect in ipairs(self:rects()) do
        region = region and region:combine(rect) or rect
    end
    self.item = nil
    if region then
        UIManager:setDirty(self.ui.dialog, "ui", region)
    end
end

local covers = setmetatable({}, { __mode = "k" }) -- document => the overview's cover image, or false
local positions = setmetatable({}, { __mode = "k" }) -- document => { filter, page } left

local NotesPage = FullscreenPage:extend{
    ui = nil,
    filter = nil, -- "bookmarks": only the bookmarks are listed (dropped when the book has none)
    on_close = nil, -- function, called once the page is closed
}

function NotesPage:init()
    -- @translators Title of the notes page, which lists the book's highlights, thoughts and bookmarks.
    self.title = C_("Notes page", "Notes")
    FullscreenPage.init(self)
    self.column_w = math.min(COLUMN_W, self.dimen.w - 2 * GUTTER)
    self.column_x = math.floor((self.dimen.w - self.column_w) / 2)
    self.list_h = self.content_rect.h - PAGE_TOP - BOTTOM_GAP
    self.text_face = Font:getFace("ui_body", EXCERPT_SIZE)
    self.text_line_h = math.floor((1 + TEXT_LINE) * self.text_face.size + 0.5) -- as TextBoxWidget does
    self.inner_w = self.column_w - 2 * CARD_BORDER - 2 * CARD_PAD_X -- inside a card's outline and side padding
    self.text_w = self.inner_w - DISC - DISC_GAP
    self.page_texts = setmetatable({}, { __mode = "k" }) -- bookmark => the text its page starts with, kept by refresh()
    self:collect()
    local left = positions[self.ui.document]
    if left and left.filter == self.filter then
        self:layOutTo(left.page)
        self.page = math.min(left.page, #self.pages)
    end
    self:build()
end

--- Reads the notes into the page's entries: the overview card, then each chapter's heading and notes, or the
-- empty card. Without bookmarks, there is no filter.
function NotesPage:collect()
    local annotations = self.ui.annotation.annotations
    self.count = self.ui.annotation:getNumberOfAnnotations()
    self.has_bookmarks = false
    for _, item in ipairs(annotations) do
        if not item.drawer then
            self.has_bookmarks = true
            break
        end
    end
    if not self.has_bookmarks then
        self.filter = nil
    end
    local entries = { { kind = "overview" } }
    local chapter
    for _, item in ipairs(annotations) do
        if self.filter ~= "bookmarks" or not item.drawer then
            local item_chapter = chapterOf(item, self.ui)
            if item_chapter ~= chapter then
                chapter = item_chapter
                table.insert(entries, { kind = "heading", title = chapter })
            end
            table.insert(entries, { kind = "card", item = item })
        end
    end
    if #entries == 1 then
        table.insert(entries, { kind = "empty" })
    end
    self.entries = entries
    self.heights = {} -- entry index => its height
    self.pages = {} -- arrays of entry indexes, laid out as far as the reader went
    self.next_entry = 1 -- the first entry not on a page yet
end

--- The space before entry `i` when it follows another one on its page: cards are 13dp apart, a heading's band
-- holds its own spacing, and so do the cards right under it.
function NotesPage:gapBefore(i)
    local kind, before = self.entries[i].kind, self.entries[i - 1].kind
    if kind == "heading" or before == "heading" then
        return 0
    end
    return CARD_GAP
end

function NotesPage:height(i)
    local h = self.heights[i]
    if h then return h end
    local entry = self.entries[i]
    if entry.kind == "overview" then
        h = 2 * CARD_BORDER + 2 * CARD_PAD_X + COVER_H
    elseif entry.kind == "empty" then
        h = EMPTY_H
    elseif entry.kind == "heading" then
        h = HEADING_H
    else
        local body = self:cardBody(entry)
        h = 2 * CARD_BORDER + 2 * CARD_PAD_Y + body:getSize().h
        body:free()
    end
    self.heights[i] = h
    return h
end

--- Lays the entries out on pages until there are `page` of them, or no entries left.
function NotesPage:layOutTo(page)
    while #self.pages < page and self.next_entry <= #self.entries do
        local indexes, used = {}, 0
        local i = self.next_entry
        while i <= #self.entries do
            local h = self:height(i) + (#indexes > 0 and self:gapBefore(i) or 0)
            if #indexes > 0 and used + h > self.list_h then break end
            table.insert(indexes, i)
            used = used + h
            i = i + 1
        end
        -- a heading goes to the next page with its first card
        if #indexes > 1 and i <= #self.entries and self.entries[indexes[#indexes]].kind == "heading" then
            table.remove(indexes)
            i = i - 1
        end
        table.insert(self.pages, indexes)
        self.next_entry = i
    end
end

--- Text at the top of a bookmarked page, or nil.
function NotesPage:pageStartText(item)
    local doc = self.ui.document
    if self.ui.rolling then
        local page = doc:getPageFromXPointer(item.page)
        local next_xp = page < doc:getPageCount() and doc:getPageXPointer(page + 1)
        return next_xp and doc:getTextFromXPointers(item.page, next_xp) or doc:getTextFromXPointer(item.page)
    end
    -- the text layer only: no reflow segmentation of scanned pages
    local boxes = doc.getPageTextBoxes and doc:getPageTextBoxes(item.page)
    if not boxes then return end
    local words = {}
    for _, line in ipairs(boxes) do
        for _, word in ipairs(line) do
            table.insert(words, word.word)
        end
        if #words > 60 then break end
    end
    return table.concat(words, " ")
end

--- A card's kind, and its text and the text quoted under it (a thought's highlighted text, a bookmark's note).
function NotesPage:cardTexts(item)
    if not item.drawer then
        local page_text = self.page_texts[item]
        if page_text == nil then
            page_text = snippet(self:pageStartText(item), 200)
            if page_text == "" then
                page_text = chapterOf(item, self.ui)
            end
            self.page_texts[item] = page_text
        end
        return "bookmark", page_text, item.note
    elseif item.note and item.note ~= "" then
        return "thought", item.note, item.text
    end
    return "highlight", item.text
end

--- The text of a card, at most three lines, and the quote under it, at most two.
function NotesPage:cardBody(entry)
    local main, quote = select(2, self:cardTexts(entry.item))
    local body = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{
            text = snippet(main, 200), face = self.text_face, width = self.text_w, line_height = TEXT_LINE,
            height = TEXT_LINES * self.text_line_h, height_adjust = true, height_overflow_show_ellipsis = true,
            fgcolor = Palette.ink, bgcolor = Palette.paper,
        },
    }
    if quote and quote ~= "" then
        local quote_face = Font:getFace("ui_label_large")
        local box = TextBoxWidget:new{
            text = snippet(quote, 120), face = quote_face, width = self.text_w - QUOTE_BAR - QUOTE_GAP,
            height = QUOTE_LINES * math.floor(1.3 * quote_face.size + 0.5), height_adjust = true,
            height_overflow_show_ellipsis = true, fgcolor = Palette.ink, bgcolor = Palette.paper,
        }
        table.insert(body, VerticalSpan:new{ width = dp(8) })
        table.insert(body, HorizontalGroup:new{
            align = "top",
            LineWidget:new{ dimen = Geom:new{ w = QUOTE_BAR, h = box:getSize().h }, background = Palette.ink },
            HorizontalSpan:new{ width = QUOTE_GAP },
            box,
        })
    end
    return body
end

--- A paper card with an ink outline and 14dp corners, `self.column_w` wide when its content is `self.inner_w`.
function NotesPage:card(content, pad_y, pad_x)
    return FrameContainer:new{
        radius = CARD_R, bordersize = CARD_BORDER, color = Palette.ink, background = Palette.paper,
        padding = 0, padding_top = pad_y, padding_bottom = pad_y, padding_left = pad_x, padding_right = pad_x,
        content,
    }
end

function NotesPage:buildCard(entry)
    local item = entry.item
    local kind = self:cardTexts(item)
    local disc = TypeDisc:new{ kind = kind, drawer = item.drawer }
    local card = Tappable:new{
        callback = function() self:jump(item) end,
        self:card(HorizontalGroup:new{
            align = "top",
            -- the disc on the first line
            CenterContainer:new{ dimen = Geom:new{ w = DISC, h = self.text_line_h }, disc },
            HorizontalSpan:new{ width = DISC_GAP },
            self:cardBody(entry),
        }, CARD_PAD_Y, CARD_PAD_X),
    }
    card.item, card.kind = item, kind
    return card
end

--- The cover, cropped to fill 64 × 91dp, made once per book; or the typographic cover.
function NotesPage:buildCover()
    local doc = self.ui.document
    if covers[doc] == nil then
        local bb = self.ui.bookinfo and self.ui.bookinfo:getCoverImage(doc)
        if bb then
            local scale = math.max(COVER_W / bb:getWidth(), COVER_H / bb:getHeight())
            local scaled = RenderImage:scaleBlitBuffer(bb, math.ceil(bb:getWidth() * scale), math.ceil(bb:getHeight() * scale), true)
            bb = scaled
        end
        covers[doc] = bb or false
    end
    local props = self.ui.doc_props
    return ShelfWidgets.cover({ title = props.display_title, authors = props.authors }, COVER_W, COVER_H,
        covers[doc] or nil, true)
end

--- A line of the overview card: an icon, then bold Label text.
local function overviewLine(icon_name, str, max_width)
    return HorizontalGroup:new{
        align = "center",
        icon(icon_name, OVERVIEW_ICON),
        HorizontalSpan:new{ width = dp(6) },
        text(str, "ui_label", nil, nil, max_width - OVERVIEW_ICON - dp(6), true),
    }
end

--- 时长: the statistics plugin's reading time of the book (its own, capped per page), or nil without it.
function NotesPage:readingTime()
    local stats = self.ui.statistics
    if not (stats and stats.isEnabled and stats:isEnabled()) then return end
    local minutes = math.floor(((stats.book_read_time or 0) + (stats.mem_read_time or 0)) / 60)
    if minutes < 60 then
        -- @translators The time spent reading this book, on its notes page (时长 25 分钟).
        return T(N_("Read for 1 minute", "Read for %1 minutes", minutes), minutes)
    end
    -- @translators The time spent reading this book, on its notes page: %1 hours, %2 minutes (时长 2 小时 5 分钟).
    return T(_("Read for %1 h %2 min"), math.floor(minutes / 60), minutes % 60)
end

function NotesPage:buildOverview()
    local text_w = self.inner_w - COVER_W - dp(16)
    local percent = math.floor(self.ui:getCurrentPage() / self.ui.document:getPageCount() * 100)
    local info = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = OVERVIEW_TEXT_TOP },
        text(self.ui.doc_props.display_title, "ui_title", HEADLINE_SIZE, nil, text_w, true),
        VerticalSpan:new{ width = OVERVIEW_LINE_GAP },
        -- @translators On the notes page: how far the book is read (%1 a percentage), and %2 its notes, bookmarks included.
        overviewLine("eink/read-to", T(N_("Read to %1% · 1 note", "Read to %1% · %2 notes", self.count), percent, self.count), text_w),
    }
    local time = self:readingTime()
    if time then
        table.insert(info, VerticalSpan:new{ width = OVERVIEW_LINE_GAP })
        table.insert(info, overviewLine("eink/trend", time, text_w))
    end
    local cover = self:buildCover()
    local overview = self:card(HorizontalGroup:new{
        align = "top",
        LeftContainer:new{ dimen = Geom:new{ w = text_w, h = COVER_H }, info },
        HorizontalSpan:new{ width = dp(16) },
        cover,
    }, CARD_PAD_X, CARD_PAD_X)
    overview.cover = cover
    return overview
end

function NotesPage:buildEmpty()
    local message = TextBoxWidget:new{
        -- @translators On the notes page of a book without notes (thoughts, highlights and bookmarks).
        text = _("You can keep your thoughts, highlights and bookmarks on this book here."),
        face = Font:getFace("ui_body"), width = self.inner_w, alignment = "center",
        fgcolor = Palette.ink, bgcolor = Palette.paper,
    }
    return self:card(CenterContainer:new{
        dimen = Geom:new{ w = self.inner_w, h = EMPTY_H - 2 * CARD_BORDER },
        message,
    }, 0, CARD_PAD_X)
end

function NotesPage:buildHeading(entry)
    local heading = text(entry.title, "ui_title", HEADLINE_SIZE, nil, self.column_w, true)
    local h = heading:getSize().h
    local top = math.max(0, HEADING_CENTER - math.floor(h / 2))
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = top },
        heading,
        VerticalSpan:new{ width = math.max(0, HEADING_H - top - h) },
    }
end

function NotesPage:buildTitle()
    local rect = self.title_rect
    local right
    self.filter_button = nil
    if self.has_bookmarks then
        local on = self.filter == "bookmarks"
        local label = HorizontalGroup:new{
            align = "center",
            icon(on and "eink/bookmark-on" or "eink/bookmark", dp(18)),
            HorizontalSpan:new{ width = dp(4) },
            -- @translators Toggle on the notes page: list only the bookmarks, or all notes again.
            text(_("Bookmarks only"), "ui_label_large", nil, nil, nil, true),
        }
        -- 8dp more each side to tap, over the band's height
        self.filter_button = Tappable:new{
            callback = function() self:toggleFilter() end,
            CenterContainer:new{ dimen = Geom:new{ w = label:getSize().w + 2 * dp(8), h = rect.h }, label },
        }
        right = self.filter_button
    else
        right = HorizontalSpan:new{ width = 0 }
    end
    local right_w = right:getSize().w
    local title_w = self.column_w - right_w + (right_w > 0 and dp(8) or 0)
    return HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = self.column_x },
        LeftContainer:new{
            dimen = Geom:new{ w = title_w, h = rect.h },
            text(self.title, "ui_title", HEADLINE_SIZE, nil, title_w - dp(8), true),
        },
        right,
    }
end

--- The entries of the page shown, in the column; a page past the first starts under a rule. `self.cards` gets
-- the cards, `self.overview` and `self.empty_card` those cards when shown.
function NotesPage:buildContent(rect)
    self:layOutTo(self.page)
    self.page = math.max(1, math.min(self.page, #self.pages))
    local list = VerticalGroup:new{ align = "left" }
    if self.page > 1 then
        table.insert(list, VerticalSpan:new{ width = PAGE_TOP - Size.border.default })
        table.insert(list, LineWidget:new{ dimen = Geom:new{ w = rect.w, h = Size.border.default }, background = Palette.rule })
    else
        table.insert(list, VerticalSpan:new{ width = PAGE_TOP })
    end
    self.cards, self.overview, self.empty_card = {}, nil, nil
    for k, i in ipairs(self.pages[self.page] or {}) do
        local entry = self.entries[i]
        if k > 1 then
            table.insert(list, VerticalSpan:new{ width = self:gapBefore(i) })
        end
        local widget
        if entry.kind == "overview" then
            widget = self:buildOverview()
            self.overview = widget
        elseif entry.kind == "empty" then
            widget = self:buildEmpty()
            self.empty_card = widget
        elseif entry.kind == "heading" then
            widget = self:buildHeading(entry)
        else
            widget = self:buildCard(entry)
            table.insert(self.cards, widget)
        end
        table.insert(list, HorizontalGroup:new{ HorizontalSpan:new{ width = self.column_x }, widget })
    end
    local more = self.next_entry <= #self.entries
    return list, #self.pages + (more and 1 or 0)
end

--- 仅显示书签: only the bookmarks, or every note again, from the first page.
function NotesPage:toggleFilter()
    self.filter = self.filter ~= "bookmarks" and "bookmarks" or nil
    self:collect()
    self.page = 1
    self:build()
    UIManager:setDirty(self, "ui", self.dimen)
end

--- The notes changed: lists them again, on the same page if it is still there, title band included.
function NotesPage:refresh()
    if self.closed then return end
    self:collect()
    self:build()
    UIManager:setDirty(self, "ui", self.dimen)
end

function NotesPage:jump(item)
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "partial", self.dimen)
    self.ui.link:addCurrentLocationToStack()
    if self.ui.rolling then
        -- no margin marker: the jump focus marks the text itself
        self.ui:handleEvent(Event:new("GotoXPointer", item.page))
    else
        self.ui.bookmark:gotoBookmark(item.page, item.pos0)
    end
    if item.drawer then
        JumpFocus.show(self.ui, item)
    end
end

function NotesPage:onCloseWidget()
    if self.ui.document then -- not when the reader closes with the page shown
        positions[self.ui.document] = { filter = self.filter, page = self.page }
    end
    if self.on_close then self.on_close() end
end


return NotesPage
