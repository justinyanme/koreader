--[[--
Groups of the reorganized settings (apps/settings/einksettings.lua), next to the
original menus' reader_menu_order.lua and filemanager_menu_order.lua. A group's `text`
is its header. The reading preferences come first without one, as in WeChat Read
(13-reading-preferences/02-settings.png): the rows of a group without a header are two
lines tall.

Each row is backed by items of the original menus, by id:
    id      row id, the target of the "ShowEinkSettings" event (as are group ids)
    items   original menu item ids; one item opens its own entries, several are listed together
    file    an element table the original menu embeds without an id (instead of items)
    build   function(ui) returning a menu item of the new settings' own (instead of items); `ui` is the reader or
            the file manager the settings show over
    open    function(settings) showing a page of the new settings' own over them (instead of items)
    toggle  the single item is a checkbox, shown as a toggle on the row
    subtitle the second line of a row of the preferences; without one, they show the row's value there
    choice  the entries up to the first separator are one single choice, shown with a check mark
    value   function(item) returning the row's current value; by default the "Name: value" text or checked radio entry
            (no item with `open`)
    preview "tap_zones": the reader can draw its tap zones from the row's page
    events  { [item id] = { event = name, text = label } }: that item's entry, labelled `text`, sends the event
            to the UI instead of running its callback
Items missing in the current context (reader-only items in the file browser) leave their row dimmed.
Everything else stays reachable through the last row, the original menu.
]]

local Device = require("device")
local _ = require("gettext")
local C_ = _.pgettext

return {
    { id = "preferences", rows = {
        { id = "left_tap_forward", text = _("Tap left side for next page"), toggle = true,
          subtitle = _("When on, taps on the left side also turn to the next page"),
          build = function() return require("apps/reader/modules/readertoolbar").genLeftTapForwardMenuItem() end },
        { id = "first_line_indent", text = _("Indent first lines of body text"), toggle = true,
          subtitle = _("When on, the body text of books is indented on first lines"),
          build = function(ui) return require("apps/reader/modules/readertypesetpanel").genGlobalIndentMenuItem(ui) end },
        { id = "show_time", text = _("Show time while reading"), toggle = true,
          subtitle = _("When on, the current system time shows while reading"),
          build = function(ui) return require("apps/reader/modules/readertoolbar").genTimeMenuItem(ui) end },
        { id = "ui_font_size", text = _("Interface font size"),
          open = function() require("apps/settings/uifontsize").show() end,
          value = function() return require("apps/settings/uifontsize").currentName() end },
        { id = "cache_cleanup", text = _("Clear cache"),
          open = function(settings) settings:confirmCacheCleanup() end,
          value = function(settings) return settings:cacheSize() end },
    } },
    { id = "reading", text = C_("Settings group", "Reading"), rows = {
        { id = "tap_zones", text = _("Page turns and tap zones"), items = { "page_turns" }, preview = "tap_zones" },
        { id = "full_refresh", text = C_("Settings", "Full refresh rate"), choice = true,
          file = Device:hasEinkScreen() and "frontend/ui/elements/refresh_menu_table.lua" or nil },
        { id = "footer", text = C_("Settings", "Status bar"), items = { "status_bar" } },
        { id = "end_action", text = _("After finishing a book"), items = { "document_end_action" } },
        { id = "highlight_style", text = C_("Settings", "Highlight style"), choice = true,
          build = function() return require("apps/reader/modules/readerhighlightbubble").genDefaultStyleMenuItem() end },
    } },
    { id = "screen", text = C_("Settings group", "Screen"), rows = {
        { id = "refresh", text = _("Refresh and ghosting"), items = { "screen_eink_opt" } },
        { id = "sleep_screen", text = C_("Settings", "Sleep screen"), items = { "screensaver" } },
        { id = "night_mode", text = _("Night mode"), items = { "night_mode" }, toggle = true },
    } },
    { id = "network", text = C_("Settings group", "Network & sync"), rows = {
        { id = "wifi", text = _("Wi-Fi"), items = { "network" },
          value = function() return require("ui/network/manager"):isWifiOn() and _("On") or _("Off") end },
        { id = "progress_sync", text = C_("Settings", "Progress sync"), items = { "progress_sync" } },
        { id = "transfer", text = _("Wireless transfer and library"), items = { "calibre", "opds", "cloudstorage" },
          -- the 书源 page; the original menu keeps the original browser and its label
          events = { opds = { event = "ShowOPDSCatalog", text = _("Book sources (OPDS)") } } },
    } },
    { id = "device", text = C_("Settings group", "Device"), rows = {
        { id = "buttons", text = _("Physical buttons"), items = { "navigation" } },
        { id = "gestures", text = _("Gestures"), items = { "taps_and_gestures" } },
        { id = "power", text = _("Power and sleep"), items = {
            "autosuspend", "autoshutdown", "autostandby", "ignore_sleepcover", "ignore_open_sleepcover",
            "cover_events", "pageturn_power", "charging_led", "ignore_battery_optimizations",
        } },
    } },
    { id = "shelf", text = _("Shelf"), rows = {
        { id = "shelf_sort", text = _("Sort by"), choice = true,
          build = function() return require("apps/shelf/shelfview").sortMenuItem() end },
    } },
    { id = "advanced", text = C_("Settings group", "Advanced"), rows = {
        { id = "plugins", text = _("Plugins"), items = { "plugin_management" } },
        { id = "original", text = _("All settings (original)"), original = true },
    } },
}
