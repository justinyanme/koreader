--[[--
iOS static-link shim, run by the launcher before reader.lua.

koreader-base is linked statically into the app executable on iOS, so there
are no bundled libraries to load: `ffi.load` of one (a `libs/` path, or the
`lib*.dylib` names ffi/loadlib.lua builds) gets `ffi.C`, and so does
"pthread" (KOPT's background reflow), which iOS only has inside libSystem;
anything else still goes to `ffi.load`, so a missing system library fails
loudly. The launcher
registers the Lua C modules in `package.preload`; resolving `libs/` modules
from the executable is only a fallback.
--]]

local ffi = require("ffi")

local executable = os.getenv("KO_IOS_EXECUTABLE")

local ffi_load = ffi.load
ffi.load = function(lib, global)
    if lib:sub(1, 5) == "libs/" or lib:match("^lib.*%.dylib$") or lib == "pthread" then
        return ffi.C
    end
    return ffi_load(lib, global)
end

local package_loadlib = package.loadlib
package.loadlib = function(path, funcname)
    if path:sub(1, 5) == "libs/" then
        path = executable
    end
    return package_loadlib(path, funcname)
end
