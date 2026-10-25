-- Credentials are resolved only at the request/edit boundary. Settings keep
-- opaque references. No logging here: even a bridge exception may contain data.
local DataStorage = require("datastorage")
local Device = require("device")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local ffiUtil = require("ffi/util")

local Store = {}
local source_fields = { "password", "access_client_id", "access_client_secret" }

function Store.available()
    local bridge = Device.bridge
    return bridge ~= nil and bridge.keychainAvailable == true
end

local function call(operation, ...)
    if not Store.available() then return nil, "unsupported" end
    local ok, value, err = pcall(Device.bridge[operation], ...)
    if not ok then return nil, "keychain_failed" end
    return value, err
end

local function put(value)
    -- References are not derived from passwords, server URLs or account names.
    -- Check for collisions, including entries retained after reinstalling.
    for _ = 1, 8 do
        local ref = require("ffi/sha2").md5(tostring({}) .. require("socket").gettime() .. math.random())
        local _, err = call("keychainGet", ref)
        if err == "not_found" then
            local ok, set_err = call("keychainSet", ref, value)
            if ok then return ref end
            return nil, set_err
        elseif err then
            return nil, err
        end
    end
    return nil, "keychain_failed"
end

function Store.delete(ref)
    if not ref then return true end
    return call("keychainDelete", ref)
end

function Store.source(source)
    if source.credential_ref then
        local value, err = call("keychainGet", source.credential_ref)
        if not value then return nil, err end
        local ok, credentials = pcall(require("json").decode, value)
        if not ok or type(credentials) ~= "table" then return nil, "invalid_credentials" end
        for _, field in ipairs(source_fields) do
            if credentials[field] ~= nil and type(credentials[field]) ~= "string" then
                return nil, "invalid_credentials"
            end
        end
        return credentials
    end
    local credentials = {}
    for _, field in ipairs(source_fields) do credentials[field] = source[field] end
    return credentials
end

function Store.userkey(settings)
    if settings.userkey_ref then return call("keychainGet", settings.userkey_ref) end
    return settings.userkey
end

-- Mutate a draft, never the live persisted record, until flush has succeeded.
-- Always create a new item: failed saves must not change the old account's key.
function Store.setSource(draft, credentials)
    if not Store.available() then
        for _, field in ipairs(source_fields) do draft[field] = credentials[field] end
        draft.credential_ref = nil
        return true
    end
    local values = {}
    for _, field in ipairs(source_fields) do values[field] = credentials[field] end
    local ref, err
    if next(values) then
        ref, err = put(require("json").encode(values))
        if not ref then return nil, err end
    end
    for _, field in ipairs(source_fields) do draft[field] = nil end
    draft.credential_ref = ref
    return true
end

function Store.setUserkey(draft, userkey)
    if not Store.available() then
        draft.userkey, draft.userkey_ref = userkey, nil
        return true
    end
    local ref, err
    if userkey then
        ref, err = put(userkey)
        if not ref then return nil, err end
    end
    draft.userkey, draft.userkey_ref = nil, ref
    return true
end

-- B5 provides atomic flush (temp + fsync + rename). A sanitized .old is written
-- through that same interface, with backup rotation disabled to avoid .old.old.
-- Retry on every launch, even when the primary file already contains only refs.
local function scrubBackup(settings, context)
    local backup = LuaSettings:wrap(settings.data)
    backup.file = settings.file .. ".old"
    local ok, result = pcall(backup.flush, backup, context, { rotate_backup = false })
    if not ok or not result then
        if context then context:recordFailure("credential backup cleanup failed") end
        return nil
    end
    local residue = settings.file .. ".old.old"
    if lfs.attributes(residue) then
        if not os.remove(residue) then
            if context then context:recordFailure("credential backup cleanup failed") end
            return nil
        end
        ffiUtil.fsyncDirectory(settings.file)
    end
    return true
end

function Store.flush(settings, context)
    local ok, result = pcall(settings.flush, settings, context)
    if not ok or not result then
        if context then context:recordFailure("credential save failed") end
        return nil, "save_failed", false
    end
    if Store.available() and settings.file and not scrubBackup(settings, context) then
        return nil, "save_failed", true
    end
    return true, nil, true
end

local function migrateSource(source, changes)
    for _, field in ipairs(source_fields) do
        if source[field] ~= nil then
            -- A prior interrupted/older write may leave both a ref and plaintext.
            local credentials = Store.source(source) or {}
            for _, key in ipairs(source_fields) do
                if source[key] ~= nil then credentials[key] = source[key] end
            end
            local previous = util.tableDeepCopy(source)
            local ok = Store.setSource(source, credentials)
            if ok then
                table.insert(changes, { record = source, previous = previous, ref_field = "credential_ref" })
                return true
            end
            return nil
        end
    end
end

local function migrateAccount(account, changes)
    if account and account.userkey ~= nil then
        local previous = util.tableDeepCopy(account)
        if not Store.setUserkey(account, account.userkey) then return nil end
        table.insert(changes, { record = account, previous = previous, ref_field = "userkey_ref" })
    end
    return true
end

local function saveMigration(settings, changes, context)
    local saved, err, primary_committed = Store.flush(settings, context)
    for _, change in ipairs(changes) do
        if primary_committed then
            Store.delete(change.previous[change.ref_field])
        else
            Store.delete(change.record[change.ref_field])
            for key in pairs(change.record) do change.record[key] = nil end
            for key, value in pairs(change.previous) do change.record[key] = value end
        end
    end
    return saved, err, primary_committed
end

function Store.migrateSettings(settings, kind, context)
    if not Store.available() then return true end
    local complete = true
    local changes = {}
    if kind == "opds" then
        for _, source in ipairs(settings:readSetting("servers") or {}) do
            local migrated = migrateSource(source, changes)
            if migrated == nil then
                for _, field in ipairs(source_fields) do
                    if source[field] ~= nil then complete = false end
                end
            end
        end
    else
        complete = migrateAccount(settings:readSetting("settings"), changes) == true
    end
    local saved, __err, primary_committed = saveMigration(settings, changes, context)
    if complete and saved then return true, nil, primary_committed end
    if not complete and context then context:recordFailure("credential migration failed") end
    return nil, "migration_incomplete", primary_committed
end

local function hasLegacySettings(path)
    if not path then return false end
    local ok, data = pcall(dofile, path)
    return ok and type(data) == "table" and (data.opds_servers ~= nil or data.kosync ~= nil)
end

function Store.migrate()
    if not Store.available() then return end
    for _, kind in ipairs{ "opds", "kosync" } do
        local path = DataStorage:getSettingsDir() .. "/" .. kind .. ".lua"
        local candidate = path
        if lfs.attributes(path, "mode") ~= "file" and lfs.attributes(path .. ".old", "mode") ~= "file" then
            candidate = path .. ".old.old"
        end
        if lfs.attributes(candidate, "mode") == "file" or lfs.attributes(path .. ".old", "mode") == "file" then
            local settings = LuaSettings:open(candidate)
            settings.file = path
            Store.migrateSettings(settings, kind)
        end
    end
    -- Older one-time migrations moved these to plugin files. Scrub any stale
    -- copies as well as settings.reader.lua.old, preserving unrelated settings.
    if G_reader_settings then
        local legacy_sources = G_reader_settings:readSetting("opds_servers")
        local legacy_sync = G_reader_settings:readSetting("kosync")
        if legacy_sources or legacy_sync or hasLegacySettings(G_reader_settings.file) then
            local changes = {}
            for _, source in ipairs(legacy_sources or {}) do
                migrateSource(source, changes)
            end
            migrateAccount(legacy_sync, changes)
            saveMigration(G_reader_settings, changes)
        elseif G_reader_settings.file then
            local path = G_reader_settings.file
            if lfs.attributes(path .. ".old.old") or hasLegacySettings(path .. ".old") then
                scrubBackup(G_reader_settings)
            end
        end
    end
end

return Store
