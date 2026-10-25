// C APIs the Swift launcher calls: SDL3 and LuaJIT, both linked statically from koreader-base.
#include <SDL3/SDL.h>
// main.swift is the entry point; SDL_main.h only declares SDL_RunApp.
#define SDL_MAIN_HANDLED
#include <SDL3/SDL_main.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

// Lua C modules linked into the executable; main.swift registers them in package.preload.
int luaopen_cre(lua_State *L);
int luaopen_djvu(lua_State *L);
int luaopen_lfs(lua_State *L);
int luaopen_lpeg(lua_State *L);
int luaopen_mime_mcore(lua_State *L);
int luaopen_nnsvg(lua_State *L);
int luaopen_rapidjson(lua_State *L);
int luaopen_socket_score(lua_State *L);
int luaopen_ssl_config(lua_State *L);
int luaopen_ssl_context(lua_State *L);
int luaopen_ssl_core(lua_State *L);
int luaopen_ssl_x509(lua_State *L);
int luaopen_xtext(lua_State *L);
