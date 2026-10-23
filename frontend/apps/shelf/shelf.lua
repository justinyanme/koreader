--[[--
The shelf: every book under the home folder (see CONTEXT.md, 书架).

Data only, no widgets. Books come from a recursive scan of the home folder that
skips hidden names, symlinked folders and KOReader's own folders. Titles,
authors and cover state come from the CoverBrowser cache (one light query, no
cover blobs) when that plugin is loaded, otherwise from file names. Book status
is KOReader's own (BookList); a book without a sidecar is "new".
]]

local BookList = require("ui/widget/booklist")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local ReadHistory = require("readhistory")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")

local Shelf = {
    -- the title menu's order: 全部, 在读, 未读, 读完, 搁置
    filters = { "all", "reading", "new", "complete", "abandoned" },
}

-- image viewers are document providers too, but photos and screenshots are not books
local image_suffixes = { png = true, jpg = true, jpeg = true, gif = true, svg = true, webp = true, bmp = true, tif = true, tiff = true }

local LIGHT_SQL = "SELECT directory, filename, title, authors, cover_fetched, has_cover, cover_sizetag, "
    .. "cover_w, cover_h, ignore_cover, ignore_meta FROM bookinfo WHERE in_progress=0;"
local LIGHT_COLS = { "directory", "filename", "title", "authors", "cover_fetched", "has_cover", "cover_sizetag",
    "cover_w", "cover_h", "ignore_cover", "ignore_meta" }

--- The home folder: what the shelf shows, and where 书源 downloads land by default.
function Shelf.homeDir()
    return G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
end

--- Returns the books (`{ file, mtime }`) under `root`, in no particular order.
function Shelf.scan(root)
    local start = time.now()
    root = ffiUtil.realpath(root) or root
    -- KOReader's own folders (resources, screenshots, updates) live under the default home on most devices
    local skip = {}
    for _, dir in ipairs{ DataStorage:getDataDir(), lfs.currentdir() } do
        skip[ffiUtil.realpath(dir) or dir] = true
    end
    local files = {}
    local dirs = { root }
    while #dirs > 0 do
        local dir = table.remove(dirs)
        local ok, iter, dir_obj = pcall(lfs.dir, dir)
        if ok then
            for name in iter, dir_obj do
                if name:sub(1, 1) ~= "." then
                    local path = dir .. "/" .. name
                    -- symlinkattributes does not follow links, so linked folders are never walked (no loops)
                    local mode = lfs.symlinkattributes(path, "mode")
                    if mode == "directory" then
                        if not name:match("%.sdr$") and not skip[path] then
                            table.insert(dirs, path)
                        end
                    elseif (mode == "file" or (mode == "link" and lfs.attributes(path, "mode") == "file"))
                            and not image_suffixes[util.getFileNameSuffix(name):lower()]
                            and DocumentRegistry:hasProvider(path) then
                        table.insert(files, { file = path, mtime = lfs.attributes(path, "modification") or 0 })
                    end
                end
            end
        end
    end
    logger.info("Shelf: scanned", #files, "books in", time.to_ms(time.since(start)), "ms")
    return files
end

--- Returns the CoverBrowser cache rows of all extracted books, keyed by path, without cover data.
function Shelf.readCache(bim)
    local rows = {}
    if not bim then return rows end
    bim:openDbConnection()
    local stmt = bim.db_conn:prepare(LIGHT_SQL)
    for row in stmt:rows() do
        local info = {}
        for i, col in ipairs(LIGHT_COLS) do
            info[col] = row[i]
        end
        info.cover_w, info.cover_h = tonumber(info.cover_w), tonumber(info.cover_h)
        rows[info.directory .. info.filename] = info
    end
    stmt:close()
    return rows
end

--- Whether `info` (a cache row or nil) lacks what the shelf shows at `cover_specs`.
function Shelf.needsExtract(bim, info, cover_specs)
    if not info then return true end
    if info.ignore_cover then return false end
    if not info.cover_fetched then return true end
    return info.has_cover and bim.isCachedCoverInvalid(info, cover_specs) and true or false
end

--- Turns scanned files into shelf books: title, authors, status, progress, last read.
-- @param bim BookInfoManager or nil
function Shelf.load(scanned, bim, cover_specs)
    local start = time.now()
    local cache = Shelf.readCache(bim)
    local last_read = {}
    for _, item in ipairs(ReadHistory.hist) do
        last_read[item.file] = item.time
    end
    local removed = Shelf.removed()
    local books = {}
    for _, found in ipairs(scanned) do
        local file = found.file
        if not removed[file] then
            local info = cache[file]
            local use_meta = info and not info.ignore_meta
            local book_info = BookList.getBookInfo(file)
            table.insert(books, {
                file = file,
                mtime = found.mtime,
                title = use_meta and info.title or util.splitFileNameSuffix(ffiUtil.basename(file)),
                authors = use_meta and info.authors and info.authors:gsub("\n", ", ") or nil,
                has_cover = info and info.has_cover and not info.ignore_cover and true or false,
                needs_extract = bim and Shelf.needsExtract(bim, info, cover_specs) or false,
                status = book_info.been_opened and book_info.status or "new",
                percent = book_info.percent_finished,
                last_read = last_read[file],
            })
        end
    end
    logger.info("Shelf: read cache and status of", #books, "books in", time.to_ms(time.since(start)), "ms")
    return books
end

local sorters = {
    -- read books by last read, newest first; then the rest by the time they landed on the device
    recent = function(a, b)
        if (a.last_read ~= nil) ~= (b.last_read ~= nil) then
            return a.last_read ~= nil
        end
        if a.last_read and a.last_read ~= b.last_read then
            return a.last_read > b.last_read
        end
        if a.mtime ~= b.mtime then
            return a.mtime > b.mtime
        end
        return a.file < b.file
    end,
    title = function(a, b)
        if a.title ~= b.title then
            return BookList.strcoll(a.title, b.title)
        end
        return a.file < b.file
    end,
    authors = function(a, b)
        local a_authors, b_authors = a.authors or "\u{FFFF}", b.authors or "\u{FFFF}"
        if a_authors ~= b_authors then
            return BookList.strcoll(a_authors, b_authors)
        end
        return BookList.strcoll(a.title, b.title)
    end,
}
Shelf.sorts = { "recent", "title", "authors" }

local function matches(book, query)
    if not query then return true end
    return util.stringLower(book.title):find(query, 1, true)
        or (book.authors and util.stringLower(book.authors):find(query, 1, true))
end

--- Returns the books shown under `filter` (sorted by `sort`) and the count for every filter,
-- both narrowed to titles and authors containing `query`.
function Shelf.view(books, filter, sort, query)
    query = query and query ~= "" and util.stringLower(query) or nil
    local counts = { all = 0, reading = 0, new = 0, complete = 0, abandoned = 0 }
    local shown = {}
    for _, book in ipairs(books) do
        if matches(book, query) then
            counts.all = counts.all + 1
            if counts[book.status] then
                counts[book.status] = counts[book.status] + 1
            end
            if filter == "all" or filter == book.status then
                table.insert(shown, book)
            end
        end
    end
    table.sort(shown, sorters[sort] or sorters.recent)
    return shown, counts
end

--- Returns the hidden books ({ [file] = time removed }). A book opened after its removal is back
-- on the shelf, and entries whose file is gone are pruned.
function Shelf.removed()
    local removed = G_reader_settings:readSetting("shelf_removed")
    if not removed then return {} end
    local changed = false
    for file, removed_at in pairs(removed) do
        local hist_idx = ReadHistory:getIndexByFile(file)
        if not lfs.attributes(file, "mode") or (hist_idx and ReadHistory.hist[hist_idx].time > removed_at) then
            removed[file] = nil
            changed = true
        end
    end
    if changed then
        G_reader_settings:saveSetting("shelf_removed", removed)
    end
    return removed
end

--- Hides books (a list of their files) from the shelf. The files stay where they are.
-- The settings are written at once, so the books stay hidden even if KOReader does not quit cleanly.
function Shelf.remove(files)
    local removed = G_reader_settings:readSetting("shelf_removed") or {}
    for _, file in ipairs(files) do
        removed[file] = os.time()
    end
    G_reader_settings:saveSetting("shelf_removed", removed)
    G_reader_settings:flush()
end

--- Sets a book's status (书籍状态: "reading", "complete" or "abandoned"), as KOReader's own status buttons do.
-- A book never opened gets its settings file for it.
function Shelf.setStatus(file, status)
    local doc_settings = DocSettings:open(file)
    local summary = doc_settings:readSetting("summary") or {}
    summary.status = status
    filemanagerutil.saveSummary(doc_settings, summary)
    BookList.setBookInfoCacheProperty(file, "status", status)
end

return Shelf
