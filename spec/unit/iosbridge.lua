-- Lua implementation of device/sdl/iosbridge's contract. Inject only through seam C.
-- options.responses[url] is a sequence of download snapshots, advanced by polls.
-- The fake writes no files: consumers needing file contents can supply fixtures at path.
local FakeBridge = {}

function FakeBridge.new(options)
    options = options or {}
    local util = require("util")
    local jobs, tasks = {}, {}
    local next_job, next_task = 0, 0
    local brightness = options.brightness or 50
    local incomplete = false
    local bridge = {}

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

    function bridge.backgroundBegin()
        if options.background_unavailable then return nil, "unavailable" end
        next_task = next_task + 1
        tasks[next_task] = { expired = false }
        return next_task
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

    function bridge.brightnessGet() return brightness end
    function bridge.brightnessSet(value)
        brightness = math.max(0, math.min(100, value))
        return true
    end

    -- Native-side expiry stimulus for lifecycle scenarios, never a callback into Lua.
    function bridge.expireBackground(handle)
        if tasks[handle] then
            tasks[handle].expired = true
            tasks[handle].ended = true
        end
    end

    return bridge
end

return FakeBridge
