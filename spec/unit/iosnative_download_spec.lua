-- device/sdl/iosnative/download: the download bridge's FFI adapter, against a stand-in for its Swift C functions.
describe("iOS download bridge adapter", function()
    local download, started

    setup(function()
        require("commonrequire")
        require("ffi/posix_h")
        local ffi = package.loaded.ffi
        -- what the adapter sees as ffi: its cdef is a no-op and ffi.C has the bridge's start function
        package.loaded.ffi = setmetatable({
            cdef = function() end,
            C = { ko_ios_download_start = function(url, headers, path, timeout)
                started = { url = url, headers = headers, path = path, timeout = timeout }
                return 7
            end },
        }, { __index = ffi })
        package.loaded["device/sdl/iosnative/download"] = nil
        download = require("device/sdl/iosnative/download")
        package.loaded.ffi = ffi
        package.loaded["device/sdl/iosnative/download"] = nil
    end)

    it("sends one line per header, so a line break in a value cannot add a header", function()
        local handle = download.downloadStart{ url = "https://nas.example/book", path = "/tmp/b.part", timeout = 15,
            headers = { ["CF-Access-Client-Secret"] = "token\r\nX-Injected: 1", Accept = "*/*" } }
        assert.are.equal(7, handle)
        assert.are.equal("https://nas.example/book", started.url)
        assert.are.equal(15, started.timeout)
        local lines = {}
        for line in started.headers:gmatch("([^\n]*)\n") do table.insert(lines, line) end
        table.sort(lines)
        assert.are.same({ "Accept: */*", "CF-Access-Client-Secret: token  X-Injected: 1" }, lines)
        assert.is_nil(started.headers:find("\r", 1, true))
    end)
end)
