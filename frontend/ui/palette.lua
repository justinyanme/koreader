--[[--
Color tokens of the e-ink redesign (see DESIGN.md, Colors).

Every token is one of Blitbuffer's 16 gray steps; there are no other colors.
The prototype's off-white paper and off-black ink simulate the panel, so they
map to plain white and black here. The grays are read from the Leaf5
reference, each rounded to the nearest step: rules and disabled outlines
measure 187 (0xBB), the unpassed part of a track and resting tiles 205 (0xCC,
also the marker highlight, matching the default lighten highlight: darkenRect
with factor 0.2).

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
    rule = Blitbuffer.COLOR_GRAY_B, -- row dividers, bar and panel edges, disabled outlines and glyphs
    light_rule = Blitbuffer.COLOR_GRAY_D, -- a thought's detail rules, lighter in the reference (229, 07-selection-and-lookup/09)
    wash = Blitbuffer.COLOR_GRAY_D, -- where ink lands on the page washed behind a confirm layer
    mark = Blitbuffer.COLOR_LIGHT_GRAY, -- marker highlight fill, the unpassed part of a track
    hit = Blitbuffer.COLOR_GRAY_B, -- the search hit's fill, as measured in the reference (04-contents-and-search/06)
    tint = Blitbuffer.COLOR_GRAY_E, -- resting large choice cards (the 导入 routes, the paragraph cards)
    -- typographic covers only
    cover_stock = Blitbuffer.COLOR_GRAY_D,
    cover_tint = Blitbuffer.COLOR_GRAY_B,
    cover_gray = Blitbuffer.COLOR_DARK_GRAY,
}
