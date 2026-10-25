describe("iOS Keychain adapter", function()
    local adapter, status, bytes, freed
    setup(function()
        require("commonrequire")
        require("ffi/posix_h")
        local ffi = package.loaded.ffi
        package.loaded.ffi = setmetatable({
            cdef = function() end,
            C = {
                ko_ios_keychain_get = function(_, output, length)
                    if status ~= 0 then return status end
                    output[0], length[0] = ffi.cast("uint8_t *", bytes), #bytes
                    return 0
                end,
                ko_ios_keychain_set = function(_, value, length)
                    bytes = ffi.string(value, length)
                    return status
                end,
                ko_ios_keychain_delete = function() return status end,
                free = function() freed = true end,
            },
        }, { __index = ffi })
        adapter = require("device/sdl/iosnative/keychain")
        package.loaded.ffi = ffi
        package.loaded["device/sdl/iosnative/keychain"] = nil
    end)
    before_each(function() status, bytes, freed = 0, "", false end)
    it("round trips empty, Unicode and embedded NUL bytes", function()
        for _, value in ipairs{ "", "密碼\000token" } do
            assert.is_true(adapter.keychainSet("opaque-ref", value))
            assert.are.equal(value, adapter.keychainGet("opaque-ref"))
            assert.is_true(freed)
        end
    end)
    it("distinguishes missing entries from inaccessible storage", function()
        status = -25300
        local value, err = adapter.keychainGet("ref")
        assert.is_nil(value)
        assert.are.equal("not_found", err)
        assert.is_true(adapter.keychainDelete("ref"))
        status = -25308
        value, err = adapter.keychainGet("ref")
        assert.is_nil(value)
        assert.are.equal("-25308", err)
        local ok
        ok, err = adapter.keychainSet("ref", "canary-secret")
        assert.is_nil(ok)
        assert.are.equal("-25308", err)
    end)
end)
