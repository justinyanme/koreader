--[[--
The shelf: every book under the home folder (see CONTEXT.md, 书架).

Data only, no widgets. Books come from a recursive scan of the home folder that
skips hidden names and symlinked folders. Titles, authors and covers come from
the CoverBrowser cache when that plugin is enabled, otherwise from file names.
Book status is KOReader's own (BookList); a book without a sidecar is "new".
]]

local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local ReadHistory = require("readhistory")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")

local Shelf = {
    -- chip order; "abandoned" books only show up under "all"
    filters = { "all", "reading", "new", "complete" },
}

local function scanDir(root)
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
                        if not name:match("%.sdr$") then
                            table.insert(dirs, path)
                        end
                    elseif (mode == "file" or (mode == "link" and lfs.attributes(path, "mode") == "file"))
                            and DocumentRegistry:hasProvider(path) then
                        table.insert(files, { file = path, mtime = lfs.attributes(path, "modification") or 0 })
                    end
                end
            end
        end
    end
    return files
end

--- Scans `root` and returns the shelf's books, in no particular order.
-- A book gets `needs_extract` when the cache lacks it or holds a cover smaller than `cover_specs`.
-- @param bim BookInfoManager or nil
function Shelf.load(root, bim, cover_specs)
    root = ffiUtil.realpath(root) or root
    local last_read = {}
    for _, item in ipairs(ReadHistory.hist) do
        last_read[item.file] = item.time
    end
    local removed = G_reader_settings:readSetting("shelf_removed") or {}
    local start = time.now()
    local found = scanDir(root)
    local scanned = time.now()
    local books = {}
    for _, book in ipairs(found) do
        if not removed[book.file] then
            local info = bim and bim:getBookInfo(book.file)
            book.needs_extract = bim and (not info or (cover_specs and not info.ignore_cover
                and (not info.cover_fetched or (info.has_cover and bim.isCachedCoverInvalid(info, cover_specs)))))
            book.title = info and info.title or util.splitFileNameSuffix(ffiUtil.basename(book.file))
            book.authors = info and info.authors and info.authors:gsub("\n", ", ")
            local book_info = BookList.getBookInfo(book.file)
            book.status = book_info.been_opened and book_info.status or "new"
            book.percent = book_info.percent_finished
            book.last_read = last_read[book.file]
            table.insert(books, book)
        end
    end
    logger.info("Shelf: scanned", #found, "files in", time.to_ms(scanned - start), "ms, read cache and status in",
        time.to_ms(time.since(scanned)), "ms")
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
    local counts = { all = 0, reading = 0, new = 0, complete = 0 }
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

--- Hides a book from the shelf. The file stays where it is.
function Shelf.remove(file)
    local removed = G_reader_settings:readSetting("shelf_removed") or {}
    removed[file] = true
    G_reader_settings:saveSetting("shelf_removed", removed)
end

return Shelf
