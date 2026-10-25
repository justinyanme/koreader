import Foundation

// SDL_RunApp hands the process to UIKit with SDL's own app and scene delegates, and calls back on
// the main thread once the app has launched. reader.lua ends the process with os.exit.
exit(SDL_RunApp(CommandLine.argc, CommandLine.unsafeArgv, { _, _ in koreaderMain() }, nil))

/// Sets up the environment and runs reader.lua in the app's only Lua state, with the launch
/// arguments as its `arg` (`xcrun simctl launch <device> me.justinyan.justreader <book>`).
nonisolated func koreaderMain() -> Int32 {
    guard let resources = Bundle.main.resourcePath, let executable = Bundle.main.executablePath else {
        print("[JustReader] no bundle paths")
        return EXIT_FAILURE
    }
    // Settings and notes until B3 (#91) moves to the Q10 layout.
    let home = URL.applicationSupportDirectory.appending(path: "koreader")
    do {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    } catch {
        print("[JustReader] cannot create \(home.path): \(error)")
        return EXIT_FAILURE
    }
    let environment = [
        "KO_HOME": home.path,
        // ios-shim.lua resolves Lua C modules from the executable.
        "KO_IOS_EXECUTABLE": executable,
        // Set so ffi/loadlib.lua doesn't io.popen("brew --prefix").
        "KO_DYLD_PREFIX": resources,
        "LC_ALL": "en_US.UTF-8",
        // ffi/SDL3.lua sizes the window to the display.
        "SDL_FULLSCREEN": "1",
        // Finger events only: SDL's synthesized mouse events would register every tap twice.
        "SDL_TOUCH_MOUSE_EVENTS": "0",
    ]
    for (name, value) in environment {
        setenv(name, value, 1)
    }
    let root = resources + "/koreader"
    guard chdir(root) == 0 else {
        print("[JustReader] chdir(\(root)) failed")
        return EXIT_FAILURE
    }

    guard let L = luaL_newstate() else {
        print("[JustReader] luaL_newstate failed")
        return EXIT_FAILURE
    }
    defer { lua_close(L) }
    luaL_openlibs(L)
    let arguments = CommandLine.arguments.dropFirst()
    lua_createtable(L, Int32(arguments.count), 0)
    for (index, argument) in arguments.enumerated() {
        lua_pushstring(L, argument)
        lua_rawseti(L, -2, Int32(index + 1))
    }
    lua_setfield(L, LUA_GLOBALSINDEX, "arg")
    preloadModules(L)
    for script in ["ios-shim.lua", "reader.lua"] {
        guard luaL_loadfilex(L, script, nil) == 0, lua_pcall(L, 0, 0, 0) == 0 else {
            print("[JustReader] \(script): \(String(cString: lua_tolstring(L, -1, nil)))")
            return EXIT_FAILURE
        }
    }
    return EXIT_SUCCESS
}

/// Registers the Lua C modules linked into the executable under the names ffi/loadlib.lua's
/// monolibtic loader asks for, so require() finds them without loading a library.
nonisolated func preloadModules(_ L: OpaquePointer) {
    let modules: [(String, lua_CFunction)] = [
        ("libs/libkoreader-cre", luaopen_cre),
        ("libs/libkoreader-djvu", luaopen_djvu),
        ("libs/libkoreader-lfs", luaopen_lfs),
        ("libs/libkoreader-nnsvg", luaopen_nnsvg),
        ("libs/libkoreader-xtext", luaopen_xtext),
        ("lpeg", luaopen_lpeg),
        ("mime.mcore", luaopen_mime_mcore),
        ("rapidjson", luaopen_rapidjson),
        ("socket.score", luaopen_socket_score),
        ("ssl.config", luaopen_ssl_config),
        ("ssl.context", luaopen_ssl_context),
        ("ssl.core", luaopen_ssl_core),
        ("ssl.x509", luaopen_ssl_x509),
    ]
    lua_getfield(L, LUA_GLOBALSINDEX, "package")
    lua_getfield(L, -1, "preload")
    for (name, open) in modules {
        lua_pushcclosure(L, open, 0)
        lua_setfield(L, -2, name)
    }
    lua_settop(L, -3)
}
