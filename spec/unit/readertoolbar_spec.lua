describe("ReaderToolbar module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderToolbar, Replacements, UIManager, Event, Geom, Screen
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local sample_pdf = "spec/front/unit/data/sample.pdf"

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderToolbar = require("apps/reader/modules/readertoolbar")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Screen = require("device").screen
        Replacements.reader_menu = ReaderToolbar
    end)

    teardown(function()
        Replacements.reader_menu = nil
    end)

    local function openReader(file)
        DocSettings:open(file):purge()
        local ui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(file),
        }
        UIManager:show(ui)
        UIManager:forceRePaint()
        return ui
    end

    local function closeReader(ui)
        ui:closeDocument()
        UIManager:close(ui)
        ui:onClose()
    end

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function tap(x, y)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
    end

    local function tapWidget(widget)
        tap(widget.dimen.x + math.floor(widget.dimen.w / 2), widget.dimen.y + math.floor(widget.dimen.h / 2))
    end

    -- Runs fn, repaints, and returns the refreshes that were requested.
    local function refreshesOf(fn)
        local refreshes = {}
        local orig = UIManager._refresh
        UIManager._refresh = function(self, mode, region, dither)
            if mode then
                table.insert(refreshes, { mode = mode, region = region })
            end
            return orig(self, mode, region, dither)
        end
        local ok, err = pcall(function()
            fn()
            UIManager:forceRePaint()
        end)
        UIManager._refresh = orig
        assert(ok, err)
        return refreshes
    end

    local function find(widget, pred)
        if type(widget) ~= "table" then return end
        if pred(widget) then return widget end
        for _, child in ipairs(widget) do
            local found = find(child, pred)
            if found then return found end
        end
        for _, key in ipairs{ "frame", "content" } do
            local found = rawget(widget, key) and find(widget[key], pred)
            if found then return found end
        end
    end

    local function findText(widget, text)
        return find(widget, function(w)
            return w.text == text and w.dimen and w.callback
        end) or find(widget, function(w)
            return w.callback and w.dimen and find(w, function(c) return c.text == text end) ~= nil
        end)
    end

    describe("with an EPUB", function()
        local ui
        setup(function() ui = openReader(sample_epub) end)
        teardown(function() closeReader(ui) end)

        it("should show the toolbar on a center tap with only two ui refreshes", function()
            local refreshes = refreshesOf(function()
                tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            end)
            local bars = ui.menu.bars
            assert.is_truthy(bars)
            assert.are.equal(bars, topWidget())
            assert.are.same({
                { mode = "ui", region = bars.top_rect },
                { mode = "ui", region = bars.bottom_rect },
            }, refreshes)

            refreshes = refreshesOf(function()
                tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            end)
            assert.is_nil(ui.menu.bars)
            assert.are.equal(ui, topWidget())
            assert.are.same({
                { mode = "ui", region = bars.top_rect },
                { mode = "ui", region = bars.bottom_rect },
            }, refreshes)
        end)

        it("should turn pages on the side thirds", function()
            local page = ui:getCurrentPage()
            tap(Screen:getWidth() - 10, Screen:getHeight() - 5)
            assert.are.equal(page + 1, ui:getCurrentPage())
            tap(10, Screen:getHeight() - 5)
            assert.are.equal(page, ui:getCurrentPage())
            assert.are.equal(ui, topWidget())
        end)

        it("should jump to the next chapter and return to the last position from the progress panel", function()
            local start_page = ui:getCurrentPage()
            local next_chapter = ui.toc:getNextChapter(start_page)
            assert.is_truthy(next_chapter)

            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local refreshes = refreshesOf(function()
                tapWidget(findText(ui.menu.bars, require("gettext")("Progress")))
            end)
            local sheet = ui.menu.sheet
            assert.are.equal(sheet, topWidget())
            assert.is_nil(ui.menu.bars)
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
            end
            assert.are.same(sheet:getRefreshRegion(), refreshes[#refreshes].region)
            assert.are.equal(2, #refreshes) -- the top bar and the sheet

            tapWidget(findText(sheet, require("gettext")("Next chapter")))
            assert.are.equal(next_chapter, ui:getCurrentPage())
            assert.are.equal(sheet, topWidget())

            UIManager:forceRePaint()
            local back = find(sheet, function(w)
                return w.callback and w.dimen and find(w, function(c)
                    return type(c.text) == "string" and c.text:find("Return to last position", 1, true)
                end) ~= nil
            end)
            assert.is_truthy(back)
            tapWidget(back)
            assert.are.equal(start_page, ui:getCurrentPage())

            UIManager:forceRePaint()
            refreshes = refreshesOf(function() sheet:onClose() end)
            assert.are.same({ { mode = "ui", region = sheet:getRefreshRegion() } }, refreshes)
            assert.are.equal(ui, topWidget())
        end)

        it("should keep the original menu reachable", function()
            ui:handleEvent(Event:new("ShowOriginalMenu"))
            assert.is_truthy(ui.menu.menu_container)
            assert.are.equal(ui.menu.menu_container, topWidget())
            ui.menu:onCloseReaderMenu()
        end)

        it("should open the original menu from the menu key on non-touch devices", function()
            local Device = require("device")
            stub(Device, "isTouchDevice")
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("KeyPressShowMenu"))
                assert.is_nil(ui.menu.bars)
                assert.is_truthy(ui.menu.menu_container)
            end)
            Device.isTouchDevice:revert()
            ui.menu:onCloseReaderMenu()
            assert(ok, err)
        end)

        it("should honor custom tap zones", function()
            G_reader_settings:saveSetting("page_turns_tap_zones", "left_right")
            G_reader_settings:saveSetting("page_turns_tap_zone_forward_size_ratio", 0.4)
            G_reader_settings:saveSetting("page_turns_tap_zone_backward_size_ratio", 0.4)
            local ok, err = pcall(function()
                local page = ui:getCurrentPage()
                -- inside the default middle third, but in the custom forward zone
                tap(Screen:getWidth() * 0.62, Screen:getHeight() / 2)
                assert.are.equal(page + 1, ui:getCurrentPage())
                assert.are.equal(ui, topWidget())
                tap(Screen:getWidth() * 0.38, Screen:getHeight() / 2)
                assert.are.equal(page, ui:getCurrentPage())
                tap(Screen:getWidth() * 0.5, Screen:getHeight() / 2)
                assert.are.equal(ui.menu.bars, topWidget())
            end)
            ui.menu:hideToolbar()
            G_reader_settings:delSetting("page_turns_tap_zones")
            G_reader_settings:delSetting("page_turns_tap_zone_forward_size_ratio")
            G_reader_settings:delSetting("page_turns_tap_zone_backward_size_ratio")
            assert(ok, err)
        end)

        it("should not turn pages on taps when page turn taps are disabled", function()
            G_reader_settings:makeTrue("page_turns_disable_tap")
            local ok, err = pcall(function()
                local page = ui:getCurrentPage()
                tap(Screen:getWidth() - 10, Screen:getHeight() / 2)
                assert.are.equal(page, ui:getCurrentPage())
                assert.are.equal(ui, topWidget())
                tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
                assert.are.equal(ui.menu.bars, topWidget())
            end)
            ui.menu:hideToolbar()
            G_reader_settings:delSetting("page_turns_disable_tap")
            assert(ok, err)
        end)

        it("should refresh only the brightness sheet, and fully only for night mode", function()
            ui.menu:openPanel("brightness")
            UIManager:forceRePaint()
            local sheet = ui.menu.sheet
            local rect = sheet:getRefreshRegion()
            local plus = find(sheet, function(w) return w.icon == "eink/plus" and w.callback ~= nil end)
            assert.is_truthy(plus)
            local refreshes = refreshesOf(function() tapWidget(plus) end)
            assert.are.same({ mode = "ui", region = rect }, refreshes[#refreshes])
            for _, r in ipairs(refreshes) do
                -- (the footer below the sheet also refreshes itself on frontlight changes)
                assert.are.equal("ui", r.mode)
                assert.is_true(rect:contains(r.region))
            end

            local function nightToggle()
                return find(ui.menu.sheet, function(w) return w.checked ~= nil and w.callback ~= nil end)
            end
            local was_night = G_reader_settings:isTrue("night_mode")
            local toggle = nightToggle()
            refreshes = refreshesOf(function() tapWidget(toggle) end)
            local full = 0
            for _, r in ipairs(refreshes) do
                if r.mode == "full" then
                    full = full + 1
                else
                    assert.are.same({ mode = "fast", region = toggle.dimen }, r)
                end
            end
            -- night mode flashes the whole screen (DeviceListener, then the reader's own repaint)
            assert.is_true(full >= 1)
            assert.are_not.equal(was_night, G_reader_settings:isTrue("night_mode"))
            tapWidget(toggle)
            UIManager:forceRePaint()
            assert.are.equal(was_night, G_reader_settings:isTrue("night_mode"))
            ui.menu:closeSheet()
            UIManager:forceRePaint()
        end)
    end)

    describe("with a PDF", function()
        it("should show the toolbar on a center tap", function()
            local ui = openReader(sample_pdf)
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            assert.is_truthy(ui.menu.bars)
            assert.are.equal(ui.menu.bars, topWidget())
            ui.menu:hideToolbar()
            closeReader(ui)
        end)
    end)

    describe("footer defaults", function()
        local saved
        before_each(function()
            saved = { G_reader_settings:readSetting("footer"), G_reader_settings:readSetting("reader_footer_mode") }
            G_reader_settings:delSetting("footer")
        end)
        after_each(function()
            G_reader_settings:saveSetting("footer", saved[1])
            G_reader_settings:saveSetting("reader_footer_mode", saved[2])
        end)

        it("should fill in the footer when nothing is saved", function()
            ReaderToolbar.applyFooterDefaults()
            local footer = G_reader_settings:readSetting("footer")
            assert.is_true(footer.chapter_progress)
            assert.is_true(footer.disable_progress_bar)
            assert.is_false(footer.page_progress)
        end)

        it("should replace a footer still equal to upstream's defaults", function()
            G_reader_settings:saveSetting("footer", require("util").tableDeepCopy(
                require("apps/reader/modules/readerfooter").default_settings))
            ReaderToolbar.applyFooterDefaults()
            assert.is_true(G_reader_settings:readSetting("footer").chapter_progress)
        end)

        it("should keep the footer toggleable", function()
            ReaderToolbar.applyFooterDefaults()
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                assert.is_true(ui.view.footer_visible)
                ui:handleEvent(Event:new("ToggleFooterMode"))
                assert.is_false(ui.view.footer_visible)
                ui:handleEvent(Event:new("ToggleFooterMode"))
                assert.is_true(ui.view.footer_visible)
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should not overwrite a customized footer", function()
            G_reader_settings:saveSetting("footer", { page_progress = true })
            ReaderToolbar.applyFooterDefaults()
            assert.are.same({ page_progress = true }, G_reader_settings:readSetting("footer"))
        end)
    end)
end)
