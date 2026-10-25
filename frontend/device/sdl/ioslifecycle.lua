-- All saving stays on the Lua main thread. UIKit only grants time and queues
-- SDL notifications; it never enters this module or the Lua VM from a callback.
local Event = require("ui/event")
local logger = require("logger")

local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new(device, uimgr)
    return setmetatable({ device = device, uimgr = uimgr }, Lifecycle)
end

-- Shared by the explicit reader save and the FlushSettings broadcast. Existing
-- handlers need not know about it; ReaderUI uses it to avoid duplicate writes.
local function saveContext(bridge, handle)
    local context = { readers = {}, optional = {}, complete = true }
    function context:recordFailure(err)
        self.complete = false
        logger.warn("iOS settings save:", err)
    end
    function context:required(action)
        local ok, result, err = pcall(action)
        if not ok or not result then
            self:recordFailure(ok and err or result)
            return nil, ok and err or result
        end
        return result
    end
    function context:defer(action)
        self.optional[#self.optional + 1] = action
    end
    function context:finish()
        if not self.complete then return end
        for _, action in ipairs(self.optional) do
            if bridge.backgroundExpired(handle) then
                self.complete = false
                break
            end
            local ok, result, err = pcall(action)
            if not ok or result == false or (result == nil and err) then
                self.complete = false
                logger.warn("iOS optional settings save:", ok and err or result)
            end
        end
    end
    return context
end

function Lifecycle:save(suspending)
    local bridge = self.device.bridge
    local handle = bridge.backgroundBegin() -- nil is allowed; still save.
    local context = saveContext(bridge, handle)
    bridge.backgroundSetSaveIncomplete(true)
    local ok, err = pcall(function()
        local reader = require("apps/reader/readerui").instance
        if reader and reader.document then
            -- Progress and notes come before global/plugin settings and exports.
            reader:saveSettings(context)
            context:defer(function()
                require("document/doccache"):serialize(reader.document.file)
            end)
        else
            context:required(function() return G_reader_settings:flush() end)
        end
        context:required(function()
            self.uimgr:flushSettings(context)
            return true
        end)
        if suspending then
            -- Timers pause after required local writes. Optional Suspend work
            -- (e.g. KOSync uploads) joins the same expiry-aware queue.
            self.uimgr:broadcastEvent(Event:new("Suspend", context))
        end
        context:finish()
    end)
    if not ok then
        context.complete = false
        logger.warn("iOS lifecycle save interrupted:", err)
    end
    -- A final check also covers expiry during the last optional operation.
    if bridge.backgroundExpired(handle) then context.complete = false end
    bridge.backgroundSetSaveIncomplete(not context.complete)
    bridge.backgroundEnd(handle) -- idempotent even when UIKit already expired it.
    if context.complete then self.dirty = nil end
    return context.complete
end

function Lifecycle:cancel(reader)
    if reader and self.pending_reader ~= reader then return end
    if self.pending then self.uimgr:unschedule(self.pending) end
    self.pending, self.pending_reader = nil, nil
end

function Lifecycle:changed(reader)
    self.dirty = true
    if self.inactive then return end
    if self.pending and self.pending_reader == reader then return end
    self:cancel()
    self.pending_reader = reader
    self.pending = function()
        self:cancel()
        if require("apps/reader/readerui").instance == reader and reader.document then
            self:save()
        end
    end
    -- A deadline from the FIRST change, rather than a debounce which continuous
    -- page turns could postpone forever. Normal main-loop scheduling is assumed.
    self.uimgr:scheduleIn(3, self.pending)
end

function Lifecycle:lowMemory()
    local cache = require("document/doccache")
    cache:clear()
    cache:clearDiskCache()
    -- Do not load caches just to clear them, nor free live widget bitmaps.
    for _, name in ipairs{ "ui/rendertext", "ui/widget/imagewidget" } do
        local module = package.loaded[name]
        if module then module.clearCache() end
    end
    collectgarbage("collect")
end

function Lifecycle:handle(code)
    local SDL = require("ffi/SDL3").SDL
    if code == SDL.SDL_EVENT_WILL_ENTER_BACKGROUND or code == SDL.SDL_EVENT_DID_ENTER_BACKGROUND then
        self:cancel()
        local suspending = not self.inactive
        self.inactive = true
        if suspending or self.dirty or self.device.bridge.backgroundSaveIncomplete() then
            -- RequestSuspend would enter SDLPowerD:beforeSuspend next tick,
            -- including input inhibition. Use synchronous saving/notifications.
            self:save(suspending)
        else
            -- didEnterBackground can arrive after the willResignActive save.
            -- Release any task acquired by the watcher for this duplicate too.
            local bridge = self.device.bridge
            bridge.backgroundEnd(bridge.backgroundBegin())
        end
    elseif code == SDL.SDL_EVENT_DID_ENTER_FOREGROUND then
        local was_inactive = self.inactive
        self.inactive = false
        if self.device.bridge.backgroundSaveIncomplete() or self.dirty then self:save() end
        -- SDL's scene/application notifications can describe the same transition.
        if was_inactive ~= false then
            if self.device.powerd then self.device.powerd:invalidateCapacityCache() end
            self.uimgr:broadcastEvent(Event:new("Resume"))
        end
        self.uimgr:setDirty("all", "full")
    elseif code == SDL.SDL_EVENT_LOW_MEMORY then
        self:lowMemory()
    elseif code == SDL.SDL_EVENT_TERMINATING then
        self:cancel()
        self:save() -- best effort; forced termination need not deliver this.
    elseif code ~= SDL.SDL_EVENT_WILL_ENTER_FOREGROUND then
        return false
    end
    return true
end

return Lifecycle
