-- What is left of the old contents drawer: the helpers other pages share (its bookmarks and notes are on the
-- notes page now, see readernotespage_spec).
describe("ReaderTocDrawer module", function()
    local TocDrawer

    setup(function()
        require("commonrequire")
        TocDrawer = require("apps/reader/modules/readertocdrawer")
    end)

    describe("paginate", function()
        it("should never end a page with a group header", function()
            local items = {
                { h = 10, is_header = true }, { h = 50 }, { h = 50 }, { h = 10, is_header = true }, { h = 50 },
            }
            assert.are.same({ { 1, 2 }, { 3 }, { 4, 5 } }, TocDrawer.paginate(items, 70))
        end)

        it("should give a row taller than the list a page of its own", function()
            assert.are.same({ { 1 }, { 2 }, { 3 } }, TocDrawer.paginate({ { h = 30 }, { h = 90 }, { h = 30 } }, 70))
        end)
    end)

    describe("swatch", function()
        it("should draw a distinct swatch for each stored highlight style", function()
            local Blitbuffer = require("ffi/blitbuffer")
            local signatures = {}
            for _, drawer in ipairs{ "lighten", "underscore", "strikeout", "invert", "wave" } do
                local swatch = TocDrawer.Swatch:new{ drawer = drawer }
                local w, h = swatch.dimen.w, swatch.dimen.h
                local bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
                bb:fill(Blitbuffer.COLOR_WHITE)
                swatch:paintTo(bb, 0, 0)
                local sig = {}
                for y = 0, h - 1 do
                    for x = 0, w - 1 do
                        sig[#sig + 1] = bb:getPixel(x, y):getColor8().a
                    end
                end
                bb:free()
                sig = table.concat(sig, ",")
                assert.is_nil(signatures[sig], drawer)
                signatures[sig] = drawer
            end
        end)
    end)
end)
