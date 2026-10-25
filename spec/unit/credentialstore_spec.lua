-- The device bridge (seam C) and serialized backup are the security boundary.
-- User-visible source operations are also exercised through FileManager in booksource_spec.
describe("Credential migration through the device bridge", function()
    local Store, Device, LuaSettings, util, dir, original_bridge
    local options, settings
    setup(function()
        require("commonrequire")
        Store = require("credentialstore")
        Device = require("device")
        LuaSettings = require("luasettings")
        util = require("util")
        dir = require("datastorage"):getDataDir() .. "/keychain_spec"
        require("libs/libkoreader-lfs").mkdir(dir)
        original_bridge = Device.bridge
    end)
    before_each(function()
        options = { keychain = {} }
        Device.bridge = require("iosbridge").new(options)
        settings = LuaSettings:wrap{
            servers = { { title = "NAS", url = "https://nas.example/opds", username = "reader",
                password = "basic-canary", access_client_id = "id-canary", access_client_secret = "secret-canary",
                downloaded = { book = "home/book.epub" } } },
        }
        settings.file = dir .. "/opds.lua"
        settings:flush()
    end)
    after_each(function() Device.bridge = original_bridge end)
    teardown(function() require("ffi/util").purgeDir(dir) end)

    local function absent(path, secrets)
        local contents = assert(util.readFromFile(path))
        for _, secret in ipairs(secrets) do assert.is_nil(contents:find(secret, 1, true)) end
    end

    it("migrates Basic and both CF token fields, retaining only an opaque reference in primary and backup", function()
        assert.is_true(Store.migrateSettings(settings, "opds"))
        local saved = LuaSettings:open(settings.file):readSetting("servers")[1]
        assert.is_string(saved.credential_ref)
        assert.is_nil(saved.password)
        assert.is_nil(saved.access_client_id)
        assert.are.same({ book = "home/book.epub" }, saved.downloaded)
        assert.are.same({ password = "basic-canary", access_client_id = "id-canary", access_client_secret = "secret-canary" },
            Store.source(saved))
        for _, suffix in ipairs{ "", ".old" } do
            absent(settings.file .. suffix, { "basic-canary", "id-canary", "secret-canary" })
        end
        local ref = saved.credential_ref
        assert.is_true(Store.migrateSettings(LuaSettings:open(settings.file), "opds"))
        assert.are.equal(ref, LuaSettings:open(settings.file):readSetting("servers")[1].credential_ref)
    end)

    it("keeps failed migrations retryable without losing the original credentials", function()
        options.keychain_error = "-25308"
        assert.is_nil(Store.migrateSettings(settings, "opds"))
        assert.are.equal("basic-canary", LuaSettings:open(settings.file):readSetting("servers")[1].password)
        options.keychain_error = nil
        assert.is_true(Store.migrateSettings(LuaSettings:open(settings.file), "opds"))
        absent(settings.file, { "basic-canary", "id-canary", "secret-canary" })
    end)

    it("scrubs a stale plaintext backup when the primary already has references", function()
        local old = util.readFromFile(settings.file)
        assert.is_true(Store.migrateSettings(settings, "opds"))
        util.writeToFile(old, settings.file .. ".old") -- interrupted backup cleanup
        assert.is_true(Store.migrateSettings(LuaSettings:open(settings.file), "opds"))
        absent(settings.file .. ".old", { "basic-canary", "id-canary", "secret-canary" })
    end)

    it("scrubs aged plaintext primary and backup files without ever rotating .old into .old.old", function()
        local fs = require("libs/libkoreader-lfs")
        local previous = os.time() - 120
        assert(util.writeToFile(util.readFromFile(settings.file), settings.file .. ".old"))
        assert(fs.touch(settings.file, previous, previous))
        assert(fs.touch(settings.file .. ".old", previous, previous))
        assert.is_true(Store.migrateSettings(settings, "opds"))
        assert.is_nil(fs.attributes(settings.file .. ".old.old"))
        absent(settings.file .. ".old", { "basic-canary", "id-canary", "secret-canary" })
    end)

    it("removes an existing .old.old plaintext residue even after the primary has been migrated", function()
        local original = util.readFromFile(settings.file)
        assert.is_true(Store.migrateSettings(settings, "opds"))
        assert(util.writeToFile(original, settings.file .. ".old.old"))
        assert.is_true(Store.migrateSettings(settings, "opds"))
        assert.is_nil(require("libs/libkoreader-lfs").attributes(settings.file .. ".old.old"))
    end)

    it("passes lifecycle context through backup failures after the primary has committed", function()
        local rename = os.rename
        local failed = stub(os, "rename", function(from, to)
            if from == settings.file .. ".old.tmp" then return nil, "backup unavailable" end
            return rename(from, to)
        end)
        finally(function() failed:revert() end)
        local context = { complete = true, recordFailure = function(self) self.complete = false end }
        local ok, __err, primary_committed = Store.migrateSettings(settings, "opds", context)
        assert.is_nil(ok)
        assert.is_true(primary_committed)
        assert.is_false(context.complete)
        assert.are.equal("basic-canary", Store.source(LuaSettings:open(settings.file):readSetting("servers")[1]).password)
    end)

    it("recovers plaintext in a mixed record even if its previous Keychain reference is missing", function()
        settings.data.servers[1].credential_ref = "missing-old-ref"
        assert.is_true(Store.migrateSettings(settings, "opds"))
        local saved = LuaSettings:open(settings.file):readSetting("servers")[1]
        assert.are.equal("basic-canary", Store.source(saved).password)
        assert.are.equal("secret-canary", Store.source(saved).access_client_secret)
        absent(settings.file, { "basic-canary", "id-canary", "secret-canary" })
    end)

    it("deletes a mixed record's superseded Keychain item only after persisting its replacement", function()
        options.keychain["previous-source-ref"] = '{"password":"old-password"}'
        settings.data.servers[1].credential_ref = "previous-source-ref"
        assert.is_true(Store.migrateSettings(settings, "opds"))
        assert.is_nil(options.keychain["previous-source-ref"])
        assert.are.equal("basic-canary", Store.source(LuaSettings:open(settings.file):readSetting("servers")[1]).password)

        options.keychain["previous-sync-ref"] = "old-digest"
        local sync = LuaSettings:wrap{ settings = { userkey = "new-digest", userkey_ref = "previous-sync-ref" } }
        sync.file = dir .. "/kosync.lua"
        assert.is_true(Store.migrateSettings(sync, "kosync"))
        assert.is_nil(options.keychain["previous-sync-ref"])
        assert.are.equal("new-digest", Store.userkey(LuaSettings:open(sync.file):readSetting("settings")))
    end)

    it("does not rewrite unrelated global settings on startup when there are no legacy credential keys", function()
        local original_settings = _G.G_reader_settings
        local global = LuaSettings:wrap{ unrelated = "preserved" }
        global.file = dir .. "/global.lua"
        global:flush()
        local fs = require("libs/libkoreader-lfs")
        local previous = os.time() - 120
        assert(fs.touch(global.file, previous, previous))
        -- Required modules read _G, while bare assignments here stay in Busted's isolated environment.
        _G.G_reader_settings = global
        finally(function() _G.G_reader_settings = original_settings end)
        local paths = stub(require("datastorage"), "getSettingsDir", function() return dir end)
        finally(function() paths:revert() end)
        Store.migrate()
        assert.are.equal(previous, fs.attributes(global.file, "modification"))
        assert.is_nil(fs.attributes(global.file .. ".old"))
    end)

    it("cleans global backup residues without rewriting an already clean primary", function()
        local original_settings = _G.G_reader_settings
        local global = LuaSettings:wrap{ unrelated = "preserved" }
        global.file = dir .. "/global-clean.lua"
        assert(global:flush())
        local residue = 'return {kosync={userkey="legacy-digest"}}'
        assert(util.writeToFile(residue, global.file .. ".old"))
        assert(util.writeToFile(residue, global.file .. ".old.old"))
        local fs = require("libs/libkoreader-lfs")
        local previous = os.time() - 120
        assert(fs.touch(global.file, previous, previous))
        _G.G_reader_settings = global
        finally(function() _G.G_reader_settings = original_settings end)
        local paths = stub(require("datastorage"), "getSettingsDir", function() return dir end)
        finally(function() paths:revert() end)
        Store.migrate()
        assert.are.equal(previous, fs.attributes(global.file, "modification"))
        assert.is_nil(fs.attributes(global.file .. ".old.old"))
        absent(global.file .. ".old", { "legacy-digest" })
    end)

    it("removes newly allocated migration items when the primary cannot commit", function()
        local failed = stub(settings, "flush", function() return nil, "disk full" end)
        finally(function() failed:revert() end)
        local ok, __err, committed = Store.migrateSettings(settings, "opds")
        assert.is_nil(ok)
        assert.is_false(committed)
        assert.is_nil(next(options.keychain))
        assert.are.equal("basic-canary", settings.data.servers[1].password)
        assert.is_nil(settings.data.servers[1].credential_ref)
    end)

    it("migrates KOSync's reusable password digest and treats a restored device as logged out", function()
        local sync = LuaSettings:wrap{ settings = { username = "reader", userkey = "digest-canary", auto_sync = true } }
        sync.file = dir .. "/kosync.lua"
        assert.is_true(Store.migrateSettings(sync, "kosync"))
        local saved = LuaSettings:open(sync.file):readSetting("settings")
        assert.is_string(saved.userkey_ref)
        assert.is_nil(saved.userkey)
        assert.are.equal("digest-canary", Store.userkey(saved))
        absent(sync.file, { "digest-canary" })
        absent(sync.file .. ".old", { "digest-canary" })
        Device.bridge = require("iosbridge").new() -- ThisDeviceOnly not restored
        assert.is_nil(Store.userkey(saved))
        assert.are.equal("reader", saved.username)
    end)

    it("keeps non-Keychain devices and unsupported bridge stubs on the legacy plaintext path", function()
        for _, bridge in ipairs{ {}, require("device/sdl/iosbridge").new() } do
            Device.bridge = bridge
            assert.is_true(Store.migrateSettings(settings, "opds"))
            assert.are.equal("basic-canary", settings.data.servers[1].password)
            local draft = { userkey_ref = "restored-ref" }
            assert.is_true(Store.setUserkey(draft, "legacy-digest"))
            assert.are.equal("legacy-digest", draft.userkey)
            assert.is_nil(draft.userkey_ref)
            draft.credential_ref = "restored-source-ref"
            assert.is_true(Store.setSource(draft, { password = "legacy-password" }))
            assert.is_nil(draft.credential_ref)
            assert.are.equal("legacy-password", Store.source(draft).password)
        end
    end)
end)
