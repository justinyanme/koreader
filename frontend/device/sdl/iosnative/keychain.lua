-- Byte-string C ABI, owned output freed here. No secrets enter errors or logs.
local ffi = require("ffi")
require("ffi/posix_h")
ffi.cdef[[
int32_t ko_ios_keychain_get(const char *key, uint8_t **output, size_t *length);
int32_t ko_ios_keychain_set(const char *key, const uint8_t *value, size_t length);
int32_t ko_ios_keychain_delete(const char *key);
]]

local C = ffi.C
local function result(status, deleting)
    status = tonumber(status)
    if status == 0 or deleting and status == -25300 then return true end
    return nil, status == -25300 and "not_found" or tostring(status)
end

return {
    keychainAvailable = true,
    keychainGet = function(key)
        local output, length = ffi.new("uint8_t *[1]"), ffi.new("size_t[1]")
        local ok, err = result(C.ko_ios_keychain_get(key, output, length))
        if not ok then return nil, err end
        local value = ffi.string(output[0], tonumber(length[0]))
        C.free(output[0])
        return value
    end,
    keychainSet = function(key, value)
        return result(C.ko_ios_keychain_set(key, value, #value))
    end,
    keychainDelete = function(key)
        return result(C.ko_ios_keychain_delete(key), true)
    end,
}
