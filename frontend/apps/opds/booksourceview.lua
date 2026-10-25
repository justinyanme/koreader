--[[--
The 书源 page: an OPDS source browsed as a remote shelf (apps/opds/booksource for the data).

A full-screen paper page over the file manager, with a page stack: a source's
home (search field, 分类 sheet, cover grid), category lists and book lists
below it, 简介 text, and the source list (管理书源). Going back uses the
loaded pages; nothing is fetched again.

Tapping a cover downloads its preferred format in a subprocess (through the
download bridge where there are none, see BookSource.bridgeDownload), with
progress on the tile; tapping it again cancels. A finished download marks the tile, so
several can run at once; tapping a marked cover opens the book. Holding a cover
opens its sheet (other formats, re-download).

Refreshes: opening and closing the page, pushing and popping pages, turning
pages and sheets are "ui" on their own rect, the confirmation layer "ui" on the
whole screen it pales; download progress is "fast" on the tile's band and
caption; covers arriving are one "ui" repaint of the grid.
]]

local BookSource = require("apps/opds/booksource")
local BottomSheet = require("ui/widget/bottomsheet")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmLayer = require("ui/widget/confirmlayer")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local OverlapGroup = require("ui/widget/overlapgroup")
local Palette = require("ui/palette")
local RenderImage = require("ui/renderimage")
local Replacements = require("apps/replacements")
local Shelf = require("apps/shelf/shelf")
local ShelfView = require("apps/shelf/shelfview")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Toast = require("ui/widget/toast")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ffi = require("ffi")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/sha2").md5
local socketutil = require("socketutil")
local util = require("util")
local Screen = Device.screen
local T = ffiUtil.template
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local C = ffi.C
require("ffi/posix_h")

local function dp(n) return Screen:scaleBySize(n) end

local GUTTER = dp(24)
local NAV_H = dp(52)
local SEARCH_H = dp(12) + dp(44)
local CHIPS_H = dp(12) + dp(30)
local CAPTION_H = dp(30)
local GRID_TOP = dp(12)
local PAGER_H = EinkControls.BottomBar.height
local ROW_H = dp(56)
local BAND_H = dp(24)
local THUMB_WAIT = 3 -- seconds before the grid shows the covers that arrived
local THUMB_JOBS = 2 -- thumbnails fetched at once through the download bridge

local function text(str, face, color, max_width, bold)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink,
        max_width = max_width, bold = bold, padding = 0 }
end

local function rule(w, color)
    return LineWidget:new{ background = color or Palette.rule, dimen = Geom:new{ w = w, h = Size.border.default } }
end

local function icon(name, size, dim)
    return IconWidget:new{ icon = name, width = size or dp(24), height = size or dp(24), alpha = true, dim = dim or nil }
end

--- Makes a tap target at least 44dp tall, whatever its drawn height (DESIGN.md).
local function tallTarget(tappable)
    tappable.ges_events.Tap = { GestureRange:new{ ges = "tap", range = function()
        local d = tappable.dimen
        if not d then return end
        local grow = math.max(0, dp(44) - d.h)
        return Geom:new{ x = d.x, y = d.y - math.floor(grow / 2), w = d.w, h = d.h + grow }
    end } }
    return tappable
end

local function isUnder(path, dir)
    path, dir = ffiUtil.realpath(path) or path, ffiUtil.realpath(dir) or dir
    return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

--- A download folder as the prototype names it: 主目录, 主目录/sub, or the full path outside the home folder.
local function folderLabel(path)
    local home = Shelf.homeDir()
    if not isUnder(path, home) then return path end
    local rel = (ffiUtil.realpath(path) or path):sub(#(ffiUtil.realpath(home) or home) + 2)
    return rel == "" and _("Home folder") or _("Home folder") .. "/" .. rel
end

-- Bytes the child process wrote to `fd` so far, without blocking.
local function readAvailable(fd)
    local n = ffiUtil.getNonBlockingReadSize(fd) or 0
    if n <= 0 then return "" end
    local buf = ffi.new("char[?]", n)
    local got = tonumber(C.read(fd, buf, n))
    return got and got > 0 and ffi.string(buf, got) or ""
end

local function sizeText(size)
    return size and util.getFriendlySize(size)
end

--- "EPUB · 296 KB · en · 1925": what the book sheet shows under the author.
local function metaLine(book, format)
    local parts = {}
    for _, part in ipairs{ format and format.ext:upper(), format and sizeText(format.size), book.language, book.year } do
        table.insert(parts, part)
    end
    return table.concat(parts, " · ")
end

local BookSourceView = InputContainer:extend{
    opds = nil, -- the OPDS plugin: servers, settings
    ui = nil, -- the file manager
}

--- Opens the 书源 page: the only source's home, or the source list.
function BookSourceView.show(opds)
    local view = BookSourceView:new{ opds = opds, ui = opds.ui }
    if #opds.servers == 1 then
        view:enterSource(opds.servers[1])
    else
        view:push{ kind = "manage" }
    end
    UIManager:show(view, "ui", view.dimen)
    view.shown = true
    return view
end

function BookSourceView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    self.content_w = self.dimen.w - 2 * GUTTER
    -- everything below the nav bar: what a new feed, a next batch or a search repaints
    self.content_rect = Geom:new{ x = 0, y = NAV_H, w = self.dimen.w, h = self.dimen.h - NAV_H }
    self.stack = {}
    self.thumb_gen = 0
    self.thumbs = {} -- thumbnail URL -> blitbuffer, scaled to the grid's cover size
    self.thumb_tried = {}
    self.downloads = {} -- book key -> running download
    self.thumb_jobs = {} -- download bridge jobs fetching thumbnails -> true
    self.ges_events = {
        TapBlock = { GestureRange:new{ ges = "tap", range = self.dimen } }, -- nothing reaches the page below
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events.Back = { { Device.input.group.Back } }
        self.key_events.NextPage = { { Device.input.group.PgFwd } }
        self.key_events.PrevPage = { { Device.input.group.PgBack } }
    end
end

function BookSourceView:top()
    return self.stack[#self.stack]
end

-- Page stack

function BookSourceView:push(page)
    page.page_no = page.page_no or 1
    table.insert(self.stack, page)
    if page.kind == "home" or page.kind == "feed" then
        self:load(page)
    end
    self:build()
    if self.shown then
        UIManager:setDirty(self, "ui", self.dimen)
    end
end

function BookSourceView:pop()
    table.remove(self.stack)
    if #self.stack == 0 then
        return self:close()
    end
    self:build()
    UIManager:setDirty(self, "ui", self.dimen)
end

function BookSourceView:enterSource(source)
    self:push{ kind = "home", source = source, title = source.title }
end

function BookSourceView:close(no_refresh)
    if self.closed then return end
    self.closed = true
    -- what this page opened on top goes first: it may show our thumbnails, freed with the page
    self:closeSheet()
    self:closeInput()
    if self.path_chooser and UIManager:isWidgetShown(self.path_chooser) then
        UIManager:close(self.path_chooser)
    end
    self.path_chooser = nil
    local canceled = next(self.downloads) ~= nil
    for key in pairs(self.downloads) do
        self:cancelDownload(key, true)
    end
    for job in pairs(self.thumb_jobs) do
        job:cancel()
    end
    self.thumb_jobs = {}
    if no_refresh then
        UIManager:close(self)
    else
        UIManager:close(self, "ui", self.dimen)
    end
    if canceled then
        UIManager:show(Toast:new{ text = _("Download canceled"), close_refresh_type = "ui" })
    end
end

function BookSourceView:onCloseWidget()
    for _, bb in pairs(self.thumbs) do
        bb:free()
    end
    self.thumbs = {}
    if self[1] then self[1]:free() end
end

function BookSourceView:onTapBlock()
    return true
end

function BookSourceView:onBack()
    self:pop()
    return true
end

function BookSourceView:onNextPage()
    local page = self:top()
    if page then self:turnPage(page.page_no + 1) end
    return true
end

function BookSourceView:onPrevPage()
    local page = self:top()
    if page then self:turnPage(page.page_no - 1) end
    return true
end

function BookSourceView:onSwipe(_, ges)
    if ges.direction == "west" or ges.direction == "north" then
        return self:onNextPage()
    elseif ges.direction == "east" or ges.direction == "south" then
        return self:onPrevPage()
    end
    return false
end

-- Loading

--- Fetches a page's feed after the loading state is on screen; asks for Wi-Fi first when offline.
function BookSourceView:load(page)
    page.result = { state = NetworkMgr:isOnline() and "loading" or "offline" }
    NetworkMgr:runWhenOnline(function()
        if self.closed then return end
        if page.result.state == "offline" then
            page.result = { state = "loading" }
            self:refreshContent(page)
        end
        UIManager:nextTick(function()
            if self.closed then return end
            self:fetch(page)
            self:refreshContent(page)
            self:prefetch(page)
        end)
    end)
end

function BookSourceView:fetch(page)
    local source = page.source
    if page.kind == "home" and not page.query and not page.url then
        local root = BookSource.load(source, source.url, true)
        page.root = root.state == "ok" and root or nil
        -- an unreachable search description: no more requests in this open, the root stands in for the home
        local home = root.state == "ok" and root.search_failed ~= "unreachable" and BookSource.homeUrl(root)
        page.home_url = home or source.url
        page.result = (not home or home == root.url) and root or BookSource.load(source, home)
    else
        local feed_url = page.query and BookSource.searchUrl(page.root, page.query) or page.url
        page.result = BookSource.load(source, feed_url)
    end
end

function BookSourceView:retry()
    local page = self:top()
    self:load(page)
    self:refreshContent(page)
end

--- Rebuilds `page` if it shows, and repaints everything below the nav bar (search row, chips, caption, grid, pager).
function BookSourceView:refreshContent(page)
    if self.closed or not self.shown or self:top() ~= page then return end
    self:build()
    UIManager:setDirty(self, "ui", self.content_rect)
end

-- Building

function BookSourceView:build()
    local page = self:top()
    local group = VerticalGroup:new{ align = "left", self:buildNavBar(page) }
    local y = NAV_H
    if page.kind == "home" then
        table.insert(group, self:buildSearch(page))
        y = y + SEARCH_H
    end
    local result = page.result
    if result and result.state == "ok" and result.facets then
        table.insert(group, self:buildFacets(page))
        y = y + CHIPS_H
    end
    if page.kind == "home" and result and result.state == "ok" and #result.books > 0 then
        table.insert(group, self:buildCaption(page))
        y = y + CAPTION_H
    end
    self.body_rect = Geom:new{ x = 0, y = y, w = self.dimen.w, h = self.dimen.h - y }
    self.pager_rect = Geom:new{ x = 0, y = self.dimen.h - PAGER_H, w = self.dimen.w, h = PAGER_H }
    self.cells = {}
    page.per_page = nil
    local body_h = self.dimen.h - y - PAGER_H
    local body, pager
    if page.kind == "manage" then
        body, pager = self:buildManage(page, body_h)
    elseif page.kind == "text" then
        body, pager = self:buildText(page, body_h)
    elseif result.state ~= "ok" then
        body = self:buildState(page)
    elseif #result.books > 0 then
        body, pager = self:buildGrid(page, body_h, y)
    elseif #result.navs > 0 then
        body, pager = self:buildList(page, body_h)
    else
        body = self:buildState(page)
    end
    table.insert(group, TopContainer:new{ dimen = Geom:new{ w = self.dimen.w, h = body_h }, body })
    table.insert(group, pager or self:buildPager(page, 1))
    if self[1] then self[1]:free() end
    self[1] = FrameContainer:new{ bordersize = 0, padding = 0, background = Palette.paper, group }
end

function BookSourceView:buildNavBar(page)
    local h = NAV_H - Size.border.default
    local function button(name, callback)
        return ShelfWidgets.Tappable:new{
            callback = callback,
            CenterContainer:new{ dimen = Geom:new{ w = NAV_H, h = h }, icon(name) },
        }
    end
    local right = HorizontalSpan:new{ width = NAV_H }
    if page.kind == "home" then
        right = button("eink/more", function() self:showSourceSheet(page.source) end)
    elseif page.kind == "manage" then
        right = button("eink/plus", function() self:showEditSheet() end)
    end
    local titles = { manage = _("Manage sources"), text = C_("OPDS book", "Description") }
    return VerticalGroup:new{
        HorizontalGroup:new{
            HorizontalSpan:new{ width = NAV_H },
            CenterContainer:new{ dimen = Geom:new{ w = self.dimen.w - 2 * NAV_H, h = h },
                text(titles[page.kind] or page.title or "", "ui_title", Palette.ink, self.dimen.w - 2 * NAV_H, true) },
            right,
        },
        rule(self.dimen.w, Palette.ink),
    }
end

function BookSourceView:buildSearch(page)
    local field_h = dp(40)
    local has_nav = page.root and #page.root.navs > 0
    local field_w = self.content_w - (has_nav and dp(10) + dp(44) or 0)
    local searchable = page.root and page.root.search_url
    local query = page.query
    local inner_h = field_h - 2 * Size.border.button
    local inner_w = field_w - dp(14) - 2 * Size.border.button
    local clear_w = query and dp(44) or 0
    local field = HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w - clear_w, h = inner_h },
            HorizontalGroup:new{
                EinkControls.Glyph:new{ icon = "eink/search", width = dp(18), height = dp(18), alpha = true,
                    enabled = searchable and true or false },
                HorizontalSpan:new{ width = dp(8) },
                text(query or _("Search this source"), "ui_label_large",
                    query and Palette.ink or searchable and Palette.ink_2 or Palette.ink_3,
                    inner_w - clear_w - dp(34)),
            },
        },
    }
    if query then
        table.insert(field, tallTarget(ShelfWidgets.Tappable:new{
            callback = function() self:search(nil) end,
            CenterContainer:new{ dimen = Geom:new{ w = clear_w, h = inner_h }, icon("eink/close", dp(18)) },
        }))
    end
    local row = HorizontalGroup:new{
        align = "center",
        ShelfWidgets.Tappable:new{
            callback = searchable and function() self:showSearch(page) end or nil,
            FrameContainer:new{
                radius = math.floor(field_h / 2),
                bordersize = Size.border.button,
                color = searchable and Palette.ink or Palette.rule,
                background = Palette.paper,
                padding = 0,
                padding_left = dp(14),
                field,
            },
        },
    }
    if has_nav then
        table.insert(row, HorizontalSpan:new{ width = dp(10) })
        table.insert(row, ShelfWidgets.Tappable:new{
            callback = function() self:showNavSheet(page) end,
            CenterContainer:new{ dimen = Geom:new{ w = dp(44), h = dp(44) }, icon("eink/grid") },
        })
    end
    return LeftContainer:new{
        dimen = Geom:new{ w = self.dimen.w, h = SEARCH_H },
        HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, VerticalGroup:new{ VerticalSpan:new{ width = dp(12) }, row } },
    }
end

--- Facet chips: one group shows its facets; several share a single "Filters" chip.
function BookSourceView:buildFacets(page)
    local groups = {}
    for name in pairs(page.result.facets) do table.insert(groups, name) end
    table.sort(groups)
    local chips = HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER } }
    local function add(chip)
        if #chips > 1 then table.insert(chips, HorizontalSpan:new{ width = dp(8) }) end
        table.insert(chips, chip)
    end
    if #groups == 1 then
        for _, link in ipairs(page.result.facets[groups[1]]) do
            add(ShelfWidgets.Chip:new{
                text = link.title or "?",
                selected = link["opds:activeFacet"] == "true",
                callback = function() self:openFacet(page, link) end,
            })
        end
    else
        add(ShelfWidgets.Chip:new{ text = _("Filters"), callback = function() self:showFacetSheet(page, groups) end })
    end
    return VerticalGroup:new{ align = "left", VerticalSpan:new{ width = dp(12) }, chips }
end

function BookSourceView:openFacet(page, link)
    page.url = link.href
    page.page_no = 1
    if page.kind == "home" then page.query = nil end
    self:load(page)
    self:refreshContent(page)
end

function BookSourceView:buildCaption(page)
    local result = page.result
    local n = #result.books
    local left = page.query and T(_("Results for “%1”"), page.query) or result.title or ""
    local right = result.next and T(_("%1 loaded"), n) or T(N_("1 book", "%1 books", n), n)
    local right_w = text(right, "ui_caption"):getSize().w
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = dp(12) },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = GUTTER },
            LeftContainer:new{ dimen = Geom:new{ w = self.content_w - right_w, h = CAPTION_H - dp(12) },
                text(left, "ui_caption", Palette.ink_2, self.content_w - right_w - dp(12)) },
            LeftContainer:new{ dimen = Geom:new{ w = right_w, h = CAPTION_H - dp(12) }, text(right, "ui_caption", Palette.ink_2) },
        },
    }
end

-- Grid of books

--- The caption under a cover's title, and whether the book is on this device.
function BookSourceView:cellStatus(page, book)
    local dl = self.downloads[book.key]
    if dl then
        if dl.size and dl.size > 0 then
            return T(_("Downloading %1%"), math.min(99, math.floor(dl.done / dl.size * 100)))
        end
        return _("Downloading…")
    end
    local file = BookSource.localFile(page.source, book)
    if file then
        local progress = BookSource.progress(file)
        if progress and progress.status == "complete" then
            return book.author or "", true, true
        elseif progress and progress.status ~= "new" then
            return ShelfView.statusText(progress), true
        end
        return book.author or "", true
    end
    return book.author or ""
end

function BookSourceView:thumbFor(book, w, h)
    local thumb_url = book.thumbnail
    if not thumb_url then return end
    local bb = self.thumbs[thumb_url]
    if bb then return bb end
    local path = BookSource.cachedThumb(thumb_url)
    if not path then return end
    local ok, image = pcall(RenderImage.renderImageFile, RenderImage, path, false)
    if not ok or not image then
        os.remove(path) -- not an image after all: fetched again next time
        return
    end
    -- keep it at the cover's fill size: pages rebuild every progress tick
    local scale = math.max(w / image:getWidth(), h / image:getHeight())
    bb = RenderImage:scaleBlitBuffer(image, math.max(1, math.floor(image:getWidth() * scale + 0.5)),
        math.max(1, math.floor(image:getHeight() * scale + 0.5)))
    self.thumbs[thumb_url] = bb
    return bb
end

function BookSourceView:buildCell(page, book, x, y)
    local w, h = self.grid.cover_w, self.grid.cover_h
    local cover = ShelfWidgets.cover(book, w, h, self:thumbFor(book, w, h), true)
    local dl = self.downloads[book.key]
    if dl then
        local bar_w = w - 2 * dp(8)
        local fill = dl.size and dl.size > 0 and math.floor(bar_w * math.min(1, dl.done / dl.size)) or 0
        local band = VerticalGroup:new{
            rule(w, Palette.ink),
            FrameContainer:new{
                bordersize = 0, padding = 0, background = Palette.paper,
                CenterContainer:new{
                    dimen = Geom:new{ w = w, h = BAND_H - Size.border.default },
                    HorizontalGroup:new{
                        LineWidget:new{ background = Palette.ink, dimen = Geom:new{ w = fill, h = dp(4) } },
                        LineWidget:new{ background = Palette.mark, dimen = Geom:new{ w = bar_w - fill, h = dp(4) } },
                    },
                },
            },
        }
        band.overlap_offset = { 0, h - BAND_H }
        cover = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, cover, band }
    end
    local status, downloaded, finished = self:cellStatus(page, book)
    if finished then
        local badge = ShelfWidgets.finishedBadge()
        badge.overlap_align = "right"
        cover = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, cover, badge }
    end
    local check_w = downloaded and dp(16) or 0
    local title = TextBoxWidget:new{
        text = book.title,
        face = Font:getFace("ui_label"),
        width = w - check_w,
        height = dp(36),
        height_adjust = true,
        height_overflow_show_ellipsis = true,
    }
    if downloaded then
        -- WeChat Read's mark for a book on this device: a gray check before the title
        title = HorizontalGroup:new{
            align = "top",
            CenterContainer:new{ dimen = Geom:new{ w = dp(13), h = title.line_height_px }, icon("eink/ring.check", dp(13), true) },
            HorizontalSpan:new{ width = check_w - dp(13) },
            title,
        }
    end
    local cell_h = h + ShelfWidgets.TEXT_H
    local rect = Geom:new{ x = x, y = y, w = w, h = cell_h }
    table.insert(self.cells, {
        book = book,
        rect = rect,
        -- what a progress tick repaints: the band and the caption below the title
        tick_rect = Geom:new{ x = x, y = y + h - BAND_H, w = w, h = cell_h - h + BAND_H },
    })
    return ShelfWidgets.Tappable:new{
        callback = function() self:tapBook(book) end,
        hold_callback = function() self:showBookSheet(book) end,
        VerticalGroup:new{
            align = "left",
            cover,
            TopContainer:new{
                dimen = Geom:new{ w = w, h = ShelfWidgets.TEXT_H },
                VerticalGroup:new{
                    align = "left",
                    VerticalSpan:new{ width = dp(8) },
                    title,
                    text(status, "ui_micro", Palette.ink_2, w),
                },
            },
        },
    }
end

function BookSourceView:buildGrid(page, body_h, top_y)
    self.grid = ShelfWidgets.gridGeometry(self.dimen.w, body_h - GRID_TOP)
    local per_page = self.grid.cols * self.grid.rows
    page.per_page = per_page
    local books = page.result.books
    local pages = math.max(1, math.ceil(#books / per_page))
    page.page_no = math.max(1, math.min(page.page_no, pages))
    local first = (page.page_no - 1) * per_page
    local grid = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = GRID_TOP } }
    local y = top_y + GRID_TOP
    local shown = {}
    for r = 1, self.grid.rows do
        local row = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = GUTTER } }
        local x = GUTTER
        for c = 1, self.grid.cols do
            local book = books[first + (r - 1) * self.grid.cols + c]
            if not book then break end
            if c > 1 then
                table.insert(row, HorizontalSpan:new{ width = self.grid.col_gap })
                x = x + self.grid.col_gap
            end
            table.insert(row, self:buildCell(page, book, x, y))
            table.insert(shown, book)
            x = x + self.grid.cover_w
        end
        if #row == 1 then break end
        if r > 1 then
            table.insert(grid, VerticalSpan:new{ width = ShelfWidgets.ROW_GAP })
            y = y + ShelfWidgets.ROW_GAP
        end
        table.insert(grid, row)
        y = y + self.grid.cover_h + ShelfWidgets.TEXT_H
    end
    self:fetchThumbs(page, shown)
    return grid, self:buildPager(page, pages)
end

function BookSourceView:buildPager(page, pages)
    page.pages = pages
    -- An unfetched batch is one available next page; while fetching, both halves are disabled.
    return EinkControls.BottomBar:new{
        width = self.dimen.w,
        page = page.loading_more and 1 or page.page_no,
        pages = page.loading_more and 1 or pages + (page.per_page and page.result and page.result.next and 1 or 0),
        actions = page.loading_more and { text(_("Loading more…"), "ui_caption", Palette.ink_2) } or nil,
        on_change = function(p) self:turnPage(p) end,
        on_back = function() self:pop() end,
    }
end

-- Items the page lists: books on a grid, rows on a list.
local function itemCount(page)
    local result = page.result
    return #result.books > 0 and #result.books or #result.navs
end

--- Fetches the server's next batch for `page` (the pager reads "Loading more…" meanwhile), then calls `done`.
function BookSourceView:fetchMore(page, done)
    local result = page.result
    page.loading_more = true
    if self:top() == page then
        self:build()
        UIManager:setDirty(self, "fast", self.pager_rect)
    end
    UIManager:nextTick(function()
        if self.closed then return end
        local more = BookSource.load(page.source, result.next)
        page.loading_more = nil
        if more.state == "ok" then
            for _, book in ipairs(more.books) do table.insert(result.books, book) end
            for _, nav in ipairs(more.navs) do table.insert(result.navs, nav) end
            result.next = more.next
        else
            UIManager:show(Notification:new{ text = BookSource.failureText(more) })
        end
        done(more.state == "ok")
    end)
end

--- Once the reader is on the last fetched page, fetches the next batch in the meantime (the prototype's turnOpds).
function BookSourceView:prefetch(page)
    local result = page.result
    if page.per_page and result and result.state == "ok" and result.next and not page.loading_more
            and page.page_no * page.per_page >= itemCount(page) then
        self:fetchMore(page, function() self:refreshContent(page) end)
    end
end

--- Turns to page `page_no`. A page the device has not fully fetched asks for the server's next batch
-- first, so it shows full and no book is skipped.
function BookSourceView:turnPage(page_no)
    local page = self:top()
    if not page.per_page or page.loading_more or page_no < 1 or page_no == page.page_no then return end
    local result = page.result
    if result and result.next and page_no * page.per_page > itemCount(page) then
        return self:fetchMore(page, function(ok)
            page.page_no = math.min(page_no, math.max(1, math.ceil(itemCount(page) / page.per_page)))
            self:refreshContent(page)
            if ok then self:prefetch(page) end -- after a failure, not the same request again
        end)
    end
    if page_no > page.pages then return end
    page.page_no = page_no
    self:build()
    UIManager:setDirty(self, "ui", self.body_rect)
    self:prefetch(page)
end

-- Thumbnails: placeholders first; the page's covers land in one grid repaint, at most THUMB_WAIT seconds later.

function BookSourceView:fetchThumbs(page, books)
    local missing = {}
    for _, book in ipairs(books) do
        local thumb_url = book.thumbnail
        if thumb_url and not self.thumbs[thumb_url] and not self.thumb_tried[thumb_url]
                and not BookSource.cachedThumb(thumb_url) then
            self.thumb_tried[thumb_url] = true
            table.insert(missing, thumb_url)
        end
    end
    if #missing == 0 then return end
    local source = page.source
    local isDone
    if Device:canForkProcesses() then
        local pid = ffiUtil.runInSubProcess(function()
            BookSource.fetchThumbs(source, missing)
        end)
        if not pid then return end
        isDone = function() return ffiUtil.isSubProcessDone(pid) end
    else
        isDone = self:bridgeThumbs(source, missing)
    end
    -- only the latest grid page's covers repaint the grid: an earlier page's late ones just stay cached
    self.thumb_gen = self.thumb_gen + 1
    local gen, page_no = self.thumb_gen, page.page_no
    local start = os.time()
    local painted = false
    local poll
    poll = function()
        local done = isDone()
        if not painted and not self.closed then
            local arrived, all = 0, true
            for _, thumb_url in ipairs(missing) do
                if lfs.attributes(BookSource.thumbPath(thumb_url), "mode") == "file" then
                    arrived = arrived + 1
                else
                    all = false
                end
            end
            if all or done or os.time() - start >= THUMB_WAIT then
                painted = true
                if arrived > 0 and gen == self.thumb_gen and self:top() == page and page.page_no == page_no then
                    self:build()
                    UIManager:setDirty(self, "ui", self.body_rect)
                end
            end
        end
        if done then
            BookSource.trimThumbs()
        else
            UIManager:scheduleIn(0.25, poll)
        end
    end
    UIManager:scheduleIn(0.25, poll)
end

--- Fetches thumbnails through the download bridge, THUMB_JOBS at a time, into the cache as BookSource.fetchThumbs
-- does. Returns a function to call from the UI loop: it moves them along and says whether all are done.
function BookSourceView:bridgeThumbs(source, thumb_urls)
    util.makePath(BookSource.thumb_dir)
    local queue, running = { unpack(thumb_urls) }, {}
    return function()
        for thumb_url, job in pairs(running) do
            local result = job:poll()
            if result then
                running[thumb_url] = nil
                self.thumb_jobs[job] = nil
                BookSource.keepThumb(BookSource.thumbPath(thumb_url), result.code, result.headers)
                job:cancel()
            end
        end
        -- a closed page canceled its jobs and starts no more
        while queue[1] and util.tableSize(running) < THUMB_JOBS and not self.closed do
            local thumb_url = table.remove(queue, 1)
            local job = BookSource.bridgeDownload(Device.bridge, source, { url = thumb_url },
                BookSource.thumbPath(thumb_url) .. ".part", BookSource.block_timeout)
            running[thumb_url] = job
            self.thumb_jobs[job] = true
        end
        return next(running) == nil
    end
end

-- Lists (categories) and text

local function listRow(width, title, summary, right, on_tap)
    local inner_w = width - 2 * GUTTER
    local right_w = right and right:getSize().w + dp(8) or 0
    local lines = VerticalGroup:new{ align = "left", text(title, "ui_body", Palette.ink, inner_w - right_w) }
    if summary then
        table.insert(lines, text(summary, "ui_caption", Palette.ink_2, inner_w - right_w))
    end
    local inner_h = ROW_H - Size.border.default
    local row = HorizontalGroup:new{
        HorizontalSpan:new{ width = GUTTER },
        LeftContainer:new{ dimen = Geom:new{ w = inner_w - right_w, h = inner_h }, lines },
    }
    if right then
        table.insert(row, CenterContainer:new{ dimen = Geom:new{ w = right_w, h = inner_h }, right })
    end
    return ShelfWidgets.Tappable:new{
        callback = on_tap,
        VerticalGroup:new{ row, HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, rule(inner_w) } },
    }
end

--- A paged list of rows; returns the list and its pager.
function BookSourceView:pagedRows(page, rows, body_h)
    local per_page = math.max(1, math.floor(body_h / ROW_H))
    page.per_page = per_page
    local pages = math.max(1, math.ceil(#rows / per_page))
    page.page_no = math.max(1, math.min(page.page_no, pages))
    local list = VerticalGroup:new{ align = "left" }
    for i = (page.page_no - 1) * per_page + 1, math.min(#rows, page.page_no * per_page) do
        table.insert(list, rows[i]())
    end
    return list, self:buildPager(page, pages)
end

function BookSourceView:buildList(page, body_h)
    local rows = {}
    for _, nav in ipairs(page.result.navs) do
        table.insert(rows, function()
            return listRow(self.dimen.w, nav.title, nav.summary, icon("eink/chev", dp(18), true),
                function() self:openNav(page, nav) end)
        end)
    end
    return self:pagedRows(page, rows, body_h)
end

function BookSourceView:openNav(page, nav)
    self:push{ kind = "feed", source = page.source, url = nav.url, title = nav.title }
end

function BookSourceView:buildManage(page, body_h)
    local servers = self.opds.servers
    if #servers == 0 then
        return self:stateBlock(_("No sources yet"), _("Add an OPDS address, such as Calibre-Web on your NAS."), nil,
            _("Add source"), function() self:showEditSheet() end)
    end
    local rows = {}
    for _, source in ipairs(servers) do
        table.insert(rows, function()
            local right = HorizontalGroup:new{ align = "center" }
            if BookSource.hasLogin(source) then
                table.insert(right, icon("eink/lock", dp(18), true))
            end
            table.insert(right, ShelfWidgets.Tappable:new{
                callback = function() self:showSourceActions(source) end,
                CenterContainer:new{ dimen = Geom:new{ w = dp(44), h = dp(44) }, icon("eink/more") },
            })
            return listRow(self.dimen.w, source.title or "", BookSource.host(source), right,
                function() self:enterSource(source) end)
        end)
    end
    return self:pagedRows(page, rows, body_h)
end

function BookSourceView:buildText(page, body_h)
    local book = page.book
    local w = self.content_w
    local head = HorizontalGroup:new{
        align = "center",
        ShelfWidgets.cover(book, dp(56), dp(75), self:thumbFor(book, self.grid.cover_w, self.grid.cover_h), true),
        HorizontalSpan:new{ width = dp(14) },
        VerticalGroup:new{
            align = "left",
            text(book.title, "ui_body", Palette.ink, w - dp(70), true),
            text(table.concat({ book.author or "", metaLine(book, book.formats[1]) }, " · "), "ui_label", Palette.ink_2, w - dp(70)),
        },
    }
    local head_h = dp(16) + head:getSize().h + dp(8)
    local box = TextBoxWidget:new{
        text = book.summary or "",
        face = Font:getFace("ui_body"),
        width = w,
        height = body_h - head_h,
    }
    local lines = box.lines_per_page
    local pages = math.max(1, math.ceil(box:getAllLineCount() / lines))
    page.per_page = 1
    page.page_no = math.max(1, math.min(page.page_no, pages))
    if page.page_no > 1 then
        box:free()
        box = TextBoxWidget:new{ text = book.summary or "", face = Font:getFace("ui_body"), width = w,
            height = body_h - head_h, virtual_line_num = (page.page_no - 1) * lines + 1 }
    end
    local body = HorizontalGroup:new{
        HorizontalSpan:new{ width = GUTTER },
        VerticalGroup:new{ align = "left", VerticalSpan:new{ width = dp(16) }, head, VerticalSpan:new{ width = dp(8) }, box },
    }
    return body, self:buildPager(page, pages)
end

-- Loading, empty and error states (DESIGN.md): in the region they replace

--- A state block: bold line, reason, optional detail, and at most one outline button.
function BookSourceView:stateBlock(bold, reason, detail, button, callback)
    local w = self.content_w
    local block = VerticalGroup:new{ align = "center", VerticalSpan:new{ width = dp(40) } }
    if bold then
        table.insert(block, text(bold, "ui_body", Palette.ink, w, true))
        table.insert(block, VerticalSpan:new{ width = dp(6) })
    end
    table.insert(block, TextBoxWidget:new{ text = reason, face = Font:getFace("ui_label_large"), fgcolor = Palette.ink_2,
        width = w, alignment = "center" })
    if detail then
        table.insert(block, VerticalSpan:new{ width = dp(6) })
        table.insert(block, text(detail, "ui_caption", Palette.ink_2, w))
    end
    if button then
        table.insert(block, VerticalSpan:new{ width = dp(18) })
        local pill = EinkControls.PillButton:new{ text = button, callback = callback }
        if pill.dimen.w < dp(132) then
            pill = EinkControls.PillButton:new{ text = button, callback = callback, width = dp(132) }
        end
        table.insert(block, pill)
    end
    return CenterContainer:new{ dimen = Geom:new{ w = self.dimen.w, h = block:getSize().h }, block }
end

function BookSourceView:buildState(page)
    local result = page.result
    local source = page.source
    local host = BookSource.host(source)
    local state = result.state
    if state == "loading" then
        return self:stateBlock(nil, T(_("Connecting to %1…"), source.title or host))
    elseif state == "ok" then -- nothing in it
        if page.query then
            return self:stateBlock(T(_("Nothing found for “%1”"), page.query), _("Try a word from the title, or the author's name."))
        end
        return self:stateBlock(_("No books here yet"), _("Add books on the server and they show up here."))
    end
    local text_of = BookSource.describe(result)
    local detail, button, callback = nil, _("Retry"), function() self:retry() end
    if state == "unreachable" then
        detail = T("%1 · %2", result.detail or _("No answer"), host)
    elseif state == "auth" or state == "not_opds" then
        detail = state == "auth" and T("HTTP %1 · %2", result.code, host) or host
        button, callback = _("Edit source"), function() self:showEditSheet(source) end
    elseif state == "http" then
        detail = T("HTTP %1%2 · %3", result.code, result.detail and " " .. result.detail or "", host)
    end
    return self:stateBlock(text_of.title, text_of.reason, detail, button, callback)
end

-- Search

function BookSourceView:showSearch(page)
    local dialog
    dialog = InputDialog:new{
        title = _("Search this source"),
        input = page.query,
        input_hint = _("Title or author"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() self:closeInput() end },
            {
                text = _("Search"),
                is_enter_default = true,
                callback = function()
                    self:closeInput()
                    self:search(dialog:getInputText())
                end,
            },
        }},
    }
    self:showInput(dialog)
end

--- Keyboard dialogs opened from the page: tracked, so closing the page closes them too.
function BookSourceView:showInput(dialog)
    self.input_dialog = dialog
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function BookSourceView:closeInput()
    if self.input_dialog and UIManager:isWidgetShown(self.input_dialog) then
        UIManager:close(self.input_dialog)
    end
    self.input_dialog = nil
end

--- Shows the results for `query` on the home page; nil or "" goes back to the home feed.
function BookSourceView:search(query)
    local page = self:top()
    query = query and util.trim(query) ~= "" and util.trim(query) or nil
    page.page_no = 1
    page.url = nil
    if query then
        page.home_result = page.home_result or page.result
        page.query = query
        self:load(page)
    else
        page.query = nil
        page.result = page.home_result or page.result
        page.home_result = nil
    end
    self:refreshContent(page)
end

-- Opening and downloading

function BookSourceView:tapBook(book)
    local page = self:top()
    if self.downloads[book.key] then
        return self:cancelDownload(book.key)
    end
    local file = BookSource.localFile(page.source, book)
    if file then
        return self:openFile(file)
    end
    if book.formats[1] then
        self:download(page, book, book.formats[1])
    end
end

function BookSourceView:openFile(file)
    self:close(true) -- opening the book is a "full" refresh
    filemanagerutil.openFile(self.ui, file)
end

--- The tile of `book` on the shown grid, if any.
function BookSourceView:cellOf(book)
    for _, cell in ipairs(self.cells or {}) do
        if cell.book.key == book.key then return cell end
    end
end

function BookSourceView:refreshTile(book, refresh_type)
    -- off the shown page: rebuilding without a repaint would leave the page's tappables without a place
    if self.closed or not self:cellOf(book) then return end
    self:build()
    local cell = self:cellOf(book)
    if cell then
        UIManager:setDirty(self, refresh_type, refresh_type == "fast" and cell.tick_rect or cell.rect)
    end
end

function BookSourceView:download(page, book, format)
    if self.downloads[book.key] then return end
    local source = page.source
    local dir = BookSource.downloadDir(source)
    if not BookSource.canWrite(dir) then
        UIManager:show(Notification:new{ text = T(_("Download failed: %1"),
            BookSource.failureText{ state = "nowrite", detail = dir }) })
        return
    end
    if not Device:canForkProcesses() then
        return self:bridgeDownload(page, book, format, dir)
    end
    local part = dir .. "/." .. md5(book.key) .. ".part"
    local pid, fd = ffiUtil.runInSubProcess(function(_pid, write_fd)
        local code, status, content_type = BookSource.downloadTo(source, format, part, function(size, server_name)
            ffiUtil.writeToFD(write_fd, T("S\t%1\t%2\n", size or "", server_name or ""))
        end)
        ffiUtil.writeToFD(write_fd, T("D\t%1\t%2\t%3\n", tostring(code), status or "", content_type or ""), true)
    end, true)
    if not pid then
        UIManager:show(Notification:new{ text = _("Cannot start the download.") })
        return
    end
    local dl = { pid = pid, fd = fd, part = part, dir = dir, book = book, format = format, source = source,
        done = 0, buffer = "" }
    self.downloads[book.key] = dl
    self:refreshTile(book, "ui")
    UIManager:show(Toast:new{ text = T(_("Download started: %1. Tap the cover to cancel."), book.title), close_refresh_type = "ui" })
    dl.poll = function() self:pollDownload(dl) end
    UIManager:scheduleIn(1, dl.poll)
end

--- download() without subprocesses: the download bridge writes the book into the cache, finishDownload moves it.
function BookSourceView:bridgeDownload(page, book, format, dir)
    util.makePath(BookSource.part_dir)
    local part = BookSource.part_dir .. "/" .. md5(book.key) .. ".part"
    local job = BookSource.bridgeDownload(Device.bridge, page.source,
        { url = format.href, headers = { ["Accept-Encoding"] = "identity" } },
        part, socketutil.FILE_BLOCK_TIMEOUT)
    local dl = { job = job, part = part, dir = dir, book = book, format = format, source = page.source,
        done = 0, size = format.size }
    self.downloads[book.key] = dl
    self:refreshTile(book, "ui")
    UIManager:show(Toast:new{ text = T(_("Download started: %1. Tap the cover to cancel."), book.title), close_refresh_type = "ui" })
    dl.poll = function() self:pollDownload(dl) end
    UIManager:scheduleIn(1, dl.poll)
end

function BookSourceView:pollBridgeDownload(dl)
    local result = dl.job:poll()
    if result then
        local headers = result.headers or {}
        -- the name and size the subprocess gets from a HEAD request come with the answer itself
        dl.server_name = result.code == 200 and BookSource.serverFileName(dl.format, headers) or nil
        return self:finishDownload(dl, { code = result.code, status = result.status,
            content_type = headers["content-type"] })
    end
    dl.size = dl.job.total or dl.format.size
    if dl.job.received ~= dl.done then
        dl.done = dl.job.received
        if dl.size then self:refreshTile(dl.book, "fast") end
    end
    UIManager:scheduleIn(1, dl.poll)
end

function BookSourceView:pollDownload(dl)
    if self.downloads[dl.book.key] ~= dl then return end
    if dl.job then return self:pollBridgeDownload(dl) end
    local exited = ffiUtil.isSubProcessDone(dl.pid)
    dl.buffer = dl.buffer .. (exited and ffiUtil.readAllFromFD(dl.fd) or readAvailable(dl.fd))
    if exited then dl.fd = nil end
    local finished
    for line in dl.buffer:gmatch("([^\n]*)\n") do
        local kind, a, b, c = line:match("^(%a)\t([^\t]*)\t?([^\t]*)\t?(.*)$")
        if kind == "S" then
            dl.size, dl.server_name = tonumber(a), b ~= "" and b or nil
        elseif kind == "D" then
            finished = { code = tonumber(a) or a, status = b, content_type = c ~= "" and c or nil }
        end
    end
    dl.buffer = dl.buffer:match("[^\n]*$")
    if finished or exited then
        return self:finishDownload(dl, finished or { code = "closed" })
    end
    local done = lfs.attributes(dl.part, "size") or 0
    if done ~= dl.done then
        dl.done = done
        if dl.size then self:refreshTile(dl.book, "fast") end
    end
    UIManager:scheduleIn(1, dl.poll)
end

function BookSourceView:finishDownload(dl, finished)
    self.downloads[dl.book.key] = nil
    if dl.fd then
        UIManager:scheduleIn(1, function() self:collect(dl) end)
    end
    local result = BookSource.downloadResult(finished.code, finished.status, finished.content_type, dl.dir)
    local file
    if result.state == "ok" then
        local name = dl.source.raw_names and dl.server_name
            and util.getSafeFilename(dl.server_name, dl.dir) or BookSource.fileName(dl.book, dl.format, dl.dir)
        file = (dl.dir ~= "/" and dl.dir or "") .. "/" .. name
        if not os.rename(dl.part, file) or lfs.attributes(file, "mode") ~= "file" then
            result = { state = "nowrite", detail = dl.dir }
        end
    end
    if dl.job then dl.job:cancel() end -- the book moved first: this releases the bridge's handle
    if result.state ~= "ok" then
        os.remove(dl.part)
        self:refreshTile(dl.book, "ui")
        UIManager:show(Notification:new{ text = T(_("Download failed: %1"), BookSource.failureText(result)) })
        return
    end
    BookSource.recordDownload(self.opds, dl.source, dl.book, file)
    -- not opened: that would close the page and cancel the other downloads; a tap on the marked tile opens it
    self:refreshTile(dl.book, "ui")
    UIManager:show(Toast:new{ text = T(_("Downloaded: %1"), dl.book.title), close_refresh_type = "ui" })
end

-- Reaps a finished or killed child and closes its pipe.
function BookSourceView:collect(dl)
    if ffiUtil.isSubProcessDone(dl.pid) then
        if dl.fd then ffiUtil.readAllFromFD(dl.fd) end
        dl.fd = nil
    else
        if dl.fd and (ffiUtil.getNonBlockingReadSize(dl.fd) or 0) > 0 then
            readAvailable(dl.fd)
        end
        UIManager:scheduleIn(1, function() self:collect(dl) end)
    end
end

function BookSourceView:cancelDownload(key, quiet)
    local dl = self.downloads[key]
    if not dl then return end
    self.downloads[key] = nil
    UIManager:unschedule(dl.poll)
    if dl.job then
        dl.job:cancel()
    else
        ffiUtil.terminateSubProcess(dl.pid)
        self:collect(dl)
        os.remove(dl.part)
    end
    if not quiet then
        self:refreshTile(dl.book, "ui")
        UIManager:show(Toast:new{ text = T(_("Download canceled: %1"), dl.book.title), close_refresh_type = "ui" })
    end
end

-- Sheets

--- A sheet row (56dp): text, optional gray value, then a check mark or a chevron.
local function sheetRow(width, label, value, callback, checked, bold)
    local mark = checked and icon("eink/check", dp(20)) or icon("eink/chev", dp(18), true)
    local value_w = value and math.floor(width * 0.5) or 0
    local value_widget = value and text(value, "ui_label", Palette.ink_2, value_w)
    local right = HorizontalGroup:new{ align = "center" }
    if value_widget then
        table.insert(right, value_widget)
        table.insert(right, HorizontalSpan:new{ width = dp(8) })
    end
    table.insert(right, mark)
    local right_w = right:getSize().w
    local inner_h = ROW_H - Size.border.default
    return ShelfWidgets.Tappable:new{
        callback = callback,
        VerticalGroup:new{
            HorizontalGroup:new{
                LeftContainer:new{ dimen = Geom:new{ w = width - right_w, h = inner_h },
                    text(label, "ui_body", Palette.ink, width - right_w - dp(8), bold) },
                CenterContainer:new{ dimen = Geom:new{ w = right_w, h = inner_h }, right },
            },
            rule(width),
        },
    }
end

function BookSourceView:showSheet(sheet)
    UIManager:show(sheet, "ui", sheet:getRefreshRegion())
    self.sheet = sheet
    return sheet
end

function BookSourceView:closeSheet()
    if self.sheet then
        local sheet = self.sheet
        self.sheet = nil
        sheet:onClose()
    end
end

function BookSourceView:openSheet(title, rows_or_content, on_close)
    self:closeSheet()
    local content = rows_or_content
    if type(content) == "table" and not content.paintTo then
        content = VerticalGroup:new{ align = "left" }
        for _, row in ipairs(rows_or_content) do table.insert(content, row) end
    end
    local sheet
    sheet = BottomSheet:new{
        title = title,
        content = content,
        on_close = function()
            if self.sheet == sheet then self.sheet = nil end
            if on_close then on_close() end
        end,
    }
    return self:showSheet(sheet)
end

-- A sheet action: closes the sheet first, so what it opens stacks on the page.
function BookSourceView:action(callback)
    return function()
        self:closeSheet()
        callback()
    end
end

function BookSourceView:showSourceSheet(source)
    local w = BottomSheet.getContentWidth()
    local folder = BookSource.downloadDir(source)
    self:openSheet(source.title or BookSource.host(source), {
        sheetRow(w, _("Edit source"), nil, self:action(function() self:showEditSheet(source) end)),
        sheetRow(w, _("Manage sources"), nil, self:action(function() self:push{ kind = "manage" } end)),
        sheetRow(w, _("Download folder"), folderLabel(folder),
            self:action(function() self:chooseFolder(source) end)),
    })
end

function BookSourceView:chooseFolder(source)
    local PathChooser = require("ui/widget/pathchooser")
    self.path_chooser = PathChooser:new{
        select_directory = true,
        select_file = false,
        show_files = false,
        path = BookSource.downloadDir(source),
        onConfirm = function(path)
            source.download_dir = path
            BookSource.save(self.opds)
            UIManager:show(Notification:new{
                text = isUnder(path, Shelf.homeDir()) and T(_("Books will be downloaded to %1"), folderLabel(path))
                    or _("This folder is outside the home folder: books downloaded here won't show up on the shelf."),
            })
        end,
    }
    UIManager:show(self.path_chooser) -- closing the page closes it if it is still up
end

--- 分类浏览: the root's entries in two columns; the home feed is marked.
function BookSourceView:showNavSheet(page)
    local w = BottomSheet.getContentWidth()
    local col_w = math.floor((w - dp(24)) / 2)
    local grid = VerticalGroup:new{ align = "left" }
    local navs = page.root.navs
    for i = 1, #navs, 2 do
        local row = HorizontalGroup:new{ align = "top" }
        for j = i, math.min(i + 1, #navs) do
            local nav = navs[j]
            local current = nav.url == page.home_url
            if j > i then table.insert(row, HorizontalSpan:new{ width = dp(24) }) end
            table.insert(row, sheetRow(col_w, nav.title, nil, current and function() self:closeSheet() end
                or self:action(function() self:openNav(page, nav) end), current, current))
        end
        table.insert(grid, row)
    end
    self:openSheet(_("Browse"), grid)
end

function BookSourceView:showFacetSheet(page, groups)
    local w = BottomSheet.getContentWidth()
    local rows = {}
    for _, group in ipairs(groups) do
        for _, link in ipairs(page.result.facets[group]) do
            table.insert(rows, sheetRow(w, T("%1: %2", group, link.title or "?"), nil,
                self:action(function() self:openFacet(page, link) end), link["opds:activeFacet"] == "true"))
        end
    end
    self:openSheet(_("Filters"), rows)
end

--- The long-press sheet: what a tap does not cover (description, other formats, download again).
function BookSourceView:showBookSheet(book)
    local page = self:top()
    local w = BottomSheet.getContentWidth()
    local file = BookSource.localFile(page.source, book)
    local main = book.formats[1]
    local meta = metaLine(book, main)
    if file then meta = meta ~= "" and meta .. " · " .. _("Downloaded") or _("Downloaded") end
    local content = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            align = "center",
            ShelfWidgets.cover(book, dp(56), dp(75), self:thumbFor(book, self.grid.cover_w, self.grid.cover_h), true),
            HorizontalSpan:new{ width = dp(14) },
            VerticalGroup:new{
                align = "left",
                text(book.title, "ui_body", Palette.ink, w - dp(70), true),
                text(book.author or "", "ui_label", Palette.ink_2, w - dp(70)),
                text(meta, "ui_caption", Palette.ink_2, w - dp(70)),
            },
        },
        VerticalSpan:new{ width = dp(8) },
    }
    if book.summary then
        table.insert(content, ShelfWidgets.Tappable:new{
            callback = self:action(function() self:push{ kind = "text", book = book } end),
            TextBoxWidget:new{
                text = book.summary:gsub("\n+", " "),
                face = Font:getFace("ui_label_large"),
                fgcolor = Palette.ink_2,
                width = w,
                height = 4 * math.floor(1.3 * Font:getFace("ui_label_large").size + 0.5), -- at most 4 lines
                height_adjust = true,
                height_overflow_show_ellipsis = true,
            },
        })
        table.insert(content, VerticalSpan:new{ width = dp(8) })
    end
    local primary
    if file then
        primary = EinkControls.PillButton:new{ text = _("Read"), solid = true, width = w,
            callback = self:action(function() self:openFile(file) end) }
    elseif main then
        primary = EinkControls.PillButton:new{ text = T(_("Download %1"), metaLine({}, main)), solid = true, width = w,
            callback = self:action(function() self:download(page, book, main) end) }
    end
    if primary then table.insert(content, primary) end
    if #book.formats > 1 then
        local others = HorizontalGroup:new{ align = "center", text(_("Other formats"), "ui_label", Palette.ink_2),
            HorizontalSpan:new{ width = dp(12) } }
        for i = 2, #book.formats do
            local format = book.formats[i]
            if i > 2 then table.insert(others, HorizontalSpan:new{ width = dp(8) }) end
            table.insert(others, EinkControls.PillButton:new{ text = metaLine({}, format),
                callback = self:action(function() self:download(page, book, format) end) })
        end
        table.insert(content, VerticalSpan:new{ width = dp(8) })
        table.insert(content, others)
    end
    if file and main then
        table.insert(content, VerticalSpan:new{ width = dp(8) })
        table.insert(content, rule(w))
        table.insert(content, sheetRow(w, _("Download again, replacing this copy"), nil,
            self:action(function() self:download(page, book, main) end)))
    end
    self:openSheet(book.title, content)
end

-- Managing sources

function BookSourceView:showSourceActions(source)
    local w = BottomSheet.getContentWidth()
    self:openSheet(source.title or BookSource.host(source), {
        sheetRow(w, _("Edit"), nil, self:action(function() self:showEditSheet(source) end)),
        sheetRow(w, _("Delete"), nil, self:action(function() self:confirmDelete(source) end)),
    })
end

--- The confirmation layer over the paled page: delete, or cancel.
function BookSourceView:confirmDelete(source)
    self:closeSheet()
    local layer
    layer = ConfirmLayer:new{
        text = T(_("Delete “%1”? Books you downloaded stay on the device."), source.title or ""),
        actions = { { text = _("Delete"), callback = function() self:deleteSource(source) end } },
        on_close = function()
            if self.sheet == layer then self.sheet = nil end
        end,
    }
    self:showSheet(layer)
end

function BookSourceView:deleteSource(source)
    for i, s in ipairs(self.opds.servers) do
        if s == source then
            table.remove(self.opds.servers, i)
            break
        end
    end
    BookSource.save(self.opds)
    self:build()
    UIManager:setDirty(self, "ui", self.dimen)
    UIManager:show(Notification:new{ text = _("Source deleted") })
end

-- Edit sheet: labelled fields; tapping one opens the keyboard dialog for it.
local edit_fields = {
    { key = "title", label = _("Name"), hint = _("e.g. NAS at home") },
    { key = "url", label = _("Address"), hint = "https://…/opds" },
    { key = "username", label = _("Username"), hint = _("Leave empty if not needed") },
    { key = "password", label = _("Password"), password = true },
    { group = _("Cloudflare Access (optional, sent only to this source's domain)") },
    { key = "access_client_id", label = _("Client ID"), hint = "….access" },
    { key = "access_client_secret", label = _("Client Secret"), password = true },
}

function BookSourceView:showEditSheet(source)
    local draft = {}
    for _, field in ipairs(edit_fields) do
        if field.key then draft[field.key] = source and source[field.key] or "" end
    end
    draft.raw_names = source and source.raw_names or false
    local sheet
    local function content()
        return self:editContent(draft, function() sheet:setContent(content()) end, function()
            self:closeSheet()
            self:saveSource(source, draft)
        end)
    end
    sheet = self:openSheet(source and _("Edit source") or _("Add source"), content())
end

function BookSourceView:editContent(draft, rebuild, save)
    local w = BottomSheet.getContentWidth()
    local label_w = dp(92)
    local input_w = w - label_w - dp(10)
    local form = VerticalGroup:new{ align = "left" }
    self.edit_rows = {}
    for _, field in ipairs(edit_fields) do
        if field.group then
            table.insert(form, VerticalSpan:new{ width = dp(14) })
            table.insert(form, text(field.group, "ui_caption", Palette.ink_2, w))
        else
            local value = draft[field.key]
            local shown = value ~= "" and (field.password and string.rep("•", math.min(#value, 12)) or value) or field.hint or ""
            local pill = FrameContainer:new{
                radius = dp(20), bordersize = Size.border.button, color = Palette.ink, background = Palette.paper,
                padding = 0, padding_left = dp(14), padding_right = dp(14),
                LeftContainer:new{ dimen = Geom:new{ w = input_w - dp(28) - 2 * Size.border.button, h = dp(40) - 2 * Size.border.button },
                    text(shown, "ui_body", value ~= "" and Palette.ink or Palette.ink_2, input_w - dp(28) - 2 * Size.border.button) },
            }
            -- the whole 52dp row is the tap target, label included
            local row = ShelfWidgets.Tappable:new{
                callback = function() self:editField(field, draft, rebuild) end,
                CenterContainer:new{
                    dimen = Geom:new{ w = w, h = dp(52) },
                    HorizontalGroup:new{
                        align = "center",
                        LeftContainer:new{ dimen = Geom:new{ w = label_w, h = dp(52) }, text(field.label, "ui_label", Palette.ink_2, label_w) },
                        HorizontalSpan:new{ width = dp(10) },
                        pill,
                    },
                },
            }
            self.edit_rows[field.key] = row
            table.insert(form, row)
        end
    end
    local toggle = EinkControls.Toggle:new{ checked = draft.raw_names }
    toggle.ges_events = {} -- the whole row toggles
    local toggle_w = toggle:getSize().w
    table.insert(form, ShelfWidgets.Tappable:new{
        callback = function()
            draft.raw_names = not draft.raw_names
            rebuild()
        end,
        HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = w - toggle_w, h = ROW_H },
                VerticalGroup:new{
                    align = "left",
                    text(_("Use server filenames"), "ui_body", Palette.ink, w - toggle_w - dp(8)),
                    text(_("When off, books are named “Author - Title”"), "ui_caption", Palette.ink_2, w - toggle_w - dp(8)),
                },
            },
            toggle,
        },
    })
    local ready = util.trim(draft.title) ~= "" and util.trim(draft.url) ~= ""
    self.save_button = EinkControls.PillButton:new{ text = _("Save"), solid = ready, enabled = ready, width = w, callback = save }
    table.insert(form, VerticalSpan:new{ width = dp(4) })
    table.insert(form, self.save_button)
    return form
end

function BookSourceView:editField(field, draft, rebuild)
    local dialog
    dialog = InputDialog:new{
        title = field.label,
        input = draft[field.key],
        input_hint = field.hint,
        text_type = field.password and "password" or nil,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() self:closeInput() end },
            {
                text = _("OK"),
                is_enter_default = true,
                callback = function()
                    self:closeInput()
                    draft[field.key] = dialog:getInputText()
                    rebuild()
                end,
            },
        }},
    }
    self:showInput(dialog)
end

local function nonEmpty(str)
    str = str and util.trim(str)
    return str ~= "" and str or nil
end

--- Writes the draft into `source` (or a new source), keeping the fields the form does not show.
function BookSourceView:saveSource(source, draft)
    local is_new = source == nil
    source = source or {}
    if source.url then BookSource.forget(source.url) end -- an old Access cookie must not hide a bad new token
    source.title = util.trim(draft.title)
    source.url = BookSource.normalizeUrl(draft.url)
    source.username = nonEmpty(draft.username)
    source.password = nonEmpty(draft.password)
    source.access_client_id = nonEmpty(draft.access_client_id)
    source.access_client_secret = nonEmpty(draft.access_client_secret)
    source.raw_names = draft.raw_names or nil
    BookSource.forget(source.url)
    if is_new then
        table.insert(self.opds.servers, source)
    end
    BookSource.save(self.opds)
    UIManager:show(Notification:new{ text = is_new and _("Source added") or _("Saved") })
    -- new credentials: ask again for what failed
    local page = self:top()
    if page.source == source and page.result and page.result.state ~= "ok" and page.result.state ~= "loading" then
        return self:retry()
    end
    self:build()
    UIManager:setDirty(self, "ui", self.dimen)
end

Replacements.opds_catalog = BookSourceView

return BookSourceView
