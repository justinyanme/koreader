-- The full-text search of the redesign, driven through the reader with taps: the contents page's search field,
-- the keyboard's keys, the search page (field, clear button, 取消, hits, pager, back arrow, 书签), the hits in
-- the book under the toolbar, and the search bar (its keyword and ×).
describe("ReaderFulltextSearch module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderToolbar, ReaderFulltextSearch, Replacements
    local UIManager, Event, Geom, Screen, Trapper, util, _
    local sample_epub = "spec/front/unit/data/juliet.epub" -- five acts, each a group of scenes
    local sample_pdf = "spec/front/unit/data/paper.pdf" -- has an outline and a text layer
    local orig_wrap, orig_run

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderToolbar = require("apps/reader/modules/readertoolbar")
        ReaderFulltextSearch = require("apps/reader/modules/readerfulltextsearch")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Screen = require("device").screen
        Trapper = require("ui/trapper")
        util = require("util")
        _ = require("gettext")
        Replacements.reader_menu = ReaderToolbar
        Replacements.reader_search = ReaderFulltextSearch
        -- the search runs in this process, at once (a subprocess needs the UI loop)
        orig_wrap, orig_run = Trapper.wrap, Trapper.dismissableRunInSubprocess
        Trapper.wrap = function(_, fn) return fn() end
        Trapper.dismissableRunInSubprocess = function(_, task) return true, task() end
    end)

    teardown(function()
        Replacements.reader_menu = nil
        Replacements.reader_search = nil
        Trapper.wrap, Trapper.dismissableRunInSubprocess = orig_wrap, orig_run
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
        UIManager:forceRePaint()
    end

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function gesture(ges, x, y)
        UIManager:sendEvent(Event:new("Gesture", { ges = ges, pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
        UIManager:forceRePaint()
    end

    local function tapRect(rect)
        gesture("tap", rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2))
    end

    local function tapWidget(widget)
        tapRect(widget.dimen)
    end

    -- Runs the tasks scheduled for later, such as the enter key's.
    local function flush()
        UIManager:shiftScheduledTasksBy(-1e9)
        UIManager:_checkTasks()
        UIManager:forceRePaint()
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

    local function modes(refreshes)
        local set = {}
        for _, r in ipairs(refreshes) do set[r.mode] = true end
        return set
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

    -- gray level of a screen pixel, 0 (ink) to 255 (paper)
    local function gray(x, y)
        return Screen.bb:getPixel(x, y):getColor8().a
    end

    -- The share of the pixels of `rect` that match `pred`.
    local function share(rect, pred)
        local n, total = 0, 0
        for y = rect.y, rect.y + rect.h - 1 do
            for x = rect.x, rect.x + rect.w - 1 do
                total = total + 1
                if pred(gray(x, y)) then n = n + 1 end
            end
        end
        return n / math.max(1, total)
    end

    local function isInk(v) return v < 0x40 end
    local function isPaper(v) return v == 0xFF end

    -- The middle of the clear button, where its disc is drawn.
    local function disc(page)
        local d, s = page.clear_button.dimen, Screen:scaleBySize(12)
        return Geom:new{ x = d.x + math.floor((d.w - s) / 2), y = d.y + math.floor((d.h - s) / 2), w = s, h = s }
    end

    local function openContents(ui)
        ui:handleEvent(Event:new("ShowToc"))
        UIManager:forceRePaint()
        return ui.menu.drawer
    end

    -- From the contents page's search field: the search page, typing.
    local function openSearch(ui)
        local contents = openContents(ui)
        tapWidget(contents.search_field)
        local page = ui.search.search_page
        assert.is_truthy(page)
        return page, contents
    end

    local function key(page, char)
        local k = find(page.input.keyboard, function(w) return w.key == char and w.dimen ~= nil end)
        assert.is_truthy(k, "no key for " .. char)
        return k
    end

    local function typeText(page, str)
        for _, char in ipairs(util.splitToChars(str)) do
            tapWidget(key(page, char))
        end
    end

    -- The enter key, which acts a little later.
    local function enter(page)
        tapWidget(key(page, "\n"))
        flush()
    end

    local function search(page, str)
        typeText(page, str)
        enter(page)
    end

    local function hitRows(page)
        local rows = {}
        for _, row in ipairs(page.shown_rows) do
            if row.hit_index then table.insert(rows, row) end
        end
        return rows
    end

    local function nextPage(page)
        tapRect(page.bar.capsule.next_rect)
    end

    -- Every page of hits from the first: the shown rows, as { title = heading } or { index = hit }.
    local function allRows(page)
        while page.bar.capsule.prev_enabled do
            tapRect(page.bar.capsule.prev_rect)
        end
        local pages = {}
        while true do
            local rows = {}
            for _, row in ipairs(page.shown_rows) do
                if row.hit_index then
                    table.insert(rows, { index = row.hit_index })
                else
                    table.insert(rows, { title = find(row, function(w) return w.text end).text })
                end
            end
            table.insert(pages, rows)
            if not page.bar.capsule.next_enabled then break end
            nextPage(page)
        end
        return pages
    end

    -- The screen rects of the matched characters in a hit row's excerpt.
    local function hitRects(row)
        local snippet = row.snippet
        local rects = snippet:getXtextHighlightRects(snippet.hit_start, snippet.hit_end, 1, #snippet.vertical_string_list)
        for _, r in ipairs(rects) do
            r.x, r.y = r.x + snippet.dimen.x, r.y + snippet.dimen.y
        end
        return rects
    end

    local function hideToolbar(ui)
        assert.is_truthy(ui.menu.bars)
        tapRect(Geom:new{ x = 0, y = math.floor(Screen:getHeight() / 2), w = Screen:getWidth(), h = 1 })
        assert.is_nil(ui.menu.bars)
    end

    -- A blank stretch of the bar, between the keyword and ×.
    local function barBlank(ui)
        local r = ui.search.bar:getRect()
        return Geom:new{ x = r.x + math.floor(r.w * 0.6), y = r.y + Screen:scaleBySize(4), w = Screen:scaleBySize(20), h = r.h - Screen:scaleBySize(8) }
    end

    -- The screen boxes of the mark of the hit shown.
    local function markBoxes(ui, item)
        local boxes = {}
        for _, box in ipairs(ui.document:getScreenBoxesFromPositions(item.start, item["end"], true)) do
            table.insert(boxes, box)
        end
        assert.is_true(#boxes > 0)
        return boxes
    end

    local function markedShare(boxes)
        local n = 0
        for _, box in ipairs(boxes) do
            n = n + share(box, function(v) return not isPaper(v) end)
        end
        return n / #boxes
    end

    describe("with an EPUB", function()
        local ui

        before_each(function()
            ui = openReader(sample_epub)
            -- past the cover: paging away from its image flashes the page (the reader's own rule for images)
            ui.rolling:onGotoPage(5)
            UIManager:forceRePaint()
        end)

        after_each(function()
            for i = #UIManager._window_stack, 1, -1 do
                local w = UIManager._window_stack[i].widget
                if w ~= ui then UIManager:close(w) end
            end
            closeReader(ui)
        end)

        it("should open over the contents page from its search field, with the keyboard, and 取消 back to it", function()
            local contents = openContents(ui)
            local refreshes = refreshesOf(function() tapWidget(contents.search_field) end)
            local page = ui.search.search_page
            assert.is_truthy(page)
            assert.are.equal(contents, page.contents)
            assert.is_true(UIManager:isWidgetShown(contents))
            -- the page whole, and the keyboard over it; nothing full
            assert.is_truthy(find(refreshes, function(r) return r.mode == "ui" and r.region == page.dimen end))
            assert.is_nil(modes(refreshes).full)
            local keyboard = page.input.keyboard
            assert.is_true(keyboard:isVisible())
            assert.are.equal(keyboard, topWidget())
            assert.is_true(page.typing)
            -- the book title, the empty field's placeholder, 取消, 书签; no hits yet
            assert.is_true(hasText(page, ui.doc_props.display_title))
            assert.are.equal("", page.input:getText())
            assert.are.equal(_("Search the whole book"), page.placeholder.text)
            assert.is_true(hasText(page.cancel_button, _("Cancel")))
            assert.is_truthy(page.bookmarks_button)
            assert.are.same({}, page.shown_rows)
            assert.is_false(page.bar.capsule.prev_enabled or page.bar.capsule.next_enabled)

            tapWidget(page.cancel_button)
            assert.is_false(UIManager:isWidgetShown(page))
            assert.is_false(keyboard:isVisible())
            assert.is_nil(ui.search.search_page)
            assert.are.equal(contents, topWidget())
            assert.are.equal(contents, ui.menu.drawer)
        end)

        it("should list the hits typed for by chapter, each once and in order, the hit paper on ink", function()
            local page = openSearch(ui)
            typeText(page, "verona")
            assert.are.equal("verona", page.input:getText())
            -- the clear button shows once there is text
            assert.is_true(share(disc(page), isInk) > 0.3)
            local refreshes = refreshesOf(function() enter(page) end)
            assert.is_nil(modes(refreshes).full)
            assert.is_nil(modes(refreshes).partial)
            assert.is_false(page.typing)
            assert.is_false(page.input.keyboard:isVisible())
            local results = ui.search.results
            assert.is_true(#results > 3)
            assert.are.equal("verona", ui.search.query)
            local pages = allRows(page)
            local next_index, chapter = 1, nil
            for _, rows in ipairs(pages) do
                -- a page starts with a heading (every hit is in a scene here)
                assert.is_truthy(rows[1].title)
                for _, row in ipairs(rows) do
                    if row.title then
                        chapter = row.title
                    else
                        assert.are.equal(next_index, row.index)
                        local toc = ui.toc
                        local entry = toc.toc[toc:getTocIndexByPage(results[row.index].start)]
                        assert.are.equal(toc:cleanUpTocTitle(entry.title, true), chapter)
                        next_index = next_index + 1
                    end
                end
            end
            assert.are.equal(#results + 1, next_index)
            assert.is_true(#pages > 1)
            -- on the page shown, the matched characters of each excerpt are paper on ink
            local rows = hitRows(page)
            assert.is_true(#rows > 0)
            for _, row in ipairs(rows) do
                local snippet = row.snippet
                local chars = util.splitToChars(snippet.text)
                local matched = table.concat(chars, "", snippet.hit_start, snippet.hit_end)
                assert.are.equal("verona", matched:lower())
                for _, rect in ipairs(hitRects(row)) do
                    assert.is_true(share(rect, isInk) > 0.5)
                end
            end
        end)

        it("should open a hit under the toolbar, then show the bar, which goes back to the hits left", function()
            local page = openSearch(ui)
            search(page, "verona")
            nextPage(page)
            local row = hitRows(page)[1]
            local item = ui.search.results[row.hit_index]
            local stack = #(ui.link.location_stack or {})
            local refreshes = refreshesOf(function() tapWidget(row) end)
            -- the search page and the contents page go; the hit's page, with the toolbar up
            assert.is_false(UIManager:isWidgetShown(page))
            assert.is_nil(ui.menu.drawer)
            assert.is_nil(ui.search.search_page)
            assert.are.equal(ui.document:getPageFromXPointer(item.start), ui.document:getCurrentPage())
            assert.are.equal(stack + 1, #ui.link.location_stack)
            assert.is_truthy(ui.menu.bars)
            assert.is_truthy(find(refreshes, function(r) return r.mode == "partial" end))
            assert.is_nil(modes(refreshes).full)
            -- the toolbar covers the bar; the hit is marked
            assert.is_true(share(barBlank(ui), isInk) < 0.5)
            local boxes = markBoxes(ui, item)
            assert.is_true(markedShare(boxes) > 0.6)

            refreshes = refreshesOf(function() hideToolbar(ui) end)
            assert.is_nil(modes(refreshes).full)
            -- the bar: ink, with the keyword in paper
            assert.is_true(share(barBlank(ui), isInk) > 0.95)
            assert.are.equal("verona", ui.search:barQuery())
            assert.is_true(markedShare(boxes) > 0.6)

            -- its keyword: the hits again, on the page left, over the contents page
            local before = ui.document:getCurrentPage()
            tapRect(Geom:new{ x = Screen:scaleBySize(60), y = ui.search.bar:getRect().y + 5, w = 1, h = 1 })
            assert.are.equal(before, ui.document:getCurrentPage())
            page = ui.search.search_page
            assert.is_truthy(page)
            assert.are.equal(page, topWidget())
            assert.are.equal(2, page.page)
            assert.is_true(page.bar.capsule.prev_enabled)
            assert.are.equal(row.hit_index, hitRows(page)[1].hit_index)
            assert.are.equal("verona", page.input:getText())
            assert.is_false(page.typing)
            assert.is_truthy(page.bookmarks_button)
            local contents = page.contents
            assert.is_truthy(contents)
            assert.are.equal(contents, ui.menu.drawer)
            assert.is_true(UIManager:isWidgetShown(contents))
            -- 取消 goes back to the contents page, and its back arrow to the book, where the search stays
            tapWidget(page.cancel_button)
            assert.is_nil(ui.search.search_page)
            assert.are.equal(contents, topWidget())
            tapWidget(contents.bar.back)
            assert.are.equal(ui, topWidget())
            assert.is_true(share(barBlank(ui), isInk) > 0.95)
            assert.is_true(markedShare(boxes) > 0.6)
        end)

        it("should lead the bar back to its own hits, whatever was searched since", function()
            local page = openSearch(ui)
            search(page, "verona")
            local verona = ui.search.results
            tapWidget(hitRows(page)[1])
            hideToolbar(ui)
            -- back to the hits, then another search that finds nothing, and back to the book
            tapRect(Geom:new{ x = Screen:scaleBySize(60), y = ui.search.bar:getRect().y + 5, w = 1, h = 1 })
            page = ui.search.search_page
            tapWidget(page.search_field)
            tapWidget(page.clear_button)
            search(page, "qzxwqzxw")
            assert.is_truthy(page.message)
            tapWidget(page.bar.back)
            -- the bar still says verona, and leads to its hits
            assert.are.equal("verona", ui.search:barQuery())
            tapRect(Geom:new{ x = Screen:scaleBySize(60), y = ui.search.bar:getRect().y + 5, w = 1, h = 1 })
            page = ui.search.search_page
            assert.are.equal("verona", page.input:getText())
            assert.are.equal(verona, page.results)
            assert.is_nil(page.message)
            assert.is_true(#hitRows(page) > 0)
        end)

        it("should end the search with ×, clearing the mark and the bar but keeping highlights", function()
            -- a highlight on the first hit's page
            local first = ui.document:findAllText("verona", true, 5, 5000, false, 0x00FF)[1]
            ui.rolling:onGotoPage(ui.document:getPageFromXPointer(first.start))
            UIManager:forceRePaint()
            ui.highlight:onHold(nil, { pos = Geom:new{ x = 260, y = 70 } })
            ui.highlight:onHoldPan(nil, { pos = Geom:new{ x = 260, y = 100 } })
            ui.highlight:onHoldRelease()
            ui.highlight:saveHighlight()
            ui.highlight:onClose()
            UIManager:forceRePaint()
            assert.are.equal(1, #ui.annotation.annotations)

            local page = openSearch(ui)
            search(page, "verona")
            local row = hitRows(page)[1]
            assert.are.equal(1, row.hit_index)
            tapWidget(row)
            hideToolbar(ui)
            local boxes = markBoxes(ui, first)
            assert.is_true(markedShare(boxes) > 0.6)
            assert.is_true(#ui.view.highlight.visible_boxes > 0)

            local bar = ui.search.bar:getRect()
            local refreshes = refreshesOf(function() tapRect(ui.search.bar:getCloseRect()) end)
            assert.is_nil(ui.search:barQuery())
            assert.is_nil(ui.search.search_page)
            -- "ui" on the bar and the mark, nothing else
            assert.are.equal(1, #refreshes)
            assert.are.equal("ui", refreshes[1].mode)
            assert.is_true(refreshes[1].region:contains(bar))
            for _, box in ipairs(boxes) do
                assert.is_true(refreshes[1].region:contains(box))
            end
            assert.is_true(share(barBlank(ui), isPaper) > 0.9)
            assert.is_true(markedShare(boxes) < 0.5)
            -- the highlight stays, drawn
            assert.are.equal(1, #ui.annotation.annotations)
            assert.is_true(#ui.view.highlight.visible_boxes > 0)
            -- and the bar's place is the page's again: a tap there turns it
            local before = ui.document:getCurrentPage()
            tapRect(Geom:new{ x = Screen:getWidth() - 20, y = bar.y + 5, w = 1, h = 1 })
            assert.are.equal(before + 1, ui.document:getCurrentPage())
        end)

        it("should keep the bar while reading on, taking only its own taps and holds", function()
            local page = openSearch(ui)
            search(page, "verona")
            tapWidget(hitRows(page)[1])
            hideToolbar(ui)
            local boxes = markBoxes(ui, ui.search.results[1])
            -- a word selected and let go elsewhere on the page (which looks it up): the mark stays
            ui.highlight:onHold(nil, { pos = Geom:new{ x = 260, y = 70 } })
            ui.highlight:onHoldRelease()
            ui.highlight:onClose()
            while topWidget() ~= ui do
                UIManager:close(topWidget())
            end
            UIManager:forceRePaint()
            assert.is_true(markedShare(boxes) > 0.6)
            local start = ui.document:getCurrentPage()
            -- a tap at the right, above the bar, turns the page; the bar stays
            local bar = ui.search.bar:getRect()
            tapRect(Geom:new{ x = Screen:getWidth() - 20, y = bar.y - 40, w = 1, h = 1 })
            assert.are.equal(start + 1, ui.document:getCurrentPage())
            assert.is_true(share(barBlank(ui), isInk) > 0.95)
            -- a hold on the bar selects nothing
            gesture("hold", math.floor(bar.w / 2), bar.y + math.floor(bar.h / 2))
            assert.is_nil(ui.highlight.hold_pos)
            gesture("hold_release", math.floor(bar.w / 2), bar.y + math.floor(bar.h / 2))
            -- a tap on the bar's right end, ×, does not turn the page
            tapRect(ui.search.bar:getCloseRect())
            assert.are.equal(start + 1, ui.document:getCurrentPage())
            assert.is_nil(ui.search:barQuery())
        end)

        it("should say when nothing matches, and let the query be changed", function()
            local page = openSearch(ui)
            search(page, "qzxwqzxw")
            assert.are.same({}, ui.search.results)
            assert.is_truthy(page.message)
            assert.are.equal(_("No matching content found"), page.message.text)
            assert.are.same({}, page.shown_rows)
            assert.is_false(page.bar.capsule.prev_enabled or page.bar.capsule.next_enabled)
            assert.are.equal("qzxwqzxw", page.input:getText())
            assert.is_false(page.typing)

            -- the field again: the keyboard, the query kept
            tapWidget(page.search_field)
            assert.is_true(page.typing)
            assert.is_true(page.input.keyboard:isVisible())
            assert.are.equal("qzxwqzxw", page.input:getText())
            -- a tap outside the field and the keyboard puts it away; the clear button empties the field
            tapRect(Geom:new{ x = 40, y = page.list_rect.y + 40, w = 1, h = 1 })
            assert.is_false(page.typing)
            tapWidget(page.clear_button)
            assert.are.equal("", page.input:getText())
            assert.is_true(page.typing)
            assert.are.equal(0, share(disc(page), isInk))
            search(page, "verona")
            assert.is_nil(page.message)
            assert.is_true(#hitRows(page) > 0)
        end)

        it("should go back to the book with the back arrow, closing the contents page too", function()
            local page, contents = openSearch(ui)
            search(page, "verona")
            local refreshes = refreshesOf(function() tapWidget(page.bar.back) end)
            assert.is_false(UIManager:isWidgetShown(page))
            assert.is_false(UIManager:isWidgetShown(contents))
            assert.is_nil(ui.menu.drawer)
            assert.are.equal(ui, topWidget())
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            -- no hit was opened: no bar
            assert.is_nil(ui.search:barQuery())
        end)

        it("should open the bookmarks from 书签, closing both pages", function()
            local page, contents = openSearch(ui)
            search(page, "verona")
            tapWidget(page.bookmarks_button)
            assert.is_false(UIManager:isWidgetShown(page))
            assert.is_false(UIManager:isWidgetShown(contents))
            local drawer = ui.menu.drawer
            assert.is_truthy(drawer)
            assert.are.equal(drawer, topWidget())
            assert.is_true(drawer.panel_rect ~= nil)
        end)

        it("should show again what was shown when a search is cancelled", function()
            local page = openSearch(ui)
            search(page, "verona")
            local results = ui.search.results
            Trapper.dismissableRunInSubprocess = function() return false end
            local ok, err = pcall(function()
                tapWidget(page.search_field)
                tapWidget(page.clear_button)
                search(page, "romeo")
            end)
            Trapper.dismissableRunInSubprocess = function(_, task) return true, task() end
            assert(ok, err)
            assert.are.equal(results, ui.search.results)
            assert.are.equal("verona", ui.search.query)
            assert.is_false(page.searching)
            assert.is_nil(page.message)
            assert.are.equal(results, page.results)
            assert.are.equal(1, hitRows(page)[1].hit_index)
            assert.are.equal("romeo", page.input:getText())
        end)

        it("should search a query given with the event, as the lookup's 在本书中搜索 will", function()
            ui:handleEvent(Event:new("ShowSearchPage", "verona"))
            UIManager:forceRePaint()
            local page = ui.search.search_page
            assert.is_truthy(page)
            assert.is_false(page.typing)
            assert.are.equal("verona", page.input:getText())
            assert.is_true(#hitRows(page) > 0)
            assert.is_nil(page.contents)
            tapWidget(page.bar.back)
            assert.are.equal(ui, topWidget())
        end)

        it("should leave the original search dialog to the original entries, such as the toolbar's search", function()
            tapRect(Geom:new{ x = 0, y = math.floor(Screen:getHeight() / 2), w = Screen:getWidth(), h = 1 })
            local search_icon = find(ui.menu.bars, function(w) return w.icon == "eink/search" and w.dimen end)
            assert.is_truthy(search_icon)
            tapWidget(search_icon)
            assert.is_truthy(ui.search.input_dialog)
            assert.are.equal(ui.search.input_dialog, topWidget())
            assert.is_nil(ui.search.search_page)
        end)
    end)

    describe("with a PDF", function()
        it("should mark a hit with the page's boxes, and clear them with ×", function()
            local ui = openReader(sample_pdf)
            -- a word of the first page
            local word
            for _, line in ipairs(ui.document:getPageTextBoxes(1)) do
                for _, w in ipairs(line) do
                    if not word and #w.word >= 6 and w.word:match("^%a+$") then word = w.word:lower() end
                end
            end
            assert.is_truthy(word)
            local page = openSearch(ui)
            search(page, word)
            local row = hitRows(page)[1]
            local item = ui.search.results[row.hit_index]
            tapWidget(row)
            assert.are.equal(item.start, ui.paging.current_page)
            hideToolbar(ui)
            assert.is_true(share(barBlank(ui), isInk) > 0.95)
            -- the mark: the word's paper turned hit gray
            local rects = ui.search:markRects()
            assert.is_true(#rects > 0)
            local function paper() local n = 0 for _, r in ipairs(rects) do n = n + share(r, isPaper) end return n / #rects end
            local marked = paper()
            assert.is_true(marked < 0.2)
            tapRect(ui.search.bar:getCloseRect())
            assert.is_nil(ui.search.hit)
            assert.is_nil(ui.search.skim_mode)
            assert.is_true(paper() > marked + 0.3)
            assert.is_true(share(barBlank(ui), isInk) < 0.5) -- the page shows there again
            closeReader(ui)
        end)
    end)
end)
