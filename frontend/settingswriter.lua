-- Settings are replaced only after a complete, synced temporary file exists.
-- A process interrupted between backup and replacement can reopen the .old file.
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local SettingsWriter = {}

function SettingsWriter.backup(path)
    if lfs.attributes(path, "mode") == "file" then
        -- Keep the existing policy: a recently modified version must not displace
        -- the older recovery copy on filesystems with unreliable sync support.
        local mtime = lfs.attributes(path, "modification")
        if mtime and mtime < os.time() - 60 then
            return os.rename(path, path .. ".old")
        end
    end
    return false
end

-- rotate_backup=false is for replacing a recovery copy itself: rotating that
-- copy could retain sensitive old data under an otherwise unused .old.old name.
function SettingsWriter.write(data, path, options)
    if not path then return nil, "no settings path" end
    -- One writer on the Lua main thread; opening truncates a previous interrupted
    -- attempt, which is never considered a settings candidate by either loader.
    local temporary = path .. ".tmp"
    local file, err = io.open(temporary, "wb")
    if not file then
        os.remove(temporary)
        return nil, err
    end
    local ok
    ok, err = file:write(table.concat{ "-- ", path, "\nreturn ", data, "\n" })
    if ok then ok, err = file:flush() end
    if ok then ok, err = ffiutil.fsyncOpenedFile(file, true) end
    local closed, close_err = file:close()
    if not ok or not closed then
        os.remove(temporary)
        return nil, err or close_err
    end

    local backed_up = false
    if not options or options.rotate_backup ~= false then
        backed_up, err = SettingsWriter.backup(path)
    end
    if backed_up == nil then
        os.remove(temporary)
        return nil, err
    end
    ok, err = os.rename(temporary, path)
    if not ok then
        if backed_up then
            local restored, restore_err = os.rename(path .. ".old", path)
            if not restored then
                -- Leave the intact .old recovery copy alone if rollback fails.
                err = err .. "; backup retained at " .. path .. ".old: " .. tostring(restore_err)
            else
                ffiutil.fsyncDirectory(path)
            end
        end
        os.remove(temporary)
        return nil, err
    end
    ok, err = ffiutil.fsyncDirectory(path)
    -- Replacement is already committed: do not retry in another location or
    -- retain old candidates merely because this filesystem cannot sync dirs.
    if not ok then logger.warn("SettingsWriter: directory sync failed:", path, err) end
    return true
end

return SettingsWriter
