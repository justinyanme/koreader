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
            tapWidget(cell(bubble, "Highlight"))
            assert.are.equal(1, #ui.annotation.annotations)
            local item = ui.annotation.annotations[1]
            assert.are.equal("to take care of the London", item.text)
            assert.are.equal(ui.view.highlight.saved_drawer, item.drawer)
            assert.is_truthy(item.pboxes)
            assert.are.equal(ui.highlight.highlight_dialog, topWidget())
            closeReader(ui)
        end)
    end)
end)
