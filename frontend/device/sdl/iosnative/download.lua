-- FFI adapter for the download bridge in device/sdl/iosbridge (Swift: Bridge/Download.swift).
local ffi = require("ffi")
require("ffi/posix_h") -- free

ffi.cdef[[
int64_t ko_ios_download_start(const char *url, const char *headers, const char *path, double timeout);
char *ko_ios_download_poll(int64_t handle);
bool ko_ios_download_cancel(int64_t handle);
]]

local C = ffi.C

return {
    downloadStart = function(request)
        local lines = {}
        for name, value in pairs(request.headers or {}) do
            -- one header per line: a pasted token with a line break must not add headers of its own
            table.insert(lines, (name:gsub("[\r\n]", " ")) .. ": " .. (tostring(value):gsub("[\r\n]", " ")) .. "\n")
        end
        local handle = C.ko_ios_download_start(request.url, table.concat(lines), request.path, request.timeout or 60)
        if handle <= 0 then return nil, "download not started" end
        return tonumber(handle)
    end,
    -- Download.swift answers "state\nreceived\ntotal\nstatus\nerror\n" then a "name: value\n" line per header.
    downloadPoll = function(handle)
        local cstr = C.ko_ios_download_poll(handle)
        if cstr == nil then return nil, "unknown download" end
        local str = ffi.string(cstr)
        C.free(cstr)
        local state, received, total, status, err, rest = str:match("^(%a*)\n(%-?%d*)\n(%-?%d*)\n(%d*)\n([^\n]*)\n(.*)$")
        if not state then return nil, "bad download state" end
        local headers = {}
        for name, value in rest:gmatch("([^:\n]+): ([^\n]*)\n") do headers[name] = value end
        total = tonumber(total)
        return {
            state = state,
            received = tonumber(received) or 0,
            total = total and total >= 0 and total or nil,
            status = tonumber(status) ~= 0 and tonumber(status) or nil,
            headers = headers,
            error = err ~= "" and err or nil,
        }
    end,
    downloadCancel = function(handle)
        C.ko_ios_download_cancel(handle)
        return true
    end,
}
