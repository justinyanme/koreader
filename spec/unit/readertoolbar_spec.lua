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

    local function closeToasts()
        for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i].widget
            if w.toast then UIManager:close(w) end
        end
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

    -- A finger that went down at (x0, y0) and is now at (x, y), as GestureDetector reports it while it moves
    -- ("pan", or `ges` such as "hold_pan"); with `end_swipe`, it lifts there and the swipe is reported from where
    -- it started.
    local function moveEvent(x0, y0, x, y, at, end_swipe, ges)
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
                ges = ges or "pan", direction = direction(dx, dy), distance = distance, relative = { x = dx, y = dy },
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

    -- Read the adjacent number and unit within one of the three visible statistics columns.
    local function statisticValues(panel, index)
        local column = panel.content[1][2 * index - 1]
        local row = find(column, function(w)
            return w[1] and w[2] and w[1].text and w[2].text
        end)
        assert.is_truthy(row)
        return { row[1].text, row[2].text }
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
        return find(bars.top, function(w) return (w.icon == "eink/bookmark-add" or w.icon == "eink/bookmark-on") and w.callback end)
    end

    -- The progress panel's ‹ 返回原进度 pill, while it shows.
    local function returnPill(panel)
        return find(panel, function(w)
            return w.callback and w.dimen and find(w, function(c) return c.text == _("Back to original position") end) ~= nil
        end)
    end

    for __, file in ipairs{ sample_epub, sample_pdf } do
        it("should synchronize the bookmark, marker and toast across reopening " .. file, function()
            local ui = openReader(file)
            if ui.rolling then
                ui:handleEvent(Event:new("SetPageMargins", { 60, 60, 60, 60 }))
                UIManager:forceRePaint()
            end
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local top_rect = ui.menu.bars.top_rect:copy()
            local refreshes = refreshesOf(function() tapWidget(bookmarkButton(ui.menu.bars)) end)
            assert.is_nil(ui.menu.bars)
            assert.is_true(ui.view.dogear_visible)
            assert.are.equal(_("Bookmark added"), topWidget().text)
            local marker = ui.view.dogear:getRefreshRegion()
            assert.are.equal(Screen:scaleBySize(17), marker.w)
            assert.are.equal(Screen:scaleBySize(42), marker.h)
            assert.are.equal(Screen:getWidth() - Screen:scaleBySize(25) - marker.w, marker.x)
            assert.is_true(inked(marker.x, marker.y, marker.x + marker.w, marker.y + marker.h))
            for _, r in ipairs(refreshes) do
                assert.is_true(r.mode == "ui" or r.mode == "fast")
                assert.is_true(r.region.h < Screen:getHeight())
                if r.mode == "fast" then assert.is_false(top_rect:contains(r.region)) end
            end
            closeToasts()
            closeReader(ui)
            ui = openReader(file, true)
            assert.is_true(ui.view.dogear_visible)
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            assert.are.equal("eink/bookmark-on", bookmarkButton(ui.menu.bars).icon)
            tapWidget(bookmarkButton(ui.menu.bars))
            assert.is_nil(ui.menu.bars)
            assert.is_false(ui.view.dogear_visible)
            assert.are.equal(_("Bookmark removed"), topWidget().text)
            closeToasts()
            closeReader(ui)
            ui = openReader(file, true)
            assert.is_false(ui.view.dogear_visible)
            closeReader(ui)
        end)
    end

    it("should mirror the ribbon and follow margins, the header and view mode", function()
        local BD = require("ui/bidi")
        for __, language in ipairs{ "en", "ar" } do
            BD.setup(language)
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetPageMargins", { 60, 60, 60, 60 }))
                ui:handleEvent(Event:new("SetStatusLine", 0))
                UIManager:forceRePaint()
                tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
                UIManager:forceRePaint()
                tapWidget(bookmarkButton(ui.menu.bars))
                closeToasts()
                UIManager:forceRePaint()
                local marker = ui.view.dogear:getRefreshRegion()
                assert.are.equal(Screen:scaleBySize(42), marker.h)
                assert.are.equal(language == "ar" and Screen:scaleBySize(25)
                    or Screen:getWidth() - Screen:scaleBySize(25) - marker.w, marker.x)
                assert.is_true(ui.document:getHeaderHeight() > 0)
                assert.are.equal(ui.document:getHeaderHeight(), marker.y)
                ui:handleEvent(Event:new("SetPageMargins", { 10, 10, 10, 10 }))
                UIManager:forceRePaint()
                marker = ui.view.dogear:getRefreshRegion()
                assert.are.equal(Screen:scaleBySize(17), marker.h)
                assert.are.equal(ui.document:getHeaderHeight(), marker.y)
                ui:handleEvent(Event:new("SetViewMode", "scroll"))
                UIManager:forceRePaint()
                assert.are.equal(0, ui.view.dogear:getRefreshRegion().y)
                ui:handleEvent(Event:new("SetViewMode", "page"))
                ui:handleEvent(Event:new("SetFontSize", 24))
                UIManager:forceRePaint()
                assert.are.equal(ui.document:getHeaderHeight(), ui.view.dogear:getRefreshRegion().y)
            end)
            closeToasts()
            closeReader(ui)
            BD.setup(G_reader_settings:readSetting("language") or "en")
            assert(ok, err)
        end
    end)

    it("should toggle a bookmark in scroll mode and restore it on reopening", function()
        local ui = openReader(sample_epub)
        ui:handleEvent(Event:new("SetViewMode", "scroll"))
        ui:handleEvent(Event:new("GotoPos", 400))
        UIManager:forceRePaint()
        local function toggle()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            tapWidget(bookmarkButton(ui.menu.bars))
            UIManager:forceRePaint()
        end
        toggle()
        assert.is_true(ui.view.dogear_visible)
        assert.are.equal(0, ui.view.dogear:getRefreshRegion().y)
        assert.are.equal(_("Bookmark added"), topWidget().text)
        closeToasts()
        closeReader(ui)
        ui = openReader(sample_epub, true)
        assert.is_true(ui.view.dogear_visible)
        ui:handleEvent(Event:new("SetViewMode", "scroll"))
        UIManager:forceRePaint()
        toggle()
        assert.is_false(ui.view.dogear_visible)
        assert.are.equal(_("Bookmark removed"), topWidget().text)
        closeToasts()
        closeReader(ui)
    end)

    it("should keep the marker until the last bookmark on a reflowed page is removed", function()
        local ui = openReader(sample_epub)
        local ok, err = pcall(function()
            ui:handleEvent(Event:new("SetFontSize", 64))
            local anchors = {}
            for page = 10, 11 do
                ui:handleEvent(Event:new("GotoPage", page))
                UIManager:forceRePaint()
                table.insert(anchors, ui.document:getXPointer())
                tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
                UIManager:forceRePaint()
                tapWidget(bookmarkButton(ui.menu.bars))
                closeToasts()
            end
            assert.are.equal(2, #ui.annotation.annotations)
            ui:handleEvent(Event:new("SetFontSize", 10))
            ui:handleEvent(Event:new("GotoXPointer", anchors[1]))
            UIManager:forceRePaint()
            assert.are.equal(ui.document:getPageFromXPointer(anchors[1]), ui.document:getPageFromXPointer(anchors[2]))
            for remaining = 1, 0, -1 do
                tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
                UIManager:forceRePaint()
                assert.are.equal("eink/bookmark-on", bookmarkButton(ui.menu.bars).icon)
                tapWidget(bookmarkButton(ui.menu.bars))
                UIManager:forceRePaint()
                assert.are.equal(remaining, #ui.annotation.annotations)
                assert.are.equal(remaining > 0, ui.view.dogear_visible)
                assert.are.equal(_("Bookmark removed"), topWidget().text)
                closeToasts()
            end
        end)
        closeToasts()
        closeReader(ui)
        assert(ok, err)
    end)

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

        it("should put bookmark, shelf state and more at the right of the top bar, in that order, with no back or search", function()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local bars = ui.menu.bars
            local sw = Screen:getWidth()
            assert.are.equal(Screen:scaleBySize(50), bars.top_rect.h)
            local bookmark, more = bookmarkButton(bars), moreButton(bars)
            local shelf = findIcon(bars.top, "eink/shelf")
            assert.is_truthy(shelf)
            assert.is_truthy(bookmark)
            assert.is_truthy(more)
            assert.are.equal(sw, more.dimen.x + more.dimen.w)
            assert.are.equal(shelf.dimen.x, bookmark.dimen.x + bookmark.dimen.w)
            assert.are.equal(more.dimen.x, shelf.dimen.x + shelf.dimen.w)
            -- 76dp apart, as in WeChat Read
            assert.are.equal(Screen:scaleBySize(76), shelf.dimen.x - bookmark.dimen.x)
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

            local track = find(panel, function(w) return w.on_jump ~= nil end)
            tap(track.dimen.x + track.width - track.end_width / 2, track.dimen.y + track.dimen.h / 2)
            assert.are.equal(next_chapter, ui:getCurrentPage())
            assert.are.equal(panel, ui.menu.panel)
            assert.are.equal(bars, topWidget())
            UIManager:forceRePaint()
            assert.is_truthy(returnPill(panel))

            -- its own entry closes the panel; the bars stay, the pill goes with the panel
            rect = panel:getRefreshRegion()
            local pill_rect = returnPill(panel).dimen:copy()
            refreshes = refreshesOf(function() tapWidget(cell("eink/progress")) end)
            assert.is_nil(ui.menu.panel)
            assert.are.equal(bars, topWidget())
            assert.are.same({
                { mode = "ui", region = pill_rect },
                { mode = "ui", region = rect:combine(bars.bottom_rect) },
            }, refreshes)
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/progress" end))

            -- while the bars show, the panel comes back with the way back to where the reader was
            tapWidget(cell("eink/progress"))
            UIManager:forceRePaint()
            tapWidget(returnPill(ui.menu.panel))
            UIManager:forceRePaint()
            assert.are.equal(start_page, ui:getCurrentPage())
            assert.is_nil(ui.menu.bars)
            assert.are.equal(ui, topWidget())
        end)

        it("should show measured book statistics and omit estimates without timed pages", function()
            local T = require("ffi/util").template
            local function has(panel, str)
                return find(panel, function(w) return w.text == str end) ~= nil
            end
            local panel = openFromToolbar("eink/progress")
            assert.are.same({ tostring(math.floor(ui:getCurrentPage() / ui.document:getPageCount() * 100)), "%" }, statisticValues(panel, 1))
            assert.are.same({ "—", "" }, statisticValues(panel, 2)) -- unavailable, not a made-up duration
            ui.menu:hideToolbar()
            for _, stats in ipairs{
                { book_read_pages = 0, mem_read_pages = 0, avg_time = 300 }, -- plugin's unread-book seed
                { book_read_pages = 2, avg_time = 0 / 0 },
                { book_read_pages = 2, avg_time = math.huge },
                { book_read_pages = 2, avg_time = 60, disabled = true },
            } do
                stats.isEnabled = function(self) return not self.disabled end
                ui.statistics = stats
                panel = openFromToolbar("eink/progress")
                assert.is_nil(find(panel, function(w)
                    return type(w.text) == "string" and w.text:find("About", 1, true)
                end))
                ui.menu:hideToolbar()
            end
            ui.statistics = {
                isEnabled = function() return true end,
                book_read_time = 1440, mem_read_time = 75, book_read_pages = 24, mem_read_pages = 1, avg_time = 60.6,
            }
            panel = openFromToolbar("eink/progress")
            local hours = math.ceil(60.6 * (ui.document:getPageCount() - ui:getCurrentPage()) / 3600)
            assert.is_true(has(panel, T(_.ngettext("About 1 hour left", "About %1 hours left", hours), hours)))
            assert.are.same({ "25", _.pgettext("Time", "min") }, statisticValues(panel, 2))
            assert.is_true(has(panel, _("Reading time")))
            ui.menu:hideToolbar()
            ui.statistics.book_read_time = 7200
            ui.statistics.mem_read_time = 0
            panel = openFromToolbar("eink/progress")
            assert.are.same({ "2.0", _.pgettext("Time", "h") }, statisticValues(panel, 2))
            ui.menu:hideToolbar()
            local lang = _.current_lang
            _.changeLang("zh_CN")
            panel = openFromToolbar("eink/progress")
            local translated_hours = statisticValues(panel, 2)
            local translated_caption = has(panel.content[1][3], "阅读时长")
            local translated_estimate = has(panel.content[1][1], "约 " .. hours .. " 小时后读完")
            local translated_notes = statisticValues(panel, 3)
            ui.menu:hideToolbar()
            ui.statistics.book_read_time = 25 * 60
            panel = openFromToolbar("eink/progress")
            local translated_minutes = statisticValues(panel, 2)
            _.changeLang(lang)
            assert.are.same({ "2.0", "小时" }, translated_hours)
            assert.are.same({ "25", "分钟" }, translated_minutes)
            assert.are.same({ tostring(ui.annotation:getNumberOfAnnotations()), " 条" }, translated_notes)
            assert.is_true(translated_estimate)
            assert.is_true(translated_caption)
            ui.statistics = nil
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should hide the Chinese estimate on the last page even with measured statistics", function()
            local page, lang = ui:getCurrentPage(), _.current_lang
            ui.statistics = {
                isEnabled = function() return true end,
                book_read_time = 120, book_read_pages = 2, avg_time = 60,
            }
            _.changeLang("zh_CN")
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("GotoPage", ui.document:getPageCount()))
                local panel = openFromToolbar("eink/progress")
                assert.are.same({ "100", "%" }, statisticValues(panel, 1))
                assert.are.same({ "2", "分钟" }, statisticValues(panel, 2))
                assert.is_nil(find(panel, function(w)
                    return type(w.text) == "string" and w.text:find("约", 1, true)
                end))
            end)
            _.changeLang(lang)
            ui.statistics = nil
            ui.menu:hideToolbar()
            ui:handleEvent(Event:new("GotoPage", page))
            UIManager:forceRePaint()
            assert(ok, err)
        end)

        it("should calculate the percentage and remaining time within the current hidden flow", function()
            local flow_page = 2
            local mocks = {
                stub(ui.document, "hasHiddenFlows", function() return true end),
                stub(ui.document, "getPageFlow", function() return 1 end),
                stub(ui.document, "getPageNumberInFlow", function() return flow_page end),
                stub(ui.document, "getTotalPagesInFlow", function(_, flow)
                    assert.are.equal(1, flow)
                    return 4
                end),
            }
            ui.statistics = {
                isEnabled = function() return true end,
                book_read_time = 3600, book_read_pages = 1, avg_time = 3600,
            }
            local ok, err = pcall(function()
                local panel = openFromToolbar("eink/progress")
                assert.are.same({ "50", "%" }, statisticValues(panel, 1))
                assert.is_truthy(find(panel.content[1][1], function(w) return w.text == "About 2 hours left" end))
                ui.menu:hideToolbar()
                flow_page = 3
                ui.statistics.avg_time = 0.5 -- a positive remainder still needs at least one hour
                panel = openFromToolbar("eink/progress")
                assert.are.same({ "75", "%" }, statisticValues(panel, 1))
                assert.is_truthy(find(panel.content[1][1], function(w) return w.text == "About 1 hour left" end))
                ui.menu:hideToolbar()
                flow_page = 4
                panel = openFromToolbar("eink/progress")
                assert.are.same({ "100", "%" }, statisticValues(panel, 1))
                assert.is_nil(find(panel, function(w)
                    return type(w.text) == "string" and w.text:find("About", 1, true)
                end))
            end)
            for _, mock in ipairs(mocks) do mock:revert() end
            ui.statistics = nil
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
            assert(ok, err)
        end)

        it("should navigate chapters from the capsule ends, disable boundaries, and retain a tapped position", function()
            local start_page = ui:getCurrentPage()
            ui:handleEvent(Event:new("GotoPage", 1))
            local panel = openFromToolbar("eink/progress")
            local function track() return find(panel, function(w) return w.on_jump ~= nil end) end
            local function endTap(right)
                local t = track()
                tap(t.dimen.x + (right and t.width - t.end_width / 2 or t.end_width / 2), t.dimen.y + t.dimen.h / 2)
                UIManager:forceRePaint()
            end
            assert.is_nil(track().previous_chapter)
            endTap(false)
            assert.are.equal(1, ui:getCurrentPage())
            local next_chapter = ui.toc:getNextChapter(1)
            endTap(true)
            assert.are.equal(next_chapter, ui:getCurrentPage())
            assert.is_nil(track().previous_chapter)
            endTap(false)
            assert.are.equal(next_chapter, ui:getCurrentPage())
            endTap(true)
            assert.are_not.equal(next_chapter, ui:getCurrentPage())
            endTap(false)
            assert.are.equal(next_chapter, ui:getCurrentPage())
            local t = track()
            tap(t.dimen.x + t.width / 2, t.dimen.y + t.dimen.h / 2)
            UIManager:forceRePaint()
            local middle = ui:getCurrentPage()
            assert.is_true(math.abs(middle / ui.document:getPageCount() - 0.5) < 0.02)
            ui.menu:hideToolbar()
            closeReader(ui)
            ui = openReader(sample_epub, true)
            assert.are.equal(middle, ui:getCurrentPage())
            ui:handleEvent(Event:new("GotoPage", ui.document:getPageCount()))
            panel = openFromToolbar("eink/progress")
            assert.is_nil(track().next_chapter)
            endTap(true)
            assert.are.equal(ui.document:getPageCount(), ui:getCurrentPage())
            ui.menu:hideToolbar()
            ui:handleEvent(Event:new("GotoPage", start_page))
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
            openFromToolbar("eink/progress")
            local bars = ui.menu.bars
            tapWidget(bookmarkButton(bars))
            assert.is_nil(ui.menu.bars)
            closeToasts()
            local panel = openFromToolbar("eink/progress")
            bars = ui.menu.bars
            assert.are.equal("eink/bookmark-on", bookmarkButton(bars).icon)
            assert.are.same({ "1", " " .. _.ngettext("item", "items", 1) }, statisticValues(panel, 3))

            local track = find(panel, function(w) return w.on_jump ~= nil end)
            tap(track.dimen.x + track.width - track.end_width / 2, track.dimen.y + track.dimen.h / 2)
            UIManager:forceRePaint()
            assert.are_not.equal(start_page, ui:getCurrentPage())
            assert.are.equal("eink/bookmark-add", bookmarkButton(bars).icon)

            tapWidget(returnPill(panel))
            UIManager:forceRePaint()
            assert.are.equal(start_page, ui:getCurrentPage())
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            bars = ui.menu.bars
            assert.are.equal("eink/bookmark-on", bookmarkButton(bars).icon)
            tapWidget(bookmarkButton(bars)) -- remove the test bookmark
            UIManager:forceRePaint()
            assert.is_false(ui.bookmark:isPageBookmarked())
            closeToasts()
            panel = openFromToolbar("eink/progress")
            assert.are.same({ "0", " " .. _.ngettext("item", "items", 0) }, statisticValues(panel, 3))
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

    describe("progress drag and 原进度", function()
        local Palette
        local clock
        setup(function()
            Palette = require("ui/palette")
            clock = time.now()
        end)

        local function point(x, y)
            return Geom:new{ x = math.floor(x), y = math.floor(y), w = 0, h = 0 }
        end

        -- The finger went down at `from` and is now at `to`: "pan", or "hold_pan" after a hold. Each comes a second
        -- after the last, past the track's rate limit.
        local function pan(from, to, ges)
            clock = clock + time.s(1)
            moveEvent(from.x, from.y, to.x, to.y, clock, false, ges)
        end

        -- The finger lifts at `pos` after moving slowly ("pan_release"), or after a hold ("hold_release").
        local function lift(pos, ges)
            clock = clock + time.s(1)
            UIManager:sendEvent(Event:new("Gesture", { ges = ges or "pan_release", pos = pos, time = clock }))
        end

        local function openProgress(ui)
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            tapWidget(findIcon(ui.menu.bars.bottom, "eink/progress"))
            UIManager:forceRePaint()
            return ui.menu.panel
        end

        local function progressTrack(panel)
            return find(panel, function(w) return w.on_jump ~= nil end)
        end

        -- The track's middle line, where the knob of `page` sits.
        local function onTrack(track, page)
            return point(track.dimen.x + track:xOf(page), track.dimen.y + track.dimen.h / 2)
        end

        -- The track's middle line at `fraction` of its width.
        local function along(track, fraction)
            return point(track.dimen.x + track.width * fraction, track.dimen.y + track.dimen.h / 2)
        end

        -- The gray level painted at `pos`: 0 is ink, 0xFF paper.
        local function shade(pos)
            return Screen.bb:getPixel(pos.x, pos.y):getColor8().a
        end

        local function countMode(refreshes, mode)
            local n = 0
            for _, r in ipairs(refreshes) do
                if r.mode == mode then n = n + 1 end
            end
            return n
        end

        -- The index of the first refresh of `mode` on exactly `rect`, if any.
        local function refreshIndex(refreshes, mode, rect)
            for i, r in ipairs(refreshes) do
                local g = r.region
                if r.mode == mode and g and g.x == rect.x and g.y == rect.y and g.w == rect.w and g.h == rect.h then
                    return i
                end
            end
        end

        local function firstIndex(refreshes, mode)
            for i, r in ipairs(refreshes) do
                if r.mode == mode then return i end
            end
        end

        local function percentFigure(ui, page)
            return { tostring(math.floor(page / ui.document:getPageCount() * 100)), "%" }
        end

        it("should only preview while the knob is dragged, and jump once when it is let go", function()
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                local start = ui:getCurrentPage()
                local panel = openProgress(ui)
                local track = progressTrack(panel)
                local band = panel:getRefreshRegion()
                local from = onTrack(track, start)
                local to = along(track, 3/4)
                local target = track:pageAt(to.x)
                local stack = #ui.link.location_stack
                local refreshes = refreshesOf(function()
                    for _, x in ipairs{ from.x + 40, along(track, 1/2).x, to.x } do
                        pan(from, point(x, from.y))
                    end
                end)
                -- the page stays; the knob and the position figure follow the finger, with ui refreshes of their own
                assert.are.equal(start, ui:getCurrentPage())
                assert.are.equal(stack, #ui.link.location_stack)
                assert.are.same(percentFigure(ui, target), statisticValues(panel, 1))
                assert.is_true(#refreshes > 0)
                for _, r in ipairs(refreshes) do
                    assert.are.equal("ui", r.mode)
                    assert.is_true(band:contains(r.region))
                end
                -- the held knob is ink; a gray dot marks where the reader is
                assert.are.equal(0, shade(onTrack(track, target)))
                assert.are.equal(Palette.mark.a, shade(from))

                -- the finger may leave the track: letting go still ends the drag, with one jump
                refreshes = refreshesOf(function() lift(point(to.x, track.dimen.y - 30)) end)
                assert.are.equal(target, ui:getCurrentPage())
                assert.are.equal(stack + 1, #ui.link.location_stack)
                assert.is_truthy(firstIndex(refreshes, "partial"))
                assert.are.same(percentFigure(ui, target), statisticValues(panel, 1))
                track = progressTrack(panel)
                assert.are.equal(0xFF, shade(onTrack(track, target))) -- the knob rests: paper again
                assert.are.equal(start, track.origin_page)
                assert.are.equal(Palette.mark.a, shade(onTrack(track, start)))
                -- ‹ 返回原进度 sits centered just above the panel
                local pill = returnPill(panel)
                assert.is_truthy(pill)
                local rect = panel:getRefreshRegion()
                assert.is_true(pill.dimen.y + pill.dimen.h <= rect.y)
                assert.is_true(rect.y - (pill.dimen.y + pill.dimen.h) < Screen:scaleBySize(26))
                assert.are.equal(math.floor((Screen:getWidth() - pill.dimen.w) / 2), pill.dimen.x)

                -- a drag let go where it started does not jump
                stack = #ui.link.location_stack
                local here = onTrack(track, target)
                pan(here, point(here.x + 60, here.y))
                assert.are_not.same(percentFigure(ui, target), statisticValues(panel, 1))
                refreshes = refreshesOf(function() lift(here) end)
                assert.are.equal(target, ui:getCurrentPage())
                assert.are.equal(stack, #ui.link.location_stack)
                assert.is_nil(firstIndex(refreshes, "partial"))
                assert.are.same(percentFigure(ui, target), statisticValues(panel, 1))
                assert.are.equal(0xFF, shade(onTrack(track, target)))

                -- drags that start off the track, or go up or down along it, move nothing
                for _, path in ipairs{
                    { point(here.x, track.dimen.y - 40), point(here.x + 200, track.dimen.y - 40) },
                    { here, point(here.x + 10, here.y - 120) },
                } do
                    pan(path[1], path[2])
                    lift(path[2])
                    assert.are.equal(target, ui:getCurrentPage())
                    assert.are.equal(stack, #ui.link.location_stack)
                    assert.are.same(percentFigure(ui, target), statisticValues(panel, 1))
                end

                -- a quick drag ends as a swipe, reported from where it started
                local quick = along(track, 1/4)
                local quick_target = track:pageAt(quick.x)
                moveEvent(here.x, here.y, quick.x, quick.y, time.now(), true)
                UIManager:forceRePaint()
                assert.are.equal(quick_target, ui:getCurrentPage())
                assert.are.equal(stack + 1, #ui.link.location_stack)
                assert.are.equal(start, progressTrack(panel).origin_page)
                ui.menu:hideToolbar()
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should keep the first 原进度 through later jumps, mark it with a dot that takes no tap, and go back to it", function()
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("GotoPage", 5))
                UIManager:forceRePaint()
                local start = ui:getCurrentPage()
                local anchor = ui.rolling:getBookLocation()
                local panel = openProgress(ui)
                local bars = ui.menu.bars
                local track = progressTrack(panel)
                assert.is_nil(track.origin_page)
                assert.is_nil(returnPill(panel))

                -- a tap on the track, a chapter arrow, then a drag: three jumps, one 原进度
                local mid = along(track, 1/2)
                tap(mid.x, mid.y)
                UIManager:forceRePaint()
                track = progressTrack(panel)
                assert.are.equal(start, track.origin_page)
                tap(track.dimen.x + track.width - track.end_width / 2, mid.y)
                UIManager:forceRePaint()
                track = progressTrack(panel)
                assert.are.equal(start, track.origin_page)
                local from = onTrack(track, ui:getCurrentPage())
                pan(from, along(track, 3/4), "hold_pan")
                lift(along(track, 3/4), "hold_release")
                UIManager:forceRePaint()
                assert.are.equal(track:pageAt(along(track, 3/4).x), ui:getCurrentPage())
                track = progressTrack(panel)
                assert.are.equal(start, track.origin_page)

                -- the dot takes no tap of its own: a tap there is a tap on the track, and the 原进度 stays
                local dot = onTrack(track, start)
                tap(dot.x, dot.y)
                UIManager:forceRePaint()
                assert.are.equal(track:pageAt(dot.x), ui:getCurrentPage())
                assert.are.equal(panel, ui.menu.panel)
                assert.are.equal(bars, ui.menu.bars)
                assert.is_truthy(returnPill(panel))
                track = progressTrack(panel)
                local away = along(track, 3/4)
                tap(away.x, away.y)
                UIManager:forceRePaint()
                assert.are_not.equal(start, ui:getCurrentPage())

                -- the pill goes back to the text the first jump left, and closes the panel and the bars
                local pill = returnPill(panel)
                local pill_rect = pill.dimen:copy()
                local refreshes = refreshesOf(function() tapWidget(pill) end)
                assert.is_nil(ui.menu.panel)
                assert.is_nil(ui.menu.bars)
                assert.are.equal(ui, topWidget())
                assert.are.equal(start, ui:getCurrentPage())
                assert.is_true(ui.document:isXPointerInCurrentPage(anchor))
                assert.is_truthy(refreshIndex(refreshes, "ui", pill_rect))
                assert.is_truthy(refreshIndex(refreshes, "ui", bars.top_rect))
                assert.is_truthy(firstIndex(refreshes, "partial"))
                assert.is_nil(firstIndex(refreshes, "full"))

                -- back there, the 原进度 is used up
                panel = openProgress(ui)
                assert.is_nil(returnPill(panel))
                assert.is_nil(progressTrack(panel).origin_page)
                ui.menu:hideToolbar()
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should keep the 原进度 while the bars switch panels, and forget it once they close", function()
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                local start = ui:getCurrentPage()
                local panel = openProgress(ui)
                local bars = ui.menu.bars
                local mid = along(progressTrack(panel), 1/2)
                tap(mid.x, mid.y)
                UIManager:forceRePaint()
                local jumped = ui:getCurrentPage()
                assert.are_not.equal(start, jumped)

                -- 更多 takes the panel's place: the page shows again where the pill was
                local pill_rect = returnPill(panel).dimen:copy()
                local refreshes = refreshesOf(function() tapWidget(moreButton(bars)) end)
                assert.are.equal("more", ui.menu.panel_name)
                assert.is_truthy(refreshIndex(refreshes, "ui", pill_rect))
                -- the bars stayed: back in the progress panel, the 原进度 is still there
                tapWidget(findIcon(bars.bottom, "eink/progress"))
                UIManager:forceRePaint()
                panel = ui.menu.panel
                assert.is_truthy(returnPill(panel))
                assert.are.equal(start, progressTrack(panel).origin_page)

                -- a tap on the page closes the bars without turning it, and ends the browsing
                pill_rect = returnPill(panel).dimen:copy()
                refreshes = refreshesOf(function() tap(Screen:getWidth() - 10, bars.top_rect.h + 10) end)
                assert.is_nil(ui.menu.bars)
                assert.are.equal(jumped, ui:getCurrentPage())
                assert.is_truthy(refreshIndex(refreshes, "ui", pill_rect))
                panel = openProgress(ui)
                assert.is_nil(returnPill(panel))
                assert.is_nil(progressTrack(panel).origin_page)
                ui.menu:hideToolbar()
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should cover the page with 加载中… only while a jump waits for the layout, and keep the 原进度's text through a reflow", function()
            -- the typeset panel opens from 字体 between the page and the bottom bar; it sets its design defaults
            -- in the global settings, which the other tests don't expect
            local Replacements_config = Replacements.reader_config
            Replacements.reader_config = require("apps/reader/modules/readertypesetpanel")
            local global_keys = { "copt_font_size", "copt_line_spacing", "copt_h_page_margins", "copt_t_page_margin",
                                  "typeset_serif_missing_shown" }
            local saved = {}
            for _, key in ipairs(global_keys) do saved[key] = G_reader_settings:readSetting(key) end
            local ui = openReader(sample_epub)
            local function runTasks()
                for _ = 1, 3 do UIManager:_checkTasks() end
            end
            -- the type size track of the typeset panel, and a tap on one of its buttons (+1 or -1)
            local function stepSize(direction)
                local size_track = find(ui.config.panel, function(w) return w.on_step and w.stopX end)
                local x = direction > 0 and size_track.dimen.w - Screen:scaleBySize(10) or Screen:scaleBySize(10)
                tap(size_track.dimen.x + x, size_track.dimen.y + math.floor(size_track.dimen.h / 2))
                runTasks() -- the re-render follows BatchedUpdateDone
                UIManager:forceRePaint()
            end
            local size = ui.document.configurable.font_size
            local grown = false
            local ok, err = pcall(function()
                runTasks() -- the reader enables partial rendering on its next tick
                ui:handleEvent(Event:new("GotoPage", 20))
                UIManager:forceRePaint()
                local start = ui:getCurrentPage()
                local anchor = ui.rolling:getBookLocation()
                local panel = openProgress(ui)
                local bars = ui.menu.bars
                local function pageArea()
                    local top = bars.show_top and bars.top_rect.h or 0
                    return Geom:new{ x = 0, y = top, w = Screen:getWidth(), h = ui.menu.panel:getRefreshRegion().y - top }
                end
                local function loadingShown()
                    local loading = _("Loading…")
                    for _, window in ipairs(UIManager._window_stack) do
                        if find(window.widget, function(w) return w.text == loading end) then return true end
                    end
                    return false
                end

                -- the book is laid out: a jump shows its page at once
                local area = pageArea()
                local mid = along(progressTrack(panel), 1/2)
                local refreshes = refreshesOf(function() tap(mid.x, mid.y) end)
                assert.are_not.equal(start, ui:getCurrentPage())
                assert.is_nil(refreshIndex(refreshes, "ui", area))
                assert.is_false(loadingShown())

                -- 字体 switches to the typeset panel, whose + grows the type: the book is laid out again only
                -- around the page shown, for now
                tapWidget(findIcon(bars.bottom, "eink/font"))
                UIManager:forceRePaint()
                assert.are.equal("font", ui.menu.panel_name)
                stepSize(1)
                grown = true
                assert.is_true(ui.document.configurable.font_size > size)
                assert.is_truthy(ui.rolling.rendering_state)
                -- back in the progress panel, the bars never closed: the 原进度 is still there, its dot where
                -- its text is now
                tapWidget(findIcon(bars.bottom, "eink/progress"))
                UIManager:forceRePaint()
                panel = ui.menu.panel
                assert.are.equal(bars, ui.menu.bars)
                assert.is_truthy(returnPill(panel))
                assert.are.equal(ui.document:getPageFromXPointer(anchor), progressTrack(panel).origin_page)

                -- a jump now waits for the target's layout: 加载中… covers the page first, with the knob let go
                -- resting where it was let go, and goes with the jump
                area = pageArea()
                local track = progressTrack(panel)
                local quarter = along(track, 1/4)
                pan(onTrack(track, ui:getCurrentPage()), quarter)
                local knob_under_cover
                local forceRePaint = UIManager.forceRePaint
                UIManager.forceRePaint = function(self)
                    forceRePaint(self)
                    if knob_under_cover == nil and loadingShown() then
                        knob_under_cover = shade(onTrack(track, track:pageAt(quarter.x)))
                    end
                end
                local jumped, jump_err = pcall(function()
                    refreshes = refreshesOf(function() lift(quarter) end)
                end)
                UIManager.forceRePaint = forceRePaint
                assert(jumped, jump_err)
                assert.are.equal(0xFF, knob_under_cover)
                local loading = refreshIndex(refreshes, "ui", area)
                assert.is_truthy(loading)
                assert.is_true(loading < firstIndex(refreshes, "partial"))
                assert.is_false(loadingShown())
                assert.are.equal(bars, topWidget())

                -- back to the 原进度: the same text, on its new page
                tapWidget(returnPill(panel))
                UIManager:forceRePaint()
                assert.is_nil(ui.menu.bars)
                assert.is_true(ui.document:isXPointerInCurrentPage(anchor))

                -- the type back to its size, through the typeset panel too: still the same text
                tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
                UIManager:forceRePaint()
                tapWidget(findIcon(ui.menu.bars.bottom, "eink/font"))
                UIManager:forceRePaint()
                stepSize(-1)
                grown = false
                assert.are.equal(size, ui.document.configurable.font_size)
                assert.is_true(ui.document:isXPointerInCurrentPage(anchor))
                ui.menu:hideToolbar()
            end)
            if grown then
                ui.config:apply("font_size", size, "SetFontSize")
            end
            closeReader(ui)
            Replacements.reader_config = Replacements_config
            for _, key in ipairs(global_keys) do
                if saved[key] == nil then
                    G_reader_settings:delSetting(key)
                else
                    G_reader_settings:saveSetting(key, saved[key])
                end
            end
            assert(ok, err)
        end)

        it("should reopen the book on the text a jump went to, without the 原进度", function()
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                local start = ui:getCurrentPage()
                local panel = openProgress(ui)
                local track = progressTrack(panel)
                local from = onTrack(track, start)
                pan(from, along(track, 2/3))
                lift(along(track, 2/3))
                UIManager:forceRePaint()
                assert.are_not.equal(start, ui:getCurrentPage())
                local landed = ui.rolling:getBookLocation()
                ui.menu:hideToolbar()
                closeReader(ui)
                ui = openReader(sample_epub, true)
                assert.is_true(ui.document:isXPointerInCurrentPage(landed))
                panel = openProgress(ui)
                assert.is_nil(returnPill(panel))
                assert.is_nil(progressTrack(panel).origin_page)
                ui.menu:hideToolbar()
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should drag after a hold, take a hold that does not move as a tap, and go back in a PDF", function()
            local ui = openReader(sample_pdf)
            local ok, err = pcall(function()
                local start = ui:getCurrentPage()
                local pages = ui.document:getPageCount()
                local panel = openProgress(ui)
                local track = progressTrack(panel)
                -- a hold that does not move jumps where it is, as a tap
                local mid = along(track, 1/2)
                lift(mid, "hold_release")
                UIManager:forceRePaint()
                local middle = track:pageAt(mid.x)
                assert.are.equal(middle, ui:getCurrentPage())
                -- a drag after a hold previews, and jumps once let go
                track = progressTrack(panel)
                local from = onTrack(track, middle)
                local last = point(track.dimen.x + track.width - track.inset, from.y)
                pan(from, last, "hold_pan")
                assert.are.equal(middle, ui:getCurrentPage())
                assert.are.same({ "100", "%" }, statisticValues(panel, 1))
                lift(last, "hold_release")
                UIManager:forceRePaint()
                assert.are.equal(pages, ui:getCurrentPage())
                assert.are.equal(start, progressTrack(panel).origin_page)

                tapWidget(returnPill(panel))
                UIManager:forceRePaint()
                assert.are.equal(start, ui:getCurrentPage())
                assert.is_nil(ui.menu.bars)
            end)
            closeReader(ui)
            assert(ok, err)
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
                local saved = require("util").tableDeepCopy(ui.annotation.annotations)
                -- Bookmarking this page and undoing it must leave its existing highlight intact.
                for __ = 1, 2 do
                    tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
                    UIManager:forceRePaint()
                    tapWidget(bookmarkButton(ui.menu.bars))
                    closeToasts()
                    UIManager:forceRePaint()
                end
                assert.are.same(saved, ui.annotation.annotations)
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

        it("should disable chapter arrows without a PDF outline and jump through the track", function()
            local ui = openReader(sample_pdf)
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            tapWidget(findIcon(ui.menu.bars.bottom, "eink/progress"))
            UIManager:forceRePaint()
            local panel = ui.menu.panel
            local track = find(panel, function(w) return w.on_jump ~= nil end)
            assert.is_nil(track.previous_chapter)
            assert.is_nil(track.next_chapter)
            local page = ui:getCurrentPage()
            tap(track.dimen.x + track.end_width / 2, track.dimen.y + track.dimen.h / 2)
            tap(track.dimen.x + track.width - track.end_width / 2, track.dimen.y + track.dimen.h / 2)
            assert.are.equal(page, ui:getCurrentPage())
            tap(track.dimen.x + track.width - track.inset, track.dimen.y + track.dimen.h / 2)
            UIManager:forceRePaint()
            assert.are.equal(ui.document:getPageCount(), ui:getCurrentPage())
            assert.are.same({ "100", "%" }, statisticValues(panel, 1))
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

    describe("with the statistics plugin", function()
        it("should display timing collected by real page turns and retain it after reopening", function()
            load_plugin("statistics.koplugin")
            local now = os.time()
            local clock = stub(os, "time", function() return now end)
            local ui
            local ok, err = pcall(function()
                ui = openReader(sample_epub)
                assert.is_true(ui.statistics:isEnabled())
                tap(Screen:getWidth() - 10, Screen:getHeight() / 2)
                now = now + 120
                tap(Screen:getWidth() - 10, Screen:getHeight() / 2)
                assert.is_true(ui.statistics.mem_read_pages > 0)
                local function check()
                    tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
                    UIManager:forceRePaint()
                    tapWidget(findIcon(ui.menu.bars.bottom, "eink/progress"))
                    UIManager:forceRePaint()
                    local panel = ui.menu.panel
                    assert.are.same({ "2", _.pgettext("Time", "min") }, statisticValues(panel, 2))
                    assert.is_truthy(find(panel, function(w)
                        return type(w.text) == "string" and w.text:find("About", 1, true)
                    end))
                    ui.menu:hideToolbar()
                end
                check()
                closeReader(ui)
                ui = openReader(sample_epub, true)
                check()
            end)
            clock:revert()
            if ui then closeReader(ui) end
            disable_plugins()
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
