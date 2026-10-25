describe("Menu widget", function()
    local Menu
    setup(function()
        require("commonrequire")
        Menu = require("ui/widget/menu")
    end)

    it("keeps the existing shortcut default for non-iOS keyboards without a DPad", function()
        local Device = require("device")
        stub(Device, "hasKeyboard", function() return true end)
        stub(Device, "hasDPad", function() return false end)
        local ok, err = pcall(function()
            -- Android QWERTY and externalkeyboard's non-DPad keyboards keep
            -- Generic's default; only the iOS variant opts out.
            local StartupMenu = dofile("frontend/ui/widget/menu.lua")
            assert.is_true(StartupMenu.is_enable_shortcut)
        end)
        Device.hasDPad:revert()
        Device.hasKeyboard:revert()
        assert(ok, err)
    end)

    it("should convert item table from touch menu properly", function()
        local cb1 = function() end
        local cb2 = function() end
        local re = Menu.itemTableFromTouchMenu({
            navi = {
                icon = 'foo/bar.png',
                { text = 'foo', callback = cb1 },
                { text = 'bar', callback = cb2 },
            },
            exit = {
                icon = 'foo/bar2.png',
                callback = cb2
            },
        })
        --- @fixme: Currently broken because pairs (c.f., https://github.com/koreader/koreader/pull/6371#issuecomment-657251302)
        assert.are.same({
            {
                text = 'exit',
                callback = cb2,
            },
            {
                text = 'navi',
                sub_item_table = {
                    icon = 'foo/bar.png',
                    { text = 'foo', callback = cb1 },
                    { text = 'bar', callback = cb2 },
                }
            },
        }, re)
    end)
end)
