describe("ReaderHighlightBubble module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderHighlightBubble, Replacements, UIManager, Event, Geom, Screen
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local sample_pdf = "spec/front/unit/data/sample.pdf"

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderHighlightBubble = require("apps/reader/modules/readerhighlightbubble")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Screen = require("device").screen
        ReaderHighlightBubble.register()
    end)

    teardown(function()
        Replacements.reader_highlight = nil
        G_reader_settings:delSetting("highlight_drawing_style")
        DocSettings:open(sample_epub):purge()
        DocSettings:open(sample_pdf):purge()
    end)

    local function openReader(file, purge)
        if purge then DocSettings:open(file):purge() end
        local ui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(file),
        }
        UIManager:show(ui)
        UIManager:forceRePaint()
        return ui
    end

    local function closeReader(ui)
        UIManager:close(ui.highlight.highlight_dialog)
        ui:onClose() -- saves the book settings
        UIManager:quit()
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

    local function assertNoFullScreen(refreshes)
        for _, r in ipairs(refreshes) do
            assert.is_truthy(r.region)
            assert.is_false(r.region.w >= Screen:getWidth() and r.region.h >= Screen:getHeight())
        end
    end

    local function hasRefresh(refreshes, mode, region)
        for _, r in ipairs(refreshes) do
            if r.mode == mode and r.region and r.region.x == region.x and r.region.y == region.y
                    and r.region.w == region.w and r.region.h == region.h then
                return true
            end
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

    local function cell(bubble, text)
        return find(bubble, function(w)
            return w.callback and w.dimen and find(w, function(c) return c.text == text or c.drawer == text end) ~= nil
        end)
    end

    local function iconOf(widget)
        return find(widget, function(w) return w.icon ~= nil end)
    end

    -- gray level of a screen pixel, 0 (ink) to 255 (paper)
    local function gray(x, y)
        return Screen.bb:getPixel(x, y):getColor8().a
    end

    local function inked(x0, y0, x1, y1)
        for y = y0, y1 do
            for x = x0, x1 do
                if gray(x, y) < 0x80 then return true end
            end
        end
        return false
    end

    -- Once painted: a paper card with an ink outline, and an outlined arrow from its edge to the first of the
    -- selection's rects when above it, the last when below.
    local function assertPopover(bubble, rects)
        local anchor = bubble.above and rects[1] or rects[#rects]
        local r, h = bubble.bubble_rect, bubble.arrow_h
        local mid_y = r.y + math.floor(r.h / 2)
        assert.is_true(gray(r.x, mid_y) < 0x80)
        assert.is_true(gray(r.x + r.w - 1, mid_y) < 0x80)
        assert.are.equal(0xFF, gray(r.x + Screen:scaleBySize(3), mid_y))
        assert.is_true(h > 0)
        assert.is_true(bubble.arrow_x >= anchor.x and bubble.arrow_x < anchor.x + anchor.w)
        local x = bubble.arrow_x
        if bubble.above then
            local base = r.y + r.h
            assert.are.equal(0xFF, gray(x, base - 1)) -- the outline opens into the arrow
            assert.are.equal(0xFF, gray(x, base + 1)) -- which is hollow
            assert.is_true(gray(x, base + h - 1) < 0x80) -- up to its tip
            assert.is_true(base + h <= anchor.y)
        else
            assert.are.equal(0xFF, gray(x, r.y))
            assert.are.equal(0xFF, gray(x, r.y - 2))
            assert.is_true(gray(x, r.y - h) < 0x80)
            assert.is_true(r.y - h >= anchor.y + anchor.h)
        end
    end

    -- Each label's cell, left to right, holds the named icon above the label, in at least 44 × 44dp.
    local function assertIconCells(bubble, cells)
        local prev_x = -1
        for _, expected in ipairs(cells) do
            local label, icon_name = expected[1], expected[2]
            local c = cell(bubble, label)
            assert.is_truthy(c, label)
            assert.is_true(c.dimen.x > prev_x, label)
            prev_x = c.dimen.x
            assert.is_true(c.dimen.w >= Screen:scaleBySize(44) and c.dimen.h >= Screen:scaleBySize(44), label)
            local icon = iconOf(c)
            assert.are.equal(icon_name, icon.icon)
            local icon_bottom = icon.dimen.y + icon.dimen.h
            assert.is_true(icon.dimen.y < c.dimen.y + c.dimen.h / 3, label)
            assert.is_true(inked(c.dimen.x, icon_bottom + 1, c.dimen.x + c.dimen.w - 1, c.dimen.y + c.dimen.h - 1), label)
        end
    end

    local SELECTION_ACTIONS = {
        { "Copy", "eink/copy" },
        { "Highlight", "eink/highlight" },
        { "Write note", "eink/thought" },
        { "Look up", "eink/search" },
        { "Search", "eink/search-text" },
    }

    -- Long-press at pos0, drag to pos1 (if any), release.
    local function select(ui, pos0, pos1)
        ui.highlight:onHold(nil, { pos = pos0 })
        if pos1 then
            ui.highlight:onHoldPan(nil, { pos = pos1 })
        end
        UIManager:forceRePaint()
        return refreshesOf(function() ui.highlight:onHoldRelease() end)
    end

    local function noteSheet()
        for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i].widget
            if w.input and w.getRefreshRegion then return w end
        end
    end

    describe("with an EPUB", function()
        local ui
        before_each(function()
            ui = openReader(sample_epub, true)
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()
        end)
        after_each(function() closeReader(ui) end)

        it("should show the selection bubble on top after a long-press, with one fast refresh of the bubble", function()
            local refreshes = select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            local bubble = ui.highlight.highlight_dialog
            assert.is_truthy(bubble)
            assert.are.equal(bubble, topWidget())
            assert.is_truthy(cell(bubble, "Highlight"))
            assert.are.same({ { mode = "fast", region = bubble:getRefreshRegion() } }, refreshes)

            -- a tap outside closes it and repaints only the bubble and the selection
            refreshes = refreshesOf(function() tap(5, Screen:getHeight() - 5) end)
            assert.is_nil(ui.highlight.highlight_dialog)
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.highlight.selected_text)
            assertNoFullScreen(refreshes)
            for _, r in ipairs(refreshes) do
                assert.are.equal("fast", r.mode)
            end
        end)

        it("should show a white popover pointing at the selection, each action an icon over its label", function()
            select(ui, Geom:new{ x = 200, y = 300 }, Geom:new{ x = 200, y = 360 })
            local bubble = ui.highlight.highlight_dialog
            UIManager:forceRePaint()
            assert.is_true(bubble.above)
            assertPopover(bubble, ui.highlight:selectionRects())
            assertIconCells(bubble, SELECTION_ACTIONS)
            ui.highlight:onClose()
        end)

        it("should keep the popover 16dp from the screen edges, its arrow still on the word", function()
            local edge = Screen:scaleBySize(16)
            -- a word at the start of a line: above it, against the left edge
            select(ui, Geom:new{ x = 100, y = 160 })
            local bubble = ui.highlight.highlight_dialog
            UIManager:forceRePaint()
            assert.is_true(bubble.above)
            assert.are.equal(edge, bubble.bubble_rect.x)
            assertPopover(bubble, ui.highlight:selectionRects())
            ui.highlight:onClose()
            UIManager:forceRePaint()

            -- a word on the first line, at its end: below it, against the right edge
            select(ui, Geom:new{ x = 480, y = 60 })
            bubble = ui.highlight.highlight_dialog
            UIManager:forceRePaint()
            assert.is_false(bubble.above)
            assert.are.equal(Screen:getWidth() - edge, bubble.bubble_rect.x + bubble.bubble_rect.w)
            assertPopover(bubble, ui.highlight:selectionRects())
            ui.highlight:onClose()
        end)

        it("should run an action from a tap on its icon", function()
            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            UIManager:forceRePaint()
            tapWidget(iconOf(cell(ui.highlight.highlight_dialog, "Highlight")))
            assert.are.equal(1, #ui.annotation.annotations)
            ui.highlight:onClose()
        end)

        it("should show the bubble, not the dictionary, for a single word", function()
            select(ui, Geom:new{ x = 400, y = 70 })
            assert.are.equal(ui.highlight.highlight_dialog, topWidget())
            ui.highlight:onClose()
        end)

        it("should highlight in the last used style, then persist a change to the wave", function()
            G_reader_settings:saveSetting("highlight_drawing_style", "underscore")
            closeReader(ui)
            ui = openReader(sample_epub)
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()

            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            local refreshes = refreshesOf(function() tapWidget(cell(ui.highlight.highlight_dialog, "Highlight")) end)
            assert.are.equal(1, #ui.annotation.annotations)
            assert.are.equal("underscore", ui.annotation.annotations[1].drawer)
            assertNoFullScreen(refreshes)

            -- then the highlight bubble, refreshed with "ui" for its gray swatch
            local bubble = ui.highlight.highlight_dialog
            assert.are.equal(bubble, topWidget())
            assert.is_truthy(cell(bubble, "wave"))
            assert.is_truthy(hasRefresh(refreshes, "ui", bubble:getRefreshRegion()))

            refreshes = refreshesOf(function() tapWidget(cell(bubble, "wave")) end)
            assertNoFullScreen(refreshes)
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
            end
            assert.are.equal("wave", ui.annotation.annotations[1].drawer)
            assert.are.equal("wave", G_reader_settings:readSetting("highlight_drawing_style"))

            closeReader(ui)
            ui = openReader(sample_epub)
            assert.are.equal(1, #ui.annotation.annotations)
            assert.are.equal("wave", ui.annotation.annotations[1].drawer)
            assert.are.equal("wave", ui.view.highlight.saved_drawer)
        end)

        it("should show the highlight bubble on a tap on a highlight, and save a note", function()
            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            ui.highlight:closeBubble()
            UIManager:forceRePaint()

            local box = ui.view.highlight.visible_boxes[1].rect
            local refreshes = refreshesOf(function()
                tap(box.x + math.floor(box.w / 2), box.y + math.floor(box.h / 2))
            end)
            local bubble = ui.highlight.highlight_dialog
            assert.are.equal(bubble, topWidget())
            assert.are.same({ { mode = "ui", region = bubble:getRefreshRegion() } }, refreshes)
            -- the same white popover: styles, then the actions as icons over labels
            assertPopover(bubble, ui.highlight:highlightRects(1))
            assert.is_truthy(cell(bubble, "wave"))
            assertIconCells(bubble, {
                { "Write note", "eink/thought" },
                { "Copy", "eink/copy" },
                { "Look up", "eink/search" },
                { "Delete", "eink/highlight-off" },
            })

            tapWidget(cell(bubble, "Write note"))
            UIManager:forceRePaint()
            local sheet = noteSheet()
            assert.is_truthy(sheet)
            sheet.input:setText("A thought")
            refreshes = refreshesOf(function() tapWidget(find(sheet, function(w) return w.text == "Save" and w.callback end)) end)
            assert.is_nil(noteSheet())
            assertNoFullScreen(refreshes)
            assert.are.equal("A thought", ui.annotation.annotations[1].note)

            closeReader(ui)
            assert.are.equal("A thought", DocSettings:open(sample_epub):readSetting("annotations")[1].note)
            ui = openReader(sample_epub)
            assert.are.equal("A thought", ui.annotation.annotations[1].note)
        end)

        it("should delete a highlight from its popover, repainting only its lines", function()
            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            UIManager:forceRePaint()
            local refreshes = refreshesOf(function() tapWidget(cell(ui.highlight.highlight_dialog, "Delete")) end)
            assert.are.equal(0, #ui.annotation.annotations)
            assert.is_nil(ui.highlight.highlight_dialog)
            assert.are.equal(ui, topWidget())
            assertNoFullScreen(refreshes)
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
            end
        end)

        it("should drop a highlight made for a note that is cancelled", function()
            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Write note"))
            UIManager:forceRePaint()
            local sheet = noteSheet()
            assert.are.equal(1, #ui.annotation.annotations)
            tapWidget(find(sheet, function(w) return w.text == "Cancel" and w.callback end))
            assert.is_nil(noteSheet())
            assert.are.equal(0, #ui.annotation.annotations)
        end)

        it("should search the whole book for the selection", function()
            stub(ui.search, "searchCallback")
            select(ui, Geom:new{ x = 400, y = 70 })
            local text = ui.highlight.selected_text.text
            tapWidget(cell(ui.highlight.highlight_dialog, "Search"))
            assert.stub(ui.search.searchCallback).was_called_with(match.is_ref(ui.search), nil, text)
            assert.is_nil(ui.highlight.highlight_dialog)
            ui.search.searchCallback:revert()
        end)

        it("should not bring back a looked-up highlight on a long-press on nothing (C1)", function()
            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            ui.highlight:closeBubble()
            UIManager:forceRePaint()
            local box = ui.view.highlight.visible_boxes[1].rect
            tap(box.x + math.floor(box.w / 2), box.y + math.floor(box.h / 2))
            UIManager:forceRePaint()
            stub(ui.dictionary, "onLookupWord")
            tapWidget(cell(ui.highlight.highlight_dialog, "Look up"))
            assert.stub(ui.dictionary.onLookupWord).was_called()
            ui.dictionary.onLookupWord:revert()
            -- long-press where there is no text
            stub(ui.document, "getWordFromPosition")
            select(ui, Geom:new{ x = Screen:getWidth() / 2, y = Screen:getHeight() - 2 })
            ui.document.getWordFromPosition:revert()
            assert.is_nil(ui.highlight.highlight_dialog)
            assert.are.equal(ui, topWidget())
            assert.are.equal(1, #ui.annotation.annotations)
        end)

        it("should keep upstream behavior with the \"Do nothing\" long-press action", function()
            ui.highlight:onSetHighlightAction(2, true) -- "nothing"
            local ok, err = pcall(function()
                select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
                assert.is_nil(ui.highlight.highlight_dialog)
                assert.are.equal(ui, topWidget())
            end)
            ui.highlight:onSetHighlightAction(1, true) -- "ask"
            assert(ok, err)
        end)

        it("should jump to a search result and record the position for going back", function()
            local Trapper = require("ui/trapper")
            local orig_wrap, orig_run = Trapper.wrap, Trapper.dismissableRunInSubprocess
            Trapper.wrap = function(_, fn) return fn() end
            Trapper.dismissableRunInSubprocess = function(_, task) return true, task() end
            local ok, err = pcall(function()
                select(ui, Geom:new{ x = 400, y = 70 })
                tapWidget(cell(ui.highlight.highlight_dialog, "Search"))
                local menu = ui.search.result_menu
                assert.is_truthy(menu)
                assert.are.equal(menu, topWidget())
                assert.is_true(#menu.item_table > 0)
                local stack = #(ui.link.location_stack or {})
                menu.onMenuChoice(menu, menu.item_table[1])
                assert.are.equal(stack + 1, #ui.link.location_stack)
            end)
            Trapper.wrap, Trapper.dismissableRunInSubprocess = orig_wrap, orig_run
            for i = #UIManager._window_stack, 1, -1 do
                local w = UIManager._window_stack[i].widget
                if w ~= ui then UIManager:close(w) end
            end
            assert(ok, err)
        end)
    end)

    describe("without the replacement", function()
        it("should offer the wave in the original Style dialog", function()
            Replacements.reader_highlight = nil
            local ok, err = pcall(function()
                local ui = openReader(sample_epub, true)
                ui.rolling:onGotoPage(10)
                ui.highlight:onHold(nil, { pos = Geom:new{ x = 400, y = 110 } })
                ui.highlight:onHoldPan(nil, { pos = Geom:new{ x = 400, y = 170 } })
                ui.highlight:saveHighlight()
                ui.highlight:onClose()
                ui.highlight:editHighlightStyle(1)
                local selector = topWidget()
                local found
                for _, v in ipairs(selector.values) do
                    if v[2] == "wave" then found = true end
                end
                assert.is_true(found)
                UIManager:close(selector)
                ui.annotation.annotations = {}
                closeReader(ui)
            end)
            ReaderHighlightBubble.register()
            assert(ok, err)
        end)
    end)

    describe("bubble placement", function()
        local SelectionBubble
        setup(function() SelectionBubble = require("ui/widget/selectionbubble") end)
        local function bubbleFor(rects)
            return SelectionBubble:new{ rows = { { { text = "Copy" }, { text = "Search" } } }, anchor_rects = rects }
        end
        local function assertOnScreen(b)
            local r = b:getRefreshRegion()
            assert.is_true(r.x >= 0 and r.y >= 0)
            assert.is_true(r.x + r.w <= Screen:getWidth() and r.y + r.h <= Screen:getHeight())
        end

        it("should go below a selection at the top", function()
            local b = bubbleFor({ Geom:new{ x = 40, y = 5, w = 100, h = 30 } })
            assert.is_false(b.above)
            assert.is_true(b.bubble_rect.y >= 35)
            assertOnScreen(b)
        end)

        it("should go above a selection at the bottom", function()
            local h = Screen:getHeight()
            local b = bubbleFor({ Geom:new{ x = 40, y = h - 40, w = 100, h = 30 } })
            assert.is_true(b.above)
            assert.is_true(b.bubble_rect.y + b.bubble_rect.h <= h - 40)
            assertOnScreen(b)
        end)

        it("should overlay a page-tall selection without an arrow, and survive no selection", function()
            local b = bubbleFor({ Geom:new{ x = 0, y = 10, w = Screen:getWidth(), h = Screen:getHeight() - 20 } })
            assert.are.equal(0, b.arrow_h)
            assertOnScreen(b)
            b = bubbleFor({})
            assert.are.equal(0, b.arrow_h)
            assertOnScreen(b)
        end)
    end)

    describe("with a PDF", function()
        it("should highlight from the bubble", function()
            local ui = openReader(sample_pdf, true)
            ui:handleEvent(Event:new("SetScrollMode", false))
            ui.paging:onGotoPage(10)
            UIManager:forceRePaint()
            select(ui, Geom:new{ x = 430, y = 210 }, Geom:new{ x = 60, y = 236 })
            local bubble = ui.highlight.highlight_dialog
            assert.are.equal(bubble, topWidget())
            UIManager:forceRePaint()
            assertPopover(bubble, ui.highlight:selectionRects())
            assertIconCells(bubble, SELECTION_ACTIONS)
            tapWidget(cell(bubble, "Highlight"))
            assert.are.equal(1, #ui.annotation.annotations)
            local item = ui.annotation.annotations[1]
            assert.are.equal("to take care of the London", item.text)
            assert.are.equal(ui.view.highlight.saved_drawer, item.drawer)
            assert.is_truthy(item.pboxes)
            assert.are.equal(ui.highlight.highlight_dialog, topWidget())
            closeReader(ui)
        end)

        it("should not save a duplicate after a looked-up highlight and a long-press on nothing (C1)", function()
            local ui = openReader(sample_pdf, true)
            ui:handleEvent(Event:new("SetScrollMode", false))
            ui.paging:onGotoPage(10)
            UIManager:forceRePaint()
            select(ui, Geom:new{ x = 430, y = 210 }, Geom:new{ x = 60, y = 236 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            ui.highlight:closeBubble()
            UIManager:forceRePaint()
            ui.highlight:showHighlightBubble(1)
            UIManager:forceRePaint()
            stub(ui.dictionary, "onLookupWord")
            tapWidget(cell(ui.highlight.highlight_dialog, "Look up"))
            ui.dictionary.onLookupWord:revert()
            stub(ui.document, "getWordFromPosition")
            select(ui, Geom:new{ x = 5, y = Screen:getHeight() - 2 })
            ui.document.getWordFromPosition:revert()
            assert.is_nil(ui.highlight.highlight_dialog)
            assert.are.equal(1, #ui.annotation.annotations)
            closeReader(ui)
        end)

        it("should write the highlight into the PDF, and the wave as an underline", function()
            local DataStorage = require("datastorage")
            local copy = DataStorage:getDataDir() .. "/readerhighlightbubble.pdf"
            require("ffi/util").copyFile(sample_pdf, copy)
            local ui = openReader(copy, true)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetScrollMode", false))
                ui.highlight.highlight_write_into_pdf = true
                ui.paging:onGotoPage(10)
                UIManager:forceRePaint()
                select(ui, Geom:new{ x = 430, y = 210 }, Geom:new{ x = 60, y = 236 })
                tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
                local annots = ui.document:getEmbeddedAnnotations()
                assert.is_truthy(annots and annots[10])
                assert.are.equal(1, #annots[10])
                UIManager:forceRePaint()
                tapWidget(cell(ui.highlight.highlight_dialog, "wave"))
                assert.are.equal("wave", ui.annotation.annotations[1].drawer)
                annots = ui.document:getEmbeddedAnnotations()
                assert.is_truthy(annots and annots[10])
                assert.are.equal(1, #annots[10])
                assert.are.equal(9, annots[10][1].type) -- underline
            end)
            closeReader(ui)
            DocSettings:open(copy):purge()
            os.remove(copy)
            assert(ok, err)
        end)
    end)
end)
