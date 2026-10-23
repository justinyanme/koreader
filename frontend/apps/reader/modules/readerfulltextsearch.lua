--[[--
Full-text search of the e-ink redesign (搜索页 and 搜索条, see DESIGN.md, Search bar and Other pages).

Replaces ReaderSearch (apps/replacements reader_search slot) and keeps all of it: the original input dialog
with its options (case, whole words, regular expressions, diacritics), its result list and its settings
stay where the original menu, gestures and the toolbar's search reach them. "ShowSearchPage" opens the
search page (apps/reader/modules/readersearchpage), over the contents page when its search field opens it,
or with a query to search at once. The page searches with the default options, ignoring case, in a
subprocess that a tap cancels, and lists the hits by chapter.

A hit opens in the book with its text marked in hit gray and the toolbar up, as in WeChat Read; a PDF keeps
its zoom, scroll and reflow, and pans to the hit. Under the toolbar the search bar docks at the bottom of the
page: an ink band with the keyword and ×. The keyword
leads back to its hits, on the page of hits left, over the contents page as in WeChat Read (so 取消 goes to
the contents page and 书签 works there); × ends the search and clears the mark, and nothing else:
highlights and notes stay. Until then the search stays (the bar, the mark and the hits) while the book is
read on, whatever is searched, selected or highlighted meanwhile.

The bar and the mark are drawn with the page (a view module, which the toolbar covers); the bar takes its
taps and holds before links, highlights and page turns (touch zones), and the rest of the page works as
usual. Opening a hit closes the pages with the reader's "partial", as a jump; × repaints the bar and the
mark ("ui").
]]

local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local Notification = require("ui/widget/notification")
local Palette = require("ui/palette")
local ReaderSearch = require("apps/reader/modules/readersearch")
local SearchPage = require("apps/reader/modules/readersearchpage")
local TextWidget = require("ui/widget/textwidget")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local Widget = require("ui/widget/widget")
local Screen = Device.screen
local _ = require("gettext")

local function dp(v) return Screen:scaleBySize(v) end

local BAR_H = dp(58)
local BAR_R = dp(19) -- its top corners
local BAR_ICON = dp(24)
local BAR_SIDE = dp(14) -- from the screen's edges to the icons
local CLOSE_W = dp(58) -- the ×'s target, at the right end
local CONTEXT_WORDS = 24 -- at least, around a hit: enough for the page's two-line excerpts (in CJK, a word is a character)
local HIT_DARKEN = 1 - Palette.hit.a / 0xFF -- darkens paper to hit gray, and leaves ink as it is

-- The search bar over the bottom of the page, and the hit's mark, while a hit is shown.
local SearchBar = Widget:extend{
    search = nil, -- the ReaderFulltextSearch
}

function SearchBar:getRect()
    return Geom:new{ x = 0, y = Screen:getHeight() - BAR_H, w = Screen:getWidth(), h = BAR_H }
end

function SearchBar:getCloseRect()
    local r = self:getRect()
    return Geom:new{ x = r.x + r.w - CLOSE_W, y = r.y, w = CLOSE_W, h = r.h }
end

--- The bar's widgets for `query`, made once per keyword.
function SearchBar:parts(query)
    if self.query ~= query then
        self:free()
        local r = self:getRect()
        local function paperIcon(name)
            -- flattened on paper, then inverted: paper strokes on an ink square
            return IconWidget:new{ icon = name, width = BAR_ICON, height = BAR_ICON, invert = true }
        end
        self.query = query
        self.search_icon, self.close_icon = paperIcon("eink/search"), paperIcon("eink/close")
        self.label = TextWidget:new{
            text = query, face = Font:getFace("ui_body"), bold = true, fgcolor = Palette.paper,
            max_width = r.w - 2 * BAR_SIDE - BAR_ICON - dp(7) - CLOSE_W,
        }
    end
    return self.search_icon, self.close_icon, self.label
end

function SearchBar:paintTo(bb, x, y)
    local hit = self.search.hit
    if not hit then return end
    for _, rect in ipairs(self.search:markRects()) do
        bb:darkenRect(x + rect.x, y + rect.y, rect.w, rect.h, HIT_DARKEN)
    end
    local r = self:getRect()
    x, y = x + r.x, y + r.y
    -- the rounded rect gives the top corners; the rest is square down to the screen's edge
    bb:paintRoundedRect(x, y, r.w, 2 * BAR_R, Palette.ink, BAR_R)
    bb:paintRect(x, y + BAR_R, r.w, r.h - BAR_R, Palette.ink)
    local search_icon, close_icon, label = self:parts(hit.query)
    local icon_y = y + math.floor((r.h - BAR_ICON) / 2)
    search_icon:paintTo(bb, x + BAR_SIDE, icon_y)
    close_icon:paintTo(bb, x + r.w - BAR_SIDE - BAR_ICON, icon_y)
    label:paintTo(bb, x + BAR_SIDE + BAR_ICON + dp(7), y + math.floor((r.h - label:getSize().h) / 2))
end

function SearchBar:free()
    for _, key in ipairs{ "search_icon", "close_icon", "label" } do
        if self[key] then
            self[key]:free()
            self[key] = nil
        end
    end
    self.query = nil
end

local ReaderFulltextSearch = ReaderSearch:extend{
    search_page = nil, -- the search page while shown
    query = nil, -- of `results`
    results = nil, -- the hits of the last search from the search page, which it shows
    hit = nil, -- while the bar is up: { item = the hit shown, query = its keyword, results = the hits it is one of,
               -- which the bar leads back to, page = the page of them left, boxes = PDF: its rects on its page }
}

--- Registers the search in its replacement slot.
function ReaderFulltextSearch.register()
    require("apps/replacements").reader_search = ReaderFulltextSearch
end

function ReaderFulltextSearch:init()
    ReaderSearch.init(self)
    self.bar = SearchBar:new{ search = self }
    self.view:registerViewModule("search_bar", self.bar)
    if not Device:isTouchDevice() then return end
    local screen = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 } -- the handlers check the bar's own rect
    self.ui:registerTouchZones({
        {
            id = "readersearch_bar_tap",
            ges = "tap",
            screen_zone = screen,
            overrides = {
                "tap_link", -- which comes before everything else
                "readerhighlight_tap",
                "tap_left_bottom_corner",
                "tap_right_bottom_corner",
                "readerfooter_tap",
                "readerconfigmenu_ext_tap",
                "readerconfigmenu_tap",
                "readermenu_ext_tap",
                "readermenu_tap",
                "tap_forward",
                "tap_backward",
            },
            handler = function(ges) return self:onTapBar(ges) end,
        },
        {
            id = "readersearch_bar_hold",
            ges = "hold",
            screen_zone = screen,
            overrides = { "readerhighlight_hold", "readerfooter_hold" },
            handler = function(ges) return self:isOnBar(ges) end,
        },
    })
end

--- The keyword the bar shows, while a hit is shown.
function ReaderFulltextSearch:barQuery()
    return self.hit and self.hit.query
end

--- Whether a gesture lands on the bar, which then takes it.
function ReaderFulltextSearch:isOnBar(ges)
    return self.hit ~= nil and self.bar:getRect():contains(ges.pos)
end

function ReaderFulltextSearch:onTapBar(ges)
    if not self:isOnBar(ges) then return false end
    if self.bar:getCloseRect():contains(ges.pos) then
        self:closeBar()
    else
        self:showHitResults()
    end
    return true
end

--- "ShowSearchPage": the search page, over the contents page `contents` when given; with `query`, its hits,
-- otherwise the keyboard for one.
function ReaderFulltextSearch:onShowSearchPage(query, contents)
    self:showPage{ contents = contents, query = query or "" }
    if query then
        self:searchForPage(query)
    else
        self.search_page:startTyping()
    end
    return true
end

--- The search page, made with `args` (see apps/reader/modules/readersearchpage).
function ReaderFulltextSearch:showPage(args)
    self:closePage()
    local page
    args.ui = self.ui
    args.on_submit = function(query) self:searchForPage(query) end
    args.on_hit = function(index) self:openHit(index) end
    args.on_close = function()
        if self.hit and page.results == self.hit.results then
            self.hit.page = page.page
        end
        if self.search_page == page then
            self.search_page = nil
        end
    end
    page = SearchPage:new(args)
    self.search_page = page
    UIManager:show(page, "ui", page.dimen)
end

--- The bar's keyword: its hits again (whatever was searched since), on the page left, over the contents page of the
-- redesign's toolbar (apps/reader/modules/readertoolbar) as in WeChat Read.
function ReaderFulltextSearch:showHitResults()
    local contents
    if self.ui.menu.showToolbar and self.ui:handleEvent(Event:new("ShowToc")) then
        contents = self.ui.menu.drawer
    end
    self.query, self.results = self.hit.query, self.hit.results
    self:showPage{ contents = contents, query = self.query, results = self.results, page = self.hit.page }
end

function ReaderFulltextSearch:closePage()
    if self.search_page then
        self.search_page:close()
        self.search_page = nil
    end
end

--- Searches the book for `query` with the default options, in a subprocess that a tap cancels, and shows the
-- hits on the search page. (Not search(): ReaderSearch:search() serves the original dialog's searches.)
function ReaderFulltextSearch:searchForPage(query)
    local page = self.search_page
    -- the keyboard may give diacritics in any order: the book's text is expected normalized
    query = Utf8Proc.normalize_NFC(query)
    Trapper:wrap(function()
        page:setSearching()
        UIManager:forceRePaint()
        local completed, results = Trapper:dismissableRunInSubprocess(function()
            return self.ui.document:findAllText(query, true, math.max(self.findall_nb_context_words, CONTEXT_WORDS),
                self.findall_max_hits, false, self.default_search_type.flags)
        end, false) -- an invisible trap: a tap anywhere cancels
        if page.closed then return end
        if not completed then
            page:showResults(nil)
            return
        end
        self.query, self.results = query, results or {}
        page:showResults(self.results)
        if #self.results >= self.findall_max_hits then
            UIManager:show(Notification:new{ text = _("Too many hits") })
        end
    end)
end

--- Opens hit `index` in the book: the search page goes (with the contents page under it), the hit is marked,
-- and the toolbar comes up over the bar.
function ReaderFulltextSearch:openHit(index)
    local item = self.results[index]
    self.hit = { item = item, query = self.query, results = self.results }
    self.search_page:leave("partial") -- which keeps the page of hits left
    self.ui.link:addCurrentLocationToStack()
    if self.ui.rolling then
        self.ui.rolling:onGotoXPointer(item.start)
    else
        self.hit.boxes = {}
        for i, box in ipairs(item.boxes) do
            self.hit.boxes[i] = self.ui.document:nativeToPageRectTransform(item.start, box) -- reflowed too
        end
        -- the reader's own zoom, scroll and reflow, panned so that the hit is in the middle of the view
        local box, view = self.hit.boxes[1], self.view
        local pos = box and {
            x = box.x + (box.w - view.visible_area.w / view.state.zoom) / 2,
            y = box.y + (box.h - view.visible_area.h / view.state.zoom) / 2,
        }
        self.ui:handleEvent(Event:new("GotoPage", item.start, pos))
    end
    if self.ui.menu.showToolbar then -- the toolbar of the redesign
        self.ui.menu:showToolbar()
    end
end

--- Where the hit's mark shows on the screen: nothing when it is on another page.
function ReaderFulltextSearch:markRects()
    local rects = {}
    local item = self.hit.item
    if self.ui.rolling then
        local document = self.ui.document
        -- as ReaderView does for highlights: the boxes only for text in view, which they are costly to get
        local top = document:getCurrentPos()
        local bottom = top + self.ui.dimen.h * ((self.view.view_mode == "page" and document:getVisiblePageCount() > 1) and 2 or 1)
        if document:getPosFromXPointer(item.start) <= bottom and document:getPosFromXPointer(item["end"]) >= top then
            for _, box in ipairs(document:getScreenBoxesFromPositions(item.start, item["end"], true) or {}) do
                if box.h ~= 0 then
                    table.insert(rects, box)
                end
            end
        end
    else
        for _, box in ipairs(self.hit.boxes) do
            local rect = self.view:pageToScreenTransform(item.start, box)
            if rect then
                table.insert(rects, rect)
            end
        end
    end
    return rects
end

--- ×: the search ends. The bar and the mark go; highlights and notes stay.
function ReaderFulltextSearch:closeBar()
    local region = self.bar:getRect()
    for _, rect in ipairs(self:markRects()) do
        region = region:combine(rect)
    end
    self.hit = nil
    self.bar:free()
    UIManager:setDirty(self.dialog, "ui", region)
end

function ReaderFulltextSearch:onSetDimensions()
    self:closePage()
    self.bar:free() -- sized for the old screen
end

function ReaderFulltextSearch:onCloseWidget()
    self:closePage()
    self.bar:free()
end

return ReaderFulltextSearch
