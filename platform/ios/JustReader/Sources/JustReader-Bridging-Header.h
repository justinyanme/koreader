// C APIs the Swift launcher calls: SDL3 and LuaJIT, both linked statically from koreader-base.
#include <SDL3/SDL.h>
// main.swift is the entry point; SDL_main.h only declares SDL_RunApp.
#define SDL_MAIN_HANDLED
#include <SDL3/SDL_main.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
