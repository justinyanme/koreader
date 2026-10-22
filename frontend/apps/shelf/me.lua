--[[--
Data behind the 我的 tab. No widgets, and no timing of its own.

Reading time comes from the statistics plugin's database, words from the
vocabulary builder's database, and notes and finished books from the sidecars
of the books in reading history (the books the exporter's "all books" covers).
Both databases are only read; a missing or unreadable one reads as empty.
The home page needs counts only; notes and words are loaded by their subpages.
]]

local BookList = require("ui/widget/booklist")
local DataStorage = require("datastorage")
local ReadHistory = require("readhistory")
local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local Me = {
    stats_db = DataStorage:getSettingsDir() .. "/statistics.sqlite3",
    vocab_db = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3",
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

--- This week, Monday first: `{ minutes = { [1..7] = n or nil for days to come }, total_minutes, today }`.
function Me.week(now)
    local t = os.date("*t", now or Me.now())
    local today = (t.wday + 5) % 7 + 1 -- os.date counts from Sunday = 1
    local first = dayStart(t, 1 - today)
    local by_day = {}
    local res = query(Me.stats_db, string.format(
        "SELECT %s AS d, sum(duration) FROM page_stat_data WHERE start_time >= %d GROUP BY d;", DAY_SQL, first))
    if res then
        for i = 1, #res[1] do
            by_day[res[1][i]] = tonumber(res[2][i])
        end
    end
    local week = { minutes = {}, total_minutes = 0, today = today }
    for i = 1, today do
        local minutes = math.floor((by_day[os.date("%Y-%m-%d", dayStart(t, i - today))] or 0) / 60)
        week.minutes[i] = minutes
        week.total_minutes = week.total_minutes + minutes
    end
    return week
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

--[[--
A book's highlights (annotations with a drawer; bookmarks excluded), in book order.
Sidecars from before annotations keep `highlight` (per page) and `bookmarks`: like the
exporter, a highlight counts when it has text and its bookmark, which may carry the note.
]]
local function bookNotes(doc_settings)
    local notes = {}
    local annotations = doc_settings:readSetting("annotations")
    if annotations then
        for _, a in ipairs(annotations) do
            if a.drawer then table.insert(notes, a) end
        end
        return notes
    end
    local bookmarks = doc_settings:readSetting("bookmarks") or {}
    for page, items in pairs(doc_settings:readSetting("highlight") or {}) do
        for _, item in ipairs(items) do
            for _, bookmark in ipairs(bookmarks) do
                if item.text and item.text ~= "" and bookmark.datetime == item.datetime then
                    local note = bookmark.text ~= item.text and not (bookmark.text or ""):match("@ %d%d%d%d%-%d%d%-%d%d")
                        and bookmark.text or nil
                    table.insert(notes, { text = item.text, note = note, drawer = item.drawer or "lighten",
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

--[[--
`{ note_count, finished_this_year }` over the books in history. Only sidecars of books with
annotations or a finished status are read. "Finished this year" approximates the date a book
was finished by its summary's `modified` date, the last time its status was set.
]]
function Me.counts(now)
    local year = os.date("%Y", now or Me.now())
    local counts = { note_count = 0, finished_this_year = 0 }
    eachHistoryBook(function(info) return info.has_annotations or info.status == "complete" end,
        function(_, doc_settings, info)
            local summary = doc_settings:readSetting("summary")
            if info.status == "complete" and summary and (summary.modified or ""):sub(1, 4) == year then
                counts.finished_this_year = counts.finished_this_year + 1
            end
            if info.has_annotations then
                counts.note_count = counts.note_count + #bookNotes(doc_settings)
            end
        end)
    return counts
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
