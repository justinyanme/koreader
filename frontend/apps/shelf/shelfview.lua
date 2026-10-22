--[[--
The 书架 tab: search field, status chips with counts, a paged cover grid.

Every interaction repaints only its own band with a "ui" refresh (DESIGN.md,
Refresh mapping); returning from the reader is already a "full" refresh.
]]

local BookList = require("ui/widget/booklist")
local CenterContainer = require("ui/widget/container/centercontainer")
local DocSettings = require("docsettings")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Notification = require("ui/widget/notification")
local Palette = require("ui/palette")
local Shelf = require("apps/shelf/shelf")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
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

local function dp(n) return Screen:scaleBySize(n) end

local GUTTER = dp(24)
local HEADER_H = dp(12) + dp(44) -- top padding + search row
local CHIPS_H = dp(12) + dp(30) -- gap + chips
local GRID_TOP = dp(18)
local PAGER_H = dp(44)
local TEXT_H = ShelfWidgets.TEXT_H
local ROW_GAP = ShelfWidgets.ROW_GAP
local EXTRACT_CHUNK = 40 -- books per background job, well under BookInfoManager's 5 minute watchdog

local filter_texts = {
    all = C_("Status of group of books", "All"),
    reading = C_("Status of group of books", "Reading"),
    new = C_("Status of group of books", "New"),
    complete = C_("Status of group of books", "Finished"),
}
local sort_texts = {
    recent = _("Last read date"),
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

local function homeDir()
    return G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
end

local ShelfView = WidgetContainer:extend{
    ui = nil, -- the FileManager
    width = nil,
    height = nil,
}

function ShelfView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    -- CoverBrowser's cache, when that plugin is loaded
    self.bim = package.loaded["bookinfomanager"]
    self.filter = "all"
    self.sort = G_reader_settings:readSetting("shelf_sort", "recent")
    self.page = 1
    self:computeGrid()
    self:reload(true)
    self:update()
end

function ShelfView:computeGrid()
    local grid = ShelfWidgets.gridGeometry(self.width, self.height - HEADER_H - CHIPS_H - GRID_TOP - PAGER_H)
    self.cols, self.rows, self.col_gap = grid.cols, grid.rows, grid.col_gap
    self.cover_w, self.cover_h = grid.cover_w, grid.cover_h
    self.cover_specs = { max_cover_w = self.cover_w, max_cover_h = self.cover_h }
end

--- Re-reads statuses and the cache, and queues extraction of what the cache lacks.
-- `rescan` also walks the home folder again; tab switches keep the last scan.
function ShelfView:reload(rescan)
    if rescan or not self.scanned then
        self.scanned = Shelf.scan(homeDir())
    end
    self.books = Shelf.load(self.scanned, self.bim, self.cover_specs)
    if self.bim and not self.extracting and #self:pendingFiles() > 0 then
        self.extracting = { total = #self:pendingFiles(), done = 0, stalls = 0, start = time.now() }
        self.poll = self.poll or function() self:pollExtraction() end
        UIManager:scheduleIn(1, self.poll)
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

function ShelfView:isShowing()
    return self.ui.content and self.ui.content[1] == self
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
        if self:isShowing() then self:update("list") else self:update() end
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

--- Updates the progress line, repainting the pager band only.
function ShelfView:setProgress(done)
    if done == self.extracting.done and self.progress_shown then return end
    self.extracting.done = done
    self.progress_shown = true
    if not self[1] then return end
    self[1][4]:free()
    self[1][4] = self:buildPager()
    UIManager:setDirty(self.ui, "ui", Geom:new{ x = self.dimen.x, y = self.dimen.y + self.height - PAGER_H, w = self.width, h = PAGER_H })
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

--- Rebuilds the view; `region` ("header", "list", "grid", "pager") names the band to refresh.
function ShelfView:update(region)
    local start = time.now()
    self.shown, self.counts = Shelf.view(self.books, self.filter, self.sort, self.query)
    local per_page = self.cols * self.rows
    self.pages = math.max(1, math.ceil(#self.shown / per_page))
    self.page = math.min(self.page, self.pages)
    if self[1] then self[1]:free() end
    self[1] = VerticalGroup:new{
        align = "left",
        self:buildHeader(),
        self:buildChips(),
        self:buildGrid(per_page),
        self:buildPager(),
    }
    if not self.rendered_once then
        self.rendered_once = true
        logger.info("Shelf: first render built in", time.to_ms(time.since(start)), "ms")
    end
    if region then
        local y = ({ header = 0, list = HEADER_H, grid = HEADER_H + CHIPS_H })[region]
        UIManager:setDirty(self.ui, "ui", Geom:new{ x = self.dimen.x, y = self.dimen.y + y, w = self.width, h = self.height - y })
    end
end

function ShelfView:buildHeader()
    local field_h = dp(40)
    local field_w = self.width - 2 * GUTTER - dp(10) - dp(44)
    local query = self.query
    local inner_h = field_h - 2 * Size.border.button
    local inner_w = field_w - dp(14) - 2 * Size.border.button
    local clear_w = query and dp(36) or 0
    local field = HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w - clear_w, h = inner_h },
            HorizontalGroup:new{
                IconWidget:new{ icon = "appbar.search", width = dp(18), height = dp(18), dim = true },
                HorizontalSpan:new{ width = dp(8) },
                TextWidget:new{
                    text = query or _("Search books"),
                    face = Font:getFace("ui_label_large"),
                    fgcolor = query and Palette.ink or Palette.ink_2,
                    max_width = inner_w - clear_w - dp(18) - dp(8) - dp(8),
                },
            },
        },
    }
    if query then
        table.insert(field, ShelfWidgets.Tappable:new{
            callback = function() self:setQuery(nil) end,
            CenterContainer:new{ dimen = Geom:new{ w = clear_w, h = inner_h },
                IconWidget:new{ icon = "close", width = dp(18), height = dp(18) } },
        })
    end
    local row = HorizontalGroup:new{
        align = "center",
        ShelfWidgets.Tappable:new{
            callback = function() self:showSearch() end,
            FrameContainer:new{
                radius = math.floor(field_h / 2),
                bordersize = Size.border.button,
                background = Palette.paper,
                padding = 0,
                padding_left = dp(14),
                field,
            },
        },
        HorizontalSpan:new{ width = dp(10) },
        ShelfWidgets.Tappable:new{
            callback = function() self:showSortSheet() end,
            CenterContainer:new{ dimen = Geom:new{ w = dp(44), h = dp(44) },
                IconWidget:new{ icon = "eink/sliders", width = dp(24), height = dp(24) } },
        },
    }
    return LeftContainer:new{
        dimen = Geom:new{ w = self.width, h = HEADER_H },
        HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, VerticalGroup:new{ VerticalSpan:new{ width = dp(12) }, row } },
    }
end

function ShelfView:buildChips()
    local chips = HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER } }
    for i, filter in ipairs(Shelf.filters) do
        if i > 1 then table.insert(chips, HorizontalSpan:new{ width = dp(8) }) end
        table.insert(chips, ShelfWidgets.Chip:new{
            text = filter_texts[filter],
            count = self.counts[filter],
            selected = filter == self.filter,
            callback = function() self:setFilter(filter) end,
        })
    end
    return VerticalGroup:new{ align = "left", VerticalSpan:new{ width = dp(12) }, chips }
end

function ShelfView:buildGrid(per_page)
    local grid_h = self.height - HEADER_H - CHIPS_H - PAGER_H
    local grid = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = GRID_TOP } }
    local first = (self.page - 1) * per_page
    if #self.shown == 0 then
        table.insert(grid, CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = dp(120) },
            TextWidget:new{ text = _("No books here yet."), face = Font:getFace("ui_label_large"), fgcolor = Palette.ink_2 },
        })
    end
    for r = 1, self.rows do
        local row = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = GUTTER } }
        for c = 1, self.cols do
            local book = self.shown[first + (r - 1) * self.cols + c]
            if not book then break end
            if c > 1 then table.insert(row, HorizontalSpan:new{ width = self.col_gap }) end
            table.insert(row, self:buildCell(book))
        end
        if #row == 1 then break end
        if r > 1 then table.insert(grid, VerticalSpan:new{ width = ROW_GAP }) end
        table.insert(grid, row)
    end
    return TopContainer:new{ dimen = Geom:new{ w = self.width, h = grid_h }, grid }
end

function ShelfView:coverWidget(book, w, h)
    -- cover blobs are read for the visible books only
    local info = book.has_cover and self.bim and self.bim:getBookInfo(book.file, true)
    return ShelfWidgets.cover(book, w, h, info and info.cover_bb)
end

function ShelfView:buildCell(book)
    return ShelfWidgets.Tappable:new{
        callback = function() self:openBook(book) end,
        hold_callback = function() self:showBookSheet(book) end,
        VerticalGroup:new{
            align = "left",
            self:coverWidget(book, self.cover_w, self.cover_h),
            TopContainer:new{
                dimen = Geom:new{ w = self.cover_w, h = TEXT_H },
                VerticalGroup:new{
                    align = "left",
                    VerticalSpan:new{ width = dp(8) },
                    TextBoxWidget:new{
                        text = book.title,
                        face = Font:getFace("ui_label"),
                        width = self.cover_w,
                        height = dp(36),
                        height_adjust = true,
                        height_overflow_show_ellipsis = true,
                    },
                    TextWidget:new{
                        text = statusText(book),
                        face = Font:getFace("ui_micro"),
                        fgcolor = Palette.ink_2,
                        max_width = self.cover_w,
                        padding = 0,
                    },
                },
            },
        },
    }
end

function ShelfView:buildPager()
    local band = HorizontalGroup:new{ align = "center" }
    if self.pages > 1 then
        table.insert(band, ShelfWidgets.Pager:new{
            page = self.page,
            pages = self.pages,
            on_change = function(page) self:setPage(page) end,
        })
    end
    if self.extracting then
        if #band > 0 then table.insert(band, HorizontalSpan:new{ width = dp(14) }) end
        table.insert(band, TextWidget:new{
            text = T(_("Indexing books %1 / %2…"), self.extracting.done, self.extracting.total),
            face = Font:getFace("ui_caption"),
            fgcolor = Palette.ink_2,
        })
    end
    return CenterContainer:new{ dimen = Geom:new{ w = self.width, h = PAGER_H }, band }
end

function ShelfView:setFilter(filter)
    self.filter = filter
    self.page = 1
    self:update("list")
end

function ShelfView:setPage(page)
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

function ShelfView:setSort(sort)
    self.sort = sort
    G_reader_settings:saveSetting("shelf_sort", sort)
    self.page = 1
    self:update("grid")
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

function ShelfView:showSortSheet()
    local rows = {}
    for _, sort in ipairs(Shelf.sorts) do
        table.insert(rows, {
            text = sort_texts[sort],
            checked = sort == self.sort,
            callback = function() self:setSort(sort) end,
        })
    end
    ShelfWidgets.BottomSheet:new{ title = _("Sort by"), rows = rows }:show()
end

function ShelfView:openBook(book)
    filemanagerutil.openFile(self.ui, book.file)
end

function ShelfView:setStatus(book, status)
    local doc_settings = DocSettings:open(book.file)
    local summary = doc_settings:readSetting("summary") or {}
    summary.status = status
    filemanagerutil.saveSummary(doc_settings, summary)
    BookList.setBookInfoCacheProperty(book.file, "status", status)
    book.status = status
    self:update("list")
end

function ShelfView:removeBook(book)
    Shelf.remove(book.file)
    for i, b in ipairs(self.books) do
        if b == book then
            table.remove(self.books, i)
            break
        end
    end
    self:update("list")
    UIManager:show(Notification:new{
        text = T(_("Removed from shelf. The file is still in %1"), filemanagerutil.abbreviate(util.splitFilePathName(book.file))),
    })
end

--- The long-press sheet; its rows are also what tests drive.
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
            callback = function() self:setStatus(book, "reading") end,
        } or {
            text = _("Mark as finished"),
            callback = function() self:setStatus(book, "complete") end,
        },
        book.status == "abandoned" and {
            text = _("Mark as reading"),
            callback = function() self:setStatus(book, "reading") end,
        } or {
            text = _("Put on hold"),
            callback = function() self:setStatus(book, "abandoned") end,
        },
        {
            text = _("Remove from shelf"),
            callback = function() self:removeBook(book) end,
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

return ShelfView
