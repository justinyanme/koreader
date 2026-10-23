--[[--
Data behind the 我 tab. No widgets, and no timing of its own.

Reading time comes from the statistics plugin's database, words from the
vocabulary builder's database, and notes (highlights, thoughts and bookmarks, see
CONTEXT.md) from the sidecars of the books in reading history (the books the
exporter's "all books" covers). Both databases are only read; a missing or
unreadable one reads as empty. The name is the nickname set on the tab, else the
KOSync user name, else the device model.
The home page needs counts only; notes and words are loaded by their subpages.
]]

local BookList = require("ui/widget/booklist")
local DataStorage = require("datastorage")
local Device = require("device")
local LuaSettings = require("luasettings")
local ReadHistory = require("readhistory")
local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local Me = {
    stats_db = DataStorage:getSettingsDir() .. "/statistics.sqlite3",
    vocab_db = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3",
    kosync_settings = DataStorage:getSettingsDir() .. "/kosync.lua",
    now = os.time, -- replaceable in specs
}

local DAY_SQL = "strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime')"

-- Runs `sql` on the database at `path`; returns the result columns, or nil.
local function query(path, sql)
    if lfs.attributes(path, "mode") ~= "file" then return end
    local ok, conn = pcall(SQ3.open, path, "ro")
    if not ok then
        logger.warn("Me: cannot open", path, conn)
        return
    end
    local res
    ok, res = pcall(conn.exec, conn, sql)
    conn:close()
    if not ok then
        logger.warn("Me: cannot read", path, res)
        return
    end
    return res
end

-- Local midnight `offset` days after the day of `t` (os.date("*t") table), DST-safe.
local function dayStart(t, offset)
    return os.time{ year = t.year, month = t.month, day = t.day + offset, hour = 0 }
end

-- A number from the first row of a query's result, 0 when there is none (sum() over no rows is NULL).
local function firstNumber(res, column)
    return res and res[column] and tonumber(res[column][1]) or 0
end

--- Minutes read: `{ total_minutes, week_minutes }`, all recorded time and this week's, from Monday 00:00 to today,
-- rounded as the statistics plugin's pages round them.
function Me.readingTime(now)
    local t = os.date("*t", now or Me.now())
    local monday = dayStart(t, -((t.wday + 5) % 7)) -- os.date counts from Sunday = 1
    local res = query(Me.stats_db, string.format("SELECT sum(duration), "
        .. "sum(CASE WHEN start_time >= %d AND start_time < %d THEN duration ELSE 0 END) FROM page_stat_data;",
        monday, dayStart(t, 1)))
    return {
        total_minutes = math.floor(firstNumber(res, 1) / 60 + 0.5),
        week_minutes = math.floor(firstNumber(res, 2) / 60 + 0.5),
    }
end

--- Consecutive days with reading, up to today, or up to yesterday while today has none yet.
function Me.streak(now)
    local t = os.date("*t", now or Me.now())
    local res = query(Me.stats_db, string.format(
        "SELECT DISTINCT %s AS d FROM page_stat_data WHERE start_time < %d ORDER BY d DESC;", DAY_SQL, dayStart(t, 1)))
    local days = res and res[1] or {}
    local offset = days[1] == os.date("%Y-%m-%d", dayStart(t, 0)) and 0 or -1
    local streak = 0
    while days[streak + 1] and days[streak + 1] == os.date("%Y-%m-%d", dayStart(t, offset - streak)) do
        streak = streak + 1
    end
    return streak
end

local function bookTitle(file, doc_settings)
    local props = doc_settings:readSetting("doc_props")
    if props and props.title and props.title ~= "" then
        return props.title
    end
    local _, name = util.splitFilePathName(file)
    return (util.splitFileNameSuffix(name))
end

-- The note a reader wrote on an old-format bookmark, not the text KOReader filled in ("Page 3 … @ 2020-01-02 …").
local function oldBookmarkNote(bookmark, highlighted_text)
    local text = bookmark.text
    if text and text ~= "" and text ~= highlighted_text and not text:match("@ %d%d%d%d%-%d%d%-%d%d") then
        return text
    end
end

--[[--
A book's notes (highlights, thoughts and bookmarks), in book order: its `annotations`, as many as its notes page
counts. Sidecars from before `annotations` keep `highlight` (per page) and `bookmarks`: like the exporter, a highlight
counts when it has text and its bookmark, which may carry the thought; the page bookmarks follow, oldest first.
]]
local function bookNotes(doc_settings)
    local annotations = doc_settings:readSetting("annotations")
    if annotations then
        return annotations
    end
    local notes = {}
    local bookmarks = doc_settings:readSetting("bookmarks") or {}
    for page, items in pairs(doc_settings:readSetting("highlight") or {}) do
        for _, item in ipairs(items) do
            for _, bookmark in ipairs(bookmarks) do
                if item.text and item.text ~= "" and bookmark.datetime == item.datetime then
                    table.insert(notes, { text = item.text, note = oldBookmarkNote(bookmark, item.text),
                        drawer = item.drawer or "lighten",
                        chapter = item.chapter, datetime = item.datetime, page = bookmark.page or item.pos0 or page,
                        pos0 = item.pos0, sort_page = page })
                    break
                end
            end
        end
    end
    table.sort(notes, function(a, b)
        if a.sort_page ~= b.sort_page then return tostring(a.sort_page) < tostring(b.sort_page) end
        return (a.datetime or "") < (b.datetime or "")
    end)
    local page_bookmarks = {}
    for _, bookmark in ipairs(bookmarks) do
        if not bookmark.highlighted then
            table.insert(page_bookmarks, { page = bookmark.page, chapter = bookmark.chapter, datetime = bookmark.datetime,
                note = oldBookmarkNote(bookmark) })
        end
    end
    table.sort(page_bookmarks, function(a, b) return (a.datetime or "") < (b.datetime or "") end)
    for _, bookmark in ipairs(page_bookmarks) do
        table.insert(notes, bookmark)
    end
    return notes
end

-- Calls fn(file, doc_settings, info) for history books whose cached info (BookList) passes `want(info)`.
local function eachHistoryBook(want, fn)
    for _, item in ipairs(ReadHistory.hist) do
        if not item.dim then
            local info = BookList.getBookInfo(item.file)
            if info.been_opened and want(info) then
                fn(item.file, BookList.getDocSettings(item.file), info)
            end
        end
    end
end

--- The notes of all the books in history, bookmarks included. Only sidecars of books with annotations are read.
function Me.noteCount()
    local count = 0
    eachHistoryBook(function(info) return info.has_annotations end, function(_, doc_settings)
        count = count + #bookNotes(doc_settings)
    end)
    return count
end

--- Books in history with notes (last read first): `{ { file, title, notes } }`.
function Me.notes()
    local books = {}
    eachHistoryBook(function(info) return info.has_annotations end, function(file, doc_settings)
        local notes = bookNotes(doc_settings)
        if #notes > 0 then
            table.insert(books, { file = file, title = bookTitle(file, doc_settings), notes = notes })
        end
    end)
    return books
end

--- The name the 我 tab shows: the nickname, else defaultName().
function Me.name()
    return Me.nickname() or Me.defaultName()
end

--- The nickname set on the 我 tab, or nil.
function Me.nickname()
    return G_reader_settings:readSetting("me_nickname")
end

--- The name without a nickname: the KOSync user name (kept after logging out), else the device model.
function Me.defaultName()
    local kosync = Me.kosyncSettings()
    if kosync.username and kosync.username ~= "" then
        return kosync.username
    end
    return Device.model or "KOReader"
end

--- Sets the nickname, written at once; an empty one goes back to the KOSync user name or the device model.
function Me.setNickname(name)
    name = util.trim(name or "")
    if name == "" then
        G_reader_settings:delSetting("me_nickname")
    else
        G_reader_settings:saveSetting("me_nickname", name)
    end
    G_reader_settings:flush()
end

--- The KOSync plugin's settings (its user name and key); KOSync itself only runs in the reader.
function Me.kosyncSettings()
    return LuaSettings:open(Me.kosync_settings):readSetting("settings") or {}
end

function Me.vocabCount()
    local res = query(Me.vocab_db, "SELECT count(*) FROM vocabulary;")
    return res and tonumber(res[1][1]) or 0
end

--- Looked-up words, newest first: `{ { word, prev_context, next_context, book, create_time } }`.
function Me.vocab()
    local words = {}
    local res = query(Me.vocab_db, "SELECT word, prev_context, next_context, create_time, name FROM vocabulary "
        .. "LEFT JOIN title ON title_id = title.id ORDER BY create_time DESC;")
    if res then
        for i = 1, #res[1] do
            table.insert(words, {
                word = res[1][i],
                prev_context = res[2][i],
                next_context = res[3][i],
                create_time = tonumber(res[4][i]),
                book = res[5][i],
            })
        end
    end
    return words
end

return Me
