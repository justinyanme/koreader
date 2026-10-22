describe("Font module", function()
    local Font
    setup(function()
        require("commonrequire")
        Font = require("ui/font")
    end)
    it("should get face", function()
        local f
        f = Font:getFace('cfont', 18)
        assert.are_not.equals(f.ftsize, nil)
        f = Font:getFace('tfont', 16)
        assert.are_not.equals(f.ftsize, nil)
        f = Font:getFace('hfont', 12)
        assert.are_not.equals(f.ftsize, nil)
    end)
    it("should resolve the redesign type scale by role name", function()
        local Screen = require("device").screen
        local roles = {
            ui_micro = { 11 }, ui_caption = { 12 }, ui_label = { 13 }, ui_label_large = { 14 },
            ui_body = { 15 }, ui_title = { 16, true }, ui_title_large = { 17, true },
            ui_headline = { 22, true }, ui_excerpt = { 15 }, ui_headword = { 26, true },
        }
        for role, spec in pairs(roles) do
            local f = Font:getFace(role)
            assert.are_not.equals(f.ftsize, nil)
            assert.are.equals(spec[1], f.orig_size)
            assert.are.equals(Screen:scaleBySize(spec[1]), f.size)
            assert.are.equals(spec[2] == true, f.is_real_bold == true)
        end
    end)
end)
