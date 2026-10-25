-- Credentials are resolved only at the request/edit boundary. Settings keep
-- opaque references. No logging here: even a bridge exception may contain data.
local DataStorage = require("datastorage")
local Device = require("device")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")

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
    if not Store.available() then draft.userkey = userkey; return true end
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
function Store.flush(settings)
    local ok, result = pcall(settings.flush, settings)
    if not ok or not result then return nil, "save_failed" end
    if Store.available() and settings.file then
        local backup = LuaSettings:wrap(settings.data)
        backup.file = settings.file .. ".old"
        backup.backup = function() end
        ok, result = pcall(backup.flush, backup)
        if not ok or not result then return nil, "save_failed" end
    end
    return true
end

local function migrateSource(source)
    for _, field in ipairs(source_fields) do
        if source[field] ~= nil then
            -- A prior interrupted/older write may leave both a ref and plaintext.
            local credentials = Store.source(source)
            if not credentials then return end
            for _, key in ipairs(source_fields) do
                if source[key] ~= nil then credentials[key] = source[key] end
            end
            return Store.setSource(source, credentials)
        end
    end
end

function Store.migrateSettings(settings, kind)
    if not Store.available() then return true end
    local complete = true
    if kind == "opds" then
        for _, source in ipairs(settings:readSetting("servers") or {}) do
            if migrateSource(source) == nil then
                for _, field in ipairs(source_fields) do
                    if source[field] ~= nil then complete = false end
                end
            end
        end
    else
        local account = settings:readSetting("settings")
        if account and account.userkey ~= nil then
            complete = Store.setUserkey(account, account.userkey) == true
        end
    end
    local saved = Store.flush(settings)
    if complete and saved then return true end
    return nil, "migration_incomplete"
end

function Store.migrate()
    if not Store.available() then return end
    for _, kind in ipairs{ "opds", "kosync" } do
        local path = DataStorage:getSettingsDir() .. "/" .. kind .. ".lua"
        if lfs.attributes(path, "mode") == "file" or lfs.attributes(path .. ".old", "mode") == "file" then
            Store.migrateSettings(LuaSettings:open(path), kind)
        end
    end
    -- Older one-time migrations moved these to plugin files. Scrub any stale
    -- copies as well as settings.reader.lua.old, preserving unrelated settings.
    if G_reader_settings then
        local legacy_sources = G_reader_settings:readSetting("opds_servers")
        local legacy_sync = G_reader_settings:readSetting("kosync")
        if legacy_sources then
            for _, source in ipairs(legacy_sources) do migrateSource(source) end
        end
        if legacy_sync and legacy_sync.userkey ~= nil then Store.setUserkey(legacy_sync, legacy_sync.userkey) end
        Store.flush(G_reader_settings)
    end
end

return Store
