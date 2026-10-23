--[[--
The 书架 tab, after WeChat Read's shelf on the Leaf5 (00-entry/01-bookshelf.png): a full-width
search field, the title row, and a paged cover grid. The title names the status filter
(书架, or 在读 ▾) and opens the filter menu; 导入 at the right of the row opens the import page
(apps/shelf/importpage), and 选择 after it enters selection mode; the order is set in 设置 → 书架.
The grid fills the content area: the next page's first row shows cut off at its foot, under the
bottom band that ShelfFileManager draws with the tab icons and the page capsule.

Selection mode (CONTEXT.md, 选择模式; 15-supplement/03–06): 选择 enters it with no book selected,
a long press on a cover with that book selected. Taps then select covers instead of opening them,
on every page; the title row reads 全选 (取消全选 once the whole filtered shelf is selected), the
count, and 取消. The band swaps the tab icons for 移出书架 (hides the books, never deletes a file)
and 标记为 (读完, 在读, 搁置), each asked in a confirm layer; either one ends selection mode.

Every interaction repaints only what changed with a "ui" refresh (DESIGN.md, Refresh
mapping): from the title row down for a filter or entering selection mode, the grid and the
bottom band for a page, the cover and the title row for a cover selected; returning from the
reader is already a "full" refresh.
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmLayer = require("ui/widget/confirmlayer")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImportPage = require("apps/shelf/importpage")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Palette = require("ui/palette")
local RightContainer = require("ui/widget/container/rightcontainer")
local SelectionBubble = require("ui/widget/selectionbubble")
local Shelf = require("apps/shelf/shelf")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local Toast = require("ui/widget/toast")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local Screen = require("device").screen
local T = ffiUtil.template
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local NC_ = _.npgettext

local function dp(n) return Screen:scaleBySize(n) end

local GUTTER = dp(22)
local SEARCH_TOP = dp(12)
local SEARCH_H = dp(50)
local HEADER_H = SEARCH_TOP + SEARCH_H
local TITLE_ROW_H = dp(76) -- from the search field to the grid
local TITLE_MID = dp(46) -- the title's middle, under the search field
local TITLE_TAP_H = dp(44)
local TITLE_ACTION_GAP = dp(24) -- between 导入 and 选择
local GRID_Y = HEADER_H + TITLE_ROW_H
local EXTRACT_CHUNK = 40 -- books per background job, well under BookInfoManager's 5 minute watchdog

local filter_texts = {
    all = C_("Status of group of books", "All"),
    reading = C_("Status of group of books", "Reading"),
    new = C_("Status of group of books", "New"),
    complete = C_("Status of group of books", "Finished"),
    abandoned = C_("Status of group of books", "On hold"),
}
-- what 标记为 offers, in this order
local mark_statuses = { "complete", "reading", "abandoned" }
local mark_texts = {
    complete = C_("Status of single book", "Finished"),
    reading = C_("Status of single book", "Reading"),
    abandoned = C_("Status of single book", "On hold"),
}
local sort_texts = {
    recent = _("Recently read"),
    title = _("Title"),
    authors = _("Authors"),
}

local function statusText(book)
    if book.status == "complete" then
        return C_("Shelf book status", "Finished")
    elseif book.status == "abandoned" then
        return C_("Shelf book status", "On hold")
    elseif book.status == "new" then
        return C_("Shelf book status", "New")
    end
    return T(_("Read %1%"), math.floor((book.percent or 0) * 100))
end

local function savedSort()
    return G_reader_settings:readSetting("shelf_sort", "recent")
end

local ShelfView = WidgetContainer:extend{
    ui = nil, -- the FileManager
    width = nil,
    height = nil,
    selected = nil, -- in selection mode, the set of selected files; nil outside it
}

function ShelfView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    -- CoverBrowser's cache, when that plugin is loaded
    self.bim = package.loaded["bookinfomanager"]
    local filter = G_reader_settings:readSetting("shelf_filter")
    self.filter = util.arrayContains(Shelf.filters, filter) and filter or "all"
    self.sort = savedSort()
    self.page = 1
    self:computeGrid()
    self:reload(true)
    self:update()
end

function ShelfView:computeGrid()
    self.grid = ShelfWidgets.shelfGrid(self.width, self.height - GRID_Y)
    self.cover_specs = { max_cover_w = self.grid.cover_w, max_cover_h = self.grid.cover_h }
end

--- Screen rects of the title row and the grid.
function ShelfView:titleRect()
    return Geom:new{ x = self.dimen.x, y = self.dimen.y + HEADER_H, w = self.width, h = TITLE_ROW_H }
end

function ShelfView:gridRect()
    return Geom:new{ x = self.dimen.x, y = self.dimen.y + GRID_Y, w = self.width, h = self.height - GRID_Y }
end

--- Re-reads statuses and the cache, and queues extraction of what the cache lacks.
-- `rescan` also walks the home folder again; tab switches keep the last scan.
function ShelfView:reload(rescan)
    if rescan or not self.scanned then
        self.scanned = Shelf.scan(Shelf.homeDir())
    end
    self.books = Shelf.load(self.scanned, self.bim, self.cover_specs)
    if self.bim and not self.extracting and #self:pendingFiles() > 0 then
        self.extracting = { total = #self:pendingFiles(), done = 0, stalls = 0, start = time.now() }
        self.poll = self.poll or function() self:pollExtraction() end
        UIManager:scheduleIn(1, self.poll)
    end
end

-- What the shelf draws of its books, and their order: compared before and after a rescan.
local function booksKey(books)
    local keys = {}
    for i, book in ipairs(books) do
        keys[i] = table.concat({ book.file, book.title, book.status, tostring(book.has_cover),
            book.last_read or "", book.mtime or "" }, "\0")
    end
    table.sort(keys)
    return table.concat(keys, "\n")
end

--- Walks the home folder again (导入 closed: books may have come in), and redraws the grid only if the books
-- or what it shows of them changed.
function ShelfView:rescan()
    local before = booksKey(self.books)
    self:reload(true)
    if booksKey(self.books) ~= before then
        self:update("grid")
    end
end

function ShelfView:pendingFiles()
    local pending = {}
    for _, book in ipairs(self.books) do
        if book.needs_extract then
            table.insert(pending, book.file)
        end
    end
    return pending
end

--- Whether 书架 is the current tab (its page drives the bottom band).
function ShelfView:isCurrent()
    return self.ui.content and self.ui.content[1] == self
end

--- Whether it is on screen: the current tab, with no full-screen page (设置, 书源) over the file manager.
-- A sheet or popover over part of it doesn't count: closing one only repaints its own rect.
function ShelfView:isShowing()
    if not self:isCurrent() then return false end
    for widget in UIManager:topdown_widgets_iter() do
        if widget == self.ui then return true end
        if widget.covers_fullscreen then return false end
    end
    return false
end

-- BookInfoManager runs one job at a time: a new job kills the running one (the file browser starts
-- its own for thumbnails), and its watchdog kills jobs older than 5 minutes. So the shelf waits its
-- turn, submits small chunks, and after each one re-queues what the cache still lacks. A book that
-- keeps failing gets a final row after BookInfoManager's max_extract_tries.
function ShelfView:pollExtraction()
    local ext = self.extracting
    if self.bim:isExtractingInBackground() then
        if ext.launched and self:isShowing() then
            local cache = Shelf.readCache(self.bim)
            local missing = 0
            for _, book in ipairs(self.books) do
                if book.needs_extract and Shelf.needsExtract(self.bim, cache[book.file], self.cover_specs) then
                    missing = missing + 1
                end
            end
            self:setProgress(ext.total - missing)
        end
        UIManager:scheduleIn(2, self.poll)
        return
    end
    -- idle: our chunk ended (done or killed), or someone else's job did
    self.books = Shelf.load(self.scanned, self.bim, self.cover_specs)
    local pending = self:pendingFiles()
    if ext.launched then
        -- safety net: stop if chunks keep ending without the cache gaining anything
        ext.stalls = #pending >= (ext.last_pending or math.huge) and ext.stalls + 1 or 0
    end
    ext.last_pending = #pending
    if #pending == 0 or ext.stalls >= 3 then
        logger.info("Shelf: extracted", ext.total - #pending, "of", ext.total, "books in",
            time.to_ms(time.since(ext.start)), "ms")
        self.extracting = nil
        self:update("title")
        return
    end
    local chunk = {}
    for i = 1, math.min(EXTRACT_CHUNK, #pending) do
        chunk[i] = { filepath = pending[i], cover_specs = self.cover_specs }
    end
    ext.launched = self.bim:extractInBackground(chunk)
    if not ext.launched then -- fork failed
        self.extracting = nil
        return
    end
    if self:isShowing() then self:setProgress(ext.total - #pending) end
    UIManager:scheduleIn(2, self.poll)
end

--- Updates the progress line beside the title, repainting the title row only.
function ShelfView:setProgress(done)
    if done == self.extracting.done and self.progress_shown then return end
    self.extracting.done = done
    self.progress_shown = true
    if not self[1] then return end
    self[1][2]:free()
    self[1][2] = self:buildTitleRow()
    UIManager:setDirty(self.ui, "ui", self:titleRect())
end

function ShelfView:stop()
    if self.poll then
        UIManager:unschedule(self.poll)
    end
    if self.extracting and self.extracting.launched then
        self.bim:terminateBackgroundJobs()
    end
    self.extracting = nil
end

--- Rebuilds the view; `region` ("header", "title", "grid") is where the repaint starts, down to the bottom band.
function ShelfView:update(region)
    local start = time.now()
    self.shown, self.counts = Shelf.view(self.books, self.filter, self.sort, self.query)
    -- a selected book that is no longer shown (gone in a rescan) is no longer selected: the count is what can be seen,
    -- and the book comes back unselected
    if self.selected then
        local shown = {}
        for _, book in ipairs(self.shown) do
            shown[book.file] = true
        end
        for file in pairs(self.selected) do
            if not shown[file] then
                self.selected[file] = nil
            end
        end
    end
    local per_page = self.grid.cols * self.grid.rows
    self.pages = math.max(1, math.ceil(#self.shown / per_page))
    self.page = math.min(self.page, self.pages)
    if self[1] then self[1]:free() end
    self[1] = VerticalGroup:new{
        align = "left",
        self:buildHeader(),
        self:buildTitleRow(),
        self:buildGrid(per_page),
    }
    if not self.rendered_once then
        self.rendered_once = true
        logger.info("Shelf: first render built in", time.to_ms(time.since(start)), "ms")
    end
    -- the page capsule in the bottom band follows the page, and is repainted with the grid
    local band_changed = self:isCurrent() and self.ui:updateBottomBar()
    if region and self:isShowing() then
        local y = ({ header = 0, title = HEADER_H, grid = GRID_Y })[region]
        local rect = Geom:new{ x = self.dimen.x, y = self.dimen.y + y, w = self.width, h = self.height - y }
        UIManager:setDirty(self.ui, "ui", band_changed and rect:combine(self.ui.tabbar_dimen) or rect)
    end
end

function ShelfView:buildHeader()
    local field_w = self.width - 2 * GUTTER
    local border = Size.border.default
    local query = self.query
    local inner_h = SEARCH_H - 2 * border
    local inner_w = field_w - dp(11) - 2 * border
    local clear_w = query and dp(44) or 0
    local icon_size = dp(24)
    local field = HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w - clear_w, h = inner_h },
            HorizontalGroup:new{
                IconWidget:new{ icon = "eink/search", width = icon_size, height = icon_size, alpha = true },
                HorizontalSpan:new{ width = dp(7) },
                TextWidget:new{
                    text = query or _("Search books"),
                    face = Font:getFace("ui_body", 16),
                    bold = query ~= nil,
                    fgcolor = query and Palette.ink or Palette.ink_2,
                    max_width = inner_w - clear_w - icon_size - dp(7) - dp(8),
                },
            },
        },
    }
    if query then
        table.insert(field, ShelfWidgets.Tappable:new{
            callback = function()
                if not self.selected then self:setQuery(nil) end
            end,
            CenterContainer:new{ dimen = Geom:new{ w = clear_w, h = inner_h },
                IconWidget:new{ icon = "close", width = dp(20), height = dp(20) } },
        })
    end
    return VerticalGroup:new{
        VerticalSpan:new{ width = SEARCH_TOP },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = GUTTER },
            ShelfWidgets.Tappable:new{
                callback = function()
                    if not self.selected then self:showSearch() end
                end,
                FrameContainer:new{
                    radius = math.floor(SEARCH_H / 2),
                    bordersize = border,
                    color = Palette.ink,
                    background = Palette.paper,
                    padding = 0,
                    padding_left = dp(11),
                    field,
                },
            },
        },
    }
end

--- The title: 书架 with every book shown, else the filter and ▾ (在读 ▾).
function ShelfView:titleText()
    if self.filter == "all" then
        return _("Shelf")
    end
    return filter_texts[self.filter] .. " ▾"
end

--- A text action of the title row (导入, 选择, 全选, 取消): 16dp bold ink text after an optional circled line icon,
-- at least 44dp to tap; a short label sits at the `align` side ("left" or "right") of its target.
function ShelfView:textAction(icon, label, callback, align)
    local icon_size = dp(20)
    local content = HorizontalGroup:new{ align = "center" }
    if icon then
        table.insert(content, IconWidget:new{ icon = icon, width = icon_size, height = icon_size, alpha = true })
        table.insert(content, HorizontalSpan:new{ width = dp(4) })
    end
    table.insert(content, TextWidget:new{ text = label, face = Font:getFace("ui_title"), fgcolor = Palette.ink })
    local size = content:getSize()
    local container = align == "left" and LeftContainer or align == "right" and RightContainer or CenterContainer
    return ShelfWidgets.Tappable:new{
        callback = callback,
        container:new{ dimen = Geom:new{ w = math.max(TITLE_TAP_H, size.w), h = math.max(TITLE_TAP_H, size.h) },
            content },
    }
end

--- The title row's vertical place: `row` (tap_h tall) centered on TITLE_MID, in TITLE_ROW_H.
local function placeTitleRow(row, tap_h)
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = TITLE_MID - math.floor(tap_h / 2) },
        row,
        VerticalSpan:new{ width = TITLE_ROW_H - TITLE_MID - math.ceil(tap_h / 2) },
    }
end

function ShelfView:buildTitleRow()
    if self.selected then
        return self:buildSelectionRow()
    end
    local title = TextWidget:new{
        text = self:titleText(),
        face = Font:getFace("ui_headword", 22),
        bold = true,
        fgcolor = Palette.ink,
        max_width = math.floor((self.width - 2 * GUTTER) / 2),
    }
    local tap_h = math.max(TITLE_TAP_H, title:getSize().h) -- the largest interface font size outgrows it
    self.title_button = ShelfWidgets.Tappable:new{
        callback = function() self:showFilterMenu() end,
        LeftContainer:new{ dimen = Geom:new{ w = title:getSize().w, h = tap_h }, title },
    }
    self.import_button = self:textAction("eink/plus.circle", C_("Shelf", "Import"),
        function() ImportPage.show(self.ui) end)
    self.select_button = self:textAction("eink/check.circle", _("Select"), function() self:startSelection() end)
    -- between the title and the actions at the right: the indexing progress, right-aligned
    local free_w = self.width - 2 * GUTTER - title:getSize().w - self.import_button:getSize().w
        - TITLE_ACTION_GAP - self.select_button:getSize().w
    local row = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = GUTTER }, self.title_button }
    if self.extracting then
        local gap = dp(16)
        local progress = TextWidget:new{
            text = T(_("Indexing books %1 / %2…"), self.extracting.done, self.extracting.total),
            face = Font:getFace("ui_label"),
            fgcolor = Palette.ink,
            max_width = free_w - 2 * gap,
        }
        table.insert(row, HorizontalSpan:new{ width = free_w - gap - progress:getSize().w })
        table.insert(row, progress)
        free_w = gap
    end
    table.insert(row, HorizontalSpan:new{ width = free_w })
    table.insert(row, self.import_button)
    table.insert(row, HorizontalSpan:new{ width = TITLE_ACTION_GAP })
    table.insert(row, self.select_button)
    return placeTitleRow(row, tap_h)
end

--- Selection mode's title row: 全选 (or 取消全选) at the left, the count centered on the screen, 取消 at the right.
function ShelfView:buildSelectionRow()
    local count = #self:selectedBooks()
    local all_selected = count > 0 and count == #self.shown
    local left = self:textAction(nil, all_selected and _("Deselect all") or _("Select all"),
        function() self:selectAll(not all_selected) end, "left")
    local right = self:textAction(nil, _("Cancel"), function() self:endSelection() end, "right")
    local side_w = math.max(left:getSize().w, right:getSize().w)
    local heading = TextWidget:new{
        text = count == 0 and _("Select books") or T(NC_("Shelf", "1 book selected", "%1 books selected", count), count),
        face = Font:getFace("ui_title"),
        fgcolor = Palette.ink,
        max_width = self.width - 2 * (GUTTER + side_w + dp(8)),
    }
    local heading_x = math.floor((self.width - heading:getSize().w) / 2)
    local tap_h = math.max(left:getSize().h, right:getSize().h, heading:getSize().h)
    local row = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = GUTTER },
        left,
        HorizontalSpan:new{ width = heading_x - GUTTER - left:getSize().w },
        heading,
        HorizontalSpan:new{ width = self.width - GUTTER - right:getSize().w - heading_x - heading:getSize().w },
        right,
    }
    return placeTitleRow(row, tap_h)
end

function ShelfView:buildGrid(per_page)
    local grid_h = self.height - GRID_Y
    local g = self.grid
    local grid = VerticalGroup:new{ align = "left" }
    local first = (self.page - 1) * per_page
    if #self.shown == 0 then
        table.insert(grid, CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = dp(120) },
            TextWidget:new{ text = _("No books here yet."), face = Font:getFace("ui_title"), bold = true, fgcolor = Palette.ink },
        })
    end
    -- the full rows, then the next page's first row, cut off by the bottom band (painted over it)
    local clip = self:gridRect()
    for r = 1, g.rows + (g.peek and 1 or 0) do
        local row = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = g.gutter } }
        for c = 1, g.cols do
            local book = self.shown[first + (r - 1) * g.cols + c]
            if not book then break end
            if c > 1 then table.insert(row, HorizontalSpan:new{ width = g.col_gap }) end
            table.insert(row, self:buildCell(book, r > g.rows and clip or nil))
        end
        if #row == 1 then break end
        if r > 1 then table.insert(grid, VerticalSpan:new{ width = g.row_gap }) end
        table.insert(grid, row)
    end
    return TopContainer:new{ dimen = Geom:new{ w = self.width, h = grid_h }, grid }
end

function ShelfView:coverWidget(book, w, h)
    -- cover blobs are read for the visible books only
    local info = book.has_cover and self.bim and self.bim:getBookInfo(book.file, true)
    return ShelfWidgets.cover(book, w, h, info and info.cover_bb)
end

--- A cover and its title. Books here are all on the device: no downloaded mark, only 读完 on finished ones.
-- `clip`: the cell is cut off there, and only takes taps inside it.
function ShelfView:buildCell(book, clip)
    local g = self.grid
    local cover = self:coverWidget(book, g.cover_w, g.cover_h)
    if book.status == "complete" then
        local badge = ShelfWidgets.finishedBadge()
        badge.overlap_align = "right"
        cover = OverlapGroup:new{ dimen = Geom:new{ w = g.cover_w, h = g.cover_h }, cover, badge }
    end
    -- entering and leaving selection mode, or selecting, only repaints: the covers are not built again
    cover = ShelfWidgets.SelectableCover:new{
        selection = function() return self.selected and self.selected[book.file] == true end,
        cover,
    }
    return ShelfWidgets.Tappable:new{
        -- in selection mode, a tap or a long press selects; neither opens the book
        callback = function()
            if self.selected then
                self:toggleSelected(book, cover)
            else
                self:openBook(book)
            end
        end,
        hold_callback = function()
            if self.selected then
                self:toggleSelected(book, cover)
            else
                self:startSelection(book)
            end
        end,
        clip = clip,
        VerticalGroup:new{
            align = "left",
            cover,
            VerticalSpan:new{ width = g.title_gap },
            TextWidget:new{
                text = book.title,
                face = Font:getFace("ui_label"),
                bold = true,
                fgcolor = Palette.ink,
                max_width = g.cover_w,
                padding = 0,
            },
        },
    }
end

--- The filter menu under the title: 全部, 在读, 未读, 读完, 搁置 with their counts, the current one framed.
function ShelfView:showFilterMenu()
    local face = Font:getFace("ui_label_large")
    local function width(str)
        local widget = TextWidget:new{ text = str, face = face, bold = true }
        local w = widget:getSize().w
        widget:free()
        return w
    end
    local label_w, count_w = 0, 0
    for _, filter in ipairs(Shelf.filters) do
        label_w = math.max(label_w, width(filter_texts[filter]))
        count_w = math.max(count_w, width(tostring(self.counts[filter])))
    end
    local gap = dp(16)
    local rows = {}
    for _, filter in ipairs(Shelf.filters) do
        local current = filter == self.filter
        local h = dp(44)
        table.insert(rows, { {
            widget = HorizontalGroup:new{
                LeftContainer:new{ dimen = Geom:new{ w = label_w, h = h },
                    TextWidget:new{ text = filter_texts[filter], face = face, bold = current, fgcolor = Palette.ink } },
                HorizontalSpan:new{ width = gap },
                LeftContainer:new{ dimen = Geom:new{ w = count_w, h = h },
                    TextWidget:new{ text = tostring(self.counts[filter]), face = face, fgcolor = Palette.ink } },
            },
            selected = current,
            callback = function()
                self:closeFilterMenu()
                self:setFilter(filter)
            end,
        } })
    end
    local bubble = SelectionBubble:new{
        rows = rows,
        anchor_rects = { self.title_button.dimen }, -- as painted, where it was tapped
        tap_close_callback = function() self:closeFilterMenu() end,
    }
    self.filter_menu = bubble
    -- black and white over the page: "fast"; closing it shows the covers again ("ui")
    UIManager:show(bubble, "fast", bubble:getRefreshRegion())
end

function ShelfView:closeFilterMenu()
    local bubble = self.filter_menu
    if not bubble then return end
    self.filter_menu = nil
    UIManager:close(bubble, "ui", bubble:getRefreshRegion())
end

function ShelfView:setFilter(filter)
    if filter == self.filter then return end
    self.filter = filter
    G_reader_settings:saveSetting("shelf_filter", filter)
    self.page = 1
    self:update("title")
end

function ShelfView:setPage(page)
    if page == self.page then return end
    self.page = page
    self:update("grid")
end

--- Turns one page forward (1) or back (-1), if there is one.
function ShelfView:turnPage(delta)
    local page = self.page + delta
    if page >= 1 and page <= self.pages then
        self:setPage(page)
    end
end

--- Takes the order chosen in 设置 → 书架; the settings page covers the shelf, so nothing is repainted here.
function ShelfView:setSort(sort)
    if sort == self.sort then return end
    self.sort = sort
    self.page = 1
    self:update()
end

function ShelfView:setQuery(query)
    self.query = query ~= "" and query or nil
    self.page = 1
    self:update("header")
end

function ShelfView:showSearch()
    local dialog
    dialog = InputDialog:new{
        title = _("Search books"),
        input = self.query,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Search"),
                is_enter_default = true,
                callback = function()
                    UIManager:close(dialog)
                    self:setQuery(dialog:getInputText())
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function ShelfView:openBook(book)
    filemanagerutil.openFile(self.ui, book.file)
end

--- The selected books of the filtered shelf, on every page, in shelf order.
function ShelfView:selectedBooks()
    local books = {}
    if not self.selected then return books end
    for _, book in ipairs(self.shown) do
        if self.selected[book.file] then
            table.insert(books, book)
        end
    end
    return books
end

--- Enters selection mode, with `book` selected if given (a long press on its cover), else none (选择).
function ShelfView:startSelection(book)
    self.selected = {}
    if book then
        self.selected[book.file] = true
    end
    self:refreshSelection()
end

--- Leaves selection mode (取消, Back), selecting nothing more.
function ShelfView:endSelection()
    if not self.selected then return end
    self.selected = nil
    self:refreshSelection()
end

--- 全选 (`on`) selects every book of the filtered shelf, not only the page shown; 取消全选 clears the selection.
function ShelfView:selectAll(on)
    self.selected = {}
    if on then
        for _, book in ipairs(self.shown) do
            self.selected[book.file] = true
        end
    end
    self:refreshSelection()
end

--- Selects or leaves out one book; `cover` is its SelectableCover, the only cover to repaint.
function ShelfView:toggleSelected(book, cover)
    self.selected[book.file] = not self.selected[book.file] or nil
    self:refreshSelection(cover:getSelectionRect())
end

--- Rebuilds the title row and the band for the selection, and repaints them with `rect` ("ui"), by default
-- everything from the title row down. The covers read the selection when painted.
function ShelfView:refreshSelection(rect)
    self[1][2]:free()
    self[1][2] = self:buildTitleRow()
    local band_changed = self.ui:updateBottomBar()
    if not self:isShowing() then return end
    local title = self:titleRect()
    if rect then
        UIManager:setDirty(self.ui, "ui", title)
    else
        rect = Geom:new{ x = title.x, y = title.y, w = self.width, h = self.height - HEADER_H }
    end
    UIManager:setDirty(self.ui, "ui", rect)
    if band_changed then
        UIManager:setDirty(self.ui, "ui", self.ui.tabbar_dimen)
    end
end

--- What the band shows in selection mode, in the tab icons' place: `items`, 移出书架 and 标记为, `enabled` once a
-- book is selected. nil outside selection mode.
function ShelfView:bandActions()
    if not self.selected then return end
    return {
        enabled = #self:selectedBooks() > 0,
        items = {
            { icon = "eink/shelf.remove", callback = function() self:confirmRemove(self:selectedBooks()) end },
            { icon = "eink/mark", callback = function() self:confirmMark() end },
        },
    }
end

--- Asks in a confirm layer over the shelf; Cancel (or a tap on the page, or Back) keeps the selection as it is.
function ShelfView:confirm(question, actions)
    local layer = ConfirmLayer:new{ text = question, actions = actions }
    UIManager:show(layer, "ui", layer:getRefreshRegion())
end

--- 移出书架 for `books` (the selection, or the book of 文件's sheet), once confirmed.
function ShelfView:confirmRemove(books)
    local question = #books == 1 and T(_("Remove “%1” from the shelf? The file stays on the device."), books[1].title)
        or T(N_("Remove 1 book from the shelf? The file stays on the device.",
            "Remove %1 books from the shelf? The files stay on the device.", #books), #books)
    self:confirm(question, { { text = C_("Shelf", "Remove"), callback = function() self:removeBooks(books) end } })
end

--- 标记为 for the selected books: 读完, 在读 or 搁置.
function ShelfView:confirmMark()
    local books = self:selectedBooks()
    local question = #books == 1 and T(_("Mark “%1” as"), books[1].title)
        or T(N_("Mark 1 book as", "Mark %1 books as", #books), #books)
    local actions = {}
    for _, status in ipairs(mark_statuses) do
        table.insert(actions, { text = mark_texts[status], callback = function() self:markBooks(books, status) end })
    end
    self:confirm(question, actions)
end

--- Hides `books` from the shelf, leaving their files where they are, and ends selection mode if on.
function ShelfView:removeBooks(books)
    local files = {}
    for _, book in ipairs(books) do
        table.insert(files, book.file)
    end
    Shelf.remove(files)
    local removed = Shelf.removed()
    for i = #self.books, 1, -1 do
        if removed[ffiUtil.realpath(self.books[i].file) or self.books[i].file] then
            table.remove(self.books, i)
        end
    end
    self.selected = nil
    self:update("title")
    local text = #books == 1
        and T(_("Removed from shelf. The file is still in %1"), filemanagerutil.abbreviate(util.splitFilePathName(books[1].file)))
        or T(N_("Removed 1 book from the shelf. The file stays on the device.",
            "Removed %1 books from the shelf. The files stay on the device.", #books), #books)
    UIManager:show(Toast:new{ text = text, close_refresh_type = "ui" }) -- it is over covers
end

--- Sets the status of `books`, which is saved with each book, and ends selection mode if on. A book whose status
-- could not be saved keeps the one it had, and the toast says how many were.
function ShelfView:markBooks(books, status)
    local saved = 0
    for _, book in ipairs(books) do
        -- one book failing (even with an error) leaves the others to go on
        local ok, done = pcall(Shelf.setStatus, book.file, status)
        if ok and done then
            book.status = status
            saved = saved + 1
        elseif not ok then
            logger.warn("Shelf: setting the status of", book.file, "failed:", done)
        end
    end
    self.selected = nil
    self:update("title")
    local text
    if saved == #books then
        text = T(N_("Marked 1 book as %2", "Marked %1 books as %2", saved), saved, mark_texts[status])
    elseif saved == 0 then
        text = T(N_("Could not save the status of 1 book.", "Could not save the status of %1 books.", #books), #books)
    else
        text = T(_("Marked %1 of %2 books as %3. The rest could not be saved."), saved, #books, mark_texts[status])
    end
    UIManager:show(Toast:new{ text = text, close_refresh_type = "ui" })
end

--- The book sheet that 文件 shows on a long press (FilesChooser); its rows are also what tests drive.
-- Its status rows and 移出书架 take the same paths as selection mode's actions.
function ShelfView:getBookActions(book)
    return {
        {
            text = book.status == "new" and _("Start reading") or _("Continue reading"),
            callback = function() self:openBook(book) end,
        },
        {
            text = _("Book information"),
            callback = function() self.ui.bookinfo:show(book.file) end,
        },
        book.status == "complete" and {
            text = _("Mark as reading"),
            callback = function() self:markBooks({ book }, "reading") end,
        } or {
            text = _("Mark as finished"),
            callback = function() self:markBooks({ book }, "complete") end,
        },
        book.status == "abandoned" and {
            text = _("Mark as reading"),
            callback = function() self:markBooks({ book }, "reading") end,
        } or {
            text = _("Put on hold"),
            callback = function() self:markBooks({ book }, "abandoned") end,
        },
        {
            text = _("Remove from shelf"),
            callback = function() self:confirmRemove({ book }) end,
        },
    }
end

function ShelfView:showBookSheet(book)
    local header = HorizontalGroup:new{
        align = "center",
        self:coverWidget(book, dp(56), dp(75)),
        HorizontalSpan:new{ width = dp(14) },
        VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = book.title, face = Font:getFace("ui_body"), bold = true,
                max_width = self.width - 2 * GUTTER - dp(70) },
            TextWidget:new{ text = book.authors and (book.authors .. " · " .. statusText(book)) or statusText(book),
                face = Font:getFace("ui_label"), fgcolor = Palette.ink_2, max_width = self.width - 2 * GUTTER - dp(70) },
        },
    }
    ShelfWidgets.BottomSheet:new{
        title = book.title,
        header = VerticalGroup:new{ align = "left", header, VerticalSpan:new{ width = dp(8) } },
        rows = self:getBookActions(book),
    }:show()
end

ShelfView.statusText = statusText

--- The entry of 设置 → 书架 that orders the shelf: 最近阅读 (the default), 书名 or 作者.
function ShelfView.sortMenuItem()
    local entries = {}
    for _, sort in ipairs(Shelf.sorts) do
        table.insert(entries, {
            text = sort_texts[sort],
            radio = true,
            checked_func = function() return savedSort() == sort end,
            callback = function()
                G_reader_settings:saveSetting("shelf_sort", sort)
                UIManager:broadcastEvent(Event:new("ShelfSortChanged", sort))
            end,
        })
    end
    return { text = _("Sort by"), sub_item_table = entries }
end

return ShelfView
