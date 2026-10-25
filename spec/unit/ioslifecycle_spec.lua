describe("iOS lifecycle persistence (seams A and C)", function()
    local SDLDevice, FakeBridge, ReaderUI, UIManager, DocumentRegistry, Event, time
    local device, reader, original_instance, host, now, original_now, archive
    local original_settings, original_package_path, sync_client, network
    local sample = "spec/front/unit/data/juliet.epub"

    local function revertStub(object, key)
        local value = rawget(object, key)
        if type(value) == "table" and value.revert then value:revert() end
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        SDLDevice = require("device/sdl/device")
        FakeBridge = require("iosbridge")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        DocumentRegistry = require("document/documentregistry")
        Event = require("ui/event")
        time = require("ui/time")
        host = require("device")
    end)

    before_each(function()
        original_instance = ReaderUI.instance
        original_package_path = package.path
        original_settings = require("util").tableDeepCopy(G_reader_settings.data)
        require("docsettings"):open(sample):purge()
        reader = ReaderUI:new{
            dimen = require("device").screen:getSize(),
            document = DocumentRegistry:openDocument(sample),
        }
        ReaderUI.instance = reader
        device = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new() }
        device:UIManagerReady(UIManager)
        stub(host, "scheduleSettingsSave", function(_, ui) device:scheduleSettingsSave(ui) end)
        stub(host, "cancelPendingSettingsSave", function(_, ui) device:cancelPendingSettingsSave(ui) end)
        UIManager:show(reader)
        now, original_now = time.now(), UIManager._now
        stub(time, "now", function() return now end)
    end)

    after_each(function()
        device:cancelPendingSettingsSave(reader)
        revertStub(device.bridge, "backgroundBegin")
        revertStub(device.bridge, "backgroundEnd")
        revertStub(reader.doc_settings, "flush")
        revertStub(G_reader_settings, "flush")
        revertStub(UIManager, "broadcastEvent")
        revertStub(host, "hasEinkScreen")
        revertStub(os, "rename")
        if reader.kosync then
            reader.kosync.settings.auto_sync = false
            reader.kosync:registerEvents()
        end
        host.scheduleSettingsSave:revert()
        host.cancelPendingSettingsSave:revert()
        time.now:revert()
        UIManager._now = original_now
        reader:onClose()
        UIManager:quit()
        if sync_client then sync_client.new:revert() sync_client = nil end
        if network then network.willRerunWhenOnline:revert() network = nil end
        package.path = original_package_path
        if archive then require("util").purgeDir(archive) archive = nil end
        G_reader_settings.data = original_settings
        ReaderUI.instance = original_instance
    end)

    local function lifecycle(name)
        local SDL = require("ffi/SDL3").SDL
        return device:handleLifecycleEvent(SDL["SDL_EVENT_" .. name])
    end

    local function changePosition()
        reader:handleEvent(Event:new("GotoPage", 20))
        reader.bookmark:toggleBookmark()
        reader.annotation:setNote(1, "remember")
    end

    it("saves synchronously from will-resign-active, ends the task and coalesces duplicates", function()
        changePosition()
        local begin, finish = device.bridge.backgroundBegin, device.bridge.backgroundEnd
        local handles, ended, events = {}, {}, {}
        stub(device.bridge, "backgroundBegin", function()
            local handle = begin()
            handles[#handles + 1] = handle
            return handle
        end)
        stub(device.bridge, "backgroundEnd", function(handle)
            ended[handle] = true
            return finish(handle)
        end)
        stub(UIManager, "broadcastEvent", function(_, event)
            events[#events + 1] = event.handler
            if event.handler == "onFlushSettings" then
                reader:onFlushSettings(unpack(event.args, 1, event.args.n))
            end
        end)
        assert.is_true(lifecycle("WILL_ENTER_BACKGROUND"))
        local saved = require("docsettings"):open(sample)
        assert.are.equal("remember", saved:readSetting("annotations")[1].note)
        assert.is_true(ended[handles[1]])
        assert.is_false(device.bridge.backgroundSaveIncomplete())
        assert.is_true(lifecycle("DID_ENTER_BACKGROUND"))
        assert.are.same({ "onFlushSettings", "onSuspend" }, events)
        assert.is_true(ended[handles[2]])
        lifecycle("DID_ENTER_FOREGROUND")
        assert.are.equal("onResume", events[#events])
    end)

    it("still writes essentials when background time is denied", function()
        device.bridge = FakeBridge.new{ background_unavailable = true }
        device:UIManagerReady(UIManager)
        changePosition()
        lifecycle("WILL_ENTER_BACKGROUND")
        assert.are.equal("remember", require("docsettings"):open(sample):readSetting("annotations")[1].note)
        assert.is_false(device.bridge.backgroundSaveIncomplete())
    end)

    it("writes essentials after expiry, skips optional work and retries on foreground", function()
        -- The watcher grants and expires time before Lua dequeues the event.
        local pending = device.bridge.watchBackground()
        device.bridge.expireBackground(pending)
        -- Observe optional work through the public archive output.
        archive = os.tmpname()
        os.remove(archive)
        require("util").makePath(archive)
        local previous = G_reader_settings:readSetting("document_metadata_arc_folder")
        local previous_enabled = G_reader_settings:readSetting("document_metadata_arc_on_closing")
        G_reader_settings:saveSetting("document_metadata_arc_folder", archive)
        G_reader_settings:saveSetting("document_metadata_arc_on_closing", true)
        reader.doc_settings:saveSetting("partial_md5_checksum", "ios-lifecycle-spec")
        changePosition()
        lifecycle("WILL_ENTER_BACKGROUND")
        assert.is_true(device.bridge.backgroundSaveIncomplete())
        assert.is_nil(require("libs/libkoreader-lfs").attributes(archive .. "/ios-lifecycle-spec.lua"))
        assert.are.equal("remember", require("docsettings"):open(sample):readSetting("annotations")[1].note)
        -- WILL and DID may share the watcher's expired task and both be queued
        -- before Lua runs. The duplicate cannot restart optional background work.
        lifecycle("DID_ENTER_BACKGROUND")
        assert.is_true(device.bridge.backgroundSaveIncomplete())
        assert.is_nil(require("libs/libkoreader-lfs").attributes(archive .. "/ios-lifecycle-spec.lua"))
        lifecycle("DID_ENTER_FOREGROUND")
        assert.is_false(device.bridge.backgroundSaveIncomplete())
        assert.is_truthy(require("libs/libkoreader-lfs").attributes(archive .. "/ios-lifecycle-spec.lua"))
        G_reader_settings:saveSetting("document_metadata_arc_folder", previous)
        G_reader_settings:saveSetting("document_metadata_arc_on_closing", previous_enabled)
        require("util").purgeDir(archive)
    end)

    it("retains failed plugin settings and retries them when returning to the foreground", function()
        local OPDS = dofile("plugins/opds.koplugin/main.lua")
        archive = os.tmpname()
        os.remove(archive)
        require("util").makePath(archive)
        local path = archive .. "/plugin.lua"
        local settings = require("luasettings"):open(path):saveSetting("source", "old")
        assert(settings:flush())
        local plugin = OPDS:extend{ settings = settings, updated = true }
        reader:registerModule("opds", plugin)
        settings:saveSetting("source", "new")
        local rename = os.rename
        stub(os, "rename", function(from, to)
            if from == path .. ".tmp" then return nil, "plugin storage unavailable" end
            return rename(from, to)
        end)
        lifecycle("WILL_ENTER_BACKGROUND")
        assert.is_true(device.bridge.backgroundSaveIncomplete())
        assert.is_true(plugin.updated)
        assert.are.equal("old", require("luasettings"):open(path):readSetting("source"))
        os.rename:revert()
        lifecycle("DID_ENTER_FOREGROUND")
        assert.is_false(device.bridge.backgroundSaveIncomplete())
        assert.is_nil(plugin.updated)
        assert.are.equal("new", require("luasettings"):open(path):readSetting("source"))
    end)

    it("ends the task and keeps retry state if a required write throws or fails", function()
        local ended = false
        stub(device.bridge, "backgroundEnd", function() ended = true return true end)
        stub(reader.doc_settings, "flush", function() error("storage failure") end)
        lifecycle("WILL_ENTER_BACKGROUND")
        assert.is_true(ended)
        assert.is_true(device.bridge.backgroundSaveIncomplete())
        reader.doc_settings.flush:revert()
        lifecycle("DID_ENTER_FOREGROUND")
        assert.is_false(device.bridge.backgroundSaveIncomplete())
    end)

    it("saves within three scheduled seconds even when changes keep arriving", function()
        local started = now
        changePosition()
        now = started + time.s(2)
        reader.annotation:setNote(1, "remembered later")
        now = started + time.s(3)
        UIManager:_checkTasks()
        assert.are.equal("remembered later", require("docsettings"):open(sample):readSetting("annotations")[1].note)
    end)

    it("cancels a pending save when its reader closes", function()
        changePosition()
        device:cancelPendingSettingsSave(reader)
        local before = require("docsettings"):open(sample):readSetting("annotations")
        now = now + time.s(4)
        UIManager:_checkTasks()
        assert.are.same(before, require("docsettings"):open(sample):readSetting("annotations"))
    end)

    it("keeps LCD brightness when a daylight frontlight schedule runs after resume", function()
        stub(host, "hasEinkScreen", function() return false end)
        G_reader_settings:saveSetting("autowarmth_fl_off_during_day", true)
        local AutoWarmth = dofile("plugins/autowarmth.koplugin/main.lua")
        local plugin = AutoWarmth:new{ ui = reader }
        reader:registerModule("autowarmth", plugin)
        assert.is_false(plugin:getFlOffDuringDayMenu().enabled_func())
        local intensity = host.powerd:frontlightIntensity()
        plugin:setFrontlight(false)
        now = now + time.s(1)
        UIManager:_checkTasks()
        assert.are.equal(intensity, host.powerd:frontlightIntensity())
    end)

    for _, expired in ipairs{ false, true } do
        it("uploads progress only after local persistence and with remaining time (expired=" .. tostring(expired) .. ")", function()
            package.path = "plugins/kosync.koplugin/?.lua;" .. package.path
            local KOSync = dofile("plugins/kosync.koplugin/main.lua")
            local plugin = KOSync:new{ ui = reader, path = "plugins/kosync.koplugin" }
            plugin.settings = { username = "user", userkey = "key", auto_sync = true }
            plugin:registerEvents()
            reader:registerModule("kosync", plugin)
            network = require("ui/network/manager")
            stub(network, "willRerunWhenOnline", function() return false end)
            sync_client = require("KOSyncClient")
            local uploads = 0
            stub(sync_client, "new", function()
                return {
                    update_progress = function(_, _, _, _, _, _, _, _, _, callback)
                        uploads = uploads + 1
                        assert.are.equal("remember", require("docsettings"):open(sample):readSetting("annotations")[1].note)
                        callback(true)
                    end,
                }
            end)
            if expired then
                local begin = device.bridge.backgroundBegin
                stub(device.bridge, "backgroundBegin", function()
                    local handle = begin()
                    device.bridge.expireBackground(handle)
                    return handle
                end)
            end
            changePosition()
            lifecycle("WILL_ENTER_BACKGROUND")
            assert.are.equal(expired and 0 or 1, uploads)
        end)
    end

    it("releases rebuildable cache files without touching persisted notes or books", function()
        changePosition()
        lifecycle("WILL_ENTER_BACKGROUND")
        local cache = require("document/doccache")
        local cached_file = cache.cache_path .. "ios-lifecycle-spec-cache"
        assert(require("util").writeToFile("rebuildable", cached_file))
        cache:refreshSnapshot()
        lifecycle("LOW_MEMORY")
        assert.is_nil(require("libs/libkoreader-lfs").attributes(cached_file))
        assert.is_truthy(require("libs/libkoreader-lfs").attributes(sample))
        assert.are.equal("remember", require("docsettings"):open(sample):readSetting("annotations")[1].note)
    end)
end)
