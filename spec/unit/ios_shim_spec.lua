describe("iOS static-link shim", function()
    local ffi = require("ffi")
    -- spec/front links to the repository's spec/, so its parent holds platform/.
    local shim_path = "spec/front/../platform/ios/ios-shim.lua"
    local orig_ffi_load, orig_loadlib, orig_getenv
    local ffi_load_calls, loadlib_calls

    before_each(function()
        orig_ffi_load, orig_loadlib, orig_getenv = ffi.load, package.loadlib, os.getenv
        ffi_load_calls, loadlib_calls = {}, {}
        ffi.load = function(lib, global)
            table.insert(ffi_load_calls, { lib, global })
            return "loaded " .. lib
        end
        package.loadlib = function(path, funcname)
            table.insert(loadlib_calls, { path, funcname })
            return "loader " .. funcname
        end
        os.getenv = function(name)
            if name == "KO_IOS_EXECUTABLE" then
                return "/app/JustReader.app/JustReader"
            end
            return orig_getenv(name)
        end
        dofile(shim_path)
    end)

    after_each(function()
        ffi.load, package.loadlib, os.getenv = orig_ffi_load, orig_loadlib, orig_getenv
    end)

    it("serves bundled libraries from the executable", function()
        assert.are.equal(ffi.C, ffi.load("libs/libkoreader-monolibtic.dylib"))
        assert.are.equal(ffi.C, ffi.load("libSDL3.0.dylib"))
        assert.are.same({}, ffi_load_calls)
    end)

    it("serves pthread from libSystem, which has no separate image on iOS", function()
        assert.are.equal(ffi.C, ffi.load("pthread"))
        assert.are.same({}, ffi_load_calls)
    end)

    it("still loads other libraries", function()
        assert.are.equal("loaded /usr/lib/libz.dylib", ffi.load("/usr/lib/libz.dylib", true))
        assert.are.equal("loaded inkview", ffi.load("inkview"))
        assert.are.same({ { "/usr/lib/libz.dylib", true }, { "inkview" } }, ffi_load_calls)
    end)

    it("resolves Lua C modules in libs/ from the executable", function()
        assert.are.equal("loader luaopen_cre", package.loadlib("libs/libkoreader-monolibtic.dylib", "luaopen_cre"))
        assert.are.same({ { "/app/JustReader.app/JustReader", "luaopen_cre" } }, loadlib_calls)
    end)

    it("leaves other package.loadlib paths alone", function()
        package.loadlib("common/socket/core.so", "luaopen_socket_core")
        assert.are.same({ { "common/socket/core.so", "luaopen_socket_core" } }, loadlib_calls)
    end)
end)
