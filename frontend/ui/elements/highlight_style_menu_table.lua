--[[--
Default style of new highlights, the 划线样式 row of the reorganized settings
(ui/elements/eink_settings_order.lua): line, marker or wave, as one choice. It is
upstream's global highlight_drawing_style; until it is saved, new highlights are
lines (doc/adr/0006-straight-line-default-highlight.md). Existing highlights keep
their own style.

A default saved in another style from the original menu (strikethrough, invert)
is listed too, checked, so that it shows as the row's value.
]]

local Event = require("ui/event")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderHighlightBubble = require("apps/reader/modules/readerhighlightbubble")
local ReaderUI = require("apps/reader/readerui")
local C_ = require("gettext").pgettext

local styles = {}
for _, style in ipairs(ReaderHighlightBubble.STYLES) do
    table.insert(styles, style)
end
local default = ReaderHighlightBubble.getDefaultDrawer()
local listed = false
for _, style in ipairs(styles) do
    if style[2] == default then listed = true end
end
if not listed then
    for _, style in ipairs(ReaderHighlight.getHighlightStyles()) do
        if style[2] == default then table.insert(styles, style) end
    end
end

local sub_item_table = {}
for _, style in ipairs(styles) do
    local label, drawer = style[1], style[2]
    table.insert(sub_item_table, {
        text = label,
        radio = true,
        checked_func = function()
            return ReaderHighlightBubble.getDefaultDrawer() == drawer
        end,
        callback = function()
            G_reader_settings:saveSetting("highlight_drawing_style", drawer)
            if ReaderUI.instance then -- for the open book's next highlight
                ReaderUI.instance:handleEvent(Event:new("DefaultHighlightStyleChanged"))
            end
        end,
    })
end

return {
    text = C_("Settings", "Highlight style"),
    sub_item_table = sub_item_table,
}
