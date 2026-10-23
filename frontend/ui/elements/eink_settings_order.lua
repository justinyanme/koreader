--[[--
Groups of the reorganized settings (apps/settings/einksettings.lua), next to the
original menus' reader_menu_order.lua and filemanager_menu_order.lua.

Each row is backed by items of the original menus, by id, or by an element table:
    id      row id, the target of the "ShowEinkSettings" event (as are group ids)
    items   original menu item ids; one item opens its own entries, several are listed together
    file    an element table (instead of items): one the original menu embeds without an id, or one of
            the redesign's own (highlight_style_menu_table.lua)
    toggle  the single item is a checkbox, shown as a toggle on the row
    choice  the entries up to the first separator are one single choice, shown with a check mark
    value   function(item) returning the row's current value; by default the "Name: value" text or checked radio entry
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
    { id = "reading", text = C_("Settings group", "Reading"), rows = {
        { id = "tap_zones", text = _("Page turns and tap zones"), items = { "page_turns" }, preview = "tap_zones" },
        { id = "full_refresh", text = C_("Settings", "Full refresh rate"), choice = true,
          file = Device:hasEinkScreen() and "frontend/ui/elements/refresh_menu_table.lua" or nil },
        { id = "footer", text = C_("Settings", "Status bar"), items = { "status_bar" } },
        { id = "end_action", text = _("After finishing a book"), items = { "document_end_action" } },
        { id = "highlight_style", text = C_("Settings", "Highlight style"), choice = true,
          file = "frontend/ui/elements/highlight_style_menu_table.lua" },
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
    { id = "advanced", text = C_("Settings group", "Advanced"), rows = {
        { id = "plugins", text = _("Plugins"), items = { "plugin_management" } },
        { id = "original", text = _("All settings (original)"), original = true },
    } },
}
