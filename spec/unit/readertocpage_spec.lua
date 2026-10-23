-- The full-screen contents page (目录页), driven through the reader with taps: the toolbar's 目录, rows, chevrons,
-- the title band's action, the page capsule, the back arrow, the search field and 书签.
describe("ReaderTocPage module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderToolbar, Replacements, UIManager, Event, Geom, Palette, Screen
    local _, C_
    local sample_epub = "spec/front/unit/data/juliet.epub" -- five acts (entries 3, 10, 18, 24, 30), each a group of scenes
    local sample_pdf = "spec/front/unit/data/paper.pdf" -- has an outline, unlike sample.pdf

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
        Palette = require("ui/palette")
        Screen = require("device").screen
        _ = require("gettext")
        C_ = _.pgettext
        Replacements.reader_menu = ReaderToolbar
    end)

    teardown(function()
        Replacements.reader_menu = nil
    end)

    local function openReader(file, keep_settings)
        if not keep_settings then
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

    -- Taps the middle of `rect` and repaints.
    local function tapRect(rect)
        tap(rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2))
        UIManager:forceRePaint()
    end

    local function tapWidget(widget)
        tapRect(widget.dimen)
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
    end

    local function hasText(widget, str)
        return find(widget, function(w) return w.text == str end) ~= nil
    end

    -- The page number drawn paper on ink, the current chapter's mark.
    local function inkNumber(row)
        -- the same color object (a cdata, whose __eq fails on anything but another color)
        return find(row, function(w) return rawequal(w.background, Palette.ink) end)
    end

    -- Reads from the start of entry `index`.
    local function readAt(ui, index)
        ui.rolling:onGotoPage(ui.document:getPageFromXPointer(ui.toc.toc[index].xpointer))
        UIManager:forceRePaint()
    end

    local function openPage(ui)
        ui:handleEvent(Event:new("ShowToc"))
        UIManager:forceRePaint()
        local page = ui.menu.drawer
        assert.is_truthy(page)
        assert.are.equal(page, topWidget())
        return page
    end

    local function back(page)
        tapWidget(page.bar.back)
        assert.is_false(UIManager:isWidgetShown(page))
    end

    local function nextPage(page)
        tapRect(page.bar.capsule.next_rect)
    end

    local function toFirstPage(page)
        while page.bar.capsule.prev_enabled do
            tapRect(page.bar.capsule.prev_rect)
        end
    end

    -- The entry indexes of every page, in order.
    local function allShown(page)
        toFirstPage(page)
        local shown = {}
        while true do
            for _, row in ipairs(page.shown_rows) do
                table.insert(shown, row.toc_index)
            end
            if not page.bar.capsule.next_enabled then break end
            nextPage(page)
        end
        return shown
    end

    local function shownRow(page, pred)
        for _, row in ipairs(page.shown_rows) do
            if pred(row) then return row end
        end
    end

    -- Turns from the first page to the one that shows entry `index`, and returns its row.
    local function rowOf(page, index)
        toFirstPage(page)
        while true do
            local row = shownRow(page, function(r) return r.toc_index == index end)
            if row then return row end
            assert.is_true(page.bar.capsule.next_enabled, "entry " .. index .. " not shown")
            nextPage(page)
        end
    end

    local function isOpen(row)
        return find(row.chevron, function(w) return w.icon == "eink/chev.up" end) ~= nil
    end

    local function tapChevron(row)
        tapWidget(row.chevron)
    end

    local function tapTitle(row)
        tapRect(Geom:new{ x = row.dimen.x, y = row.dimen.y, w = row.dimen.w, h = row.dimen.h })
    end

    -- Collapses every open group with its chevron.
    local function collapseAll(page)
        toFirstPage(page)
        while true do
            local open = shownRow(page, function(r) return r.is_group and isOpen(r) end)
            if open then
                tapChevron(open)
            elseif page.bar.capsule.next_enabled then
                nextPage(page)
            else
                break
            end
        end
    end

    describe("with an EPUB", function()
        local ui
        before_each(function()
            ui = openReader(sample_epub)
            ui.rolling:onGotoPage(10) -- in Act I
            UIManager:forceRePaint()
        end)
        after_each(function()
            if ui.menu.drawer then
                ui.menu:closeDrawer()
                UIManager:forceRePaint()
            end
            closeReader(ui)
        end)

        it("should open full screen from the toolbar's Contents, on the current chapter, with ui refreshes only", function()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local contents = find(ui.menu.bars, function(w)
                return w.callback and w.dimen and hasText(w, C_("Reader toolbar", "Contents"))
            end)
            local refreshes = refreshesOf(function() tapWidget(contents) end)
            local page = ui.menu.drawer
            assert.are.equal(page, topWidget())
            assert.is_true(page.covers_fullscreen)
            assert.is_nil(ui.menu.bars)
            assert.is_true(#refreshes > 0)
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
            end
            assert.is_true(refreshes[#refreshes].region:contains(page.dimen))

            -- book title, the search field and 书签 around the list
            assert.is_true(hasText(page, ui.doc_props.display_title))
            assert.is_true(hasText(page.search_field, _("Search the whole book")))
            assert.is_true(hasText(page.bookmarks_button, _("Bookmarks")))
            -- on the current chapter, whose page number alone is ink-filled; titles are bold, as in the reference
            local current = ui.toc:getTocIndexByPage(ui.document:getXPointer())
            local row = shownRow(page, function(r) return r.is_current end)
            assert.is_truthy(row)
            assert.are.equal(current, row.toc_index)
            assert.is_true(hasText(inkNumber(row), ui.bookmark:getBookmarkPageString(ui.toc.toc[current].xpointer)))
            for _, r in ipairs(page.shown_rows) do
                if r ~= row then assert.is_nil(inkNumber(r)) end
                assert.is_truthy(find(r, function(w) return w.bold == true and w.text end))
            end
            -- start pages at the right; a group's chevron, open
            local act1 = shownRow(page, function(r) return r.toc_index == 3 end)
            assert.is_true(act1.is_group)
            assert.is_true(isOpen(act1))
            assert.is_true(hasText(act1, ui.bookmark:getBookmarkPageString(ui.toc.toc[3].xpointer)))
            assert.is_false(shownRow(page, function(r) return r.toc_index == 5 end).is_group)

            refreshes = refreshesOf(function() back(page) end)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.menu.drawer)
        end)

        it("should collapse and expand a group, paging the rows left without losing any, and keep it for the book", function()
            local page = openPage(ui)
            local all = {}
            for i = 1, #ui.toc.toc do all[i] = i end
            assert.are.same(all, allShown(page))

            local act1 = rowOf(page, 3)
            local refreshes = refreshesOf(function() tapChevron(act1) end)
            assert.are.same({ { mode = "ui", region = page.body_rect } }, refreshes)
            assert.are.equal(1, page.page)
            act1 = shownRow(page, function(r) return r.toc_index == 3 end)
            assert.is_false(isOpen(act1))
            -- its scenes are gone and Act II follows on the same page; nothing else is lost
            assert.is_nil(shownRow(page, function(r) return r.toc_index == 4 end))
            assert.is_truthy(shownRow(page, function(r) return r.toc_index == 10 end))
            local expected = { 1, 2, 3 }
            for i = 10, #ui.toc.toc do table.insert(expected, i) end
            assert.are.same(expected, allShown(page))
            assert.are.same({ [3] = "Act I" }, ui.doc_settings:readSetting("contents_page_collapsed"))

            -- kept when the page and the book open again, outside Act I
            back(page)
            closeReader(ui)
            ui = openReader(sample_epub, true)
            readAt(ui, 19) -- Act III
            page = openPage(ui)
            assert.are.same(expected, allShown(page))

            -- expanding forgets it
            tapChevron(rowOf(page, 3))
            assert.is_truthy(shownRow(page, function(r) return r.toc_index == 4 end))
            assert.is_nil(ui.doc_settings:readSetting("contents_page_collapsed"))
            back(page)
        end)

        it("should show the current chapter in a collapsed group, and keep that group collapsed", function()
            local page = openPage(ui)
            tapChevron(rowOf(page, 3))
            back(page)

            -- still in Act I: its scenes show and the current one is marked
            page = openPage(ui)
            local current = ui.toc:getTocIndexByPage(ui.document:getXPointer())
            assert.is_true(current > 3 and current < 10)
            local row = shownRow(page, function(r) return r.is_current end)
            assert.are.equal(current, row.toc_index)
            assert.is_true(isOpen(rowOf(page, 3)))
            -- collapsing another group doesn't forget Act I
            tapChevron(rowOf(page, 10))
            back(page)
            assert.are.same({ [3] = "Act I", [10] = "Act II" }, ui.doc_settings:readSetting("contents_page_collapsed"))
            readAt(ui, 19) -- Act III
            page = openPage(ui)
            assert.are.same({ 1, 2, 3, 10, 18 }, { table.unpack(allShown(page), 1, 5) })
            back(page)
        end)

        it("should go to the bottom and back to the top, the action and the capsule following the ends", function()
            local page = openPage(ui)
            assert.are.equal(1, page.page)
            assert.is_true(page.page_count >= 3)
            assert.is_false(page.bar.capsule.prev_enabled)
            assert.is_true(page.bar.capsule.next_enabled)
            assert.is_true(hasText(page.action_button, _("Go to bottom")))

            -- the list and the bar, and the title band for its new action (UIManager merges the two into the page)
            local refreshes = refreshesOf(function() tapWidget(page.action_button) end)
            assert.are.same({ mode = "ui", region = page.body_rect }, refreshes[1])
            assert.are.same({ mode = "ui", region = page.title_rect }, refreshes[2])
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
                assert.is_true(page.dimen:contains(r.region))
            end
            assert.are.equal(page.page_count, page.page)
            assert.is_true(hasText(page.action_button, _("Go to top")))
            assert.is_true(page.bar.capsule.prev_enabled)
            assert.is_false(page.bar.capsule.next_enabled)
            assert.is_truthy(shownRow(page, function(r) return r.toc_index == #ui.toc.toc end))

            tapWidget(page.action_button)
            assert.are.equal(1, page.page)
            assert.is_true(hasText(page.action_button, _("Go to bottom")))

            -- a middle page keeps ↓去底部 and the title band as painted
            refreshes = refreshesOf(function() nextPage(page) end)
            assert.are.equal(2, page.page)
            assert.are.same({ { mode = "ui", region = page.body_rect } }, refreshes)
            assert.is_true(hasText(page.action_button, _("Go to bottom")))
            back(page)

            -- every act collapsed, read outside them: one page, no action, a gray capsule
            ui.rolling:onGotoPage(2)
            UIManager:forceRePaint()
            page = openPage(ui)
            collapseAll(page)
            assert.are.same({ 1, 2, 3, 10, 18, 24, 30 }, allShown(page))
            assert.are.equal(1, page.page_count)
            assert.is_nil(page.action_button)
            assert.is_false(page.bar.capsule.prev_enabled)
            assert.is_false(page.bar.capsule.next_enabled)
            back(page)
        end)

        it("should jump to an entry, a group's too, remembering the position left, with the reader's partial", function()
            local stack_size = #(ui.link.location_stack or {})
            local page = openPage(ui)
            local row = rowOf(page, 18) -- Act III, a group: its title jumps, only its chevron collapses
            assert.is_true(row.is_group)
            local refreshes = refreshesOf(function() tapTitle(row) end)
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.menu.drawer)
            assert.are.equal(ui.document:getPageFromXPointer(ui.toc.toc[18].xpointer), ui:getCurrentPage())
            assert.are.equal(stack_size + 1, #ui.link.location_stack)
            assert.is_nil(ui.doc_settings:readSetting("contents_page_collapsed"))
            assert.is_true(#refreshes > 0)
            for _, r in ipairs(refreshes) do
                assert.are.equal("partial", r.mode)
            end
        end)

        it("should hand the search field over to the full-text search input", function()
            local page = openPage(ui)
            tapWidget(page.search_field)
            assert.is_false(UIManager:isWidgetShown(page))
            assert.is_nil(ui.menu.drawer)
            assert.is_truthy(ui.search.input_dialog)
            assert.are.equal(ui.search.input_dialog, topWidget())
            UIManager:close(ui.search.input_dialog)
            UIManager:forceRePaint()
        end)

        it("should open the bookmarks of the old drawer from 书签, which no longer has a contents tab", function()
            local page = openPage(ui)
            local refreshes = refreshesOf(function() tapWidget(page.bookmarks_button) end)
            local drawer = ui.menu.drawer
            assert.is_false(UIManager:isWidgetShown(page))
            assert.are.equal(drawer, topWidget())
            assert.are.equal("bookmarks", drawer.tab)
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
            end
            assert.is_true(hasText(drawer.panel, _("No bookmarks yet")))
            assert.is_nil(find(drawer.panel, function(w) return w.text == C_("Reader toolbar", "Contents") end))
            drawer:onClose()
            UIManager:forceRePaint()
            assert.is_nil(ui.menu.drawer)
        end)

        it("should build only the shown rows of a very long, very deep table of contents, and measure it once", function()
            local TextBoxWidget = require("ui/widget/textboxwidget")
            local orig_toc = ui.toc.toc
            local big = {}
            while #big < 3000 do
                for _, e in ipairs(orig_toc) do
                    -- every 10th entry nested 60 levels deep: the indent must stay capped
                    table.insert(big, { title = e.title .. " " .. #big, xpointer = e.xpointer, page = e.page,
                                        depth = #big % 10 == 0 and 60 or e.depth })
                end
            end
            table.sort(big, function(a, b) return a.page < b.page end)
            ui.toc.toc = big
            local boxes = 0
            local orig_init = TextBoxWidget.init
            TextBoxWidget.init = function(...) boxes = boxes + 1 return orig_init(...) end
            local ok, err = pcall(function()
                local page = openPage(ui)
                assert.are.equal(#page.shown_rows, boxes) -- one title box per shown row, nothing more
                assert.is_true(page.page_count > 50)
                for _, row in ipairs(page.shown_rows) do
                    assert.are.equal(Screen:getWidth(), row.dimen.w)
                end
                boxes = 0
                local measure = spy.on(page, "measure")
                if page.bar.capsule.next_enabled then nextPage(page) else tapRect(page.bar.capsule.prev_rect) end
                assert.spy(measure).was_not_called()
                assert.are.equal(#page.shown_rows, boxes)
                back(page)
            end)
            TextBoxWidget.init = orig_init
            ui.toc.toc = orig_toc
            assert(ok, err)
        end)
    end)

    describe("with a PDF", function()
        it("should list the outline and jump to an entry", function()
            local ui = openReader(sample_pdf)
            local ok, err = pcall(function()
                local page = openPage(ui)
                assert.is_true(#ui.toc.toc > 0)
                local row = shownRow(page, function(r)
                    return not r.is_group and ui.toc.toc[r.toc_index].page > ui:getCurrentPage()
                end)
                assert.is_truthy(row)
                tapTitle(row)
                assert.are.equal(ui.toc.toc[row.toc_index].page, ui:getCurrentPage())
                assert.are.equal(ui, topWidget())
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should repaint the reader when the entry is on the page shown", function()
            local ui = openReader(sample_pdf)
            local ok, err = pcall(function()
                assert.are.equal(1, ui:getCurrentPage())
                local page = openPage(ui)
                local row = shownRow(page, function(r) return r.is_current end)
                assert.are.equal(1, ui.toc.toc[row.toc_index].page)
                local refreshes = refreshesOf(function() tapTitle(row) end)
                assert.are.equal(ui, topWidget())
                assert.are.equal(1, ui:getCurrentPage())
                -- the page's place goes back to the reader with a partial, even if the reader had nothing to turn
                local covered = false
                for _, r in ipairs(refreshes) do
                    assert.are_not.equal("full", r.mode)
                    covered = covered or r.mode == "partial" and (r.region == nil or r.region:contains(page.dimen))
                end
                assert.is_true(covered)
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should say there is no table of contents, with nothing to page", function()
            local ui = openReader("spec/front/unit/data/sample.pdf")
            local ok, err = pcall(function()
                local page = openPage(ui)
                assert.is_true(hasText(page, _("No table of contents")))
                assert.are.same({}, page.shown_rows)
                assert.is_nil(page.action_button)
                assert.is_false(page.bar.capsule.next_enabled)
                back(page)
            end)
            closeReader(ui)
            assert(ok, err)
        end)
    end)

    describe("without the toolbar", function()
        it("should keep the original table of contents", function()
            Replacements.reader_menu = nil
            local ui = openReader(sample_epub)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("ShowToc"))
                assert.is_nil(ui.menu.drawer)
                assert.is_truthy(ui.toc.toc_menu)
                ui.toc.toc_menu:close_callback()
            end)
            closeReader(ui)
            Replacements.reader_menu = ReaderToolbar
            assert(ok, err)
        end)
    end)
end)
