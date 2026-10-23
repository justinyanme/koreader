describe("ReaderMorePanel module", function()
    local DataStorage, DocumentRegistry, DocSettings, ReaderUI, ReaderToolbar, Replacements, UIManager, Event, Geom
    local Key, Palette, Size, Screen, ffiUtil, _
    local sample_epub, sample_pdf

    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("exporter.koplugin")
        DataStorage = require("datastorage")
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderToolbar = require("apps/reader/modules/readertoolbar")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Key = require("device/key")
        Palette = require("ui/palette")
        Size = require("ui/size")
        Screen = require("device").screen
        ffiUtil = require("ffi/util")
        _ = require("gettext")
        Replacements.reader_menu = ReaderToolbar
        -- copies of their own: the book details write the books' settings
        sample_epub = DataStorage:getDataDir() .. "/readermorepanel.epub"
        ffiUtil.copyFile("spec/front/unit/data/juliet.epub", sample_epub)
        sample_pdf = DataStorage:getDataDir() .. "/readermorepanel.pdf"
        ffiUtil.copyFile("spec/front/unit/data/sample.pdf", sample_pdf)
    end)

    teardown(function()
        Replacements.reader_menu = nil
        for _, file in ipairs{ sample_epub, sample_pdf } do
            DocSettings:open(file):purge()
            os.remove(file)
        end
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

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function tap(x, y)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
    end

    local function tapWidget(widget)
        tap(widget.dimen.x + math.floor(widget.dimen.w / 2), widget.dimen.y + math.floor(widget.dimen.h / 2))
    end

    local function press(name)
        UIManager:sendEvent(Event:new("KeyPress", Key:new(name, {})))
    end

    local function runTasks()
        for _ = 1, 3 do UIManager:_checkTasks() end
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

    local function fullScreen()
        return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    end

    -- No refresh flashes: only opening a book, going back to the shelf and night mode may.
    local function assertNoFlash(refreshes)
        for _, r in ipairs(refreshes) do
            assert.is_falsy(r.mode == "full" or r.mode:find("^flash"), "flashing refresh: " .. r.mode)
        end
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

    local function findAll(widget, pred, found)
        found = found or {}
        if type(widget) ~= "table" then return found end
        if pred(widget) then table.insert(found, widget) end
        for _, child in ipairs(widget) do
            findAll(child, pred, found)
        end
        return found
    end

    local function hasText(widget, text)
        return find(widget, function(w) return w.text == text end) ~= nil
    end

    -- The darkest gray (0 = ink) on the screen in that band of rows: below 0x40 where the page's text shows,
    -- no darker than the wash where it is washed.
    local function darkest(y0, y1)
        local min = 0xFF
        for y = math.max(0, y0), math.min(Screen:getHeight() - 1, y1), 2 do
            for x = 0, Screen:getWidth() - 1, 2 do
                local v = Screen.bb:getPixel(x, y):getColor8().a
                if v < min then min = v end
            end
        end
        return min
    end

    -- What the screen shows now, washed as the 更多 panel washes the page (to free).
    local function washedCopy()
        local copy = Screen.bb:copy()
        copy:lightenRect(0, 0, copy:getWidth(), copy:getHeight(), Palette.wash.a / 0xFF)
        return copy
    end

    -- Whether the screen shows what `expected` does in that band of rows.
    local function shows(expected, y0, y1)
        for y = y0, y1, 3 do
            for x = 0, Screen:getWidth() - 1, 3 do
                if math.abs(Screen.bb:getPixel(x, y):getColor8().a - expected:getPixel(x, y):getColor8().a) > 1 then
                    return false
                end
            end
        end
        return true
    end

    local function showBars(ui)
        tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
        UIManager:forceRePaint()
        return ui.menu.bars
    end

    local function moreButton(bars)
        return find(bars.top, function(w) return w.icon == "eink/more" and w.callback end)
    end

    -- The rows of the list, top to bottom.
    local function rows(list)
        return findAll(list, function(w) return w.text ~= nil and w.ges_events and w.ges_events.TapSelect end)
    end

    local function rowNamed(list, text)
        for _, r in ipairs(rows(list)) do
            if r.text == text then return r end
        end
    end

    local function rowTexts(list)
        local texts = {}
        for _, r in ipairs(rows(list)) do table.insert(texts, r.text) end
        return texts
    end

    -- 更多 from the top bar of the toolbar.
    local function openMore(ui)
        local bars = ui.menu.bars or showBars(ui)
        tapWidget(moreButton(bars))
        UIManager:forceRePaint()
        assert.are.equal("more", ui.menu.panel_name)
        return ui.menu.panel
    end

    -- Picks a row of the list.
    local function choose(ui, text)
        local list = openMore(ui)
        tapWidget(rowNamed(list, text))
        UIManager:forceRePaint()
    end

    local ROWS -- the list without the statistics plugin
    setup(function()
        ROWS = {
            _("Brightness and warmth"), _("Book details"), _("Export notes"), _("Tap zones"),
            _("Settings"), _("All settings (original)"), _("Cancel"),
        }
    end)

    describe("with an EPUB", function()
        local ui
        setup(function()
            ui = openReader(sample_epub)
            ui.rolling:onGotoPage(10) -- text, past the cover
            UIManager:forceRePaint()
        end)
        teardown(function() ui:onClose() end)
        after_each(function()
            ui.menu:hideToolbar()
            if ui.menu.menu_container then ui.menu:onCloseReaderMenu() end
            while topWidget() ~= ui do UIManager:close(topWidget()) end
            UIManager:forceRePaint()
        end)

        it("should show the list above the bottom bar with both bars, the page between them washed, in one ui refresh", function()
            local page = ui:getCurrentPage()
            local washed_page = washedCopy()
            local bars = showBars(ui)
            tapWidget(find(bars.bottom, function(w) return w.callback and find(w, function(c) return c.icon == "eink/progress" end) end))
            UIManager:forceRePaint()
            local progress_band = ui.menu.panel:getRefreshRegion():combine(bars.bottom_rect)

            local refreshes = refreshesOf(function() tapWidget(moreButton(bars)) end)
            local list = ui.menu.panel
            assert.are.equal("more", ui.menu.panel_name)
            assert.are.equal(bars, ui.menu.bars)
            assert.are.equal(bars, topWidget())
            assert.is_true(bars.show_top)
            -- one refresh, from under the top bar down
            local more_band = list:getRefreshRegion():combine(bars.bottom_rect)
            assert.are.equal(bars.top_rect.h, more_band.y)
            assert.are.equal(Screen:getHeight(), more_band.y + more_band.h)
            assert.are.same({ { mode = "ui", region = progress_band:combine(more_band) } }, refreshes)
            -- the local capabilities, in the ruling's order (no statistics plugin here), then Cancel;
            -- 刷新与残影 stays in 设置 → 屏幕
            assert.are.same(ROWS, rowTexts(list))
            assert.is_false(hasText(list, _("Refresh and ghosting")))
            -- no question: the first row right under the 2dp ink rule, the last right on the bottom bar
            local all = rows(list)
            local band_y = bars.bottom_rect.y - list.band_h
            assert.are.equal(band_y + Size.border.thick, all[1].dimen.y)
            assert.are.equal(bars.bottom_rect.y, all[#all].dimen.y + all[#all].dimen.h)
            for _, r in ipairs(all) do
                assert.is_true(r.dimen.h >= Screen:scaleBySize(44))
            end
            -- the page between the bars is washed once (not what the progress panel left there), the bars are not
            assert.is_true(darkest(bars.top_rect.h + 1, band_y - 1) >= Palette.wash.a)
            assert.is_true(shows(washed_page, bars.top_rect.h + 1, band_y - 1))
            washed_page:free()
            assert.is_true(darkest(0, bars.top_rect.h - 2) < 0x40)
            assert.is_true(darkest(bars.bottom_rect.y + 2, Screen:getHeight() - 1) < 0x40)
            assert.are.equal(page, ui:getCurrentPage())
        end)

        it("should close only the list on Cancel, Back or 更多, and the bars too on a tap on the wash, without a page turn", function()
            local page = ui:getCurrentPage()
            local function pageShows(bars)
                return darkest(bars.top_rect.h + 1, bars.bottom_rect.y - 1) < 0x40
            end
            local list_only = {
                function(list) tapWidget(rowNamed(list, _("Cancel"))) end,
                function() press("Back") end,
                function() tapWidget(moreButton(ui.menu.bars)) end,
            }
            for _, leave in ipairs(list_only) do
                local list = openMore(ui)
                local bars = ui.menu.bars
                -- what reaches the wash stays there: no page turn by swipe or page key
                UIManager:sendEvent(Event:new("Gesture", {
                    ges = "swipe", direction = "west", distance = 200,
                    pos = Geom:new{ x = 400, y = 200, w = 0, h = 0 }, time = require("ui/time").now(),
                }))
                press("RPgFwd")
                assert.are.equal(list, ui.menu.panel)
                local band = list:getRefreshRegion():combine(bars.bottom_rect)
                local refreshes = refreshesOf(function() leave(list) end)
                assert.is_nil(ui.menu.panel)
                assert.are.equal(bars, topWidget())
                assert.are.same({ { mode = "ui", region = band } }, refreshes)
                assert.is_true(pageShows(bars))
                assert.are.equal(page, ui:getCurrentPage())
            end
            -- the page's right third, a page turn otherwise
            openMore(ui)
            local bars = ui.menu.bars
            local refreshes = refreshesOf(function() tap(Screen:getWidth() - 10, Screen:getHeight() / 4) end)
            assertNoFlash(refreshes)
            assert.is_nil(ui.menu.panel)
            assert.is_nil(ui.menu.bars)
            assert.are.equal(ui, topWidget())
            assert.are.equal(page, ui:getCurrentPage())
            assert.is_true(pageShows(bars))
        end)

        it("should open the brightness panel in its place from 亮度与色温, then leave layer by layer", function()
            local list = openMore(ui)
            local bars = ui.menu.bars
            local more_band = list:getRefreshRegion():combine(bars.bottom_rect)
            local refreshes = refreshesOf(function() tapWidget(rowNamed(list, _("Brightness and warmth"))) end)
            assert.are.equal("brightness", ui.menu.panel_name)
            assert.are.equal(bars, ui.menu.bars)
            assert.are.equal(bars, topWidget())
            assert.is_true(bars.show_top)
            assert.is_truthy(hasText(ui.menu.panel, _("Night mode (white on black)")))
            local brightness_band = ui.menu.panel:getRefreshRegion():combine(bars.bottom_rect)
            assert.are.same({ { mode = "ui", region = more_band:combine(brightness_band) } }, refreshes)
            -- the page above the panel is no longer washed
            assert.is_true(darkest(bars.top_rect.h + 1, brightness_band.y - 1) < 0x40)

            press("Back")
            UIManager:forceRePaint()
            assert.is_nil(ui.menu.panel)
            assert.are.equal(bars, topWidget())
            press("Back")
            UIManager:forceRePaint()
            assert.is_nil(ui.menu.bars)
            assert.are.equal(ui, topWidget())
        end)

        it("should wash the page only once, also when the bookmark is toggled with the list open", function()
            local list = openMore(ui)
            local bars = ui.menu.bars
            local band_y = bars.bottom_rect.y - list.band_h
            local function washedOnce()
                local v = darkest(bars.top_rect.h + 1, band_y - 1)
                return v >= Palette.wash.a - 2 and v <= Palette.wash.a + 2
            end
            assert.is_true(washedOnce())
            local bookmark = find(bars.top, function(w) return w.icon == "eink/bookmark" and w.callback end)
            local refreshes = refreshesOf(function() tapWidget(bookmark) end)
            assertNoFlash(refreshes)
            assert.are.equal("eink/bookmark-on", bookmark.icon)
            assert.are.equal(list, ui.menu.panel)
            assert.is_true(washedOnce())
            tapWidget(bookmark) -- remove the test bookmark
            UIManager:forceRePaint()
            assert.is_false(ui.bookmark:isPageBookmarked())
            assert.is_true(washedOnce())
        end)

        it("should show the book details with the reader's own rating and review, and keep them", function()
            local refreshes = refreshesOf(function() choose(ui, _("Book details")) end)
            assertNoFlash(refreshes)
            local details = topWidget()
            -- the list and the bars went first
            assert.is_nil(ui.menu.panel)
            assert.is_nil(ui.menu.bars)
            assert.is_true(hasText(details, ui.doc_props.display_title))
            local function stars()
                return findAll(details, function(w)
                    return (w.icon == "star.empty" or w.icon == "star.full") and w.callback ~= nil
                end)
            end
            assert.are.equal(5, #stars())
            -- four stars
            tapWidget(stars()[4])
            UIManager:forceRePaint()
            local full = 0
            for _, s in ipairs(stars()) do
                if s.icon == "star.full" then full = full + 1 end
            end
            assert.are.equal(4, full)
            -- a review, through the review box and its dialog
            tapWidget(details.note_frame)
            local dialog = details.note_dialog
            assert.is_truthy(dialog)
            UIManager:forceRePaint()
            dialog._input_widget:setText("A test review")
            tapWidget(find(dialog, function(w) return w.text == _("Save review") and w.callback end))
            UIManager:forceRePaint()
            assert.are.equal(details, topWidget())
            assert.is_true(hasText(details, "A test review"))

            -- its close button leads back to the page, without a flash
            local close = find(details, function(w) return w.icon == "close" and w.callback end)
            refreshes = refreshesOf(function() tapWidget(close) end)
            assertNoFlash(refreshes)
            assert.are.equal(ui, topWidget())
            -- both are saved with the book
            local summary = DocSettings:open(sample_epub):readSetting("summary")
            assert.are.equal(4, summary.rating)
            assert.are.equal("A test review", summary.note)

            -- and show again next time
            choose(ui, _("Book details"))
            details = topWidget()
            local again = 0
            for _, s in ipairs(stars()) do
                if s.icon == "star.full" then again = again + 1 end
            end
            assert.are.equal(4, again)
            assert.is_true(hasText(details, "A test review"))
            details:onClose()
            UIManager:forceRePaint()
            summary = ui.doc_settings:readSetting("summary")
            summary.rating, summary.note = nil, nil
            ui.doc_settings:flush()
        end)

        it("should draw the tap zones from 点击区域 until a tap, then come back to the page", function()
            local page = ui:getCurrentPage()
            local refreshes = refreshesOf(function() choose(ui, _("Tap zones")) end)
            assertNoFlash(refreshes)
            local zones = topWidget()
            assert.is_nil(ui.menu.bars)
            assert.are.equal(require("apps/reader/modules/readermorepanel").TapZones, getmetatable(zones).__index)
            local C_ = _.pgettext
            local drawn = {}
            for _, z in ipairs(zones.zones) do table.insert(drawn, z.widget) end
            for _, name in ipairs{ C_("Tap zones", "Previous page"), C_("Tap zones", "Toolbar"), C_("Tap zones", "Next page") } do
                assert.is_true(hasText(drawn, name), name)
            end
            refreshes = refreshesOf(function() tap(Screen:getWidth() - 10, Screen:getHeight() / 2) end)
            assertNoFlash(refreshes)
            assert.are.equal(ui, topWidget())
            assert.are.equal(page, ui:getCurrentPage())
        end)

        it("should open the settings from 设置 with the rows a book needs, which close back to the page", function()
            local EinkSettings = require("apps/settings/einksettings")
            local refreshes = refreshesOf(function() choose(ui, _("Settings")) end)
            assertNoFlash(refreshes)
            local page = topWidget()
            assert.are.equal(EinkSettings, getmetatable(page).__index)
            assert.is_nil(ui.menu.bars)
            assert.are.equal(_("Settings"), page.title)
            -- the shown row named `name`, turning the list's pages until found
            local function settingsRow(name)
                for p = 1, #page.pages do
                    if p ~= page.page then
                        page:goToPage(p)
                        UIManager:forceRePaint()
                    end
                    for __, spec in ipairs(page.shown) do
                        if spec.name == name then return spec end
                    end
                end
            end
            -- rows that act on the open book are there, unlike from 我 → 设置 on the shelf
            for __, name in ipairs{ _("Page turns and tap zones"), _.pgettext("Settings", "Status bar") } do
                local spec = settingsRow(name)
                assert.is_true(spec.enabled, name)
                assert.are_not.equal(_("Open a book first"), spec.value)
            end
            -- 翻页与点击区域 opens its own entries
            tapWidget({ dimen = settingsRow(_("Page turns and tap zones")).rect })
            UIManager:forceRePaint()
            assert.are.equal(_("Page turns and tap zones"), page.title)
            assert.is_true(#page.shown > 1)
            for __, spec in ipairs(page.shown) do
                assert.are_not.equal(_("Open a book first"), spec.value)
                assert.are_not.equal(_("Open a book first"), spec.name)
            end
            -- back up, then out to the page
            tapWidget(page.bar.back)
            UIManager:forceRePaint()
            assert.are.equal(_("Settings"), page.title)
            refreshes = refreshesOf(function() tapWidget(page.bar.back) end)
            assertNoFlash(refreshes)
            assert.are.equal(ui, topWidget())
        end)

        it("should open the original menu from 全部设置（原版）, which closes back to the page", function()
            choose(ui, _("All settings (original)"))
            assert.is_nil(ui.menu.bars)
            assert.is_truthy(ui.menu.menu_container)
            assert.are.equal(ui.menu.menu_container, topWidget())
            ui.menu:onCloseReaderMenu()
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())
        end)

        describe("导出笔记", function()
            local clipping_dir
            setup(function()
                clipping_dir = DataStorage:getDataDir() .. "/readermorepanel-clippings"
                ffiUtil.purgeDir(clipping_dir)
                require("libs/libkoreader-lfs").mkdir(clipping_dir)
            end)
            teardown(function()
                ffiUtil.purgeDir(clipping_dir)
                local exporter = ui.exporter
                exporter.targets.text.settings.enabled = nil
                exporter.settings.clipping_dir = nil
            end)

            it("should be faded and do nothing while the book has no notes", function()
                assert.is_false(ui.annotation:hasAnnotations())
                local list = openMore(ui)
                local row = rowNamed(list, _("Export notes"))
                assert.are.equal(Palette.ink_3, row.label.fgcolor)
                assert.are.equal(Palette.ink, rowNamed(list, _("Book details")).label.fgcolor)
                tapWidget(row)
                UIManager:forceRePaint()
                assert.are.equal(list, ui.menu.panel)
                assert.are.equal(ui.menu.bars, topWidget())
            end)

            it("should show where formats are chosen when none is, then export the book's notes", function()
                -- a highlight on the page
                local pos = Geom:new{ x = 400, y = 110, w = 0, h = 0 }
                ui.highlight:onHold(nil, { pos = pos })
                ui.highlight:onHoldRelease()
                local text = ui.highlight.selected_text.text
                ui.highlight:saveHighlight()
                ui.highlight:onClose()
                -- upstream ReaderHighlight also looks the word up on release
                while topWidget() ~= ui do UIManager:close(topWidget()) end
                UIManager:forceRePaint()
                assert.is_true(ui.annotation:hasAnnotations())
                assert.is_truthy(text ~= nil and text ~= "")

                -- no format or service chosen yet: the original menu, on the tab that holds the exporter
                local list = openMore(ui)
                assert.are.equal(Palette.ink, rowNamed(list, _("Export notes")).label.fgcolor)
                tapWidget(rowNamed(list, _("Export notes")))
                UIManager:forceRePaint()
                local menu = ui.menu.menu_container
                assert.is_truthy(menu)
                assert.are.equal(menu, topWidget())
                assert.are.equal("appbar.tools", ui.menu.tab_item_table[menu[1].cur_tab].icon)
                ui.menu:onCloseReaderMenu()
                UIManager:forceRePaint()
                assert.are.equal(ui, topWidget())

                -- with plain text chosen, into the chosen folder
                ui.exporter.targets.text.settings.enabled = true
                ui.exporter.settings.clipping_dir = clipping_dir
                choose(ui, _("Export notes"))
                runTasks()
                UIManager:forceRePaint()
                local exported
                for f in require("libs/libkoreader-lfs").dir(clipping_dir) do
                    if f:match("%.txt$") then exported = clipping_dir .. "/" .. f end
                end
                assert.is_truthy(exported)
                local fd = io.open(exported, "r")
                local content = fd:read("*all")
                fd:close()
                assert.is_truthy(content:find(text, 1, true))
                -- the exporter says where it went; dismissing its messages leads back to the page
                local said = false
                for i = #UIManager._window_stack, 1, -1 do
                    local w = UIManager._window_stack[i].widget
                    if w == ui then break end
                    said = said or (type(w.text) == "string" and w.text:find(exported, 1, true) ~= nil)
                end
                assert.is_true(said)
                while topWidget() ~= ui do UIManager:close(topWidget()) end
                UIManager:forceRePaint()
                assert.are.equal(ui, topWidget())

                -- remove the test highlight
                ui.highlight:deleteHighlight(1)
                assert.is_false(ui.annotation:hasAnnotations())
            end)
        end)

        it("should put 阅读统计 before 全部设置（原版） with the statistics plugin, and come back from its page", function()
            -- the plugin's own reading progress page, on controlled data (lj-sqlite3 doesn't load under busted)
            local ReaderProgress = dofile("plugins/statistics.koplugin/readerprogress.lua")
            local week = {}
            for i = 1, 7 do
                table.insert(week, { 12, 600, os.date("%Y-%m-%d", os.time() - (i - 1) * 86400) })
            end
            ui.statistics = {
                onShowReaderProgress = function()
                    UIManager:show(ReaderProgress:new{
                        dates = week,
                        current_duration = 600, current_pages = 12, today_duration = 600, today_pages = 12,
                    })
                end,
            }
            local ok, err = pcall(function()
                local list = openMore(ui)
                local texts = rowTexts(list)
                assert.are.equal(_("Reading statistics"), texts[#texts - 3])
                assert.are.equal(_("Settings"), texts[#texts - 2])
                tapWidget(rowNamed(list, _("Reading statistics")))
                UIManager:forceRePaint()
                local progress = topWidget()
                assert.are.equal(ReaderProgress, getmetatable(progress).__index)
                progress:onClose()
                UIManager:forceRePaint()
                assert.are.equal(ui, topWidget())
            end)
            ui.statistics = nil
            assert(ok, err)
        end)

        it("should close the list when the screen rotates, and fit it between the bars in landscape", function()
            openMore(ui)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
                runTasks()
                UIManager:forceRePaint()
                assert.is_nil(ui.menu.panel)
                assert.is_nil(ui.menu.bars)
                assert.are.equal(ui, topWidget())
                -- landscape is 600dp tall on any screen: every row, 阅读统计 included, sits under the top bar
                ui.statistics = { onShowReaderProgress = function() end }
                local list = openMore(ui)
                ui.statistics = nil
                local bars = ui.menu.bars
                assert.are.equal(#ROWS + 1, #rows(list))
                assert.is_true(rows(list)[1].dimen.y >= bars.top_rect.h)
                ui.menu:hideToolbar()
                UIManager:forceRePaint()
            end)
            ui.statistics = nil
            ui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
            runTasks()
            UIManager:forceRePaint()
            assert(ok, err)
        end)
    end)

    describe("with a PDF", function()
        local ui
        setup(function() ui = openReader(sample_pdf) end)
        teardown(function() ui:onClose() end)

        it("should offer the same list, and come back to the page from the book details and the brightness panel", function()
            local list = openMore(ui)
            assert.are.equal(ui.menu.bars, topWidget())
            assert.are.same(ROWS, rowTexts(list))
            tapWidget(rowNamed(list, _("Book details")))
            UIManager:forceRePaint()
            local details = topWidget()
            assert.is_true(hasText(details, ui.doc_props.display_title))
            tapWidget(find(details, function(w) return w.icon == "close" and w.callback end))
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())

            choose(ui, _("Brightness and warmth"))
            assert.are.equal("brightness", ui.menu.panel_name)
            assert.are.equal(ui.menu.bars, topWidget())
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())
        end)
    end)
end)
