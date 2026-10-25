-- Both functions are in libSystem, resolved by dyld (not in ffi-symbols.txt).
-- os_proc_available_memory returns 0 when the process has no jetsam limit (the
-- simulator); fall back to the physical memory there.
local ffi = require("ffi")
local logger = require("logger")

ffi.cdef[[
size_t os_proc_available_memory(void);
int sysctlbyname(const char *, void *, size_t *, void *, size_t);
]]

-- Logged once: the first call sizes DocCache, later ones (ImageWidget) come often.
local logged = false
local function log(bytes, source)
    if logged then return end
    logged = true
    logger.info("memoryAvailable:", bytes, "bytes (" .. source .. ")")
end

return {
    memoryAvailable = function()
        local available = tonumber(ffi.C.os_proc_available_memory())
        if available > 0 then
            log(available, "os_proc_available_memory")
            return available
        end
        local memsize = ffi.new("uint64_t[1]")
        local len = ffi.new("size_t[1]", ffi.sizeof("uint64_t"))
        if ffi.C.sysctlbyname("hw.memsize", memsize, len, nil, 0) ~= 0 then
            return nil, "sysctlbyname hw.memsize failed: " .. ffi.errno()
        end
        log(tonumber(memsize[0]), "hw.memsize, no process memory limit")
        return tonumber(memsize[0])
    end,
}
