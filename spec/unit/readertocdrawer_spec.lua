describe("ReaderTocDrawer module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderToolbar, TocDrawer, Replacements, UIManager, Event, Geom, Screen
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local sample_pdf = "spec/front/unit/data/paper.pdf" -- has an outline, unlike sample.pdf

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderToolbar = require("apps/reader/modules/readertoolbar")
        TocDrawer = require("apps/reader/modules/readertocdrawer")
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
    end

    local function findText(widget, text)
        return find(widget, function(w)
            return w.callback and w.dimen and find(w, function(c) return c.text == text end) ~= nil
        end)
    end

    local function openDrawer(ui)
        ui:handleEvent(Event:new("ShowToc"))
        UIManager:forceRePaint()
        assert.is_truthy(ui.menu.drawer)
        return ui.menu.drawer
    end

    local function tab(drawer, name)
        return find(drawer.panel, function(w) return w.selected ~= nil and w.callback and w.text:find(name, 1, true) end)
    end

    local function shownRow(drawer, pred)
        for _, row in ipairs(drawer.shown_rows) do
            if pred(row) then return row end
        end
    end

    describe("paginate", function()
        it("should never end a page with a group header", function()
            local items = {
                { h = 10, is_header = true }, { h = 50 }, { h = 50 }, { h = 10, is_header = true }, { h = 50 },
            }
            assert.are.same({ { 1, 2 }, { 3 }, { 4, 5 } }, TocDrawer.paginate(items, 70))
        end)

        it("should give a row taller than the list a page of its own", function()
            assert.are.same({ { 1 }, { 2 }, { 3 } }, TocDrawer.paginate({ { h = 30 }, { h = 90 }, { h = 30 } }, 70))
        end)
    end)

    describe("swatch", function()
        it("should draw a distinct swatch for each stored highlight style", function()
            local Blitbuffer = require("ffi/blitbuffer")
            local signatures = {}
            for _, drawer in ipairs{ "lighten", "underscore", "strikeout", "invert", "wave" } do
                local swatch = TocDrawer.Swatch:new{ drawer = drawer }
                local w, h = swatch.dimen.w, swatch.dimen.h
                local bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
                bb:fill(Blitbuffer.COLOR_WHITE)
                swatch:paintTo(bb, 0, 0)
                local sig = {}
                for y = 0, h - 1 do
                    for x = 0, w - 1 do
                        sig[#sig + 1] = bb:getPixel(x, y):getColor8().a
                    end
                end
                bb:free()
                sig = table.concat(sig, ",")
                assert.is_nil(signatures[sig], drawer)
                signatures[sig] = drawer
            end
        end)
    end)

    describe("with an EPUB", function()
        local ui
        setup(function()
            ui = openReader(sample_epub)
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()
        end)
        teardown(function() closeReader(ui) end)

        it("should open from the toolbar on top of the reader, marking the current chapter, with ui refreshes only", function()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local contents = findText(ui.menu.bars, require("gettext").pgettext("Reader toolbar", "Contents"))
            local refreshes = refreshesOf(function() tapWidget(contents) end)
            local drawer = ui.menu.drawer
            assert.are.equal(drawer, topWidget())
            assert.is_nil(ui.menu.bars)
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
            end
            -- the bars' and the drawer's ui refreshes, which UIManager may merge into their bounding box
            assert.is_true(refreshes[#refreshes].region:contains(drawer.panel_rect))

            local current = ui.toc:getTocIndexByPage(ui.document:getXPointer())
            assert.is_truthy(current)
            local row = shownRow(drawer, function(r) return r.is_current end)
            assert.is_truthy(row)
            assert.are.equal(current, row.toc_index)
            assert.is_truthy(find(row, function(w) return w.text == require("gettext")("Reading") end))

            refreshes = refreshesOf(function() tap(Screen:getWidth() - 5, Screen:getHeight() / 2) end)
            assert.are.same({ { mode = "ui", region = drawer.panel_rect } }, refreshes)
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.menu.drawer)
        end)

        it("should show how to add bookmarks and notes when there are none", function()
            local drawer = openDrawer(ui)
            local refreshes = refreshesOf(function() tapWidget(tab(drawer, "Bookmarks")) end)
            assert.are.same({ { mode = "ui", region = drawer.panel_rect } }, refreshes)
            assert.is_truthy(find(drawer.panel, function(w) return w.text == "No bookmarks yet" end))
            tapWidget(tab(drawer, "Notes"))
            UIManager:forceRePaint()
            assert.is_truthy(find(drawer.panel, function(w) return w.text == "No notes yet" end))
            drawer:onClose()
            UIManager:forceRePaint()
        end)

        it("should jump to a note and remember the position left", function()
            ui.rolling:onGotoPage(12)
            ui.highlight:onHold(nil, { pos = Geom:new{ x = 260, y = 70 } })
            ui.highlight:onHoldPan(nil, { pos = Geom:new{ x = 260, y = 100 } })
            ui.highlight:onHoldRelease()
            ui.highlight:saveHighlight()
            ui.highlight:onClose()
            UIManager:forceRePaint()
            assert.are.equal(1, #ui.annotation.annotations)
            local note_page = ui.document:getPageFromXPointer(ui.annotation.annotations[1].pos0)
            ui.rolling:onGotoPage(2)
            UIManager:forceRePaint()
            local stack_size = #(ui.link.location_stack or {})

            local drawer = openDrawer(ui)
            tapWidget(tab(drawer, "Notes"))
            UIManager:forceRePaint()
            local row = shownRow(drawer, function(r) return r.note end)
            assert.is_truthy(row)
            local refreshes = refreshesOf(function() tapWidget(row) end)
            assert.are.equal(note_page, ui:getCurrentPage())
            assert.are.equal(ui, topWidget())
            assert.are.equal(stack_size + 1, #ui.link.location_stack)
            assert.is_true(#refreshes > 0)
            for _, r in ipairs(refreshes) do
                assert.are_not.equal("full", r.mode)
                assert.are_not.equal("ui", r.mode) -- the drawer closes without a refresh of its own
            end
        end)

        it("should list bookmarks with their page's text and jump to them", function()
            ui.rolling:onGotoPage(20)
            ui.bookmark:onToggleBookmark()
            local page_text = ui.document:getTextFromXPointers(ui.document:getXPointer(), ui.document:getPageXPointer(21))
            ui.rolling:onGotoPage(3)
            UIManager:forceRePaint()
            local drawer = openDrawer(ui)
            tapWidget(tab(drawer, "Bookmarks 1"))
            UIManager:forceRePaint()
            local row = drawer.shown_rows[1]
            local first_word = page_text:match("%S+")
            assert.is_truthy(find(row, function(w) return type(w.text) == "string" and w.text:find(first_word, 1, true) end))
            tapWidget(row)
            assert.are.equal(20, ui:getCurrentPage())
        end)

        it("should page long lists, refreshing only the list", function()
            for page = 30, 60, 2 do
                ui.rolling:onGotoPage(page)
                ui.bookmark:onToggleBookmark()
            end
            local drawer = openDrawer(ui)
            tapWidget(tab(drawer, "Bookmarks"))
            UIManager:forceRePaint()
            assert.is_true(drawer.page_count > 1)
            local next_button = find(drawer.panel, function(w)
                return w.icon == "eink/chev" and w.icon_rotation_angle == 0 and w.callback ~= nil
            end)
            local refreshes = refreshesOf(function() tapWidget(next_button) end)
            assert.are.same({ { mode = "ui", region = drawer.list_rect } }, refreshes)
            assert.are.equal(2, drawer.pages.bookmarks)
            drawer:onClose()
            UIManager:forceRePaint()
        end)

        it("should export notes through the exporter, or open its settings when no target is enabled", function()
            local exported = false
            local ready = true
            ui.exporter = {
                isReady = function() return ready end,
                onExportCurrentNotes = function() exported = true end,
            }
            local ok, err = pcall(function()
                local drawer = openDrawer(ui)
                tapWidget(tab(drawer, "Notes"))
                UIManager:forceRePaint()
                tapWidget(findText(drawer.panel, "Export notes"))
                assert.is_true(exported)
                assert.is_nil(ui.menu.drawer)

                ready = false
                drawer = openDrawer(ui)
                tapWidget(tab(drawer, "Notes"))
                UIManager:forceRePaint()
                tapWidget(findText(drawer.panel, "Export notes"))
                assert.is_truthy(ui.menu.menu_container)
                ui.menu:onCloseReaderMenu()
            end)
            ui.exporter = nil
            assert(ok, err)
        end)
    end)

    describe("with a PDF", function()
        it("should list the outline and jump to an entry", function()
            local ui = openReader(sample_pdf)
            local ok, err = pcall(function()
                local drawer = openDrawer(ui)
                assert.are.equal(drawer, topWidget())
                assert.is_true(#ui.toc.toc > 0)
                local row = shownRow(drawer, function(r)
                    return r.toc_index and ui.toc.toc[r.toc_index].page > ui:getCurrentPage()
                end)
                assert.is_truthy(row)
                tapWidget(row)
                assert.are.equal(ui.toc.toc[row.toc_index].page, ui:getCurrentPage())
                assert.are.equal(ui, topWidget())
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
