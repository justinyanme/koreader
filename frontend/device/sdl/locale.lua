-- System language selection before gettext (and therefore Device) can be loaded.
-- Q32 uses SDL's locale API directly, not the native bridge.
local ffi = require("ffi")
local ffiUtil = require("ffi/util")

local Locale = {}

local regional_defaults = {
    af = "af_ZA", bg = "bg_BG", it = "it_IT", ko = "ko_KR", lt = "lt_LT",
    lv = "lv", nb = "nb_NO", nl = "nl_NL", pt = "pt_PT",
}

local function catalogExists(language)
    local file = io.open("l10n/" .. language .. "/koreader.mo", "rb")
    if not file then return false end
    file:close()
    return true
end

local function catalogFor(language, country)
    local tag = language:lower():gsub("_", "-")
    local base = tag:match("^([a-z]+)")
    if not base then return end
    local region = (country or tag:match("%-([a-z][a-z])$") or ""):upper()
    if base == "zh" then
        local traditional = tag:find("hant", 1, true)
            or (not tag:find("hans", 1, true) and (region == "TW" or region == "HK" or region == "MO"))
        local catalog = traditional and "zh_TW" or "zh_CN"
        return catalogExists(catalog) and catalog or nil
    elseif base == "en" then
        return region == "GB" and catalogExists("en_GB") and "en_GB" or "C"
    end
    local candidates = { base .. "_" .. region, base, regional_defaults[base] }
    for _, candidate in ipairs(candidates) do
        if catalogExists(candidate) then return candidate end
    end
end

function Locale.resolveLanguage()
    local SDL = ffiUtil.loadSDL3()
    if not SDL then return end
    require("ffi/SDL3_h")
    if ffi.string(SDL.SDL_GetPlatform()) ~= "iOS" then return end

    -- Keep these local to the device layer until base declares SDL's locale API.
    -- Separate declarations allow either one to have been declared already.
    pcall(ffi.cdef, [[
        typedef struct SDL_Locale {
            const char *language;
            const char *country;
        } SDL_Locale;
    ]])
    pcall(ffi.cdef, [[SDL_Locale **SDL_GetPreferredLocales(int *count);]])
    local count = ffi.new("int[1]")
    local ok, locales = pcall(function() return SDL.SDL_GetPreferredLocales(count) end)
    if not ok or locales == nil then return "C" end
    locales = ffi.gc(locales, SDL.SDL_free)
    local selected
    for i = 0, count[0] - 1 do
        local locale = locales[i]
        if locale ~= nil and locale.language ~= nil then
            selected = catalogFor(ffi.string(locale.language),
                locale.country ~= nil and ffi.string(locale.country) or nil)
            if selected then break end
        end
    end
    ffi.gc(locales, nil)
    SDL.SDL_free(locales)
    return selected or "C"
end

return Locale
