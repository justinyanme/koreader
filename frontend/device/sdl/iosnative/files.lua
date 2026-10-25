-- The document picker's FFI adapter (B3): platform/ios/JustReader/Sources/FilePicker.swift.
local ffi = require("ffi")

ffi.cdef[[
int ko_ios_files_pick_start(const char *extensions);
const char *ko_ios_files_pick_poll(void);
]]

local C = ffi.C
local START_ERRORS = { [1] = "busy", [2] = "no window" }

local Files = {}

function Files.pickFilesStart(request)
    local rc = C.ko_ios_files_pick_start(table.concat(request.extensions or {}, "\n"))
    if rc ~= 0 then return nil, START_ERRORS[rc] or "failed" end
    return true
end

function Files.pickFilesPoll()
    local snapshot = { paths = {}, errors = {} }
    for line in ffi.string(C.ko_ios_files_pick_poll()):gmatch("[^\n]+") do
        local kind, rest = line:match("^(%a+)\t(.*)$")
        if kind == "state" then
            snapshot.state = rest
        elseif kind == "path" then
            table.insert(snapshot.paths, rest)
        elseif kind == "fail" then
            local name, reason = rest:match("^(.-)\t(.*)$")
            if name then snapshot.errors[name] = reason end
        elseif kind == "error" then
            snapshot.error = rest
        end
    end
    return snapshot
end

return Files
