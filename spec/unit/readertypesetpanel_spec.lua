describe("ReaderTypesetPanel module", function()
    local Blitbuffer, DocumentRegistry, DocSettings, ReaderUI, ReaderTypesetPanel, Replacements, UIManager, Event, Geom, Screen
    local _
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local sample_pdf = "spec/front/unit/data/sample.pdf"

    setup(function()
        require("commonrequire")
        disable_plugins()
        Blitbuffer = require("ffi/blitbuffer")
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderTypesetPanel = require("apps/reader/modules/readertypesetpanel")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Screen = require("device").screen
        _ = require("gettext")
        Replacements.reader_menu = require("apps/reader/modules/readertoolbar")
        Replacements.reader_config = ReaderTypesetPanel
    end)

    teardown(function()
        Replacements.reader_menu = nil
        Replacements.reader_config = nil
    end)

    -- Opens a book with fresh settings, plus `settings` (unless `keep` is set: then with its saved settings).
    local function openReader(file, settings, keep)
        if not keep then
            local doc_settings = DocSettings:open(file)
            doc_settings:purge()
            if settings then
                doc_settings = DocSettings:open(file)
                for k, v in pairs(settings) do doc_settings:saveSetting(k, v) end
                doc_settings:flush()
            end
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

    local function tapWidget(widget, x_ratio)
        tap(widget.dimen.x + math.floor(widget.dimen.w * (x_ratio or 0.5)), widget.dimen.y + math.floor(widget.dimen.h / 2))
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
        for _, key in ipairs{ "frame", "content", "sample" } do
            local found = rawget(widget, key) and find(widget[key], pred)
            if found then return found end
        end
    end

    local function hasText(widget, text)
        return find(widget, function(c) return c.text == text end) ~= nil
    end

    local function segmented(sheet, first_label)
        return find(sheet, function(w) return getmetatable(w) and w.labels and w.labels[1] == first_label end)
    end

    local function fontCard(sheet, name)
        return find(sheet, function(w) return w.name == name and w.callback end)
    end

    local function openPanel(ui)
        ui:handleEvent(Event:new("ShowConfigMenu"))
        UIManager:forceRePaint()
        return ui.config.sheet
    end

    describe("with an EPUB", function()
        local ui
        setup(function() ui = openReader(sample_epub) end)
        teardown(function() closeReader(ui) end)

        it("should open and close the panel with ui refreshes of its rect only", function()
            local sheet
            local refreshes = refreshesOf(function()
                ui:handleEvent(Event:new("ShowConfigMenu"))
                sheet = ui.config.sheet
            end)
            assert.is_truthy(sheet)
            assert.are.equal(sheet, topWidget())
            assert.are.same({ { mode = "ui", region = sheet:getRefreshRegion() } }, refreshes)

            refreshes = refreshesOf(function() sheet:onClose() end)
            assert.is_nil(ui.config.sheet)
            assert.are.equal(ui, topWidget())
            assert.are.same({ { mode = "ui", region = sheet:getRefreshRegion() } }, refreshes)
        end)

        it("should open from the toolbar's Font entry", function()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local bars = ui.menu.bars
            local font = find(bars, function(w) return w.callback and w.text == _("Font") end)
            local refreshes = refreshesOf(function() tapWidget(font) end)
            local sheet = ui.config.sheet
            assert.is_truthy(sheet)
            assert.are.equal(sheet, topWidget())
            assert.is_true(hasText(sheet, _("Font & layout")))
            -- the bottom bar's rect lies inside the sheet's: UIManager merges them into the sheet's refresh
            local allowed = { bars.top_rect, bars.bottom_rect, sheet:getRefreshRegion() }
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
                assert.is_true(r.region == allowed[1] or r.region == allowed[2] or r.region == allowed[3])
            end
            assert.is_true(refreshes[#refreshes].region == sheet:getRefreshRegion())
            sheet:onClose()
        end)

        it("should apply font size, line spacing and margins at once and keep the panel open", function()
            -- a text page: landing on a page with images flashes on its own ("refresh_on_pages_with_images")
            ui:handleEvent(Event:new("GotoPage", 20))
            UIManager:forceRePaint()
            local sheet = openPanel(ui)
            local size = ui.document.configurable.font_size
            local plus = find(sheet, function(w) return w.icon == "eink/plus" and w.callback end)
            UIManager.refresh_count = 0
            local refreshes = refreshesOf(function() tapWidget(plus) end)
            assert.is_true(ui.document.configurable.font_size > size)
            assert.are.equal(sheet, topWidget())
            local modes = {}
            for _, r in ipairs(refreshes) do
                modes[r.mode] = true
                if r.mode == "ui" then
                    assert.are.same(sheet:getRefreshRegion(), r.region)
                end
            end
            assert.is_nil(modes.full)
            assert.is_true(modes.partial) -- the re-laid out page, as for a page turn
            assert.is_true(modes.ui) -- the sheet

            tapWidget(segmented(sheet, _.pgettext("Line spacing", "Compact")), 5/6)
            UIManager:forceRePaint()
            assert.are.equal(145, ui.document.configurable.line_spacing)
            tapWidget(segmented(sheet, _.pgettext("Margins", "Narrow")), 1/6)
            UIManager:forceRePaint()
            assert.are.same({ 18, 18 }, ui.document.configurable.h_page_margins)
            assert.are.equal(Screen:scaleBySize(18), ui.document:getPageMargins().left)
            assert.are.equal(sheet, topWidget())

            ui:saveSettings()
            assert.are.equal(ui.document.configurable.font_size, ui.doc_settings:readSetting("copt_font_size"))
            assert.are.equal(145, ui.doc_settings:readSetting("copt_line_spacing"))
            assert.are.same({ 18, 18 }, ui.doc_settings:readSetting("copt_h_page_margins"))
            sheet:onClose()
        end)

        it("should keep the new values after reopening the book", function()
            local size = ui.document.configurable.font_size
            closeReader(ui)
            ui = openReader(sample_epub, nil, true)
            assert.are.equal(size, ui.document.configurable.font_size)
            assert.are.equal(145, ui.document.configurable.line_spacing)
            assert.are.same({ 18, 18 }, ui.document.configurable.h_page_margins)
            assert.are.equal(Screen:scaleBySize(18), ui.document:getPageMargins().left)
            local sheet = openPanel(ui)
            assert.are.equal(3, segmented(sheet, _.pgettext("Line spacing", "Compact")).value)
            assert.are.equal(1, segmented(sheet, _.pgettext("Margins", "Narrow")).value)
            sheet:onClose()
        end)

        it("should use the Latin faces for an English book", function()
            local sheet = openPanel(ui)
            tapWidget(fontCard(sheet, _("Source Han Sans")))
            UIManager:forceRePaint()
            assert.are.equal("Noto Sans", ui.font.font_face)
            tapWidget(fontCard(sheet, _("Source Han Serif")))
            UIManager:forceRePaint()
            assert.are.equal("Noto Serif", ui.font.font_face)
            assert.are.equal(sheet, topWidget()) -- no prompt
            sheet:onClose()
        end)

        it("should page to the more layout options and back", function()
            local sheet = openPanel(ui)
            tapWidget(find(sheet, function(w) return w.callback and hasText(w, _("More layout options: weight, hyphenation, indent, style tweaks")) end))
            UIManager:forceRePaint()
            assert.are.equal("more", ui.config.page)
            assert.is_true(hasText(sheet, _("Render Mode")))
            sheet.on_back()
            UIManager:forceRePaint()
            assert.are.equal("main", ui.config.page)
            sheet:onClose()
        end)

        it("should open the existing menus from its links", function()
            for _, case in ipairs{
                { "main", _("More fonts") },
                { "more", _("Hyphenation") },
                { "more", _("Paragraph indent") },
                { "more", _("Paragraph spacing") },
                { "more", _("Style tweaks") },
            } do
                local sheet = openPanel(ui)
                if case[1] == "more" then
                    ui.config:showPage("more")
                    UIManager:forceRePaint()
                end
                local link = find(sheet, function(w) return w.callback and w.dimen and (w.name == case[2] or (w.label and w.label.text == case[2])) end)
                assert.is_truthy(link, case[2])
                tapWidget(link)
                UIManager:forceRePaint()
                assert.is_nil(ui.config.sheet)
                local menu = topWidget()[1]
                assert.is_truthy(menu and menu.tab_item_table and #menu.tab_item_table[1] > 0, case[2])
                menu:closeMenu()
                UIManager:forceRePaint()
                assert.are.equal(ui, topWidget())
            end
        end)

        it("should keep the original bottom bar reachable", function()
            ui:handleEvent(Event:new("ShowOriginalConfigMenu"))
            UIManager:forceRePaint()
            assert.is_truthy(ui.config.config_dialog)
            assert.are.equal(ui.config.config_dialog, topWidget())
            ui.config.config_dialog:closeDialog()
            UIManager:forceRePaint()
        end)

        it("should draw the chapter header only when the top margin holds it", function()
            local header = ui.view.view_modules.chapter_header
            assert.is_truthy(header)
            local function inkInTopMargin()
                local w, h = Screen:getWidth(), ui.document:getPageMargins().top
                local bb = Blitbuffer.new(w, Screen:getHeight(), Blitbuffer.TYPE_BB8)
                bb:fill(Blitbuffer.COLOR_WHITE)
                header:paintTo(bb, 0, 0)
                for y = 0, h - 1 do
                    for x = 0, w - 1 do
                        if bb:getPixel(x, y):getColor8().a ~= 0xFF then
                            bb:free()
                            return true
                        end
                    end
                end
                bb:free()
                return false
            end
            ui:handleEvent(Event:new("SetPageTopMargin", 44))
            assert.is_true(inkInTopMargin())
            ui:handleEvent(Event:new("SetPageTopMargin", 15))
            assert.is_false(inkInTopMargin())
        end)
    end)

    describe("with a CJK book and no Source Han Serif", function()
        local ui
        setup(function()
            G_reader_settings:delSetting("typeset_serif_missing_shown")
            ui = openReader(sample_epub, { text_lang = "zh-CN" })
        end)
        teardown(function()
            closeReader(ui)
            G_reader_settings:delSetting("typeset_serif_missing_shown")
        end)

        it("should fall back to Source Han Sans and say so once on first open", function()
            assert.are.equal("Noto Sans CJK SC", ui.font.font_face)
            local prompt = topWidget()
            assert.is_truthy(prompt.text and prompt.text:find("Source Han Serif", 1, true))
            UIManager:close(prompt)
            UIManager:forceRePaint()
            assert.is_true(G_reader_settings:isTrue("typeset_serif_missing_shown"))
        end)

        it("should prompt and keep Source Han Sans when the serif card is tapped", function()
            local sheet = openPanel(ui)
            local serif = fontCard(sheet, require("ffi/util").template(_("%1 · not installed"), _("Source Han Serif")))
            assert.is_truthy(serif)
            tapWidget(serif)
            UIManager:forceRePaint()
            local prompt = topWidget()
            assert.are_not.equal(sheet, prompt)
            assert.is_truthy(prompt.text and prompt.text:find("Source Han Serif", 1, true))
            assert.are.equal("Noto Sans CJK SC", ui.font.font_face)
            UIManager:close(prompt)
            ui.config:closeSheet(true)
            UIManager:forceRePaint()
        end)
    end)

    describe("with a PDF", function()
        local ui
        setup(function() ui = openReader(sample_pdf) end)
        teardown(function() closeReader(ui) end)

        it("should open the original bottom bar", function()
            ui:handleEvent(Event:new("ShowConfigMenu"))
            UIManager:forceRePaint()
            assert.is_nil(ui.config.sheet)
            assert.is_truthy(ui.config.config_dialog)
            assert.are.equal(ui.config.config_dialog, topWidget())
            ui.config.config_dialog:closeDialog()
            UIManager:forceRePaint()
        end)
    end)

    it("should never override existing design defaults", function()
        local saved = G_reader_settings:readSetting("copt_font_size")
        G_reader_settings:saveSetting("copt_font_size", 23)
        ReaderTypesetPanel.applyTypesetDefaults()
        assert.are.equal(23, G_reader_settings:readSetting("copt_font_size"))
        for _, key in ipairs{ "copt_line_spacing", "copt_h_page_margins", "copt_t_page_margin" } do
            assert.is_truthy(G_reader_settings:readSetting(key))
        end
        if saved then
            G_reader_settings:saveSetting("copt_font_size", saved)
        else
            G_reader_settings:delSetting("copt_font_size")
        end
        for _, key in ipairs{ "copt_line_spacing", "copt_h_page_margins", "copt_t_page_margin" } do
            G_reader_settings:delSetting(key)
        end
    end)
end)
