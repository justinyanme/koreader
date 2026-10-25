-- Seam B: the real shelf/FileManager entry and the shared controls it uses.
-- These cases use B0's point-equivalent offscreen ruler. Q46: written, not run.
describe("B0 narrow-screen rules", function()
    local Screen, Device, BB, Geom, FM, Replacements, Widgets, Controls, UIManager
    local original_bb, original_size, original_minimum, original_home

    setup(function()
        require("commonrequire")
        disable_plugins()
        Device = require("device")
        Screen = Device.screen
        BB = require("ffi/blitbuffer")
        Geom = require("ui/geometry")
        original_bb, original_size = Screen.bb, Screen.screen_size
        original_minimum = Device.minimum_touch_size
        original_home = G_reader_settings:readSetting("home_dir")
        stub(Screen, "scaleBySize", function(_, n) return math.ceil(n) end)
        stub(Screen, "scaleByDPI", function(_, n) return math.ceil(n) end)
        Replacements = require("apps/replacements")
        Replacements.filemanager = require("apps/shelf/shelffilemanager")
        Widgets = require("apps/shelf/shelfwidgets")
        Controls = require("ui/widget/einkcontrols")
        UIManager = require("ui/uimanager")
        FM = require("apps/filemanager/filemanager")
    end)

    local function size(w, h)
        if Screen.bb ~= original_bb then Screen.bb:free() end
        Screen.bb = BB.new(w, h, BB.TYPE_BBRGB32)
        Screen.screen_size = { w = w, h = h }
    end

    after_each(function()
        if FM.instance then FM.instance:onClose() end
        Device.minimum_touch_size = original_minimum
    end)

    teardown(function()
        if Screen.bb ~= original_bb then Screen.bb:free() end
        Screen.bb, Screen.screen_size = original_bb, original_size
        Screen.scaleBySize:revert()
        Screen.scaleByDPI:revert()
        Replacements.filemanager = nil
        G_reader_settings:saveSetting("home_dir", original_home)
    end)

    it("R1 gives the 390dp shelf two centered 123x178dp covers", function()
        size(390, 844)
        G_reader_settings:saveSetting("home_dir", "spec/front/unit/data")
        FM:showFiles("spec/front/unit/data")
        UIManager:forceRePaint()
        local grid = FM.instance.shelf_view.grid
        assert.are.equal(2, grid.cols)
        assert.are.equal(123, grid.cover_w)
        assert.are.equal(178, grid.cover_h)
        assert.are.equal(61, grid.gutter)
        assert.are.equal(22, grid.col_gap)
    end)

    it("R1 never lets the source row-fitting heuristic shrink narrow covers", function()
        size(390, 844)
        for _, height in ipairs{ 240, 340, 450, 620 } do
            local grid = Widgets.gridGeometry(390, height)
            assert.are.equal(2, grid.cols)
            assert.are.equal(123, grid.cover_w)
            assert.are.equal(164, grid.cover_h)
            assert.are.equal(62, grid.gutter)
            assert.are.equal(20, grid.col_gap)
        end
    end)

    it("keeps the existing iPad physical-width columns and natural font-grid layout", function()
        size(820, 1180)
        stub(Screen, "getDPI", function() return 160 end)
        local grid = Widgets.shelfGrid(820, 800)
        Screen.getDPI:revert()
        assert.are.equal(4, grid.cols) -- P1 remains an observation, not a new tablet layout.
        assert.are.equal(177, grid.cover_w)
    end)

    it("R2 steps once toward a distant tap only when adjacent stops overlap the 33dp knob", function()
        size(390, 844)
        for _, count in ipairs{ 10, 7, 9, 9 } do
            local changed, stepped
            local track = Controls.Track:new{ width = 346, count = count, position = 4,
                low = "小", high = "大", on_change = function(v) changed = v end,
                on_step = function(v) stepped = v end }
            track:paintTo(Screen.bb, 22, 100)
            track:onTapTrack(nil, { pos = Geom:new{ x = 22 + track:stopX(count), y = 120 } })
            assert.are.equal(1, stepped)
            assert.is_nil(changed)
            stepped = nil
            track:onTapTrack(nil, { pos = Geom:new{ x = 22 + track:stopX(1), y = 120 } })
            assert.are.equal(-1, stepped)
            track:free()
        end
        size(820, 1180)
        local changed
        local track = Controls.Track:new{ width = 776, count = 10, position = 4,
            on_change = function(v) changed = v end }
        track:paintTo(Screen.bb, 22, 100)
        track:onTapTrack(nil, { pos = Geom:new{ x = 22 + track:stopX(9), y = 120 } })
        assert.are.equal(9, changed)
        track:free()
    end)

    it("expands only iOS hit areas while preserving the 40dp pill drawing", function()
        size(390, 844)
        for _, minimum in ipairs{ 0, 44 } do
            Device.minimum_touch_size = minimum
            local pill = Controls.PillButton:new{ text = "Add source" }
            pill:paintTo(Screen.bb, 80, 100)
            assert.are.equal(40, pill:getSize().h)
            local hit = pill.ges_events.TapSelect[1]:match{
                ges = "tap", pos = Geom:new{ x = 90, y = 99 } }
            assert.are.equal(minimum == 44, hit)
            pill:free()
        end
    end)
end)
