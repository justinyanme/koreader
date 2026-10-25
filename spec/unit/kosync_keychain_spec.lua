describe("KOSync Keychain account lifecycle", function()
    local Device, Store, LuaSettings, Sync, sync, dir, original_bridge, request_stub, options
    local response_code, response_body, requests, wire_debug, original_spore_debug, old_path
    setup(function()
        require("commonrequire")
        old_path = package.path
        package.path = "plugins/kosync.koplugin/?.lua;" .. package.path
        Device, Store, LuaSettings = require("device"), require("credentialstore"), require("luasettings")
        Sync = dofile("plugins/kosync.koplugin/main.lua")
        dir = require("datastorage"):getDataDir() .. "/kosync_keychain_spec"
        require("libs/libkoreader-lfs").mkdir(dir)
        original_bridge = Device.bridge
        original_spore_debug = require("Spore").debug
    end)
    before_each(function()
        options, requests, wire_debug = { keychain = {} }, {}, {}
        Device.bridge = require("iosbridge").new(options)
        require("Spore").debug = { write = function(_, ...) table.insert(wire_debug, { ... }) end }
        response_code, response_body = 200, '{"authorized":"OK"}'
        request_stub = stub(require("socket.http"), "request", function(request)
            table.insert(requests, request)
            request.sink(response_body)
            return 1, response_code, { ["content-type"] = "application/json" }, "HTTP/1.1 " .. response_code
        end)
        Sync.settings_obj = LuaSettings:wrap{ settings = { custom_server = "http://sync.example/", username = "reader" } }
        Sync.settings_obj.file = dir .. "/kosync.lua"
        sync = Sync:extend{ settings_file = Sync.settings_obj.file, path = "plugins/kosync.koplugin" }
        sync:loadSettings()
    end)
    after_each(function()
        request_stub:revert()
        Device.bridge = original_bridge
        require("Spore").debug = original_spore_debug
        Sync.settings_obj = nil
        local UIManager = require("ui/uimanager")
        while UIManager._window_stack[1] do UIManager:close(UIManager._window_stack[1].widget) end
    end)
    teardown(function() package.path = old_path; require("ffi/util").purgeDir(dir) end)

    it("logs in with Keychain-backed auth, disables wire logging, and deletes the item on logout", function()
        sync:doLogin("reader", "password-canary")
        assert.are.equal(require("ffi/sha2").md5("password-canary"), sync:getUserkey())
        local saved = LuaSettings:open(sync.settings_file):readSetting("settings")
        assert.is_nil(saved.userkey)
        assert.is_string(saved.userkey_ref)
        assert.are.equal("reader", requests[1].headers["x-auth-user"])
        assert.are.equal(sync:getUserkey(), requests[1].headers["x-auth-key"])
        -- new_from_spec may log the local spec filename; no HTTP headers may be dumped.
        for _, args in ipairs(wire_debug) do
            for _, value in ipairs(args) do
                assert.is_nil(tostring(value):find("password-canary", 1, true))
                assert.is_nil(tostring(value):find(sync:getUserkey(), 1, true))
            end
        end
        sync:logout()
        assert.is_nil(sync:getUserkey())
        assert.is_nil(Store.userkey(LuaSettings:open(sync.settings_file):readSetting("settings")))
        assert.is_nil(options.keychain[saved.userkey_ref])
    end)

    it("does not persist a new password when Keychain cannot save it", function()
        options.keychain_error = "-25308"
        sync:doLogin("reader", "rejected-password")
        assert.is_nil(sync.settings.userkey)
        assert.is_nil(sync.settings.userkey_ref)
        assert.is_nil(LuaSettings:open(sync.settings_file):readSetting("settings").userkey)
    end)

    it("registers into Keychain and leaves a restored device logged out without draining queued progress", function()
        response_code, response_body = 201, '{"username":"reader"}'
        sync:doRegister("reader", "registered-password")
        assert.is_string(sync.settings.userkey_ref)
        Device.bridge = require("iosbridge").new()
        assert.is_nil(sync:getUserkey())
        local finished = false
        local count = #requests
        sync:drainQueue(function() finished = true end)
        assert.is_true(finished)
        assert.are.equal(count, #requests)
    end)

    it("deletes a new item if the primary save fails, retaining the previous account", function()
        sync:doLogin("reader", "old-password")
        local ref = sync.settings.userkey_ref
        local failed = stub(Sync.settings_obj, "flush", function() return nil, "disk full" end)
        finally(function() failed:revert() end)
        sync:doLogin("reader", "new-password")
        assert.are.equal(ref, sync.settings.userkey_ref)
        assert.are.equal(ref, next(options.keychain))
        assert.is_nil(next(options.keychain, ref))
        assert.are.equal(require("ffi/sha2").md5("old-password"), sync:getUserkey())
    end)

    it("retains a committed account and its Keychain item when backup cleanup fails", function()
        local flush = LuaSettings.flush
        local failed = stub(LuaSettings, "flush", function(object, ...)
            if object.file == sync.settings_file .. ".old" then return nil, "disk full" end
            return flush(object, ...)
        end)
        finally(function() failed:revert() end)
        sync:doLogin("reader", "saved-password")
        local saved = LuaSettings:open(sync.settings_file):readSetting("settings")
        assert.are.equal(saved.userkey_ref, sync.settings.userkey_ref)
        assert.are.equal(require("ffi/sha2").md5("saved-password"), sync:getUserkey())
    end)

    it("passes lifecycle save context through cleanup and retains pending settings after failure", function()
        sync.updated = true
        local rename = os.rename
        local failed = stub(os, "rename", function(from, to)
            if from == sync.settings_file .. ".old.tmp" then return nil, "backup unavailable" end
            return rename(from, to)
        end)
        finally(function() failed:revert() end)
        local context = { complete = true, recordFailure = function(self) self.complete = false end }
        sync:onFlushSettings(false, context)
        assert.is_true(sync.updated)
        assert.is_false(context.complete)
        failed:revert()
        context.complete = true
        sync:onFlushSettings(false, context)
        assert.is_nil(sync.updated)
        assert.is_true(context.complete)
    end)

    it("clears queued progress when logout commits despite a backup cleanup failure", function()
        sync:doLogin("reader", "password")
        local queue = require("KOSyncQueue")
        queue:push{ document = "old-account-document", progress = "12", percentage = 0.4, device = "reader" }
        finally(function() queue:clear() end)
        local rename = os.rename
        local failed = stub(os, "rename", function(from, to)
            if from == sync.settings_file .. ".old.tmp" then return nil, "backup unavailable" end
            return rename(from, to)
        end)
        finally(function() failed:revert() end)
        sync:logout()
        assert.is_nil(sync:getUserkey())
        assert.are.equal(0, queue:count())
        assert.is_true(sync.updated)
    end)

    it("does not log an error response containing credentials, even with debug enabled", function()
        local logger = require("logger")
        local logged = {}
        local logging = stub(logger, "dbg", function(...)
            for _, value in ipairs{ ... } do
                table.insert(logged, require("dump")(value))
            end
        end)
        response_code = 500
        response_body = '{"message":"echoed-password-canary"}'
        local client = require("KOSyncClient"):new{
            custom_url = "http://sync.example/", service_spec = "plugins/kosync.koplugin/api.json",
        }
        client:authorize("username-canary", "echoed-password-canary")
        logging:revert()
        local output = table.concat(logged)
        assert.is_nil(output:find("echoed-password-canary", 1, true))
        assert.is_nil(output:find("username-canary", 1, true))
        assert.is_nil(output:find("sync.example", 1, true))
    end)
end)
