describe("ReaderToolbar module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderToolbar, ReaderToolbarHint, Replacements, UIManager, Event, Geom
    local Screen, time, _
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local sample_pdf = "spec/front/unit/data/sample.pdf"

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderToolbar = require("apps/reader/modules/readertoolbar")
        ReaderToolbarHint = require("apps/reader/modules/readertoolbarhint")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Screen = require("device").screen
        time = require("ui/time")
        _ = require("gettext")
        Replacements.reader_menu = ReaderToolbar
    end)

    teardown(function()
        Replacements.reader_menu = nil
    end)

    -- `keep` keeps the book's settings (its position) from a previous opening.
    local function openReader(file, keep)
        if not keep then
            DocSettings:open(file):purge()
        end
        local ui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(file),
        }
        UIManager:show(ui)
        UIManager:forceRePaint()
        return ui
    end

    -- As the reader closes a book: CloseDocument reaches its modules (the footer's and the hint's tasks go).
    local function closeReader(ui)
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

    local function direction(dx, dy)
        if math.abs(dx) > math.abs(dy) then
            return dx > 0 and "east" or "west"
        end
        return dy > 0 and "south" or "north"
    end

    -- A finger that went down at (x0, y0) and is now at (x, y), as GestureDetector reports it while it moves;
    -- with `end_swipe`, it lifts there and the swipe is reported from where it started.
    local function moveEvent(x0, y0, x, y, at, end_swipe)
        local dx, dy = x - x0, y - y0
        local start = Geom:new{ x = x0, y = y0, w = 0, h = 0 }
        local here = Geom:new{ x = x, y = y, w = 0, h = 0 }
        local distance = math.floor(math.sqrt(dx * dx + dy * dy))
        if end_swipe then
            UIManager:sendEvent(Event:new("Gesture", {
                ges = "swipe", direction = direction(dx, dy), distance = distance,
                pos = start, end_pos = here, time = at,
            }))
        else
            UIManager:sendEvent(Event:new("Gesture", {
                ges = "pan", direction = direction(dx, dy), distance = distance, relative = { x = dx, y = dy },
                start_pos = start, pos = here, time = at,
            }))
        end
    end

    -- A quick swipe: pans while the finger moves, then the swipe.
    local function swipe(x0, y0, x1, y1)
        for _, f in ipairs{ 0.25, 0.5 } do
            moveEvent(x0, y0, x0 + math.floor((x1 - x0) * f), y0 + math.floor((y1 - y0) * f), time.now())
        end
        moveEvent(x0, y0, x1, y1, time.now(), true)
    end

    -- Whether anything is drawn on the screen in that rect.
    local function inked(x0, y0, x1, y1)
        for y = math.max(0, y0), math.min(Screen:getHeight() - 1, y1) do
            for x = math.max(0, x0), math.min(Screen:getWidth() - 1, x1) do
                if Screen.bb:getPixel(x, y):getColor8().a ~= 0xFF then
                    return true
                end
            end
        end
        return false
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

    -- The tappable widget showing `icon` (or its filled variant), such as an entry of a bar.
    local function findIcon(widget, icon)
        return find(widget, function(w)
            return w.callback and w.dimen and find(w, function(c) return c.icon == icon or c.icon == icon .. ".bold" end) ~= nil
        end)
    end

    local function moreButton(bars)
        return find(bars.top, function(w) return w.icon == "eink/more" and w.callback end)
    end

    local function bookmarkButton(bars)
        return find(bars.top, function(w) return (w.icon == "eink/bookmark" or w.icon == "eink/bookmark-on") and w.callback end)
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

        local function cell(icon)
            return findIcon(ui.menu.bars.bottom, icon)
        end

        it("should close the bars on a tap on the page without turning it, even on a side third", function()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local bars = ui.menu.bars
            local page = ui:getCurrentPage()
            tap(Screen:getWidth() - 10, Screen:getHeight() / 2)
            assert.is_nil(ui.menu.bars)
            assert.are.equal(page, ui:getCurrentPage())
            assert.are.equal(ui, topWidget())
            UIManager:forceRePaint()
            assert.is_nil(bars.toolbar.bars)
        end)

        it("should lay the bottom bar out as back, a short rule, then contents, notes, progress and font, icons only", function()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local bars = ui.menu.bars
            local sw = Screen:getWidth()
            assert.are.equal(Screen:scaleBySize(58), bars.bottom_rect.h)
            local back = findIcon(bars.bottom, "eink/arrow.left")
            assert.is_truthy(back)
            assert.are.equal(0, back.dimen.x)
            -- a short rule-gray rule after it
            local rule = find(bars.bottom, function(w) return w.background and w.dimen and w.dimen.h > w.dimen.w end)
            assert.is_truthy(rule)
            assert.are.equal(require("ui/palette").rule, rule.background)
            assert.is_true(rule.dimen.h < bars.bottom_rect.h / 2)
            -- then the four entries, left to right, sharing the rest of the width; no 听, no brightness
            local prev
            for _, icon in ipairs{ "eink/toc", "eink/notes", "eink/progress", "eink/font" } do
                local c = findIcon(bars.bottom, icon)
                assert.is_truthy(c, icon)
                if prev then
                    assert.are.equal(prev.dimen.x + prev.dimen.w, c.dimen.x, icon)
                    assert.are.equal(prev.dimen.w, c.dimen.w, icon)
                else
                    assert.is_true(c.dimen.x >= back.dimen.x + back.dimen.w, icon)
                end
                assert.is_true(c.dimen.w >= Screen:scaleBySize(44) and c.dimen.h >= Screen:scaleBySize(44), icon)
                prev = c
            end
            assert.is_true(sw - (prev.dimen.x + prev.dimen.w) < 4)
            assert.is_nil(findIcon(bars.bottom, "eink/light"))
            -- icons without labels
            assert.is_nil(find(bars.bottom, function(w) return type(w.text) == "string" end))
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should put the bookmark and more at the right of the top bar, in that order, with no back or search", function()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local bars = ui.menu.bars
            local sw = Screen:getWidth()
            assert.are.equal(Screen:scaleBySize(50), bars.top_rect.h)
            local bookmark, more = bookmarkButton(bars), moreButton(bars)
            assert.is_truthy(bookmark)
            assert.is_truthy(more)
            assert.are.equal(sw, more.dimen.x + more.dimen.w)
            assert.are.equal(more.dimen.x, bookmark.dimen.x + bookmark.dimen.w)
            -- 76dp apart, as in WeChat Read
            assert.are.equal(Screen:scaleBySize(76), more.dimen.x - bookmark.dimen.x)
            assert.is_true(bookmark.dimen.h >= Screen:scaleBySize(44))
            for _, icon in ipairs{ "eink/back", "eink/arrow.left", "eink/search", "eink/light" } do
                assert.is_nil(findIcon(bars.top, icon), icon)
            end
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should open the notes from the bottom bar's 笔记, after closing the bars", function()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local bars = ui.menu.bars
            local refreshes = refreshesOf(function() tapWidget(findIcon(bars.bottom, "eink/notes")) end)
            assert.is_nil(ui.menu.bars)
            local page = ui.menu.drawer
            assert.is_truthy(page)
            assert.are.equal(page, topWidget())
            assert.is_nil(page.filter)
            -- the notes page covers the bars: one "ui" refresh of the whole screen
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            ui.menu:closeDrawer()
            UIManager:forceRePaint()

            -- the contents page's 书签 sends the same event, for the bookmarks (there are none here)
            ui:handleEvent(Event:new("ShowNotes", "bookmarks"))
            assert.is_true(ui.menu.drawer.covers_fullscreen)
            assert.are.equal(ui.menu.drawer, topWidget())
            ui.menu:closeDrawer()
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())
        end)

        it("should show the bars on a swipe up, from the middle of the page or its bottom edge", function()
            local sw, sh = Screen:getWidth(), Screen:getHeight()
            local page = ui:getCurrentPage()
            local refreshes = refreshesOf(function() swipe(sw / 2, sh * 0.6, sw / 2, sh * 0.3) end)
            local bars = ui.menu.bars
            assert.is_truthy(bars)
            assert.are.equal(bars, topWidget())
            assert.are.same({
                { mode = "ui", region = bars.top_rect },
                { mode = "ui", region = bars.bottom_rect },
            }, refreshes)
            assert.are.equal(page, ui:getCurrentPage())
            ui.menu:hideToolbar()
            UIManager:forceRePaint()

            -- from the bottom edge, where the original bottom menu used to open
            swipe(sw / 2, sh - 5, sw / 2, sh * 0.7)
            UIManager:forceRePaint()
            assert.are.equal(ui.menu.bars, topWidget())
            assert.is_nil(ui.menu.panel)
            assert.is_nil(ui.config.config_dialog)
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
            assert.are.equal(page, ui:getCurrentPage())
            assert.are.equal(ui, topWidget())
        end)

        it("should leave swipes up to scrolling in scroll mode, except from the bottom edge", function()
            local sw, sh = Screen:getWidth(), Screen:getHeight()
            ui:handleEvent(Event:new("SetViewMode", "scroll"))
            local ok, err = pcall(function()
                swipe(sw / 2, sh * 0.6, sw / 2, sh * 0.3)
                UIManager:forceRePaint()
                assert.is_nil(ui.menu.bars)
                assert.are.equal(ui, topWidget())
                -- from the bottom edge: the pans that leave the edge scroll, as on a device, once scrolling's
                -- activation delay has passed; the swipe then shows the bars and scrolls back
                local pos = ui.rolling.current_pos
                local x, y0, t0 = sw / 2, sh - 5, time.now()
                moveEvent(x, y0, x, sh * 0.85, t0) -- on the edge: the toolbar takes it, waiting for the swipe
                moveEvent(x, y0, x, sh * 0.6, t0 + time.s(0.2)) -- off the edge: scrolling starts...
                moveEvent(x, y0, x, sh * 0.4, t0 + time.s(0.8)) -- ...once its delay has passed
                assert.are_not.equal(pos, ui.rolling.current_pos)
                moveEvent(x, y0, x, sh * 0.3, t0 + time.s(0.9), true)
                UIManager:forceRePaint()
                assert.are.equal(ui.menu.bars, topWidget())
                assert.is_nil(ui.config.config_dialog)
                assert.are.equal(pos, ui.rolling.current_pos)
            end)
            ui.menu:hideToolbar()
            ui:handleEvent(Event:new("SetViewMode", "page"))
            UIManager:forceRePaint()
            assert(ok, err)
        end)

        it("should open a panel with both bars on ShowToolbarPanel, as from 更多's 亮度", function()
            local refreshes = refreshesOf(function() ui:handleEvent(Event:new("ShowToolbarPanel", "progress")) end)
            local bars = ui.menu.bars
            assert.are.equal(bars, topWidget())
            assert.are.equal("progress", ui.menu.panel_name)
            assert.is_true(bars.show_top)
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/progress.bold" end))
            assert.are.same({
                { mode = "ui", region = bars.top_rect },
                { mode = "ui", region = ui.menu.panel:getRefreshRegion():combine(bars.bottom_rect) },
            }, refreshes)
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should turn pages on sideways swipes, without the bars", function()
            local sw, sh = Screen:getWidth(), Screen:getHeight()
            local page = ui:getCurrentPage()
            swipe(sw * 0.7, sh / 2, sw * 0.2, sh / 2)
            assert.are.equal(page + 1, ui:getCurrentPage())
            swipe(sw * 0.2, sh / 2, sw * 0.7, sh / 2)
            assert.are.equal(page, ui:getCurrentPage())
            assert.is_nil(ui.menu.bars)
            assert.are.equal(ui, topWidget())
        end)


        local function openFromToolbar(icon)
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            tapWidget(cell(icon))
            UIManager:forceRePaint()
            return ui.menu.panel
        end

        -- 亮度与色温 is the first row of 更多, whose place its panel takes.
        local function openBrightness()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            tapWidget(moreButton(ui.menu.bars))
            UIManager:forceRePaint()
            tapWidget(find(ui.menu.panel, function(w) return w.text == _("Brightness and warmth") and w.callback end))
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
            local refreshes = refreshesOf(function() tapWidget(cell("eink/progress")) end)
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
            refreshes = refreshesOf(function() tapWidget(cell("eink/progress")) end)
            assert.is_nil(ui.menu.panel)
            assert.are.equal(bars, topWidget())
            assert.are.same({ { mode = "ui", region = rect:combine(bars.bottom_rect) } }, refreshes)
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/progress" end))
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should switch panels in place from the bars, one panel at a time, without turning the page", function()
            local page = ui:getCurrentPage()
            local progress = openFromToolbar("eink/progress")
            local bars = ui.menu.bars
            local windows = #UIManager._window_stack
            -- the top bar's more opens its panel in place of the open one
            local progress_band = progress:getRefreshRegion():combine(bars.bottom_rect)
            local refreshes = refreshesOf(function() tapWidget(moreButton(bars)) end)
            local more = ui.menu.panel
            assert.are.equal("more", ui.menu.panel_name)
            assert.are.equal(bars, topWidget())
            assert.are.equal(windows, #UIManager._window_stack)
            local more_band = more:getRefreshRegion():combine(bars.bottom_rect)
            assert.are.same({ { mode = "ui", region = progress_band:combine(more_band) } }, refreshes)
            assert.is_nil(find(bars.bottom, function(w) return type(w.icon) == "string" and w.icon:find("%.bold$") end))

            -- its 亮度与色温 opens the brightness panel in its place, with both bars
            refreshes = refreshesOf(function()
                tapWidget(find(more, function(w) return w.text == _("Brightness and warmth") and w.callback end))
            end)
            local brightness = ui.menu.panel
            assert.are.equal("brightness", ui.menu.panel_name)
            assert.are.equal(bars, ui.menu.bars)
            assert.are.equal(bars, topWidget())
            assert.is_true(bars.show_top)
            assert.are.equal(windows, #UIManager._window_stack)
            local brightness_band = brightness:getRefreshRegion():combine(bars.bottom_rect)
            assert.are.same({ { mode = "ui", region = more_band:combine(brightness_band) } }, refreshes)

            -- an entry of the bottom bar switches again
            refreshesOf(function() tapWidget(cell("eink/progress")) end)
            assert.are.equal("progress", ui.menu.panel_name)
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/progress.bold" end))
            -- the open entry, below the page's right third, closes only the panel
            tapWidget(moreButton(bars))
            tapWidget(moreButton(bars))
            assert.is_nil(ui.menu.panel)
            assert.are.equal(bars, topWidget())
            assert.are.equal(page, ui:getCurrentPage())
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())
        end)

        it("should leave the page keys to the open panel, without turning the page", function()
            local Key = require("device/key")
            local function pageKey(name) UIManager:sendEvent(Event:new("KeyPress", Key:new(name, {}))) end
            local page = ui:getCurrentPage()
            pageKey("LPgFwd") -- without the toolbar, the key turns the page
            assert.are.equal(page + 1, ui:getCurrentPage())
            pageKey("LPgBack")
            assert.are.equal(page, ui:getCurrentPage())

            local panel = openFromToolbar("eink/progress")
            pageKey("LPgFwd")
            pageKey("LPgBack")
            UIManager:forceRePaint()
            assert.are.equal(page, ui:getCurrentPage())
            assert.are.equal(panel, ui.menu.panel)
            assert.are.equal(ui.menu.bars, topWidget())
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should close the bars and the panel on rotation, and lay them out again for the new screen", function()
            local function runTasks() for _ = 1, 3 do UIManager:_checkTasks() end end
            local panel = openFromToolbar("eink/progress")
            local bars = ui.menu.bars
            assert.is_truthy(panel)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
                runTasks()
                UIManager:forceRePaint()
                assert.is_true(Screen:getWidth() > Screen:getHeight())
                assert.is_nil(ui.menu.bars)
                assert.is_nil(ui.menu.panel)
                for _, window in ipairs(UIManager._window_stack) do
                    assert.are_not.equal(bars, window.widget)
                end
                assert.are.equal(ui, topWidget())

                panel = openFromToolbar("eink/progress")
                local rect = panel:getRefreshRegion()
                assert.are.equal(Screen:getWidth(), rect.w)
                assert.are.equal(Screen:getHeight(), ui.menu.bars.bottom_rect.y + ui.menu.bars.bottom_rect.h)
                assert.are.equal(ui.menu.bars.bottom_rect.y, rect.y + rect.h)
                ui.menu:hideToolbar()
            end)
            ui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
            runTasks()
            UIManager:forceRePaint()
            assert(ok, err)
        end)

        it("should keep the bookmark icon in step with the page the panel jumps to", function()
            local start_page = ui:getCurrentPage()
            local panel = openFromToolbar("eink/progress")
            local bars = ui.menu.bars
            tapWidget(bookmarkButton(bars))
            UIManager:forceRePaint()
            assert.are.equal("eink/bookmark-on", bookmarkButton(bars).icon)

            tapWidget(findText(panel, _("Next chapter")))
            UIManager:forceRePaint()
            assert.are_not.equal(start_page, ui:getCurrentPage())
            assert.are.equal("eink/bookmark", bookmarkButton(bars).icon)

            tapWidget(find(panel, function(w)
                return w.callback and w.dimen and find(w, function(c)
                    return type(c.text) == "string" and c.text:find("Return to last position", 1, true)
                end) ~= nil
            end))
            UIManager:forceRePaint()
            assert.are.equal(start_page, ui:getCurrentPage())
            assert.are.equal("eink/bookmark-on", bookmarkButton(bars).icon)
            tapWidget(bookmarkButton(bars)) -- remove the test bookmark
            UIManager:forceRePaint()
            assert.is_false(ui.bookmark:isPageBookmarked())
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should close the panel and both bars on a tap on the page, without turning the page", function()
            local panel = openFromToolbar("eink/progress")
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
            local panel = openBrightness()
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
            local panel = openBrightness()
            assert.is_truthy(panel)
            tapWidget(moreButton(ui.menu.bars))
            UIManager:forceRePaint()
            local row = find(ui.menu.panel, function(w) return w.text == _("Book details") and w.callback end)
            tapWidget(row)
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
            local panel = openBrightness()
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

    describe("back to the shelf", function()
        it("should close the book and show its folder from the bottom bar's back arrow", function()
            local FileManager = require("apps/filemanager/filemanager")
            local ui = openReader(sample_epub)
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            tapWidget(findIcon(ui.menu.bars.bottom, "eink/arrow.left"))
            local fm = FileManager.instance
            local ok, err = pcall(function()
                assert.is_nil(ui.menu.bars)
                assert.is_nil(ReaderUI.instance)
                assert.is_truthy(fm)
                for _, window in ipairs(UIManager._window_stack) do
                    assert.are_not.equal(ui, window.widget)
                end
            end)
            if fm then fm:onClose() end
            UIManager:forceRePaint()
            assert(ok, err)
        end)
    end)

    describe("taps on the content", function()
        it("should follow a link in the middle of the page instead of showing the bars", function()
            local ui = openReader("spec/front/unit/data/leaves.epub")
            local ok, err = pcall(function()
                ui.rolling:onGotoPage(5)
                UIManager:forceRePaint()
                local x = 320 -- a link, in the middle third
                assert.is_true(x > Screen:getWidth() / 3 and x < Screen:getWidth() * 2 / 3)
                tap(x, 190)
                assert.are.equal(37, ui:getCurrentPage())
                assert.is_nil(ui.menu.bars)
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should open a highlight tapped in the middle of the page, without the bars or a page turn", function()
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                ui.rolling:onGotoPage(10)
                UIManager:forceRePaint()
                ui.highlight:onHold(nil, { pos = Geom:new{ x = 60, y = 110 } })
                ui.highlight:onHoldPan(nil, { pos = Geom:new{ x = 500, y = 170 } })
                ui.highlight:onHoldRelease()
                ui.highlight:saveHighlight()
                ui.highlight:clear()
                if ui.highlight.highlight_dialog then
                    UIManager:close(ui.highlight.highlight_dialog)
                end
                UIManager:forceRePaint()
                local cx = math.floor(Screen:getWidth() / 2)
                local box
                for _, b in ipairs(ui.view.highlight.visible_boxes) do
                    if b.rect.x <= cx and cx < b.rect.x + b.rect.w then
                        box = b.rect
                        break
                    end
                end
                assert.is_truthy(box)
                local page = ui:getCurrentPage()
                tap(cx, box.y + math.floor(box.h / 2))
                assert.is_nil(ui.menu.bars)
                assert.are.equal(page, ui:getCurrentPage())
                assert.are_not.equal(ui, topWidget())
                UIManager:close(topWidget())
                UIManager:forceRePaint()
            end)
            closeReader(ui)
            assert(ok, err)
        end)
    end)

    describe("open-book hint", function()
        local saved
        setup(function()
            saved = G_reader_settings:readSetting("footer")
            G_reader_settings:delSetting("footer")
            ReaderToolbar.applyFooterDefaults() -- nothing but the hint in the middle of the footer line
        end)
        teardown(function()
            G_reader_settings:saveSetting("footer", saved)
        end)

        -- Whether anything is drawn in the middle of the footer line.
        local function hintShown(ui)
            UIManager:forceRePaint()
            local cx, half = math.floor(Screen:getWidth() / 2), Screen:scaleBySize(40)
            return inked(cx - half, Screen:getHeight() - ui.view.footer:getHeight(), cx + half, Screen:getHeight() - 1)
        end

        -- Lets `seconds` pass for the scheduled tasks.
        local function wait(seconds)
            UIManager:shiftScheduledTasksBy(-time.s(seconds))
            UIManager:_checkTasks()
        end

        local function fastRefreshes(refreshes)
            local fast = {}
            for _, r in ipairs(refreshes) do
                if r.mode == "fast" then table.insert(fast, r) end
            end
            return fast
        end

        it("should show on the footer line when a book opens, through page turns, and go after about a minute", function()
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                assert.is_true(hintShown(ui))
                assert.is_truthy(find(ui.view.view_modules.toolbar_hint, function(w)
                    return w.text == _("Swipe up to show the toolbar")
                end))
                tap(Screen:getWidth() - 10, Screen:getHeight() / 2)
                assert.is_true(hintShown(ui))
                -- the footer repainting itself alone (as on resume, frontlight or charging changes) keeps it
                ui:handleEvent(Event:new("FrontlightStateChanged"))
                assert.is_true(hintShown(ui))
                wait(ReaderToolbarHint.TIMEOUT - 2)
                assert.is_true(hintShown(ui))
                -- then it goes with a fast refresh of its own rect, on the footer line
                local refreshes = fastRefreshes(refreshesOf(function() wait(3) end))
                assert.are.equal(1, #refreshes)
                local rect = refreshes[1].region
                local center_y = rect.y + rect.h / 2
                assert.is_true(center_y >= Screen:getHeight() - ui.view.footer:getHeight() and center_y < Screen:getHeight())
                assert.is_true(rect.w < Screen:getWidth() / 2)
                assert.is_false(hintShown(ui))
                -- and page turns don't bring it back
                tap(Screen:getWidth() - 10, Screen:getHeight() / 2)
                assert.is_false(hintShown(ui))
                tap(10, Screen:getHeight() / 2)
                assert.is_false(hintShown(ui))
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should go the first time the bars show, under the bottom bar, and not come back", function()
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                assert.is_true(hintShown(ui))
                local sw, sh = Screen:getWidth(), Screen:getHeight()
                local refreshes = refreshesOf(function() swipe(sw / 2, sh * 0.6, sw / 2, sh * 0.3) end)
                local bars = ui.menu.bars
                assert.is_truthy(bars)
                assert.are.same({
                    { mode = "ui", region = bars.top_rect },
                    { mode = "ui", region = bars.bottom_rect },
                }, refreshes)
                ui.menu:hideToolbar()
                assert.is_false(hintShown(ui))
                assert.are.same({}, fastRefreshes(refreshesOf(function() wait(ReaderToolbarHint.TIMEOUT + 1) end)))
                tap(sw / 2, sh / 2)
                ui.menu:hideToolbar()
                tap(sw - 10, sh / 2)
                assert.is_false(hintShown(ui))
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should come back each time the book opens, but not when a setting reloads it", function()
            local ui = openReader(sample_epub)
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            ui.menu:hideToolbar()
            assert.is_false(hintShown(ui))
            closeReader(ui)
            ui = openReader(sample_epub, true)
            assert.is_true(hintShown(ui))
            -- what changing some settings does: the reader closes and opens the book again
            ui:reloadDocument()
            for _ = 1, 3 do UIManager:_checkTasks() end
            local reloaded = ReaderUI.instance
            assert.is_truthy(reloaded)
            assert.are_not.equal(ui, reloaded)
            assert.is_false(hintShown(reloaded))
            closeReader(reloaded)
        end)

        it("should not cover the text near the bottom when the footer is hidden", function()
            -- with the footer's height reclaimed, hiding it lets the text run down to the bottom margin
            local footer_settings = G_reader_settings:readSetting("footer")
            footer_settings.reclaim_height = true
            local ui = openReader(sample_epub)
            local rect
            -- The darkest pixel where the hint shows: its pencil gray over its paper, or the book's ink without it.
            local function darkest()
                UIManager:forceRePaint()
                local v = 0xFF
                for y = rect.y, rect.y + rect.h - 1 do
                    for x = rect.x, rect.x + rect.w - 1 do
                        v = math.min(v, Screen.bb:getPixel(x, y):getColor8().a)
                    end
                end
                return v
            end
            local ok, err = pcall(function()
                ui.rolling:onGotoPage(10)
                assert.is_true(hintShown(ui))
                rect = ui.view.view_modules.toolbar_hint.dimen:copy()
                assert.is_true(darkest() >= 0x40) -- the hint, gray on paper
                -- the reader hides the footer: the text now reaches the hint's line, and shows there
                ui:handleEvent(Event:new("ToggleFooterMode"))
                assert.is_false(ui.view.footer_visible)
                assert.is_true(darkest() < 0x20)
                -- and the hint doesn't come back with the footer
                ui:handleEvent(Event:new("ToggleFooterMode"))
                assert.is_true(ui.view.footer_visible)
                assert.is_false(hintShown(ui))
                ui:handleEvent(Event:new("ToggleFooterMode"))
            end)
            closeReader(ui)
            assert(ok, err)
            -- a book opened with the footer hidden gets no hint over its last line
            ui = openReader(sample_epub, true)
            ok, err = pcall(function()
                assert.is_false(ui.view.footer_visible)
                assert.is_true(darkest() < 0x20)
            end)
            ui:handleEvent(Event:new("ToggleFooterMode")) -- the footer back on, as the other tests expect
            closeReader(ui)
            footer_settings.reclaim_height = false
            assert(ok, err)
        end)

        it("should not show when Activate menu leaves swipes out, which then don't show the bars", function()
            local saved_activation = G_reader_settings:readSetting("activate_menu")
            G_reader_settings:saveSetting("activate_menu", "tap") -- the original menu's 激活菜单 without 滑动
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                assert.is_false(hintShown(ui))
                local sw, sh = Screen:getWidth(), Screen:getHeight()
                swipe(sw / 2, sh * 0.6, sw / 2, sh * 0.3)
                swipe(sw / 2, sh - 5, sw / 2, sh * 0.7)
                UIManager:forceRePaint()
                assert.is_nil(ui.menu.bars)
                assert.is_nil(ui.config.config_dialog)
                assert.are.equal(ui, topWidget())
                -- the middle still takes taps
                tap(sw / 2, sh / 2)
                assert.are.equal(ui.menu.bars, topWidget())
                ui.menu:hideToolbar()
            end)
            closeReader(ui)
            G_reader_settings:saveSetting("activate_menu", saved_activation)
            assert(ok, err)
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
            tapWidget(findIcon(bars.bottom, "eink/progress"))
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
            tapWidget(findIcon(ui.menu.bars.bottom, "eink/font"))
            UIManager:forceRePaint()
            assert.is_nil(ui.menu.bars)
            assert.is_nil(ui.menu.panel)
            assert.is_truthy(ui.config.config_dialog)
            assert.are.equal(ui.config.config_dialog, topWidget())
            ui.config.config_dialog:closeDialog()
            UIManager:forceRePaint()
            closeReader(ui)
        end)

        it("should leave swipes to page flipping mode", function()
            local ui = openReader(sample_pdf)
            local ok, err = pcall(function()
                ui.paging:onGotoPage(3)
                ui:handleEvent(Event:new("TogglePageFlipping"))
                assert.is_true(ui.paging.page_flipping_mode)
                ui.paging:onGotoPage(5)
                swipe(Screen:getWidth() / 2, Screen:getHeight() * 0.6, Screen:getWidth() / 2, Screen:getHeight() * 0.3)
                assert.is_nil(ui.menu.bars)
                -- a swipe goes back to the page flipping started from
                assert.are.equal(3, ui:getCurrentPage())
                ui:handleEvent(Event:new("TogglePageFlipping"))
                UIManager:forceRePaint()
            end)
            closeReader(ui)
            assert(ok, err)
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

        -- The time at the left, the page / pages at the right, nothing else.
        local function isNewDefault(footer)
            return footer.time and footer.page_progress and footer.dynamic_filler and footer.disable_progress_bar
                and not (footer.chapter_progress or footer.percentage or footer.battery or footer.pages_left)
                and footer.order[1] == "time" and footer.order[2] == "dynamic_filler" and footer.order[3] == "page_progress"
        end

        it("should fill in the footer when nothing is saved", function()
            ReaderToolbar.applyFooterDefaults()
            assert.is_true(isNewDefault(G_reader_settings:readSetting("footer")))
        end)

        it("should replace a footer still equal to upstream's defaults", function()
            G_reader_settings:saveSetting("footer", require("util").tableDeepCopy(
                require("apps/reader/modules/readerfooter").default_settings))
            ReaderToolbar.applyFooterDefaults()
            assert.is_true(isNewDefault(G_reader_settings:readSetting("footer")))
        end)

        it("should replace the first round's default footer, but not once changed", function()
            local util = require("util")
            local first_round = util.tableDeepCopy(require("apps/reader/modules/readerfooter").default_settings)
            for k, v in pairs{
                page_progress = false, pages_left = false, book_time_to_read = false, chapter_time_to_read = false,
                chapter_progress = true, percentage = true, time = true, battery = require("device"):hasBattery(),
                dynamic_filler = true, all_at_once = true, disable_progress_bar = true,
                item_prefix = "compact_items", items_separator = "none", text_font_size = 12,
            } do
                first_round[k] = v
            end
            first_round.order = { [0] = "off", "chapter_progress", "dynamic_filler", "percentage", "time", "battery" }
            local changed = util.tableDeepCopy(first_round)
            G_reader_settings:saveSetting("footer", first_round)
            ReaderToolbar.applyFooterDefaults()
            assert.is_true(isNewDefault(G_reader_settings:readSetting("footer")))

            changed.battery = not changed.battery
            G_reader_settings:saveSetting("footer", changed)
            ReaderToolbar.applyFooterDefaults()
            assert.are.equal(changed, G_reader_settings:readSetting("footer"))
            assert.is_true(G_reader_settings:readSetting("footer").chapter_progress)
        end)

        -- The footer's text, with the hair spaces of compact items as spaces.
        local function footerText(ui)
            return (ui.view.footer.footer_text.text:gsub("\u{200A}", " "))
        end

        it("should show the time at the left and the page / pages at the right, lined up with the text", function()
            ReaderToolbar.applyFooterDefaults()
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                ui.rolling:onGotoPage(5)
                UIManager:forceRePaint()
                local footer = ui.view.footer
                assert.is_true(ui.view.footer_visible)
                local text = footerText(ui)
                local clock, page, pages = text:match("^(%d+:%d%d)%s+(%d+) / (%d+)$")
                assert.is_truthy(clock, text)
                assert.are.equal(ui:getCurrentPage(), tonumber(page))
                assert.are.equal(ui.document:getPageCount(), tonumber(pages))
                -- both ends line up with the page's text, give or take a filler space
                local margins = ui.document:getPageMargins()
                local box = footer.text_container.dimen
                local space = footer.filler_space_width
                assert.is_true(math.abs(box.x - margins.left) <= space, box.x .. " vs " .. margins.left)
                assert.is_true(math.abs(Screen:getWidth() - margins.right - (box.x + box.w)) <= space)
                -- and follow the margins when they change
                ui:handleEvent(Event:new("SetPageHorizMargins", { 44, 44 }))
                UIManager:forceRePaint()
                margins = ui.document:getPageMargins()
                assert.are.equal(Screen:scaleBySize(44), margins.left)
                box = footer.text_container.dimen
                assert.is_true(math.abs(box.x - margins.left) <= space, box.x .. " vs " .. margins.left)
                assert.is_true(math.abs(Screen:getWidth() - margins.right - (box.x + box.w)) <= space)
                -- in the reference's serif, 11dp, on a line centered 33dp above the bottom
                assert.is_truthy(footer.settings.text_font_face:find("NotoSerif%-Regular"))
                assert.are.equal(11, footer.settings.text_font_size)
                assert.is_true(math.abs(Screen:scaleBySize(33) - (footer.bottom_padding + math.floor(footer.height / 2))) <= 1)
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should keep the same text on the page when a reflow or a new opening renumbers the pages", function()
            ReaderToolbar.applyFooterDefaults()
            local ui = openReader(sample_epub)
            local xp, pages
            local ok, err = pcall(function()
                ui.rolling:onGotoPage(12)
                UIManager:forceRePaint()
                xp = ui.rolling:getBookLocation()
                pages = ui.document:getPageCount()
                ui:handleEvent(Event:new("SetFontSize", ui.document.configurable.font_size + 6))
                UIManager:forceRePaint()
                assert.is_true(ui.document:isXPointerInCurrentPage(xp))
                assert.are_not.equal(pages, ui.document:getPageCount())
                -- the footer shows the new numbering, not the old one
                assert.is_truthy(footerText(ui):find(ui:getCurrentPage() .. " / " .. ui.document:getPageCount(), 1, true))
                pages = ui.document:getPageCount()
            end)
            ui:onClose()
            assert(ok, err)
            ui = openReader(sample_epub, true)
            ok, err = pcall(function()
                assert.is_true(ui.document:isXPointerInCurrentPage(xp))
                assert.are.equal(pages, ui.document:getPageCount())
                assert.is_truthy(footerText(ui):find(ui:getCurrentPage() .. " / " .. pages, 1, true))
            end)
            closeReader(ui)
            assert(ok, err)
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
    describe("with the gestures plugin", function()
        local DataStorage, LuaSettings, util
        local gestures_file
        setup(function()
            DataStorage = require("datastorage")
            LuaSettings = require("luasettings")
            util = require("util")
            -- a reader's own edge gesture: a swipe up along the left edge toggles the bookmark
            gestures_file = DataStorage:getSettingsDir() .. "/gestures.lua"
            local data = util.tableDeepCopy(LuaSettings:open("plugins/gestures.koplugin/defaults.lua").data)
            data.gesture_reader.one_finger_swipe_left_edge_up = { toggle_bookmark = true }
            local settings = LuaSettings:open(gestures_file)
            settings.data = data
            settings:flush()
            load_plugin("gestures.koplugin")
        end)
        teardown(function()
            disable_plugins()
            os.remove(gestures_file)
        end)

        it("should leave its edge gestures their priority over the swipe up", function()
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                assert.is_truthy(ui.gestures)
                local sh = Screen:getHeight()
                assert.is_false(ui.bookmark:isPageBookmarked())
                swipe(5, sh * 0.6, 5, sh * 0.3)
                assert.is_true(ui.bookmark:isPageBookmarked())
                assert.is_nil(ui.menu.bars)
                -- elsewhere, the swipe up shows the bars
                swipe(Screen:getWidth() / 2, sh * 0.6, Screen:getWidth() / 2, sh * 0.3)
                assert.are.equal(ui.menu.bars, topWidget())
                ui.menu:hideToolbar()
                ui.bookmark:onToggleBookmark()
                UIManager:forceRePaint()
            end)
            closeReader(ui)
            assert(ok, err)
        end)
    end)
end)
