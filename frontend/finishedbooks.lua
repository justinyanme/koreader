--[[--
The books marked 读完 on this device, of any year, in the order they were marked: the N of 读完的第 N 本
(see CONTEXT.md).

The books are those of reading history and of the shelf (the home folder, hidden ones included), each file
on its own, so two formats of a book are two books. The list is built once, opening each book's settings at
most once and not at all when BookList already knows the book is not finished. Afterwards only the books
whose BookList info changed (a status set, a settings file reset or written) are read again.
]]

local BookList = require("ui/widget/booklist")
local DocSettings = require("docsettings")
local ReadHistory = require("readhistory")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")

local FinishedBooks = {}

local books -- real path → when it was marked finished, or false; nil until built
local scanned_home -- the home folder the list was built from
local changed = {} -- files to read again

-- The day (YYYY-MM-DD) a finished book was marked finished, from its summary. Books finished before that
-- time was recorded (`finished_time`) only have the day their status last changed.
local function finishedDay(summary)
    return summary.finished_time and os.date("%Y-%m-%d", summary.finished_time) or summary.modified or ""
end

local function finishedKey(path, summary)
    return { path = path, time = summary.finished_time, day = finishedDay(summary) }
end

-- Books without a recorded time come before the recorded ones of their day.
local function finishedBefore(a, b)
    if a.day ~= b.day then return a.day < b.day end
    if (a.time == nil) ~= (b.time == nil) then return a.time == nil end
    if a.time ~= b.time then return a.time < b.time end
    return a.path < b.path
end

-- Records the book at `path`: when it was marked finished, or false.
local function read(path)
    local real = ffiUtil.realpath(path) -- nil once the file is gone
    if not real then return end
    local summary
    if BookList.hasBookInfoCache(path) then
        local info = BookList.getBookInfo(path)
        if info.been_opened and info.status == "complete" then
            summary = DocSettings:open(path):readSetting("summary")
        end
    elseif DocSettings:hasSidecarFile(path) then
        summary = BookList.getDocSettings(path):readSetting("summary") -- also caches its book info
    end
    books[real] = summary and summary.status == "complete" and finishedKey(real, summary) or false
    changed[path] = nil -- caching its book info just marked it
end

local function build(Shelf, home)
    books, scanned_home, changed = {}, home, {}
    for _, item in ipairs(ReadHistory.hist) do
        read(item.file)
    end
    for _, book in ipairs(Shelf.scan(home)) do
        if books[ffiUtil.realpath(book.file) or book.file] == nil then
            read(book.file)
        end
    end
end

--- Called by BookList when the status or settings file of the book at `file` may have changed.
function FinishedBooks.changed(file)
    if books then changed[file] = true end
end

--[[--
The place of the book at `file` among the books marked 读完, the first one marked being 1, counting the book
itself, whose `summary` may be newer than its settings file. Returns nil unless that summary says 读完.
]]
function FinishedBooks.number(file, summary)
    if not (summary and summary.status == "complete") then return end
    local Shelf = require("apps/shelf/shelf") -- the shelf's books; loaded once a finished book is numbered
    local home = Shelf.homeDir()
    if not books or home ~= scanned_home then
        build(Shelf, home)
    end
    local own_path = ffiUtil.realpath(file) or file
    local own = finishedKey(own_path, summary)
    books[own_path] = own
    changed[file] = nil
    local todo = changed
    changed = {}
    for path in pairs(todo) do
        read(path)
    end
    local number = 1
    for path, key in pairs(books) do
        if key and path ~= own_path and finishedBefore(key, own) and lfs.attributes(path, "mode") == "file" then
            number = number + 1
        end
    end
    return number
end

return FinishedBooks
