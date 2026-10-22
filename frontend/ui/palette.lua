--[[--
Color tokens of the e-ink redesign (see DESIGN.md, Colors).

Every token is one of Blitbuffer's 16 gray steps; there are no other colors.
The prototype's off-white paper and off-black ink simulate the panel, so they
map to plain white and black here. The marker highlight sits one step darker
than the row divider so the two stay distinguishable on device, and matches
the output of the default lighten highlight (darkenRect with factor 0.2).

@usage
    local Palette = require("ui/palette")
    local line = LineWidget:new{ background = Palette.rule, ... }
]]

local Blitbuffer = require("ffi/blitbuffer")

return {
    paper = Blitbuffer.COLOR_WHITE,
    ink = Blitbuffer.COLOR_BLACK,
    ink_2 = Blitbuffer.COLOR_GRAY_5, -- secondary text
    ink_3 = Blitbuffer.COLOR_GRAY_9, -- disabled, chevrons, fine print
    rule = Blitbuffer.COLOR_GRAY_D, -- row dividers, disabled outlines
    mark = Blitbuffer.COLOR_LIGHT_GRAY, -- marker highlight fill
    bubble_rule = Blitbuffer.COLOR_GRAY_4, -- dividers inside the black selection bubble
    marker_on_ink = Blitbuffer.COLOR_DARK_GRAY, -- marker swatch on the black bubble
    -- typographic covers only
    cover_stock = Blitbuffer.COLOR_GRAY_D,
    cover_tint = Blitbuffer.COLOR_GRAY_B,
    cover_gray = Blitbuffer.COLOR_DARK_GRAY,
}
