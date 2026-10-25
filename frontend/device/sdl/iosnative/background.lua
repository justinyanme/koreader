local ffi = require("ffi")

ffi.cdef[[
int64_t ko_ios_background_begin(void);
void ko_ios_background_end(int64_t handle);
bool ko_ios_background_expired(int64_t handle);
bool ko_ios_background_save_incomplete(void);
void ko_ios_background_set_save_incomplete(bool incomplete);
]]

return {
    backgroundBegin = function()
        local handle = tonumber(ffi.C.ko_ios_background_begin())
        if handle == 0 then return nil, "background time unavailable" end
        return handle
    end,
    backgroundEnd = function(handle)
        ffi.C.ko_ios_background_end(handle or 0)
        return true
    end,
    backgroundExpired = function(handle)
        return ffi.C.ko_ios_background_expired(handle or 0)
    end,
    backgroundSaveIncomplete = function()
        return ffi.C.ko_ios_background_save_incomplete()
    end,
    backgroundSetSaveIncomplete = function(value)
        ffi.C.ko_ios_background_set_save_incomplete(value)
        return true
    end,
}
