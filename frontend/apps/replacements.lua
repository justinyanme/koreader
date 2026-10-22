--[[--
Hook points for the e-ink redesign (see doc/adr/0001-new-modules-with-hook-points.md).

Each slot holds a class used instead of the original one. Replacements are
expected to `:extend{}` the original, so that menu registration, plugins and
the original menu (reachable through the "ShowOriginalMenu" event) keep working.
An empty slot means upstream behavior.

@usage
    local Replacements = require("apps/replacements")
    Replacements.reader_menu = ReaderMenu:extend{ ... }
]]

return {
    reader_menu = nil, -- instead of ReaderMenu
    reader_config = nil, -- instead of ReaderConfig, which owns ConfigDialog
    reader_highlight = nil, -- instead of ReaderHighlight, which owns the selection and highlight dialogs
    filemanager = nil, -- instead of FileManager, whose setupLayout() builds the home screen
}
