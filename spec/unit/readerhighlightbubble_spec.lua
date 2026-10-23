describe("ReaderHighlightBubble module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderHighlightBubble, Replacements, UIManager, Event, Geom, Screen
    local Device, Toast
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
        Device = require("device")
        Screen = Device.screen
        Toast = require("ui/widget/toast")
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
            -- drawn from its own SVG: a missing one keeps the name but paints icon-not-found.svg
            assert.are.equal("/" .. icon_name .. ".svg", icon.file:sub(-#icon_name - 5), label)
            local icon_bottom = icon.dimen.y + icon.dimen.h
            assert.is_true(icon.dimen.y < c.dimen.y + c.dimen.h / 3, label)
            assert.is_true(inked(c.dimen.x, icon_bottom + 1, c.dimen.x + c.dimen.w - 1, c.dimen.y + c.dimen.h - 1), label)
        end
    end

    -- for Latin text, as WeChat Read: highlight, translate, write note, copy; no listening, no search
    local SELECTION_ACTIONS = {
        { "Highlight", "eink/highlight" },
        { "Translate", "eink/translate" },
        { "Write note", "eink/thought" },
        { "Copy", "eink/copy" },
    }
    -- the same in the same places on a highlight, which can be deleted from the first one
    local HIGHLIGHT_ACTIONS = {
        { "Delete highlight", "eink/highlight-off" },
        { "Translate", "eink/translate" },
        { "Write note", "eink/thought" },
        { "Copy", "eink/copy" },
    }

    -- The popover shows exactly these actions in one row, left to right, each an icon over its label.
    local function assertActions(bubble, actions)
        assert.are.equal(1, #bubble.rows)
        local labels, expected = {}, {}
        for i, cell_spec in ipairs(bubble.rows[1]) do labels[i] = cell_spec.text end
        for i, a in ipairs(actions) do expected[i] = a[1] end
        assert.are.same(expected, labels)
        assertIconCells(bubble, actions)
    end

    -- Long-press at pos0, drag to pos1 (if any), release.
    local function select(ui, pos0, pos1)
        ui.highlight:onHold(nil, { pos = pos0 })
        if pos1 then
            ui.highlight:onHoldPan(nil, { pos = pos1 })
        end
        UIManager:forceRePaint()
        return refreshesOf(function() ui.highlight:onHoldRelease() end)
    end

    -- the topmost widget made by `class`, if any
    local function shown(class)
        for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i].widget
            if getmetatable(w).__index == class then return w end
        end
    end

    -- a point inside the first visible box of a highlight
    local function highlightPoint(ui)
        local r = ui.highlight:boxToScreen(ui.view.highlight.visible_boxes[1])
        return Geom:new{ x = r.x + math.floor(r.w / 2), y = r.y + math.floor(r.h / 2) }
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
            assertActions(bubble, SELECTION_ACTIONS)
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

        it("should draw new highlights as lines until a default style is saved, whatever the book saved", function()
            G_reader_settings:delSetting("highlight_drawing_style")
            closeReader(ui)
            -- upstream saves the current style with the book on every close: the marker until now
            local doc_settings = DocSettings:open(sample_epub)
            doc_settings:saveSetting("highlight_drawer", "lighten")
            doc_settings:flush()
            ui = openReader(sample_epub)
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()

            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            assert.are.equal("underscore", ui.annotation.annotations[1].drawer)
            assert.is_nil(G_reader_settings:readSetting("highlight_drawing_style")) -- nothing was saved
            ui.highlight:closeBubble()

            -- the book keeps its own style, for upstream KOReader and devices without touch
            closeReader(ui)
            assert.are.equal("lighten", DocSettings:open(sample_epub):readSetting("highlight_drawer"))

            -- a saved default is used as it is
            G_reader_settings:saveSetting("highlight_drawing_style", "wave")
            ui = openReader(sample_epub)
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()
            select(ui, Geom:new{ x = 200, y = 300 }, Geom:new{ x = 200, y = 360 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            local drawers = {}
            for _, item in ipairs(ui.annotation.annotations) do drawers[item.drawer] = true end
            assert.are.same({ underscore = true, wave = true }, drawers)
            G_reader_settings:delSetting("highlight_drawing_style")
            closeReader(ui)
            assert.are.equal("lighten", DocSettings:open(sample_epub):readSetting("highlight_drawer"))
            -- and a book without one still has none
            DocSettings:open(sample_epub):purge()
            ui = openReader(sample_epub)
            closeReader(ui)
            assert.is_nil(DocSettings:open(sample_epub):readSetting("highlight_drawer"))
            ui = openReader(sample_epub)
        end)

        it("should give the next highlight the default style chosen in the settings", function()
            G_reader_settings:delSetting("highlight_drawing_style")
            local page = require("apps/settings/einksettings").show(ui, ui.menu, "highlight_style")
            UIManager:forceRePaint()
            local wave
            for _, spec in ipairs(page.shown) do
                if spec.name == "Wavy underline" then wave = spec end
            end
            UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{
                x = wave.rect.x + math.floor(wave.rect.w / 2), y = wave.rect.y + math.floor(wave.rect.h / 2), w = 0, h = 0 } }))
            assert.are.equal("wave", G_reader_settings:readSetting("highlight_drawing_style"))
            page:closeMenu()
            UIManager:forceRePaint()
            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            assert.are.equal("wave", ui.annotation.annotations[1].drawer)
            ui.highlight:closeBubble()
            G_reader_settings:delSetting("highlight_drawing_style")
        end)

        it("should keep drawing old marker and wave highlights", function()
            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            select(ui, Geom:new{ x = 200, y = 300 }, Geom:new{ x = 200, y = 360 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            ui.highlight:closeBubble()
            -- as made with the old popover's style row
            for i, drawer in ipairs{ "lighten", "wave" } do
                ui.annotation.annotations[i].drawer = drawer
            end
            closeReader(ui)
            ui = openReader(sample_epub)
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()
            local drawn = {}
            for _, box in ipairs(ui.view.highlight.visible_boxes) do drawn[box.drawer] = box end
            assert.is_truthy(drawn.lighten and drawn.wave)
            assert.are.equal("underscore", ui.view.highlight.saved_drawer)
            -- the marker fills its box: hardly any paper is left in it
            local function paperShare(r)
                local paper, all = 0, 0
                for y = r.y, r.y + r.h - 1 do
                    for x = r.x, r.x + r.w - 1 do
                        all = all + 1
                        if gray(x, y) >= 0xF8 then paper = paper + 1 end
                    end
                end
                return paper / all
            end
            assert.is_true(paperShare(ui.highlight:boxToScreen(drawn.lighten)) < 0.1)
            assert.is_true(paperShare(ui.highlight:boxToScreen(drawn.wave)) > 0.5) -- unlike text without it
            -- the wave runs under the glyphs without a gap, even between words
            local w = ui.highlight:boxToScreen(drawn.wave)
            -- (in the highlight color: the emulator's screen is a color one)
            local function marked(x, y0, y1)
                for y = y0, y1 do
                    if gray(x, y) < 0xF0 then return true end
                end
                return false
            end
            for x = w.x, w.x + w.w - 1 do
                assert.is_true(marked(x, w.y + math.floor(w.h / 2), w.y + w.h + Screen:scaleBySize(4)), x)
            end
        end)

        it("should turn Highlight into Delete highlight in the same place once highlighted", function()
            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            local bubble = ui.highlight.highlight_dialog
            UIManager:forceRePaint()
            local before = { above = bubble.above, y = bubble:getRefreshRegion().y, arrow_x = bubble.arrow_x }
            tapWidget(cell(bubble, "Highlight"))
            UIManager:forceRePaint()
            assert.are.equal(1, #ui.annotation.annotations)
            bubble = ui.highlight.highlight_dialog
            assert.are.equal(bubble, topWidget())
            -- on the same side of the same text, pointing at the same place; only the label width can differ
            assert.are.same(before, { above = bubble.above, y = bubble:getRefreshRegion().y, arrow_x = bubble.arrow_x })
            assertPopover(bubble, ui.highlight:highlightRects(1))
            assertActions(bubble, HIGHLIGHT_ACTIONS)
            ui.highlight:closeBubble()
        end)

        it("should show a highlight's popover on a long-press on a word of it, and delete it from there", function()
            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            ui.highlight:closeBubble()
            UIManager:forceRePaint()
            local pos = highlightPoint(ui)
            local word = ui.document:getWordFromPosition(ui.view:screenToPageTransform(pos)).word
            local refreshes = select(ui, pos)
            local bubble = ui.highlight.highlight_dialog
            assert.are.equal(bubble, topWidget())
            assertNoFullScreen(refreshes)
            UIManager:forceRePaint()
            assertPopover(bubble, ui.highlight:highlightRects(1))
            assertActions(bubble, HIGHLIGHT_ACTIONS)
            assert.is_nil(ui.highlight.selected_text) -- the word's selection is gone
            assert.are.equal(1, #ui.annotation.annotations) -- and no second highlight
            -- the look-up is still for the word pressed, not the whole highlight
            assert.are_not.equal(word, ui.annotation.annotations[1].text)
            stub(ui.dictionary, "onLookupWord")
            tapWidget(cell(bubble, "Translate"))
            assert.stub(ui.dictionary.onLookupWord).was_called()
            assert.are.equal(word, ui.dictionary.onLookupWord.calls[1].vals[2])
            ui.dictionary.onLookupWord:revert()
            ui.highlight:onClose()
            UIManager:forceRePaint()
            select(ui, highlightPoint(ui))
            bubble = ui.highlight.highlight_dialog
            UIManager:forceRePaint()
            tapWidget(cell(bubble, "Delete highlight"))
            UIManager:forceRePaint()
            assert.are.equal(0, #ui.annotation.annotations)
            assert.are.same({}, ui.view.highlight.visible_boxes)
            closeReader(ui)
            assert.are.same({}, DocSettings:open(sample_epub):readSetting("annotations"))
            ui = openReader(sample_epub)
        end)

        it("should copy the selection, close the popover and confirm with a toast", function()
            local copied
            stub(Device.input, "setClipboardText", function(text) copied = text end)
            local mock_time = require("mock_time")
            mock_time:install()
            UIManager:_checkTasks() -- the clock is now the mock's
            local ok, err = pcall(function()
                select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
                local text = require("util").cleanupSelectedText(ui.highlight.selected_text.text)
                local refreshes = refreshesOf(function() tapWidget(cell(ui.highlight.highlight_dialog, "Copy")) end)
                assert.are.equal(text, copied)
                assert.is_nil(ui.highlight.highlight_dialog)
                assert.is_nil(ui.highlight.selected_text)
                assert.are.equal(0, #ui.annotation.annotations)
                local toast = shown(Toast)
                assert.are.equal(toast, topWidget())
                assert.are.equal("Copied", toast.text)
                assertNoFullScreen(refreshes)
                assert.is_truthy(hasRefresh(refreshes, "fast", toast.dimen))
                -- an ink box over the lower part of the page, at least as wide as in the reference
                local r = toast.dimen
                assert.is_true(r.y > Screen:getHeight() / 2 and r.y + r.h < Screen:getHeight())
                assert.is_true(r.w >= Screen:scaleBySize(248))
                assert.is_true(gray(r.x + math.floor(r.w / 2), r.y + 2) < 0x80)
                assert.are.equal(Screen:getWidth() - r.x - r.w, r.x) -- centered

                -- gone by itself after 2 s
                mock_time:increase(1)
                UIManager:_checkTasks()
                assert.are.equal(toast, shown(Toast))
                mock_time:increase(1)
                refreshes = refreshesOf(function() UIManager:_checkTasks() end)
                assert.is_nil(shown(Toast))
                assert.are.same({ { mode = "fast", region = r } }, refreshes)

                -- or as soon as the next long-press, which still selects
                select(ui, Geom:new{ x = 400, y = 70 })
                tapWidget(cell(ui.highlight.highlight_dialog, "Copy"))
                assert.is_truthy(shown(Toast))
                local pos = Geom:new{ x = 400, y = 110, w = 0, h = 0 }
                UIManager:sendEvent(Event:new("Gesture", { ges = "hold", pos = pos }))
                UIManager:sendEvent(Event:new("Gesture", { ges = "hold_release", pos = pos }))
                assert.is_nil(shown(Toast))
                assert.are.equal(ui.highlight.highlight_dialog, topWidget())
                ui.highlight:onClose()

                -- a highlight's text is copied the same way, and the highlight stays
                select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
                tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
                UIManager:forceRePaint()
                tapWidget(cell(ui.highlight.highlight_dialog, "Copy"))
                assert.are.equal(ui.annotation.annotations[1].text, copied)
                assert.is_nil(ui.highlight.highlight_dialog)
                assert.are.equal(1, #ui.annotation.annotations)
                assert.is_truthy(shown(Toast))
                UIManager:close(shown(Toast))
            end)
            mock_time:uninstall()
            Device.input.setClipboardText:revert()
            assert(ok, err)
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
            -- the same black and white popover, with no row of styles
            assert.are.same({ { mode = "fast", region = bubble:getRefreshRegion() } }, refreshes)
            assertPopover(bubble, ui.highlight:highlightRects(1))
            assertActions(bubble, HIGHLIGHT_ACTIONS)

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
            local bubble_region = ui.highlight.highlight_dialog:getRefreshRegion()
            local lines = ui.highlight:linesRegion(ui.highlight:highlightRects(1))
            local refreshes = refreshesOf(function() tapWidget(cell(ui.highlight.highlight_dialog, "Delete highlight")) end)
            assert.are.equal(0, #ui.annotation.annotations)
            assert.is_nil(ui.highlight.highlight_dialog)
            assert.are.equal(ui, topWidget())
            -- the popover leaves with "fast" (nothing gray under it), the highlight's lines with "ui"
            -- (UIManager may merge the two into one "ui" region), and the status bar counts one note less
            local footer_h = ui.view.footer:getHeight()
            local footer = Geom:new{ x = 0, y = Screen:getHeight() - footer_h, w = Screen:getWidth(), h = footer_h }
            local both, lines_repainted = bubble_region:combine(lines), false
            for _, r in ipairs(refreshes) do
                if r.mode == "fast" then
                    assert.are.same(bubble_region, r.region)
                else
                    assert.are.equal("ui", r.mode)
                    assert.is_true(both:contains(r.region) or footer:contains(r.region))
                    lines_repainted = lines_repainted or r.region:contains(lines)
                end
            end
            assert.is_true(lines_repainted)
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

        it("should not bring back a looked-up highlight on a long-press on nothing (C1)", function()
            select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            ui.highlight:closeBubble()
            UIManager:forceRePaint()
            local box = ui.view.highlight.visible_boxes[1].rect
            tap(box.x + math.floor(box.w / 2), box.y + math.floor(box.h / 2))
            UIManager:forceRePaint()
            stub(ui.dictionary, "onLookupWord")
            tapWidget(cell(ui.highlight.highlight_dialog, "Translate"))
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
    end)

    -- The selection is an ink underline with a drop handle under each end; dragging a handle moves that end.
    -- Driven by gestures as the gesture detector sends them, through the window stack.
    describe("selection underline and handles", function()
        local time
        setup(function() time = require("ui/time") end)

        local clock = 0 -- gesture times, a second apart: past any rate limit
        local function point(p) return Geom:new{ x = p.x, y = p.y, w = 0, h = 0 } end
        -- fields: start_pos (pans) or end_pos (swipes), as points too
        local function gesture(kind, pos, fields)
            clock = clock + 1
            local ev = { ges = kind, pos = point(pos), time = time.s(clock) }
            for k, v in pairs(fields or {}) do ev[k] = v end
            ev.start_pos = ev.start_pos and point(ev.start_pos)
            ev.end_pos = ev.end_pos and point(ev.end_pos)
            UIManager:sendEvent(Event:new("Gesture", ev))
        end

        -- A long-press at `from`, dragged to `to` if given, then released.
        local function longPress(from, to)
            gesture("hold", from)
            if to then gesture("hold_pan", to) end
            UIManager:forceRePaint()
            gesture("hold_release", to or from)
            UIManager:forceRePaint()
        end

        -- A finger put down at `from` and moved to `to` in three pans, then lifted: slowly (pan_release), or
        -- quickly (swipe, reported from where it went down). Returns the refreshes of the pans.
        local function drag(from, to, lift)
            local refreshes = refreshesOf(function()
                for i = 1, 3 do
                    local p = { x = from.x + math.floor((to.x - from.x) * i / 3), y = from.y + math.floor((to.y - from.y) * i / 3) }
                    gesture("pan", p, { start_pos = from, relative = { x = p.x - from.x, y = p.y - from.y } })
                end
            end)
            if lift == "swipe" then
                gesture("swipe", from, { end_pos = to })
            else
                gesture("pan_release", to)
            end
            UIManager:forceRePaint()
            return refreshes
        end

        -- The row of a segment's underline: the lowest ink in its columns, under its glyphs.
        local function underlineRow(r)
            for row = r.y + r.h - 1, r.y, -1 do
                for x = r.x, r.x + r.w - 1 do
                    if gray(x, row) < 0x80 then return row end
                end
            end
        end

        -- A 1dp ink line under the segment's glyphs, not touching them (where a line highlight would be), and no
        -- fill: paper in its box, where crengine's gray selection would be.
        local function assertUnderline(r)
            local u = underlineRow(r)
            for x = r.x, r.x + r.w - 1 do
                assert.is_true(gray(x, u) < 0x80, "underline at " .. x)
                assert.is_true(gray(x, u + Screen:scaleBySize(1)) >= 0x80, "1dp at " .. x)
                assert.is_true(gray(x, u - 1) >= 0x80, "under the glyphs at " .. x)
                assert.is_true(gray(x, r.y + 1) >= 0xF0, "fill at " .. x)
            end
            -- paper between the glyphs and the line, but for the tips of their strokes
            local paper = 0
            for x = r.x, r.x + r.w - 1 do
                if gray(x, u - 1) >= 0xF0 then paper = paper + 1 end
            end
            assert.is_true(paper > r.w * 0.9)
        end

        -- The 25dp ink drop hanging under the start or end of a segment, its flat top 4dp above the underline,
        -- its corner toward the text squared and the other ones round (checked when clear of other text).
        -- Returns its square.
        local function assertHandle(r, side, clear)
            local d, u = Screen:scaleBySize(25), underlineRow(r)
            local h = Geom:new{ x = side == "start" and r.x - d or r.x + r.w, y = u - Screen:scaleBySize(4), w = d, h = d }
            local inner, outer = h.x, h.x + d - 1
            if side == "start" then inner, outer = outer, inner end
            assert.is_true(gray(inner, h.y + 1) < 0x80, side .. ": squared corner")
            assert.is_true(gray(h.x + math.floor(d / 2), h.y + math.floor(d / 2)) < 0x80, side .. ": center")
            if clear then
                assert.is_true(gray(outer, h.y + 1) >= 0xF0, side .. ": round top corner")
                assert.is_true(gray(inner, h.y + d - 1) >= 0xF0, side .. ": round bottom corner")
                assert.is_true(gray(h.x + math.floor(d / 2), h.y + d - 1) < 0x80, side .. ": bottom")
                assert.is_true(gray(h.x + math.floor(d / 2), h.y + d + 1) >= 0xF0, side .. ": below")
            end
            return h
        end

        local function center(r)
            return { x = r.x + math.floor(r.w / 2), y = r.y + math.floor(r.h / 2) }
        end

        local function assertNoNotes(ui)
            assert.are.equal(0, #ui.annotation.annotations)
        end

        describe("with an EPUB", function()
            local ui
            before_each(function()
                ui = openReader(sample_epub, true)
                ui.rolling:onGotoPage(10)
                UIManager:forceRePaint()
            end)
            after_each(function() closeReader(ui) end)

            -- SAMPSON, a speaker's name alone on its line, at the start of the text column
            local SAMPSON = { x = 100, y = 160 }

            it("should underline a long-pressed word in ink and hang a drop handle under each end", function()
                local refreshes = refreshesOf(function() gesture("hold", SAMPSON) end)
                local r = ui.highlight:selectionRects()[1]
                assert.are.equal("SAMPSON", ui.highlight.selected_text.text)
                assertUnderline(r)
                local handles = { assertHandle(r, "start", true), assertHandle(r, "end", true) }
                -- shown as soon as the word is selected, along with it
                assertNoFullScreen(refreshes)
                local shown_all = false
                for _, refresh in ipairs(refreshes) do
                    shown_all = shown_all or (refresh.region:contains(handles[1]) and refresh.region:contains(handles[2]))
                end
                assert.is_true(shown_all)

                -- still there with the popover, which points at the word
                gesture("hold_release", SAMPSON)
                UIManager:forceRePaint()
                local bubble = ui.highlight.highlight_dialog
                assert.are.equal(bubble, topWidget())
                assertPopover(bubble, ui.highlight:selectionRects())
                assertUnderline(r)
                assertHandle(r, "start", true)
                assertHandle(r, "end", true)
                assertNoNotes(ui)

                -- and gone with it
                refreshes = refreshesOf(function() tap(Screen:getWidth() - 5, Screen:getHeight() - 5) end)
                assert.is_nil(ui.highlight.selected_text)
                assertNoFullScreen(refreshes)
                for _, h in ipairs(handles) do
                    assert.is_true(gray(h.x + math.floor(h.w / 2), h.y + math.floor(h.h / 2)) >= 0xF0)
                    local repainted = false
                    for _, refresh in ipairs(refreshes) do
                        repainted = repainted or refresh.region:contains(h)
                    end
                    assert.is_true(repainted)
                end
            end)

            it("should underline every line of a selection dragged over several", function()
                longPress(SAMPSON, { x = 300, y = 200 })
                local rects = ui.highlight:selectionRects()
                assert.is_true(rects[#rects].y > rects[1].y)
                for _, r in ipairs(rects) do assertUnderline(r) end
                assertHandle(rects[1], "start", true)
                assertHandle(rects[#rects], "end")
                ui.highlight:onClose()
            end)

            it("should move the end with its handle across lines, then show the popover again, saving nothing", function()
                longPress(SAMPSON)
                local before = ui.highlight.selected_text
                local r = ui.highlight:selectionRects()[1]
                local handle = assertHandle(r, "end", true)
                local bubble = ui.highlight.highlight_dialog
                local card = bubble.bubble_rect
                local from = center(handle)
                local to = { x = from.x + 130, y = from.y + 40 }

                -- the popover hides while the handle is dragged; the page shows again where it was
                gesture("pan", { x = from.x + 40, y = from.y + 10 }, { start_pos = from })
                UIManager:forceRePaint()
                assert.is_true(bubble.hidden)
                assert.is_true(gray(card.x, card.y + math.floor(card.h / 2)) >= 0xF0)

                local refreshes = drag(from, to)
                local selected = ui.highlight.selected_text
                assert.are.equal(before.pos0, selected.pos0) -- the start stays
                assert.are_not.equal(before.pos1, selected.pos1)
                assert.are.equal(1, selected.text:find("SAMPSON", 1, true))
                local rects = ui.highlight:selectionRects()
                assert.is_true(rects[#rects].y > r.y) -- another line
                for _, rect in ipairs(rects) do assertUnderline(rect) end
                assertHandle(rects[1], "start", true)
                local new_handle = assertHandle(rects[#rects], "end")
                assert.is_true(gray(handle.x + handle.w - 1, handle.y + 1) >= 0xF0) -- the old one is gone
                -- only lines and handles repainted, black and white: fast
                assert.is_true(#refreshes > 0)
                assertNoFullScreen(refreshes)
                for _, refresh in ipairs(refreshes) do
                    assert.are.equal("fast", refresh.mode)
                end
                assert.is_true(refreshes[#refreshes].region:contains(new_handle))

                -- still a selection: its popover is back, at its new place
                bubble = ui.highlight.highlight_dialog
                assert.are.equal(bubble, topWidget())
                assert.is_falsy(bubble.hidden)
                assertPopover(bubble, rects)
                assertActions(bubble, SELECTION_ACTIONS)
                assertNoNotes(ui)

                -- a tap on a handle keeps it; one elsewhere clears it, and nothing was saved
                tap(new_handle.x + math.floor(new_handle.w / 2), new_handle.y + math.floor(new_handle.h / 2))
                assert.are.equal(selected, ui.highlight.selected_text)
                assert.are.equal(bubble, topWidget())
                tap(Screen:getWidth() - 5, Screen:getHeight() - 5)
                assert.is_nil(ui.highlight.selected_text)
                assert.are.equal(ui, topWidget())
                closeReader(ui)
                assert.are.same({}, DocSettings:open(sample_epub):readSetting("annotations") or {})
                ui = openReader(sample_epub)
            end)

            it("should move the start with its handle after a hold, the end staying", function()
                longPress(SAMPSON)
                local before = ui.highlight.selected_text
                local r = ui.highlight:selectionRects()[1]
                local from = center(assertHandle(r, "start", true))
                local to = { x = from.x + 250, y = from.y - 60 }
                -- a slow drag: the hold comes once the finger moved off the handle, short of a pan
                gesture("touch", from)
                gesture("hold", { x = from.x + 28, y = from.y + 28 })
                gesture("hold_pan", to)
                gesture("hold_release", to)
                UIManager:forceRePaint()
                local selected = ui.highlight.selected_text
                assert.are.equal(before.pos1, selected.pos1)
                assert.are_not.equal(before.pos0, selected.pos0)
                local rects = ui.highlight:selectionRects()
                assert.is_true(rects[1].y < r.y)
                assertHandle(rects[1], "start")
                assertHandle(rects[#rects], "end", true)
                assert.are.equal(ui.highlight.highlight_dialog, topWidget())
                assertNoNotes(ui)
                ui.highlight:onClose()
            end)

            it("should swap the ends when a handle is dragged past the other one, also with a quick swipe", function()
                longPress(SAMPSON)
                local before = ui.highlight.selected_text
                local r = ui.highlight:selectionRects()[1]
                local from = center(assertHandle(r, "end", true))
                drag(from, { x = from.x + 200, y = from.y - 60 }, "swipe")
                local selected = ui.highlight.selected_text
                -- from a word on the line above to the end of the name, which the start was in
                assert.are.equal(before.pos1, selected.pos1)
                assert.are_not.equal(before.pos0, selected.pos0)
                local rects = ui.highlight:selectionRects()
                assert.is_true(rects[1].y < r.y)
                assertHandle(rects[#rects], "end", true)
                assert.are.equal(ui.highlight.highlight_dialog, topWidget())
                assertNoNotes(ui)
                ui.highlight:onClose()
            end)

            it("should not leave the hidden popover behind when the dragged selection has no line on the screen", function()
                longPress(SAMPSON)
                local popover = ui.highlight.highlight_dialog
                local from = center(assertHandle(ui.highlight:selectionRects()[1], "end", true))
                gesture("pan", { x = from.x + 40, y = from.y + 10 }, { start_pos = from })
                assert.is_true(popover.hidden)
                -- as when nothing of it is left on the screen: upstream's menu instead
                local rects = ui.highlight.selectionRects
                ui.highlight.selectionRects = function() return {} end
                local ok, err = pcall(function()
                    gesture("pan_release", { x = from.x + 40, y = from.y + 10 })
                    for _, window in ipairs(UIManager._window_stack) do
                        assert.are_not.equal(popover, window.widget)
                    end
                end)
                ui.highlight.selectionRects = rects
                assert(ok, err)
                ui.highlight:onClose()
            end)

            it("should keep a popover below a selection at the page top clear of its handles", function()
                longPress({ x = 300, y = 30 }) -- on the first line
                local bubble = ui.highlight.highlight_dialog
                assert.is_false(bubble.above)
                local r = ui.highlight:selectionRects()[1]
                local h = assertHandle(r, "end")
                assert.is_true(bubble:getRefreshRegion().y >= h.y + h.h)
                ui.highlight:onClose()
            end)

            it("should keep the handles on the page and the popover above at the page foot", function()
                local last = { x = 100, y = 740 } -- SAMPSON again, on the last line
                longPress(last)
                local bubble = ui.highlight.highlight_dialog
                assert.is_true(bubble.above)
                local r = ui.highlight:selectionRects()[1]
                assert.is_true(r.y > Screen:getHeight() * 0.85)
                for _, side in ipairs{ "start", "end" } do
                    local h = assertHandle(r, side)
                    assert.is_true(h.y + h.h <= Screen:getHeight())
                end
                ui.highlight:onClose()
            end)

            it("should underline a selection where a line highlight already is on the same line", function()
                G_reader_settings:saveSetting("highlight_color", "gray") -- as on a black and white screen
                ui.view.highlight.saved_color = "gray"
                local r = (function()
                    gesture("hold", SAMPSON)
                    local rect = ui.highlight:selectionRects()[1]
                    ui.highlight:onClose()
                    UIManager:forceRePaint()
                    return rect
                end)()
                local glyphs = underlineRow(r) -- on a clean page: the glyphs' bottom
                longPress(SAMPSON)
                tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
                ui.highlight:closeBubble()
                UIManager:forceRePaint()
                local line = underlineRow(r) -- the highlight's line, 2dp thick
                assert.are.equal(glyphs + Screen:scaleBySize(3) + Screen:scaleBySize(2), line)
                -- a selection from the line above over it: its underline is on that line, not under it
                longPress({ x = 400, y = 110 }, { x = 120, y = 160 })
                local rects = ui.highlight:selectionRects()
                assert.are.equal(r.y, rects[#rects].y)
                assert.are.equal(line, underlineRow(r))
                assertHandle(rects[#rects], "end")
                ui.highlight:onClose()
                G_reader_settings:delSetting("highlight_color")
            end)

            it("should select across pages with a handle dragged to the bottom corner, then turn back", function()
                local page = ui.view.state.page
                longPress({ x = 100, y = 740 }) -- the last line
                local before = ui.highlight.selected_text
                local r = ui.highlight:selectionRects()[1]
                local from = center(assertHandle(r, "end"))
                local w, h = Screen:getWidth(), Screen:getHeight()
                -- out of the corner first, then into it: the page scrolls a third of the screen up, and the
                -- selection with it, even released there
                gesture("pan", { x = from.x + 100, y = from.y }, { start_pos = from })
                gesture("pan", { x = w - 5, y = h - 5 }, { start_pos = from })
                assert.are.equal("scroll", ui.view.view_mode)
                gesture("pan_release", { x = w - 5, y = h - 5 })
                UIManager:forceRePaint()
                local selected = ui.highlight.selected_text
                local lines = ui.document:getScreenBoxesFromPositions(selected.pos0, selected.pos1, true)
                assert.is_true(lines[1].y < r.y - Screen:getHeight() / 4)
                for _, line in ipairs(lines) do assertUnderline(line) end
                local handle = assertHandle(lines[#lines], "end")
                assert.are.equal(ui.highlight.highlight_dialog, topWidget())
                -- and goes on from there into the next page's text
                from = center(handle)
                drag(from, { x = w - 150, y = math.min(h - 150, from.y + 200) })
                selected = ui.highlight.selected_text
                assert.are.equal(before.pos0, selected.pos0)
                assert.are.equal(1, ui.document:compareXPointers(before.pos1, selected.pos1))
                assert.is_true(#selected.text > #"SAMPSON" + 40) -- on into the next page's text
                assert.are.equal(ui.highlight.highlight_dialog, topWidget())
                assertNoNotes(ui)
                -- clearing turns back to the page it started on
                tap(5, 5)
                UIManager:forceRePaint()
                assert.are.equal("page", ui.view.view_mode)
                assert.are.equal(page, ui.view.state.page)
                assertNoNotes(ui)
            end)

            -- During fn: the bottom of the lowest line ReaderView:underlineY() is asked about, and whether it read
            -- a pixel off the screen (the screen buffer has no bounds checks: that reads other memory, or crashes).
            -- Such a read is counted, then made on the screen.
            local function underlineReads(fn)
                local lowest, off_screen = math.huge, false
                local underlineY = ui.view.underlineY
                ui.view.underlineY = function(view, bb, rects)
                    lowest = math.min(lowest, rects[1].y + rects[1].h - 1)
                    local checked = setmetatable({
                        getPixel = function(_, px, py)
                            local w, h = bb:getWidth(), bb:getHeight()
                            if px < 0 or px >= w or py < 0 or py >= h then
                                off_screen = true
                                px, py = math.max(0, math.min(w - 1, px)), math.max(0, math.min(h - 1, py))
                            end
                            return bb:getPixel(px, py)
                        end,
                    }, { __index = function(_, k)
                        local method = bb[k]
                        return function(_, ...) return method(bb, ...) end
                    end })
                    return underlineY(view, checked, rects)
                end
                local ok, err = pcall(fn)
                ui.view.underlineY = nil -- back to ReaderView's
                assert(ok, err)
                return lowest, off_screen
            end

            it("should draw a long-press drag from the first line on across pages, its lines off the screen left out", function()
                local page = ui.view.state.page
                local w, h = Screen:getWidth(), Screen:getHeight()
                local lowest, off_screen = underlineReads(function()
                    gesture("hold", { x = 300, y = 30 })
                    UIManager:forceRePaint()
                    gesture("hold_pan", { x = 300, y = 400 })
                    gesture("hold_pan", { x = w - 5, y = h - 5 }) -- into the corner: the page scrolls up
                    UIManager:forceRePaint()
                end)
                assert.are.equal("scroll", ui.view.view_mode)
                local selected = ui.highlight.selected_text
                local lines = ui.document:getScreenBoxesFromPositions(selected.pos0, selected.pos1, true)
                assert.is_true(lines[1].y + lines[1].h < 0) -- its first lines went above the screen
                assert.is_true(lowest >= 0) -- and were not measured
                assert.is_false(off_screen)
                local visible = 0
                for _, line in ipairs(lines) do
                    if line.y >= 0 and line.y + line.h <= h then
                        assertUnderline(line)
                        visible = visible + 1
                    end
                end
                assert.is_true(visible >= 3)
                assertHandle(lines[#lines], "end")
                gesture("hold_release", { x = w - 5, y = h - 5 })
                UIManager:forceRePaint()
                assert.are.equal(ui.highlight.highlight_dialog, topWidget())
                tap(5, 5)
                UIManager:forceRePaint()
                assert.are.equal("page", ui.view.view_mode)
                assert.are.equal(page, ui.view.state.page)
                assertNoNotes(ui)
            end)

            it("should draw a line highlight going above the screen in scroll mode, the rest of it as always", function()
                G_reader_settings:saveSetting("highlight_color", "gray") -- as on a black and white screen
                ui.view.highlight.saved_color = "gray"
                ui:handleEvent(Event:new("SetViewMode", "scroll"))
                UIManager:forceRePaint()
                longPress(SAMPSON, { x = 300, y = 290 })
                tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
                ui.highlight:closeBubble()
                UIManager:forceRePaint()
                local item = ui.annotation.annotations[1]
                local boxes = ui.document:getScreenBoxesFromPositions(item.pos0, item.pos1, true)
                -- scrolled until its first lines are above the screen, repainted, scrolled on a little
                local lowest, off_screen = underlineReads(function()
                    ui.rolling:_gotoPos(ui.document:getCurrentPos() + boxes[2].y + boxes[2].h + 2)
                    UIManager:forceRePaint()
                    ui.rolling:_gotoPos(ui.document:getCurrentPos() + 7)
                    UIManager:forceRePaint()
                end)
                assert.is_true(lowest < 0) -- asked about lines above the screen
                assert.is_false(off_screen) -- without reading there
                boxes = ui.document:getScreenBoxesFromPositions(item.pos0, item.pos1, true)
                assert.is_true(boxes[2].y + boxes[2].h <= 0)
                local visible = 0
                for _, box in ipairs(boxes) do
                    if box.y >= 0 and box.y + box.h <= Screen:getHeight() then
                        local row = underlineRow(box)
                        for x = box.x, box.x + box.w - 1 do
                            assert.is_true(gray(x, row) < 0x80, "line at " .. x)
                        end
                        visible = visible + 1
                    end
                end
                assert.is_true(visible >= 2)
                G_reader_settings:delSetting("highlight_color")
            end)

            it("should keep the handles over the footer when it repaints itself, and draw the underline once", function()
                ui:handleEvent(Event:new("SetPageBottomMargin", 0)) -- the last line right above the footer
                UIManager:forceRePaint()
                local page = ui.document:getTextFromPositions({ x = 0, y = 0 },
                    { x = Screen:getWidth(), y = Screen:getHeight() }, true)
                ui.document:clearSelection()
                UIManager:forceRePaint()
                local last = page.sboxes[#page.sboxes]
                local word = { x = last.x + 10, y = last.y + math.floor(last.h / 2) }
                local start = ui.document:getWordFromPosition(word, true).sbox
                -- the footer's own paper in the column of the start handle's middle
                local x = start.x - math.floor(Screen:scaleBySize(25) / 2) - 1
                local footer_top = Screen:getHeight() - ui.view.footer:getHeight()
                local paper = {}
                for y = footer_top, Screen:getHeight() - 1 do
                    if gray(x, y) >= 0xF0 then table.insert(paper, y) end
                end
                local function handleOverFooter()
                    local covered = 0
                    for _, y in ipairs(paper) do
                        if gray(x, y) < 0x80 then covered = covered + 1 end
                    end
                    return covered
                end
                gesture("hold", word)
                UIManager:forceRePaint()
                local r = ui.highlight:selectionRects()[1]
                local marked = handleOverFooter()
                assert.is_true(marked > 0)
                local line = underlineRow(r)
                -- the clock ticks: the footer repaints itself alone, over the handles
                ui.view.footer:onUpdateFooter(true)
                assert.are.equal(marked, handleOverFooter())
                assert.are.equal(line, underlineRow(r))
                gesture("hold_release", word)
                ui.highlight:onClose()
            end)
        end)

        describe("with right-to-left text", function()
            local ffiUtil, lfs
            setup(function()
                ffiUtil = require("ffi/util")
                lfs = require("libs/libkoreader-lfs")
            end)

            it("should hang the handles at its start and end, at the right and at the left, and drag its end", function()
                local dir = require("datastorage"):getDataDir() .. "/rtl_selection"
                lfs.mkdir(dir)
                local path = dir .. "/book.html"
                local f = assert(io.open(path, "w"))
                f:write('<html><body><p dir="rtl" lang="he">'
                    .. string.rep("שלום עולם זהו טקסט בעברית לבדיקה של בחירה מימין לשמאל ", 8) .. "</p></body></html>")
                f:close()
                local ui = openReader(path, true)
                UIManager:forceRePaint()
                local ok, err = pcall(function()
                    -- from the right of the first line, its start, down to the third
                    longPress({ x = 500, y = 30 }, { x = 300, y = 90 })
                    local before = ui.highlight.selected_text
                    local rects = ui.highlight:selectionRects()
                    local first, last = rects[1], rects[#rects]
                    assert.is_true(last.y > first.y)
                    -- the start handle hangs to the right of the first line, its square corner at its top left
                    local d = Screen:scaleBySize(25)
                    local u = underlineRow(first)
                    local start = Geom:new{ x = first.x + first.w, y = u - Screen:scaleBySize(4), w = d, h = d }
                    assert.is_true(gray(start.x, start.y + 1) < 0x80)
                    assert.is_true(gray(start.x + d - 1, start.y + 1) >= 0x80)
                    assert.is_true(gray(start.x + math.floor(d / 2), start.y + math.floor(d / 2)) < 0x80)
                    -- the end one to the left of the last line's left, where the selection stops
                    u = underlineRow(last)
                    local stop = Geom:new{ x = last.x - d, y = u - Screen:scaleBySize(4), w = d, h = d }
                    assert.is_true(gray(stop.x + d - 1, stop.y + 1) < 0x80)
                    assert.is_true(gray(stop.x + math.floor(d / 2), stop.y + math.floor(d / 2)) < 0x80)
                    -- dragged a line further, the end moves on and the start stays where it was
                    local from = center(stop)
                    drag(from, { x = from.x - 60, y = from.y + 30 })
                    local selected = ui.highlight.selected_text
                    assert.are.equal(before.pos0, selected.pos0)
                    assert.are.equal(1, ui.document:compareXPointers(before.pos1, selected.pos1))
                    assert.are.equal(1, selected.text:find(before.text, 1, true))
                    assert.are.equal(ui.highlight.highlight_dialog, topWidget())
                    assertNoNotes(ui)
                end)
                closeReader(ui)
                DocSettings:open(path):purge()
                ffiUtil.purgeDir(dir)
                assert(ok, err)
            end)
        end)

        describe("with a PDF", function()
            it("should underline the selection at the bottom of its boxes, with handles that drag its end", function()
                local ui = openReader(sample_pdf, true)
                ui:handleEvent(Event:new("SetScrollMode", false))
                ui.paging:onGotoPage(10)
                UIManager:forceRePaint()
                longPress({ x = 430, y = 210 })
                assert.is_nil(next(ui.view.highlight.temp)) -- not ReaderView's gray boxes
                local rects = ui.highlight:selectionRects()
                local r = rects[1]
                for x = r.x, r.x + r.w - 1 do
                    assert.is_true(gray(x, r.y + r.h - 1) < 0x80, "underline at " .. x)
                end
                local handle = Geom:new{ x = r.x + r.w, y = r.y + r.h - 1 - Screen:scaleBySize(4),
                    w = Screen:scaleBySize(25), h = Screen:scaleBySize(25) }
                local from = center(handle)
                assert.is_true(gray(from.x, from.y) < 0x80)
                assert.is_true(gray(r.x - math.floor(handle.w / 2), from.y) < 0x80) -- and the start's
                local text = ui.highlight.selected_text.text
                drag(from, { x = from.x - 300, y = from.y + 26 })
                local selected = ui.highlight.selected_text
                assert.are_not.equal(text, selected.text)
                assert.are.equal(1, selected.text:find(text, 1, true))
                assert.is_nil(next(ui.view.highlight.temp))
                assert.are.equal(ui.highlight.highlight_dialog, topWidget())
                assertNoNotes(ui)
                tap(5, Screen:getHeight() - 5)
                assert.is_nil(ui.highlight.selected_text)
                assertNoNotes(ui)
                closeReader(ui)
            end)
        end)
    end)

    describe("line highlights under the glyphs", function()
        local ffiUtil, lfs
        setup(function()
            ffiUtil = require("ffi/util")
            lfs = require("libs/libkoreader-lfs")
        end)
        after_each(function()
            G_reader_settings:delSetting("highlight_drawing_style")
            G_reader_settings:delSetting("highlight_color")
        end)

        local function writeFile(path, content)
            local f = assert(io.open(path, "w"))
            f:write(content)
            f:close()
        end

        -- A book of one HTML page with `body`, and `files` beside it, open on its first page; with a cleanup.
        local function openHtml(name, body, files)
            local dir = require("datastorage"):getDataDir() .. "/" .. name
            lfs.mkdir(dir)
            for file, content in pairs(files or {}) do writeFile(dir .. "/" .. file, content) end
            local path = dir .. "/book.html"
            writeFile(path, "<html><body>" .. body .. "</body></html>")
            local ui = openReader(path, true)
            UIManager:forceRePaint()
            return ui, function()
                closeReader(ui)
                DocSettings:open(path):purge()
                ffiUtil.purgeDir(dir)
            end
        end

        local GREEK = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho "
            .. "sigma tau upsilon phi chi psi omega "

        -- The screen boxes, one per line, from the start of the first match of `from` on the page to the end
        -- of the first match of `to` after it.
        local function boxesOf(ui, from, to)
            local function match(pattern, after)
                local found = ui.document:findText(pattern, 0, 0, false, ui.document:getCurrentPage(), false, 50)
                ui.document:clearSelection()
                for _, m in ipairs(found or {}) do
                    if not after or ui.document:compareXPointers(after, m.start) >= 0 then return m end
                end
                error("no " .. pattern)
            end
            local a = match(from)
            return ui.document:getScreenBoxesFromPositions(a.start, match(to or from, a.start)["end"], true)
        end

        -- Highlights those boxes' text with a long-press and a drag, in the default style.
        local function highlight(ui, boxes)
            local first, last = boxes[1], boxes[#boxes]
            select(ui, Geom:new{ x = first.x + 2, y = first.y + math.floor(first.h / 2) },
                Geom:new{ x = last.x + last.w - 2, y = last.y + math.floor(last.h / 2) })
            tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
            ui.highlight:closeBubble()
            UIManager:forceRePaint()
        end

        -- With paper light (dark ink) or not: whether a pixel is paper, and whether it is ink.
        local function isPaper(x, y, dark) local g = gray(x, y) if dark then return g < 0x10 end return g >= 0xF0 end
        local function isInk(x, y, dark) return (gray(x, y) >= 0x80) == (dark or false) end

        -- The lowest row of ink in the lower half of the segments of one line (box), skipping columns.
        local function glyphBottom(rects, dark, skip)
            local box = rects[1]
            for row = box.y + box.h - 1, box.y + math.floor(box.h / 2), -1 do
                for _, r in ipairs(rects) do
                    for x = r.x, r.x + r.w - 1 do
                        if not (skip and skip(x)) and isInk(x, row, dark) then return row end
                    end
                end
            end
        end

        -- The line highlight of segments rects whose glyphs end at row g: paper for 3dp, then a 2dp band
        -- with no paper left (pure ink when ink is given), then paper again.
        local function assertLineUnder(rects, g, dark, ink)
            local gap, line_h = Screen:scaleBySize(3), Screen:scaleBySize(2)
            local function every(row, pred)
                for _, r in ipairs(rects) do
                    for x = r.x, r.x + r.w - 1 do
                        if not pred(x, row) then return false end
                    end
                end
                return true
            end
            for row = g + 1, g + gap do
                assert.is_true(every(row, function(x, y) return isPaper(x, y, dark) end), "gap row " .. row)
            end
            for row = g + gap + 1, g + gap + line_h do
                assert.is_true(every(row, function(x, y)
                    if ink then return gray(x, y) < 0x20 end
                    return not isPaper(x, y, dark)
                end), "line row " .. row)
            end
            assert.is_false(every(g + gap + line_h + 1, function(x, y) return not isPaper(x, y, dark) end))
            assert.is_true(g + gap + line_h < rects[1].y + rects[1].h - 1) -- well above the bottom of the box
        end

        it("should draw a line in ink, 2dp thick, 3dp under the glyphs rather than at the bottom of the leading", function()
            G_reader_settings:saveSetting("highlight_color", "gray") -- as on a black and white screen
            local ui, cleanup = openHtml("lines_ink", "<p style='line-height: 2'>" .. string.rep(GREEK, 4) .. "</p>")
            local ok, err = pcall(function()
                local boxes = boxesOf(ui, "gamma", "theta")
                local g = glyphBottom({ boxes[1] })
                highlight(ui, boxes)
                assert.are.equal("underscore", ui.annotation.annotations[1].drawer)
                assertLineUnder({ boxes[1] }, g, false, true)
            end)
            cleanup()
            assert(ok, err)
        end)

        it("should put a wave where a line would be", function()
            G_reader_settings:saveSetting("highlight_drawing_style", "wave")
            G_reader_settings:saveSetting("highlight_color", "gray")
            local ui, cleanup = openHtml("lines_wave", "<p style='line-height: 2'>" .. string.rep(GREEK, 4) .. "</p>")
            local ok, err = pcall(function()
                local boxes = boxesOf(ui, "gamma", "theta")
                local r = boxes[1]
                local g = glyphBottom({ r })
                highlight(ui, boxes)
                assert.are.equal("wave", ui.annotation.annotations[1].drawer)
                local top = g + Screen:scaleBySize(3) + 1
                for x = r.x, r.x + r.w - 1 do
                    for row = g + 1, top - 1 do
                        assert.is_true(isPaper(x, row), "gap row " .. row)
                    end
                    local marked = false
                    for row = top, top + Screen:scaleBySize(5) do
                        if not isPaper(x, row) then marked = true end
                    end
                    assert.is_true(marked, x)
                end
            end)
            cleanup()
            assert(ok, err)
        end)

        it("should find the glyphs in night mode, the screen inverted", function()
            G_reader_settings:saveSetting("highlight_color", "gray")
            local ui, cleanup = openHtml("lines_night", "<p style='line-height: 2'>" .. string.rep(GREEK, 4) .. "</p>")
            local night = G_reader_settings:readSetting("night_mode")
            local ok, err = pcall(function()
                local boxes = boxesOf(ui, "gamma", "theta")
                local g = glyphBottom({ boxes[1] })
                ui:handleEvent(Event:new("ToggleNightMode"))
                UIManager:forceRePaint()
                -- the glyphs are light on the screen, though they read back dark
                assert.are.equal(1, Screen.bb:getInverse())
                local r = boxes[1]
                local glyph_x
                for x = r.x, r.x + r.w - 1 do
                    if isInk(x, g) then glyph_x = x break end
                end
                assert.is_true(Screen.bb:getPixelP(glyph_x, g)[0]:getColor8().a >= 0x80)
                highlight(ui, boxes)
                assertLineUnder({ r }, g, false, true)
            end)
            if Screen.bb:getInverse() == 1 then ui:handleEvent(Event:new("ToggleNightMode")) end
            G_reader_settings:saveSetting("night_mode", night)
            cleanup()
            assert(ok, err)
        end)

        it("should find light glyphs on a dark page", function()
            G_reader_settings:saveSetting("highlight_color", "yellow") -- a light line, to be seen on the page
            local ui, cleanup = openHtml("lines_dark",
                "<div style='background-color: #000000; color: #ffffff'><p style='line-height: 2'>"
                .. string.rep(GREEK, 4) .. "</p></div>")
            local ok, err = pcall(function()
                local boxes = boxesOf(ui, "gamma", "theta")
                local r = boxes[1]
                assert.is_true(isPaper(r.x, r.y + r.h - 1, true)) -- the page is dark
                local g = glyphBottom({ r }, true)
                highlight(ui, boxes)
                assertLineUnder({ r }, g, true)
            end)
            cleanup()
            assert(ok, err)
        end)

        it("should leave out an inline image reaching lower than the glyphs", function()
            G_reader_settings:saveSetting("highlight_color", "gray")
            local ui, cleanup = openHtml("lines_image",
                "<p style='line-height: 2'>alpha beta <img src='black.svg' style='height: 2.5em; vertical-align: bottom'/> "
                .. "gamma " .. string.rep(GREEK, 3) .. "</p>",
                { ["black.svg"] = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="40">'
                    .. '<rect width="20" height="40" fill="#000"/></svg>' })
            local ok, err = pcall(function()
                local boxes = boxesOf(ui, "beta", "gamma")
                local r = boxes[1]
                -- crengine counts the image in the segment, and it reaches the bottom of the box
                local image = {}
                for x = r.x, r.x + r.w - 1 do
                    if isInk(x, r.y + r.h - 1) then image[x] = true end
                end
                assert.is_truthy(next(image))
                local function skip(x) return image[x] or image[x - 1] or image[x + 1] end
                local g = glyphBottom({ r }, false, skip)
                assert.is_true(g < r.y + r.h - 1 - Screen:scaleBySize(6))
                highlight(ui, boxes)
                -- the line runs under the image's bottom too: check it beside the image
                local text_rects = {}
                local run
                for x = r.x, r.x + r.w - 1 do
                    if skip(x) then run = nil
                    elseif run then run.w = run.w + 1
                    else
                        run = Geom:new{ x = x, y = r.y, w = 1, h = r.h }
                        table.insert(text_rects, run)
                    end
                end
                assertLineUnder(text_rects, g, false, true)
            end)
            cleanup()
            assert(ok, err)
        end)

        it("should put the highlights of one line on one line, and each line of a long one under its own glyphs", function()
            G_reader_settings:saveSetting("highlight_color", "gray")
            local ui, cleanup = openHtml("lines_many", "<p style='line-height: 2'>" .. string.rep(GREEK, 6) .. "</p>")
            local ok, err = pcall(function()
                -- two highlights on the first line, and one overlapping the second one there
                local a = boxesOf(ui, "alpha")
                local e = boxesOf(ui, "epsilon", "zeta")
                local z = boxesOf(ui, "zeta", "theta")
                assert.are.equal(a[1].y, e[1].y)
                assert.are.equal(a[1].y, z[1].y)
                local first_line = { a[1], e[1], z[1] }
                local g1 = glyphBottom(first_line)
                -- a long one, over three lines
                local long = boxesOf(ui, "sigma", "rho")
                assert.is_true(#long >= 3)
                local gs = {}
                for i, box in ipairs(long) do gs[i] = glyphBottom({ box }) end
                highlight(ui, a)
                highlight(ui, e)
                highlight(ui, z)
                highlight(ui, long)
                assert.are.equal(4, #ui.annotation.annotations)
                -- one line under all three, 2dp thick even where two overlap
                assertLineUnder(first_line, g1, false, true)
                for i, box in ipairs(long) do
                    assertLineUnder({ box }, gs[i], false, true)
                end
            end)
            cleanup()
            assert(ok, err)
        end)

        it("should read only the highlighted lines, and nothing on pages without line highlights", function()
            local ui, cleanup = openHtml("lines_reads", string.rep("<p>" .. string.rep(GREEK, 3) .. "</p>", 12))
            local ok, err = pcall(function()
                highlight(ui, boxesOf(ui, "beta", "rho"))
                local calls = {}
                local underlineY = ui.view.underlineY
                ui.view.underlineY = function(view, bb, rects)
                    table.insert(calls, rects)
                    return underlineY(view, bb, rects)
                end
                ui.rolling:onGotoPage(2)
                UIManager:forceRePaint()
                assert.are.same({}, calls)
                ui.rolling:onGotoPage(1)
                UIManager:forceRePaint()
                -- once per line of the highlight, with that line's segment only
                local lines = {}
                for _, box in ipairs(ui.view.highlight.visible_boxes) do
                    lines[box.rect.y] = box.rect
                end
                local n = 0
                for __ in pairs(lines) do n = n + 1 end
                assert.are.equal(n, #calls)
                for _, rects in ipairs(calls) do
                    assert.are.equal(1, #rects)
                    assert.are.same(lines[rects[1].y], rects[1])
                end
                ui.view.underlineY = nil
            end)
            cleanup()
            assert(ok, err)
        end)
    end)

    describe("with the notes list", function()
        local ReaderToolbar
        setup(function()
            ReaderToolbar = require("apps/reader/modules/readertoolbar")
            Replacements.reader_menu = ReaderToolbar
        end)
        teardown(function() Replacements.reader_menu = nil end)

        it("should drop a highlight deleted from its popover from the notes list too", function()
            local ui = openReader(sample_epub, true)
            local ok, err = pcall(function()
                ui.rolling:onGotoPage(10)
                UIManager:forceRePaint()
                -- the cards of the notes page the contents page's 书签 opens
                local function noteCards()
                    ui:handleEvent(Event:new("ShowToc"))
                    UIManager:forceRePaint()
                    tapWidget(ui.menu.drawer.bookmarks_button)
                    UIManager:forceRePaint()
                    local page = ui.menu.drawer
                    local cards = #page.cards
                    page:goBack()
                    UIManager:forceRePaint()
                    return cards
                end
                select(ui, Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
                tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
                ui.highlight:closeBubble()
                UIManager:forceRePaint()
                assert.are.equal(1, noteCards())
                tap(highlightPoint(ui).x, highlightPoint(ui).y)
                UIManager:forceRePaint()
                tapWidget(cell(ui.highlight.highlight_dialog, "Delete highlight"))
                UIManager:forceRePaint()
                assert.are.equal(0, noteCards())
            end)
            closeReader(ui)
            assert(ok, err)
        end)
    end)

    describe("with CJK text", function()
        it("should name the look-up 查询 (Look up) and give it the magnifier, on a selection and on a highlight", function()
            local file = require("datastorage"):getDataDir() .. "/readerhighlightbubble_cjk.txt"
            local f = assert(io.open(file, "w"))
            f:write(string.rep("加入蘋果前：史丹佛人工智慧實驗室，全錄研究中心。泰斯勒對人工智慧的看法，後來被稱為泰斯勒定理。\n", 20))
            f:close()
            local ui = openReader(file, true)
            local ok, err = pcall(function()
                local actions = {
                    { "Highlight", "eink/highlight" },
                    { "Look up", "eink/search" },
                    { "Write note", "eink/thought" },
                    { "Copy", "eink/copy" },
                }
                select(ui, Geom:new{ x = 200, y = 200 }, Geom:new{ x = 400, y = 200 })
                local bubble = ui.highlight.highlight_dialog
                assert.is_true(require("util").hasCJKChar(ui.highlight.selected_text.text))
                UIManager:forceRePaint()
                assertActions(bubble, actions)
                stub(ui.dictionary, "onLookupWord")
                tapWidget(cell(bubble, "Look up"))
                assert.stub(ui.dictionary.onLookupWord).was_called()
                ui.dictionary.onLookupWord:revert()
                ui.highlight:onClose()
                UIManager:forceRePaint()

                select(ui, Geom:new{ x = 200, y = 200 }, Geom:new{ x = 400, y = 200 })
                tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
                UIManager:forceRePaint()
                actions[1] = { "Delete highlight", "eink/highlight-off" }
                assertActions(ui.highlight.highlight_dialog, actions)
                ui.highlight:closeBubble()
            end)
            closeReader(ui)
            DocSettings:open(file):purge()
            os.remove(file)
            assert(ok, err)
        end)

        it("should name it Look up for mixed text, Translate for digits and for Latin text with CJK punctuation", function()
            local file = require("datastorage"):getDataDir() .. "/readerhighlightbubble_punct.txt"
            local f = assert(io.open(file, "w"))
            f:write("iPhone手机\n\n2000\n\n" .. string.rep("PARC，Xerox。", 100))
            f:close()
            local ui = openReader(file, true)
            local ok, err = pcall(function()
                UIManager:forceRePaint()
                -- long-press the first match of pattern on the page, dragging to its end
                local function selectText(pattern)
                    local found = ui.document:findText(pattern, 0, 0, false, ui.document:getCurrentPage(), false, 1)
                    assert.is_truthy(found and found[1], pattern)
                    ui.document:clearSelection()
                    local boxes = ui.document:getScreenBoxesFromPositions(found[1].start, found[1]["end"], true)
                    local first, last = boxes[1], boxes[#boxes]
                    select(ui, Geom:new{ x = first.x + 2, y = first.y + math.floor(first.h / 2) },
                        Geom:new{ x = last.x + last.w - 2, y = last.y + math.floor(last.h / 2) })
                    UIManager:forceRePaint()
                    return ui.highlight.selected_text.text
                end
                local function label()
                    local bubble = ui.highlight.highlight_dialog
                    local name = cell(bubble, "Look up") and "Look up" or cell(bubble, "Translate") and "Translate"
                    ui.highlight:onClose()
                    UIManager:forceRePaint()
                    return name
                end
                local text = selectText("iPhone手机")
                assert.is_truthy(text:find("iPhone", 1, true) and text:find("手机", 1, true), text)
                assert.are.equal("Look up", label())
                assert.are.equal("2000", selectText("2000"))
                assert.are.equal("Translate", label())
                text = selectText("PARC，Xerox。")
                assert.is_truthy(text:find("，", 1, true), text)
                assert.is_true(require("util").hasCJKChar(text)) -- the punctuation counts as CJK there
                assert.are.equal("Translate", label())
            end)
            closeReader(ui)
            DocSettings:open(file):purge()
            os.remove(file)
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
            assertActions(bubble, SELECTION_ACTIONS)
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
            tapWidget(cell(ui.highlight.highlight_dialog, "Translate"))
            ui.dictionary.onLookupWord:revert()
            stub(ui.document, "getWordFromPosition")
            select(ui, Geom:new{ x = 5, y = Screen:getHeight() - 2 })
            ui.document.getWordFromPosition:revert()
            assert.is_nil(ui.highlight.highlight_dialog)
            assert.are.equal(1, #ui.annotation.annotations)
            closeReader(ui)
        end)

        it("should name the look-up by the book's language when a selection has no text (a scanned page)", function()
            local ui = openReader(sample_pdf, true)
            local pos = Geom:new{ x = 430, y = 210 }
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetScrollMode", false))
                ui.paging:onGotoPage(10)
                UIManager:forceRePaint()
                local word = ui.document:getWordFromPosition(ui.view:screenToPageTransform(pos))
                word.word = "" -- a scanned page has boxes but no text, until OCR
                stub(ui.document, "getWordFromPosition", function() return word end)
                local function label()
                    select(ui, pos)
                    local bubble = ui.highlight.highlight_dialog
                    assert.are.equal("", ui.highlight.selected_text.text)
                    local name = cell(bubble, "Look up") and "Look up" or cell(bubble, "Translate") and "Translate"
                    ui.highlight:onClose()
                    UIManager:forceRePaint()
                    return name
                end
                assert.is_nil(ui.doc_props.language)
                assert.are.equal("Look up", label()) -- unknown
                ui.doc_props.language = "en"
                assert.are.equal("Translate", label())
                ui.doc_props.language = "zh-TW"
                assert.are.equal("Look up", label())
                -- or the OCR language, once it is not the default one
                ui.doc_props.language = nil
                ui.document.configurable.doc_language = "fra"
                assert.are.equal("Translate", label())
                ui.document.configurable.doc_language = "chi_sim"
                assert.are.equal("Look up", label())
                -- on a highlight of it, too
                ui.document.configurable.doc_language = "fra"
                select(ui, pos)
                tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
                UIManager:forceRePaint()
                assert.are.equal("", ui.annotation.annotations[1].text)
                assertActions(ui.highlight.highlight_dialog, HIGHLIGHT_ACTIONS)
                ui.highlight:closeBubble()
            end)
            if ui.document.getWordFromPosition.revert then ui.document.getWordFromPosition:revert() end
            closeReader(ui)
            assert(ok, err)
        end)

        it("should show a highlight's popover on a long-press in it, and copy with a toast that leaves with ui", function()
            local ui = openReader(sample_pdf, true)
            stub(Device.input, "setClipboardText")
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetScrollMode", false))
                ui.paging:onGotoPage(10)
                UIManager:forceRePaint()
                select(ui, Geom:new{ x = 430, y = 210 }, Geom:new{ x = 60, y = 236 })
                tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
                ui.highlight:closeBubble()
                UIManager:forceRePaint()
                local pos = highlightPoint(ui)
                local word = ui.document:getWordFromPosition(ui.view:screenToPageTransform(pos)).word
                select(ui, pos)
                local bubble = ui.highlight.highlight_dialog
                assert.are.equal(bubble, topWidget())
                UIManager:forceRePaint()
                assertActions(bubble, HIGHLIGHT_ACTIONS)
                assert.are.equal(1, #ui.annotation.annotations)
                -- the look-up is for the word pressed, not the whole highlight
                assert.are_not.equal(word, ui.annotation.annotations[1].text)
                stub(ui.dictionary, "onLookupWord")
                tapWidget(cell(bubble, "Translate"))
                assert.stub(ui.dictionary.onLookupWord).was_called()
                assert.are.equal(word, ui.dictionary.onLookupWord.calls[1].vals[2])
                ui.dictionary.onLookupWord:revert()
                ui.highlight:onClose()
                UIManager:forceRePaint()
                select(ui, pos)
                bubble = ui.highlight.highlight_dialog
                UIManager:forceRePaint()
                local refreshes = refreshesOf(function() tapWidget(cell(bubble, "Copy")) end)
                assert.stub(Device.input.setClipboardText).was_called_with(ui.annotation.annotations[1].text)
                local toast = shown(Toast)
                assert.is_truthy(hasRefresh(refreshes, "fast", toast.dimen)) -- solid ink
                -- but the rendered page under it is gray
                refreshes = refreshesOf(function() UIManager:close(toast) end)
                assert.are.same({ { mode = "ui", region = toast.dimen } }, refreshes)
            end)
            Device.input.setClipboardText:revert()
            closeReader(ui)
            assert(ok, err)
        end)

        it("should write the highlight into the PDF, and a wave as an underline", function()
            local DataStorage = require("datastorage")
            local copy = DataStorage:getDataDir() .. "/readerhighlightbubble.pdf"
            require("ffi/util").copyFile(sample_pdf, copy)
            G_reader_settings:saveSetting("highlight_drawing_style", "wave")
            local ui = openReader(copy, true)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetScrollMode", false))
                ui.highlight.highlight_write_into_pdf = true
                ui.paging:onGotoPage(10)
                UIManager:forceRePaint()
                select(ui, Geom:new{ x = 430, y = 210 }, Geom:new{ x = 60, y = 236 })
                tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
                assert.are.equal("wave", ui.annotation.annotations[1].drawer)
                local annots = ui.document:getEmbeddedAnnotations()
                assert.is_truthy(annots and annots[10])
                assert.are.equal(1, #annots[10])
                assert.are.equal(9, annots[10][1].type) -- underline
            end)
            G_reader_settings:delSetting("highlight_drawing_style")
            closeReader(ui)
            DocSettings:open(copy):purge()
            os.remove(copy)
            assert(ok, err)
        end)
    end)
end)
