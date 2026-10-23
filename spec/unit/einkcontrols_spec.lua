describe("EinkControls.Glyph", function()
    local Blitbuffer, EinkControls, Palette

    setup(function()
        require("commonrequire")
        Blitbuffer = require("ffi/blitbuffer")
        EinkControls = require("ui/widget/einkcontrols")
        Palette = require("ui/palette")
    end)

    -- Paints a 48px chevron on a buffer filled with `ground`: the darkest gray painted, and the gray of its top-left
    -- corner, which the chevron leaves bare.
    local function paint(enabled, ground)
        local glyph = EinkControls.Glyph:new{ icon = "eink/chev.up", width = 48, height = 48, alpha = true, enabled = enabled }
        local size = glyph:getSize()
        local bb = Blitbuffer.new(size.w, size.h, Blitbuffer.TYPE_BB8)
        bb:fill(ground)
        glyph:paintTo(bb, 0, 0)
        local darkest = 0xFF
        for y = 0, size.h - 1 do
            for x = 0, size.w - 1 do
                darkest = math.min(darkest, bb:getPixel(x, y):getColor8().a)
            end
        end
        local corner = bb:getPixel(0, 0):getColor8().a
        bb:free()
        glyph:free()
        return darkest, corner
    end

    it("draws a disabled icon's ink in rule gray, on paper as on a gray ground, which it leaves as it was", function()
        local rule, mark = Palette.rule:getColor8().a, Palette.mark:getColor8().a
        assert.are.same({ rule, 0xFF }, { paint(false, Palette.paper) })
        assert.are.same({ rule, mark }, { paint(false, Palette.mark) })
    end)

    it("draws an enabled icon in ink", function()
        assert.are.same({ 0, Palette.mark:getColor8().a }, { paint(true, Palette.mark) })
    end)
end)
