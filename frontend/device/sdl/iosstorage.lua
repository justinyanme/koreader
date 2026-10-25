--[[--
The iOS sandbox layout (Q10, Q30). Books are in Documents, the home folder that the Files app shows as
"On My iPhone › Just Reader"; settings, notes and docsettings are in KO_HOME under Library/Application Support,
caches in KO_CACHE_HOME under Library/Caches (both set by the launcher, see datastorage). Sidecars are kept
in docsettings ("dir"), so no .sdr folder shows in Files. Nothing is excluded from backups (Q33).

The container's path changes when the app is reinstalled, and may change when it is updated. Everything that
holds an absolute path is moved along at the next start: the sidecars (docsettings is keyed by the book's path),
the paths in the reader settings, in history.lua and in every settings/*.lua (collections, and plugins such as
book shortcuts or folder defaults, which key by path), and the cover cache's folders. Statistics, the vocabulary
builder and progress sync key books by checksum or title, and sidecars' doc_path is rewritten on opening, so
those need nothing. Each step can run again: the new container is only recorded once all of them are done,
so a start interrupted halfway does the rest the next time.
]]

local DataStorage = require("datastorage")
local dump = require("dump")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local IosStorage = {}

--- The container's path, and its resolved form where that differs (/var is a link to /private/var on iOS):
-- both kinds are stored, depending on whether the path went through realpath.
function IosStorage.roots(container)
    local roots = { container }
    local real = ffiUtil.realpath(container)
    if real and real ~= container then
        table.insert(roots, real)
    end
    return roots
end

--- Where the system leaves copies for the app: Documents/Inbox for "Open with" (copies, as
-- LSSupportsOpeningDocumentsInPlace is NO), tmp/<bundle id>-Inbox for the document picker and newer iOS.
function IosStorage.inboxes(container)
    local dirs = { container .. "/Documents/Inbox" }
    local tmp = container .. "/tmp"
    if lfs.attributes(tmp, "mode") == "directory" then
        for name in lfs.dir(tmp) do
            if name:match("%-Inbox$") then
                table.insert(dirs, tmp .. "/" .. name)
            end
        end
    end
    return dirs
end

-- `value` with any path under an old root moved to the matching new one; strings and, in tables, values and
-- keys (some settings key by folder). Returns the value and whether anything changed.
local function rebase(value, moves)
    if type(value) == "string" then
        for _, move in ipairs(moves) do
            local old = move[1]
            if value == old or value:sub(1, #old + 1) == old .. "/" then
                return move[2] .. value:sub(#old + 1), true
            end
        end
    elseif type(value) == "table" then
        local changed, renamed = false, {}
        for k, v in pairs(value) do
            local new_v, v_changed = rebase(v, moves)
            if v_changed then
                value[k] = new_v
                changed = true
            end
            local new_k, k_changed = rebase(k, moves)
            if k_changed then renamed[k] = new_k end
        end
        for k, new_k in pairs(renamed) do
            value[new_k], value[k] = value[k], nil
            changed = true
        end
        return value, changed
    end
    return value, false
end

-- Moves the tree `src` to `dst`; where `dst` exists already (an earlier, interrupted run), only what it lacks:
-- a file in both is the one the app went on using at the new path.
local function moveTree(src, dst)
    local mode = lfs.attributes(src, "mode")
    if not mode then return end
    if not lfs.attributes(dst, "mode") then
        util.makePath(ffiUtil.dirname(dst))
        local ok, err = os.rename(src, dst)
        if not ok then logger.warn("IosStorage: could not move", src, err) end
    elseif mode == "directory" then
        local names = {}
        for name in lfs.dir(src) do
            if name ~= "." and name ~= ".." then table.insert(names, name) end
        end
        for __, name in ipairs(names) do
            moveTree(src .. "/" .. name, dst .. "/" .. name)
        end
        lfs.rmdir(src)
    else
        os.remove(src)
    end
end

local function rebaseFile(path, moves)
    local ok, data = pcall(dofile, path)
    if not ok or type(data) ~= "table" then return end
    local _, changed = rebase(data, moves)
    if changed then
        util.writeToFile(dump(data, nil, true), path, true, true)
    end
end

local function rebaseCoverCache(db_path, moves)
    if lfs.attributes(db_path, "mode") ~= "file" then return end
    local ok, err = pcall(function()
        local db = require("lua-ljsqlite3/init").open(db_path)
        -- folders end with "/"; OR IGNORE keeps a row extracted already at the new path
        local stmt = db:prepare("UPDATE OR IGNORE bookinfo SET directory = ? || substr(directory, ?) WHERE substr(directory, 1, ?) = ?;")
        for _, move in ipairs(moves) do
            local old = move[1] .. "/"
            stmt:reset():bind(move[2] .. "/", #old + 1, #old, old):step()
        end
        stmt:close()
        db:close()
    end)
    if not ok then logger.warn("IosStorage: cover cache not moved:", err) end
end

--- Moves the paths under `old_roots` to `new_roots` (pairwise, as IosStorage.roots returns them), in `settings`
-- (G_reader_settings, already open) and in the files of `data_dir` (DataStorage's by default).
function IosStorage.migrate(settings, old_roots, new_roots, data_dir)
    data_dir = data_dir or DataStorage:getDataDir()
    local moves = {}
    for i, old in ipairs(old_roots) do
        local new = new_roots[i] or new_roots[1]
        if old ~= new then table.insert(moves, { old, new }) end
    end
    if #moves == 0 then return end
    logger.info("IosStorage: the container moved, updating paths", moves)
    for _, move in ipairs(moves) do
        moveTree(data_dir .. "/docsettings" .. move[1], data_dir .. "/docsettings" .. move[2])
    end
    rebaseFile(data_dir .. "/history.lua", moves)
    local settings_dir = data_dir .. "/settings"
    if lfs.attributes(settings_dir, "mode") == "directory" then
        for name in lfs.dir(settings_dir) do
            if name:match("%.lua$") then
                rebaseFile(settings_dir .. "/" .. name, moves)
            end
        end
    end
    rebaseCoverCache(settings_dir .. "/bookinfo_cache.sqlite3", moves)
    rebase(settings.data, moves)
end

--- Sets up the layout for the container `container` (HOME) and returns the home folder.
function IosStorage.setup(settings, container, data_dir)
    local roots = IosStorage.roots(container)
    local old_roots = settings:readSetting("ios_container_roots")
    -- decided first: migrating rewrites old_roots, which is in the settings, too
    local changed = not util.tableEquals(old_roots or {}, roots)
    if old_roots and changed then
        IosStorage.migrate(settings, old_roots, roots, data_dir)
    end
    local home = container .. "/Documents"
    if lfs.attributes(home, "mode") ~= "directory" then
        lfs.mkdir(home)
    end
    -- resolved, as the file browser's paths are: the lock compares them as strings
    home = ffiUtil.realpath(home) or home
    -- the only root (Q30): 文件 can't go above it
    settings:saveSetting("home_dir", home)
    settings:makeTrue("lock_home_folder")
    if not settings:has("document_metadata_folder") then
        settings:saveSetting("document_metadata_folder", "dir")
    end
    if changed then
        settings:saveSetting("ios_container_roots", roots)
        settings:flush()
    end
    return home
end

return IosStorage
