-- Lua implementation of device/sdl/iosbridge's contract. Inject only through seam C.
-- options.responses[url] is a sequence of download snapshots, advanced by polls.
-- The fake writes no files: consumers needing contents can copy fixtures to the temporary path.
local FakeBridge = {}

function FakeBridge.new(options)
    options = options or {}
    local util = require("util")
    local jobs, tasks = {}, {}
    local next_job, next_task = 0, 0
    local brightness = options.brightness or 50
    local incomplete = false
    local keyboard_connected = options.keyboard_connected == true
    local share
    local bridge = { opened = {}, shared = {} }

    function bridge.keyboardConnected() return keyboard_connected end
    -- Native-side hotplug stimulus, observed on the next input wait (no callback).
    function bridge.setKeyboardConnected(connected) keyboard_connected = connected end

    function bridge.downloadStart(request)
        next_job = next_job + 1
        jobs[next_job] = {
            request = util.tableDeepCopy(request),
            responses = util.tableDeepCopy((options.responses or {})[request.url]
                or { { state = "pending", received = 0 } }),
            index = 0,
        }
        return next_job
    end

    function bridge.downloadPoll(handle)
        local job = jobs[handle]
        if not job then return nil, "unknown download" end
        job.index = math.min(job.index + 1, #job.responses)
        local response = util.tableDeepCopy(job.responses[job.index])
        response.path = response.path or job.request.path
        return response
    end

    function bridge.downloadCancel(handle)
        local job = jobs[handle]
        if job then
            os.remove(job.request.path)
            jobs[handle] = nil
        end
        return true
    end

    local pending_task
    local function acquireBackground()
        if options.background_unavailable then return nil, "unavailable" end
        next_task = next_task + 1
        tasks[next_task] = { expired = false }
        return next_task
    end

    function bridge.backgroundBegin()
        if pending_task then
            local handle = pending_task
            pending_task = nil
            return handle
        end
        return acquireBackground()
    end

    -- Native watcher stimulus, including expiry before Lua claims the task.
    function bridge.watchBackground()
        if not pending_task then pending_task = acquireBackground() end
        return pending_task
    end

    function bridge.backgroundEnd(handle)
        if tasks[handle] then tasks[handle].ended = true end
        return true
    end

    function bridge.backgroundExpired(handle)
        return tasks[handle] ~= nil and tasks[handle].expired
    end

    function bridge.backgroundSaveIncomplete() return incomplete end
    function bridge.backgroundSetSaveIncomplete(value)
        incomplete = value
        return true
    end

    function bridge.safeAreaInsets()
        return util.tableDeepCopy(options.insets or { top = 0, right = 0, bottom = 0, left = 0 })
    end

    function bridge.memoryAvailable()
        if options.memory_available == nil then return nil, "unsupported" end
        return options.memory_available
    end

    function bridge.brightnessGet() return brightness end
    function bridge.brightnessSet(value)
        brightness = math.max(0, math.min(100, value))
        return true
    end

    -- options.picks is a sequence of picker sessions, each a sequence of snapshots advanced by polls.
    local picks, picking = util.tableDeepCopy(options.picks or {}), nil
    bridge.picker_requests = {}
    function bridge.pickFilesStart(request)
        if picking then return nil, "busy" end
        table.insert(bridge.picker_requests, util.tableDeepCopy(request))
        picking = { snapshots = table.remove(picks, 1) or { { state = "cancelled" } }, index = 0 }
        return true
    end
    function bridge.pickFilesPoll()
        if not picking then return { state = "idle" } end
        picking.index = math.min(picking.index + 1, #picking.snapshots)
        local snapshot = util.tableDeepCopy(picking.snapshots[picking.index])
        if snapshot.state ~= "pending" then picking = nil end
        return snapshot
    end

    function bridge.openURL(url)
        if options.open_url_error then return nil, options.open_url_error end
        table.insert(bridge.opened, url)
        return true
    end

    function bridge.shareStart(paths)
        if options.share_error then return nil, options.share_error end
        table.insert(bridge.shared, util.tableDeepCopy(paths))
        share = { handle = #bridge.shared, state = "presenting" }
        return share.handle
    end

    function bridge.sharePoll(handle)
        if not share or share.handle ~= handle then return nil, "unknown share" end
        return share.state
    end

    -- Native-side dismissal stimulus: "completed", "cancelled" or "failed".
    function bridge.finishShare(state)
        share.state = state
    end

    -- Native-side expiry stimulus for lifecycle scenarios, never a callback into Lua.
    function bridge.expireBackground(handle)
        if tasks[handle] then
            tasks[handle].expired = true
            tasks[handle].ended = true
            incomplete = true
        end
    end

    return bridge
end

return FakeBridge
