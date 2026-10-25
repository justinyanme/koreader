--[[--
iOS static-link shim, run by the launcher before reader.lua.

koreader-base is linked statically into the app executable on iOS, so there
are no libraries to load: every `ffi.load` of a bundled library (by name or
under `libs/`) gets `ffi.C`, and Lua C modules that ffi/loadlib.lua looks up
in `libs/` resolve from the executable itself.
--]]

local ffi = require("ffi")

local executable = os.getenv("KO_IOS_EXECUTABLE")

local ffi_load = ffi.load
ffi.load = function(lib, global)
    if lib:sub(1, 1) == "/" then
        return ffi_load(lib, global)
    end
    return ffi.C
end

local package_loadlib = package.loadlib
package.loadlib = function(path, funcname)
    if path:sub(1, 5) == "libs/" then
        path = executable
    end
    return package_loadlib(path, funcname)
end
