describe("ReaderToolbar module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderToolbar, Replacements, UIManager, Event, Geom, Screen, _
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
        _ = require("gettext")
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

        local function cell(text)
            return findText(ui.menu.bars.bottom, text)
        end

        local function openFromToolbar(text)
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            tapWidget(cell(text))
            UIManager:forceRePaint()
            return ui.menu.panel
        end

        it("should keep both bars while the progress panel is open, between the page and the bottom bar", function()
            local start_page = ui:getCurrentPage()
            local next_chapter = ui.toc:getNextChapter(start_page)
            assert.is_truthy(next_chapter)

            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local bars = ui.menu.bars
            -- no panel: every entry has its plain icon
            assert.is_nil(find(bars.bottom, function(w) return type(w.icon) == "string" and w.icon:find("%.bold$") end))
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/toc" end))
            local refreshes = refreshesOf(function() tapWidget(cell(_("Progress"))) end)
            local panel = ui.menu.panel
            assert.is_truthy(panel)
            assert.are.equal("progress", ui.menu.panel_name)
            -- one window: the bars stay, the panel joins them
            assert.are.equal(bars, ui.menu.bars)
            assert.are.equal(bars, topWidget())
            assert.is_true(bars.show_top)
            local rect = panel:getRefreshRegion()
            assert.are.equal(bars.bottom_rect.y, rect.y + rect.h)
            assert.is_true(rect.y >= bars.top_rect.h)
            assert.are.same({ { mode = "ui", region = rect:combine(bars.bottom_rect) } }, refreshes)
            -- the open panel's icon is filled; the panel has no title bar and no close button
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/progress.bold" end))
            assert.is_nil(find(panel, function(w) return w.icon == "eink/close" end))
            assert.is_nil(find(panel, function(w) return w.text == _("Progress") end))

            tapWidget(findText(panel, _("Next chapter")))
            assert.are.equal(next_chapter, ui:getCurrentPage())
            assert.are.equal(panel, ui.menu.panel)
            assert.are.equal(bars, topWidget())

            UIManager:forceRePaint()
            local back = find(panel, function(w)
                return w.callback and w.dimen and find(w, function(c)
                    return type(c.text) == "string" and c.text:find("Return to last position", 1, true)
                end) ~= nil
            end)
            assert.is_truthy(back)
            tapWidget(back)
            assert.are.equal(start_page, ui:getCurrentPage())

            -- its own entry closes the panel; the bars stay
            UIManager:forceRePaint()
            rect = panel:getRefreshRegion()
            refreshes = refreshesOf(function() tapWidget(cell(_("Progress"))) end)
            assert.is_nil(ui.menu.panel)
            assert.are.equal(bars, topWidget())
            assert.are.same({ { mode = "ui", region = rect:combine(bars.bottom_rect) } }, refreshes)
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/progress" end))
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should switch panels in place from the bars, one panel at a time, without turning the page", function()
            local page = ui:getCurrentPage()
            local progress = openFromToolbar(_("Progress"))
            local bars = ui.menu.bars
            local windows = #UIManager._window_stack
            local old_rect = progress:getRefreshRegion()
            local refreshes = refreshesOf(function() tapWidget(cell(_("Brightness"))) end)
            local brightness = ui.menu.panel
            assert.are_not.equal(progress, brightness)
            assert.are.equal("brightness", ui.menu.panel_name)
            assert.are.equal(bars, topWidget())
            assert.are.equal(windows, #UIManager._window_stack)
            local band = old_rect:combine(brightness:getRefreshRegion()):combine(bars.bottom_rect)
            assert.are.same({ { mode = "ui", region = band } }, refreshes)
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/light.bold" end))
            assert.is_nil(find(bars.bottom, function(w) return w.icon == "eink/progress.bold" end))

            -- the top bar's more opens its panel the same way
            refreshes = refreshesOf(function()
                tapWidget(find(bars.top, function(w) return w.icon == "eink/more" and w.callback end))
            end)
            assert.are.equal("more", ui.menu.panel_name)
            assert.are.equal(windows, #UIManager._window_stack)
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
            end
            assert.is_nil(find(bars.bottom, function(w) return type(w.icon) == "string" and w.icon:find("%.bold$") end))
            -- the open entry, below the page's right third, closes only the panel
            tapWidget(find(bars.top, function(w) return w.icon == "eink/more" and w.callback end))
            assert.is_nil(ui.menu.panel)
            assert.are.equal(bars, topWidget())
            assert.are.equal(page, ui:getCurrentPage())
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())
        end)

        it("should keep the bookmark icon in step with the page the panel jumps to", function()
            local start_page = ui:getCurrentPage()
            local panel = openFromToolbar(_("Progress"))
            local bars = ui.menu.bars
            local function bookmarkButton()
                return find(bars.top, function(w)
                    return (w.icon == "eink/bookmark" or w.icon == "eink/bookmark-on") and w.callback
                end)
            end
            tapWidget(bookmarkButton())
            UIManager:forceRePaint()
            assert.are.equal("eink/bookmark-on", bookmarkButton().icon)

            tapWidget(findText(panel, _("Next chapter")))
            UIManager:forceRePaint()
            assert.are_not.equal(start_page, ui:getCurrentPage())
            assert.are.equal("eink/bookmark", bookmarkButton().icon)

            tapWidget(find(panel, function(w)
                return w.callback and w.dimen and find(w, function(c)
                    return type(c.text) == "string" and c.text:find("Return to last position", 1, true)
                end) ~= nil
            end))
            UIManager:forceRePaint()
            assert.are.equal(start_page, ui:getCurrentPage())
            assert.are.equal("eink/bookmark-on", bookmarkButton().icon)
            tapWidget(bookmarkButton()) -- remove the test bookmark
            UIManager:forceRePaint()
            assert.is_false(ui.bookmark:isPageBookmarked())
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should close the panel and both bars on a tap on the page, without turning the page", function()
            local panel = openFromToolbar(_("Progress"))
            local bars = ui.menu.bars
            local page = ui:getCurrentPage()
            -- a tap on the panel itself, away from its controls, stays there
            local rect = panel:getRefreshRegion()
            tap(rect.x + 2, rect.y + 2)
            assert.are.equal(panel, ui.menu.panel)
            assert.are.equal(bars, topWidget())

            local band = rect:combine(bars.bottom_rect)
            -- the right third of the page, between the top bar and the panel: a page turn tap otherwise
            local refreshes = refreshesOf(function() tap(Screen:getWidth() - 10, bars.top_rect.h + 10) end)
            assert.is_nil(ui.menu.panel)
            assert.is_nil(ui.menu.bars)
            assert.are.equal(ui, topWidget())
            assert.are.equal(page, ui:getCurrentPage())
            assert.are.same({
                { mode = "ui", region = bars.top_rect },
                { mode = "ui", region = band },
            }, refreshes)
        end)

        it("should leave the panel, then the bars, on Back", function()
            local Key = require("device/key")
            local function back() UIManager:sendEvent(Event:new("KeyPress", Key:new("Back", {}))) end
            local panel = openFromToolbar(_("Brightness"))
            local bars = ui.menu.bars
            local band = panel:getRefreshRegion():combine(bars.bottom_rect)
            local refreshes = refreshesOf(back)
            assert.is_nil(ui.menu.panel)
            assert.are.equal(bars, topWidget())
            assert.are.same({ { mode = "ui", region = band } }, refreshes)
            back()
            UIManager:forceRePaint()
            assert.is_nil(ui.menu.bars)
            assert.are.equal(ui, topWidget())
        end)

        it("should open a panel's target after closing the panel and the bars", function()
            local panel = openFromToolbar(_("Brightness"))
            assert.is_truthy(panel)
            tapWidget(find(ui.menu.bars.top, function(w) return w.icon == "eink/more" and w.callback end))
            UIManager:forceRePaint()
            local tile = find(ui.menu.panel, function(w) return w.label == _("Book information") and w.callback end)
            tapWidget(tile)
            UIManager:forceRePaint()
            assert.is_nil(ui.menu.panel)
            assert.is_nil(ui.menu.bars)
            assert.are_not.equal(ui, topWidget())
            UIManager:close(topWidget())
            UIManager:forceRePaint()
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

        it("should refresh only the brightness panel, and fully only for night mode", function()
            ui.menu:openPanel("brightness")
            UIManager:forceRePaint()
            local panel = ui.menu.panel
            local bars = ui.menu.bars
            assert.are.equal(bars, topWidget())
            local rect = panel:getRefreshRegion()
            local plus = find(panel, function(w) return w.icon == "eink/plus" and w.callback ~= nil end)
            assert.is_truthy(plus)
            local refreshes = refreshesOf(function() tapWidget(plus) end)
            local panel_refreshed = false
            for _, r in ipairs(refreshes) do
                panel_refreshed = panel_refreshed or r.region == rect or require("util").tableEquals(r.region, rect)
                -- (the footer, under the bottom bar, also refreshes itself on frontlight changes)
                assert.are.equal("ui", r.mode)
                assert.is_true(rect:contains(r.region) or bars.bottom_rect:contains(r.region))
            end
            assert.is_true(panel_refreshed)

            local function nightToggle()
                return find(ui.menu.panel, function(w) return w.checked ~= nil and w.callback ~= nil end)
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
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)
    end)

    describe("with a PDF", function()
        it("should keep both bars with the progress panel, and open the original bottom bar from Font", function()
            local ui = openReader(sample_pdf)
            local page = ui:getCurrentPage()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            assert.is_truthy(ui.menu.bars)
            assert.are.equal(ui.menu.bars, topWidget())
            UIManager:forceRePaint()
            local bars = ui.menu.bars
            tapWidget(findText(bars.bottom, require("gettext")("Progress")))
            UIManager:forceRePaint()
            assert.are.equal("progress", ui.menu.panel_name)
            assert.are.equal(bars, topWidget())
            assert.is_true(bars.show_top)
            local rect = ui.menu.panel:getRefreshRegion()
            assert.are.equal(bars.bottom_rect.y, rect.y + rect.h)
            -- a tap on the page closes both, without turning the page
            tap(Screen:getWidth() - 10, bars.top_rect.h + 10)
            UIManager:forceRePaint()
            assert.is_nil(ui.menu.bars)
            assert.are.equal(page, ui:getCurrentPage())

            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            tapWidget(findText(ui.menu.bars.bottom, require("gettext")("Font")))
            UIManager:forceRePaint()
            assert.is_nil(ui.menu.bars)
            assert.is_nil(ui.menu.panel)
            assert.is_truthy(ui.config.config_dialog)
            assert.are.equal(ui.config.config_dialog, topWidget())
            ui.config.config_dialog:closeDialog()
            UIManager:forceRePaint()
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
