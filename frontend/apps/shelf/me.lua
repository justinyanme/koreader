--[[--
Data behind the 我的 tab. No widgets, and no timing of its own.

Reading time comes from the statistics plugin's database, words from the
vocabulary builder's database, and notes and finished books from the sidecars
of the books in reading history (the books the exporter's "all books" covers).
Both databases are only read; a missing or unreadable one reads as empty.
]]

local BookList = require("ui/widget/booklist")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local ReadHistory = require("readhistory")
local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local Me = {
    stats_db = DataStorage:getSettingsDir() .. "/statistics.sqlite3",
    vocab_db = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3",
}

local DAY_SQL = "strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime')"

-- Runs `sql` on the database at `path`; returns the result columns, or nil.
local function query(path, sql)
    if lfs.attributes(path, "mode") ~= "file" then return end
    local ok, result = pcall(function()
        local conn = SQ3.open(path, "ro")
        local res = conn:exec(sql)
        conn:close()
        return res
    end)
    if not ok then
        logger.warn("Me: cannot read", path, result)
        return
    end
    return result
end

-- Local midnight `offset` days after the day of `t` (os.date("*t") table), DST-safe.
local function dayStart(t, offset)
    return os.time{ year = t.year, month = t.month, day = t.day + offset, hour = 0 }
end

--- This week, Monday first: `{ minutes = { [1..7] = n or nil for days to come }, total_minutes, today }`.
function Me.week(now)
    local t = os.date("*t", now or os.time())
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
    local t = os.date("*t", now or os.time())
    local read = {}
    local res = query(Me.stats_db, string.format(
        "SELECT DISTINCT %s FROM page_stat_data WHERE start_time >= %d;", DAY_SQL, dayStart(t, -400)))
    if res then
        for _, d in ipairs(res[1]) do read[d] = true end
    end
    local offset = read[os.date("%Y-%m-%d", dayStart(t, 0))] and 0 or -1
    local streak = 0
    while read[os.date("%Y-%m-%d", dayStart(t, offset - streak))] do
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
One pass over the sidecars of the books in history (last read first).
Returns `{ books = { { file, title, notes } }, note_count, finished_this_year }`; `notes` are the
book's highlights (annotations with a drawer, bookmarks excluded), in book order, and only books
with notes are listed. A book counts as finished this year when its status was set to finished this year.
]]
-- ponytail: opens every history sidecar on each visit to 我的; cache by sidecar mtime if history gets big.
function Me.library(now)
    local year = os.date("%Y", now or os.time())
    local lib = { books = {}, note_count = 0, finished_this_year = 0 }
    for _, item in ipairs(ReadHistory.hist) do
        if not item.dim and BookList.hasBookBeenOpened(item.file) then
            local doc_settings = DocSettings:open(item.file)
            local summary = doc_settings:readSetting("summary")
            if summary and summary.status == "complete" and (summary.modified or ""):sub(1, 4) == year then
                lib.finished_this_year = lib.finished_this_year + 1
            end
            local notes = {}
            for _, a in ipairs(doc_settings:readSetting("annotations") or {}) do
                if a.drawer then table.insert(notes, a) end
            end
            if #notes > 0 then
                table.insert(lib.books, { file = item.file, title = bookTitle(item.file, doc_settings), notes = notes })
                lib.note_count = lib.note_count + #notes
            end
        end
    end
    return lib
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
