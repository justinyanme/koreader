describe("ReaderTypesetPanel module", function()
    local Blitbuffer, DocumentRegistry, DocSettings, Panel, ReaderUI, ReaderTypesetPanel, Replacements, UIManager, Event, Geom, Screen
    local _
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local sample_pdf = "spec/front/unit/data/sample.pdf"

    setup(function()
        require("commonrequire")
        disable_plugins()
        Blitbuffer = require("ffi/blitbuffer")
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        Panel = require("ui/widget/panel")
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

    local DEFAULT_KEYS = { "copt_font_size", "copt_line_spacing", "copt_h_page_margins", "copt_t_page_margin" }
    local function clearDefaults()
        for _, key in ipairs(DEFAULT_KEYS) do
            G_reader_settings:delSetting(key)
        end
    end

    -- Runs the tasks scheduled by the reader (e.g. the re-render after BatchedUpdateDone).
    local function runTasks()
        for _ = 1, 3 do UIManager:_checkTasks() end
    end

    teardown(function()
        clearDefaults()
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
        -- CloseDocument handlers cancel pending reflow work before the document is released.
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

    -- The tracks of the panel, top to bottom: font size, weight, line spacing, margins.
    local function tracks(panel)
        local found, seen = {}, {}
        local function walk(widget)
            if type(widget) ~= "table" or seen[widget] then return end
            seen[widget] = true
            if widget.on_step and widget.stopX then
                table.insert(found, widget)
                return
            end
            for _, child in ipairs(widget) do walk(child) end
            if rawget(widget, "content") then walk(widget.content) end
        end
        walk(panel)
        return found
    end

    local function trackOf(ui, i)
        return tracks(ui.config.panel)[i]
    end

    local function tapTrack(track, x)
        tap(track.dimen.x + x, track.dimen.y + math.floor(track.dimen.h / 2))
        UIManager:forceRePaint()
    end

    -- the painted gray level at (x, y): 0 is ink, 255 is paper
    local function gray(x, y)
        return Screen.bb:getPixel(x, y):getColor8().a
    end

    -- What a track shows: the text painted in its knob, and the color its − (-1) or + (+1) button is outlined in.
    local function knobText(track)
        local size = track.knob_text:getSize()
        local cx = track.dimen.x + track:stopX(math.max(1, math.min(track.count, track.position)))
        local mid = track.minus_rect.y + math.floor(track.minus_rect.h / 2)
        for x = cx - math.floor(size.w / 2), cx + math.floor(size.w / 2) do
            for y = mid - math.floor(size.h / 4), mid + math.floor(size.h / 4) do
                if gray(x, y) < 0x80 then return track.knob_text.text end -- inked
            end
        end
    end
    local function buttonOutline(track, direction)
        local x = direction < 0 and track.dimen.x or track.dimen.x + track.dimen.w - Screen:scaleBySize(33)
        return gray(x, track.minus_rect.y + math.floor(track.minus_rect.h / 2)) -- its outer edge
    end
    local INK, RULE = require("ui/palette").ink:getColor8().a, require("ui/palette").rule:getColor8().a
    -- the darkest painted gray level in `rect`
    local function darkestIn(rect)
        local v = 0xFF
        for y = rect.y, rect.y + rect.h - 1 do
            for x = rect.x, rect.x + rect.w - 1 do
                v = math.min(v, gray(x, y))
            end
        end
        return v
    end
    -- The color a button's − or + glyph is painted in: INK, RULE, or else the darkest gray found. At the test
    -- screen's density the thin stroke never reaches full ink (its darkest pixel is about 0x33), so the glyph counts
    -- as ink below 0x44, and as rule gray within one gray step above rule gray, where lightening leaves that pixel.
    local function buttonGlyph(track, direction)
        local v = darkestIn(track.icons[direction].dimen)
        if v < 0x44 then return INK end
        if v >= RULE and v < RULE + 0x11 then return RULE end
        return v
    end

    -- The − and + buttons at the ends of a track, and its stops.
    local function tapMinus(track) tapTrack(track, Screen:scaleBySize(10)) end
    local function tapPlus(track) tapTrack(track, track.dimen.w - Screen:scaleBySize(10)) end
    local function tapStop(track, i) tapTrack(track, track:stopX(i)) end

    local function fontCard(panel, name)
        return find(panel, function(w) return w.name == name and w.callback end)
    end

    local function openPanel(ui)
        ui:handleEvent(Event:new("ShowConfigMenu"))
        UIManager:forceRePaint()
        return ui.config.panel
    end

    -- the pill at the right of the panel's title row, naming the paragraph mode
    local function paragraphPill(panel)
        return find(panel, function(w) return w.callback and type(w.text) == "string" end)
    end

    -- Taps the pill of the panel's title row: the paragraph panel.
    local function openParagraph(panel)
        tapWidget(paragraphPill(panel))
        UIManager:forceRePaint()
    end

    -- the row of a panel that `label` names
    local function row(panel, label)
        return find(panel, function(w) return w.callback and w.label and w.label.text == label end)
    end

    -- From the panel, taps its pill, then the paragraph panel's last row: the more layout settings.
    local function openLayoutOptions(ui)
        openParagraph(ui.config.panel)
        tapWidget(row(ui.config.panel, _("More layout options")))
        UIManager:forceRePaint()
    end

    -- the back arrow of the bottom bar under a nested panel
    local function backArrow(bars)
        return find(bars.bottom, function(w)
            return w.callback and w.dimen and find(w, function(c) return c.icon == "eink/arrow.left" end) ~= nil
        end)
    end

    local function back()
        UIManager:sendEvent(Event:new("KeyPress", require("device/key"):new("Back", {})))
        UIManager:forceRePaint()
    end

    describe("with an EPUB", function()
        local ui
        setup(function() ui = openReader(sample_epub) end)
        teardown(function() closeReader(ui) end)


        it("should open above the bottom bar, without the top bar, and close with it, refreshing only their rects", function()
            local panel
            local refreshes = refreshesOf(function()
                ui:handleEvent(Event:new("ShowConfigMenu"))
                panel = ui.config.panel
            end)
            local bars = ui.menu.bars
            assert.is_truthy(panel)
            assert.are.equal(panel, ui.menu.panel)
            assert.are.equal("font", ui.menu.panel_name)
            assert.are.equal(bars, topWidget())
            assert.is_false(bars.show_top) -- as in WeChat Read: the page shows up to the panel
            local band = panel:getRefreshRegion():combine(bars.bottom_rect)
            assert.are.same({ { mode = "ui", region = band } }, refreshes)
            assert.are.equal(bars.bottom_rect.y, panel:getRefreshRegion().y + panel:getRefreshRegion().h)
            assert.is_nil(find(panel, function(w) return w.icon == "eink/close" end))

            -- a tap on the page, where the top bar would be, closes the panel and the bottom bar
            refreshes = refreshesOf(function() tap(Screen:getWidth() / 2, 10) end)
            assert.is_nil(ui.config.panel)
            assert.is_nil(ui.menu.bars)
            assert.are.equal(ui, topWidget())
            assert.are.same({ { mode = "ui", region = band } }, refreshes)
        end)

        it("should open from the toolbar's Font entry, under its title row, and switch to another panel in place", function()
            tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
            UIManager:forceRePaint()
            local bars = ui.menu.bars
            -- the entries are icons without labels
            local function entry(icon)
                return find(bars.bottom, function(w)
                    return w.callback and find(w, function(c) return c.icon == icon or c.icon == icon .. ".bold" end) ~= nil
                end)
            end
            local page = ui:getCurrentPage()
            -- the top bar hides over the typeset panel: it and the band of the panel and the bottom bar refresh
            local refreshes = refreshesOf(function() tapWidget(entry("eink/font")) end)
            local panel = ui.config.panel
            assert.is_truthy(panel)
            assert.are.equal(bars, ui.menu.bars)
            assert.are.equal(bars, topWidget())
            assert.is_false(bars.show_top)
            assert.is_true(hasText(panel, _("Font settings")))
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/font.bold" end))
            local font_band = panel:getRefreshRegion():combine(bars.bottom_rect)
            assert.are.same({
                { mode = "ui", region = bars.top_rect },
                { mode = "ui", region = font_band },
            }, refreshes)

            -- the progress panel brings the top bar back
            refreshes = refreshesOf(function() tapWidget(entry("eink/progress")) end)
            assert.is_nil(ui.config.panel)
            assert.are.equal("progress", ui.menu.panel_name)
            assert.are.equal(bars, topWidget())
            assert.is_true(bars.show_top)
            local progress_band = ui.menu.panel:getRefreshRegion():combine(bars.bottom_rect)
            assert.are.same({
                { mode = "ui", region = bars.top_rect },
                { mode = "ui", region = font_band:combine(progress_band) },
            }, refreshes)

            tapWidget(entry("eink/font"))
            UIManager:forceRePaint()
            assert.are.equal(ui.config.panel, ui.menu.panel)
            font_band = ui.config.panel:getRefreshRegion():combine(bars.bottom_rect)
            -- the open entry closes its panel; the bars stay, the top bar with them
            refreshes = refreshesOf(function() tapWidget(entry("eink/font")) end)
            assert.is_nil(ui.config.panel)
            assert.is_nil(ui.menu.panel)
            assert.are.equal(bars, topWidget())
            assert.is_true(bars.show_top)
            assert.are.same({
                { mode = "ui", region = bars.top_rect },
                { mode = "ui", region = font_band },
            }, refreshes)
            assert.are.equal(page, ui:getCurrentPage())
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should apply font size, weight, line spacing and margins at once and keep the panel open", function()
            -- a text page: landing on a page with images flashes on its own ("refresh_on_pages_with_images")
            ui:handleEvent(Event:new("GotoPage", 20))
            UIManager:forceRePaint()
            local panel = openPanel(ui)
            local bars = ui.menu.bars
            local size = ui.document.configurable.font_size
            local xpointer = ui.document:getXPointer()
            UIManager.refresh_count = 0
            local refreshes = refreshesOf(function()
                tapPlus(trackOf(ui, 1))
                runTasks() -- the re-render follows BatchedUpdateDone
            end)
            assert.is_true(ui.document.configurable.font_size > size)
            assert.are.equal(panel, ui.config.panel)
            assert.are.equal(bars, topWidget())
            local modes = {}
            for _, r in ipairs(refreshes) do
                modes[r.mode] = true
                if r.mode == "ui" then
                    assert.are.same(panel:getRefreshRegion(), r.region)
                end
            end
            assert.is_nil(modes.full)
            assert.is_true(modes.partial) -- the re-laid out page, as for a page turn
            assert.is_true(modes.ui) -- the panel
            -- the page re-laid out around the same text
            assert.are.equal(ui.document:getCurrentPage(), ui.document:getPageFromXPointer(xpointer))

            tapPlus(trackOf(ui, 2))
            assert.are.equal(0.5, ui.document.configurable.font_base_weight)
            tapStop(trackOf(ui, 3), 7)
            assert.are.equal(145, ui.document.configurable.line_spacing)
            tapStop(trackOf(ui, 4), 3)
            runTasks()
            assert.are.same({ 18, 18 }, ui.document.configurable.h_page_margins)
            assert.are.equal(Screen:scaleBySize(18), ui.document:getPageMargins().left)
            assert.are.equal(panel, ui.config.panel)
            assert.are.equal(bars, topWidget())

            ui:saveSettings()
            assert.are.equal(ui.document.configurable.font_size, ui.doc_settings:readSetting("copt_font_size"))
            assert.are.equal(0.5, ui.doc_settings:readSetting("copt_font_base_weight"))
            assert.are.equal(145, ui.doc_settings:readSetting("copt_line_spacing"))
            assert.are.same({ 18, 18 }, ui.doc_settings:readSetting("copt_h_page_margins"))
            assert.are.equal(18, ui.doc_settings:readSetting("typeset_margin"))
            ui.menu:hideToolbar()
        end)

        it("should keep the new values after reopening the book", function()
            local size = ui.document.configurable.font_size
            closeReader(ui)
            ui = openReader(sample_epub, nil, true)
            assert.are.equal(size, ui.document.configurable.font_size)
            assert.are.equal(0.5, ui.document.configurable.font_base_weight)
            assert.are.equal(145, ui.document.configurable.line_spacing)
            assert.are.same({ 18, 18 }, ui.document.configurable.h_page_margins)
            assert.are.equal(Screen:scaleBySize(18), ui.document:getPageMargins().left)
            openPanel(ui)
            assert.are.equal(string.format("%g", size), knobText(trackOf(ui, 1)))
            assert.are.equal("4", knobText(trackOf(ui, 2)))
            assert.are.equal(7, trackOf(ui, 3).position)
            assert.are.equal(3, trackOf(ui, 4).position)
            ui.menu:hideToolbar()
        end)

        it("should preview real font names, select in black and retain the font when reopened", function()
            local panel = openPanel(ui)
            local sans = fontCard(panel, "Noto Sans")
            assert.is_truthy(sans)
            local name = find(sans, function(w) return w.text == "Noto Sans" end)
            assert.is_truthy(name)
            assert.is_truthy(name.face.realname:find("NotoSans", 1, true))
            local xpointer = ui.document:getXPointer()
            tapWidget(sans)
            runTasks()
            UIManager:forceRePaint()
            assert.are.equal("Noto Sans", ui.document:getFontFace())
            assert.are.equal(ui.document:getCurrentPage(), ui.document:getPageFromXPointer(xpointer))
            assert.are.equal("Noto Sans", ui.font.font_face)
            assert.is_truthy(hasText(ui.config.panel, "Current selection · Noto Sans"))
            sans = fontCard(ui.config.panel, "Noto Sans")
            assert.are.equal(INK, gray(sans.dimen.x + math.floor(sans.dimen.w / 2), sans.dimen.y + 3))
            assert.are.equal(255, find(sans, function(w) return w.text == "Noto Sans" end).fgcolor:getColor8().a)
            assert.are.equal(ui.menu.bars, topWidget())
            ui.menu:hideToolbar()
            closeReader(ui)
            ui = openReader(sample_epub, nil, true)
            assert.are.equal("Noto Sans", ui.font.font_face)
            openPanel(ui)
            assert.is_truthy(fontCard(ui.config.panel, "Noto Sans").selected)
            ui.menu:hideToolbar()
        end)

        it("should keep the grid usable at the largest interface font size", function()
            local Font = require("ui/font")
            Font:setUIScale(1.35)
            local panel = openPanel(ui)
            local sans = fontCard(panel, "Noto Sans")
            local name = find(sans, function(w) return w.text == "Noto Sans" end)
            local label_width = name:getSize().w
            local panel_top = panel:getRefreshRegion().y
            tapWidget(sans)
            UIManager:forceRePaint()
            Font:setUIScale(1)
            assert.is_true(label_width < sans.dimen.w)
            assert.is_true(panel_top >= 0)
            assert.are.equal("Noto Sans", ui.font.font_face)
            assert.is_true(fontCard(ui.config.panel, "Noto Sans").selected)
            ui.menu:hideToolbar()
        end)

        it("should open more fonts as a bottom panel and collapse to typesetting without turning the book", function()
            local main = openPanel(ui)
            local bars, anchor = ui.menu.bars, ui.rolling:getBookLocation()
            local old_band = main:getRefreshRegion():combine(bars.bottom_rect)
            local refreshes = refreshesOf(function() tapWidget(fontCard(main, _("View more") .. " ›")) end)
            local fonts = ui.config.panel
            assert.are_not.equal(main, fonts)
            assert.are.equal(fonts, ui.menu.panel)
            assert.are.equal(bars, topWidget())
            assert.is_false(bars.show_top)
            assert.is_false(bars.show_bottom)
            local region = fonts:getRefreshRegion()
            assert.are.equal(Screen:getHeight(), region.y + region.h)
            assert.is_true(region.h >= Screen:getHeight() * 0.58 and region.h <= Screen:getHeight() * 0.62)
            assert.are.same({ { mode = "ui", region = old_band:combine(region) } }, refreshes)
            assert.is_true(hasText(fonts, _("Font")))
            assert.is_truthy(fonts.collapse)
            tapWidget(fonts.collapse)
            UIManager:forceRePaint()
            assert.are.equal("main", ui.config.page)
            assert.is_true(ui.menu.bars.show_bottom)
            assert.is_false(ui.menu.bars.show_top)
            assert.are.equal(anchor, ui.rolling:getBookLocation())
            ui.menu:hideToolbar()
        end)

        it("should keep the font panel within its region at the largest interface font size", function()
            local Font = require("ui/font")
            Font:setUIScale(1.35)
            local ok, err = pcall(function()
                openPanel(ui)
                tapWidget(fontCard(ui.config.panel, _("View more") .. " ›"))
                UIManager:forceRePaint()
                local page = ui.config.panel
                local title_h = page.header[1][1]:getSize().h
                assert.is_true(title_h <= page.header.dimen.h)
                assert.is_true(page:getRefreshRegion().y > 0)
                find(page, function(w)
                    if w.font_face then
                        assert.is_true(w.dimen.y >= page.tabs.dimen.y + page.tabs.dimen.h)
                        assert.is_true(w.dimen.y + w.dimen.h <= (page.capsule and page.capsule.dimen.y or Screen:getHeight()))
                        local label = find(w, function(c) return c.text == w.name end)
                        assert.is_true(label:getSize().w < w.dimen.w)
                    end
                    return false
                end)
                back()
                ui.menu:hideToolbar()
            end)
            Font:setUIScale(1)
            assert(ok, err)
        end)

        it("should return from the font panel to the typesetting panel and toolbar without changing the chosen font", function()
            local panel = openPanel(ui)
            local bars, selected = ui.menu.bars, ui.font.font_face
            tapWidget(fontCard(panel, _("View more") .. " ›"))
            UIManager:forceRePaint()
            local page = ui.config.panel
            assert.is_true(page:getRefreshRegion().y > 0)
            assert.are_not.equal(panel, ui.config.panel)
            assert.are.equal(bars, ui.menu.bars)
            assert.is_true(fontCard(page, selected).selected)
            back()
            assert.are.equal(bars, topWidget())
            panel = ui.config.panel
            assert.are.equal("main", ui.config.page)
            assert.is_true(bars.show_bottom)
            assert.is_false(bars.show_top)
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/font.bold" end))
            assert.are.equal(selected, ui.font.font_face)
            assert.is_truthy(fontCard(panel, selected).selected)
            ui.menu:hideToolbar()
        end)

        it("should record a font selected on the font panel and refresh its body", function()
            local panel = openPanel(ui)
            tapWidget(fontCard(panel, _("View more") .. " ›"))
            UIManager:forceRePaint()
            local page = ui.config.panel
            local refreshes = refreshesOf(function() tapWidget(fontCard(page, "FreeSerif")) end)
            local ui_refreshes = {}
            for _, refresh in ipairs(refreshes) do
                if refresh.mode == "ui" then
                    table.insert(ui_refreshes, refresh)
                else
                    assert.are.equal("partial", refresh.mode) -- the reader's font re-layout
                end
            end
            assert.are.same({ { mode = "ui", region = page:getRefreshRegion() } }, ui_refreshes)
            assert.is_true(page:getRefreshRegion().y > 0)
            assert.is_true(hasText(page, require("ffi/util").template(_("Current selection · %1"), "FreeSerif")))
            assert.are.equal("FreeSerif", G_reader_settings:readSetting("cre_fonts_recently_selected")[1])
            assert.is_true(G_reader_settings:readSetting("cre_fonts_explicitly_selected").FreeSerif)
            back()
            assert.are.equal("main", ui.config.page)
            assert.is_true(fontCard(ui.config.panel, "FreeSerif").selected)
            ui.menu:hideToolbar()
        end)

        it("should select a font by name from More and show it selected when reopening", function()
            ui:handleEvent(Event:new("GotoPage", 4))
            runTasks()
            local panel = openPanel(ui)
            local xpointer = ui.rolling:getBookLocation()
            tapWidget(fontCard(panel, _("View more") .. " ›"))
            UIManager:forceRePaint()
            local page = ui.config.panel
            local item
            for __ = 1, page.page_count do
                item = fontCard(page, "FreeSerif")
                if item then break end
                if page.capsule then tapWidget(page.capsule, 0.75) end
                UIManager:forceRePaint()
            end
            assert.is_truthy(item)
            tapWidget(item)
            runTasks()
            UIManager:forceRePaint()
            assert.is_true(fontCard(page, "FreeSerif").selected)
            back()
            assert.are.equal("FreeSerif", ui.document:getFontFace())
            assert.are.equal(xpointer, ui.rolling:getBookLocation())
            assert.are.equal(ui.document:getCurrentPage(), ui.document:getPageFromXPointer(xpointer))
            ui:saveSettings()
            closeReader(ui)
            ui = openReader(sample_epub, nil, true)
            assert.are.equal("FreeSerif", ui.document:getFontFace())
            assert.are.equal(xpointer, ui.rolling:getBookLocation())
            openPanel(ui)
            assert.is_true(fontCard(ui.config.panel, "FreeSerif").selected)
            ui.menu:hideToolbar()
        end)

        it("should apply profile and gesture SetFont events through the registered engine fonts", function()
            local xpointer = ui.rolling:getBookLocation()
            ui:handleEvent(Event:new("SetFont", "Noto Serif"))
            runTasks()
            assert.are.equal(xpointer, ui.rolling:getBookLocation())
            assert.are.equal("Noto Serif", ui.document:getFontFace())
            assert.are.equal(ui.document:getCurrentPage(), ui.document:getPageFromXPointer(xpointer))
            ui:handleEvent(Event:new("SetFont", "Missing profile font"))
            assert.are.equal("Noto Serif", ui.document:getFontFace())
        end)

        it("should recover a removed font to the default reading font in a Latin EPUB", function()
            closeReader(ui)
            ui = openReader(sample_epub, { font_face = "Removed user font" })
            openPanel(ui)
            assert.are.equal(ui.document.default_font, ui.font.font_face)
            assert.are.equal(ui.document.default_font, ui.document:getFontFace())
            assert.is_true(fontCard(ui.config.panel, ui.document.default_font).selected)
            ui.menu:hideToolbar()
        end)

        it("should recover a removed font to the system font for Chinese text", function()
            closeReader(ui)
            ui = openReader(sample_epub, { font_face = "Removed user font", text_lang = "zh-CN" })
            openPanel(ui)
            assert.are.equal("Noto Sans CJK SC", ui.document:getFontFace())
            assert.is_true(fontCard(ui.config.panel, _("System font")).selected)
            ui.menu:hideToolbar()
        end)

        it("should open the more layout settings from the paragraph panel's last row, with only a back arrow below", function()
            openPanel(ui)
            local bars = ui.menu.bars
            openParagraph(ui.config.panel)
            local paragraph = ui.config.panel
            local paragraph_band = paragraph:getRefreshRegion():combine(bars.bottom_rect)
            local refreshes = refreshesOf(function() tapWidget(row(paragraph, _("More layout options"))) end)
            local more = ui.config.panel
            assert.are.equal("more", ui.config.page)
            assert.are.equal(more, ui.menu.panel)
            assert.is_true(hasText(more, _("Render Mode")))
            assert.is_false(hasText(more, _("Font Weight"))) -- on the panel's own track now
            -- the top bar stays hidden, the bottom bar holds only a back arrow
            assert.are.equal(bars, topWidget())
            assert.is_false(bars.show_top)
            assert.is_truthy(backArrow(bars))
            assert.are.equal(0, backArrow(bars).dimen.x) -- at the bottom left, as on full-screen pages
            assert.is_nil(find(bars.bottom, function(w) return w.icon == "eink/progress" end))
            assert.are.same({
                { mode = "ui", region = paragraph_band:combine(more:getRefreshRegion():combine(bars.bottom_rect)) },
            }, refreshes)

            -- back to the paragraph panel it was opened from, then to the panel
            tapWidget(backArrow(bars))
            UIManager:forceRePaint()
            assert.are.equal("paragraph", ui.config.page)
            assert.are.equal(ui.config.panel, ui.menu.panel)
            assert.is_false(bars.show_top)
            assert.is_truthy(backArrow(bars))
            tapWidget(backArrow(bars))
            UIManager:forceRePaint()
            assert.are.equal("main", ui.config.page)
            assert.are.equal(ui.config.panel, ui.menu.panel)
            assert.is_false(bars.show_top)
            assert.is_truthy(find(bars.bottom, function(w) return w.icon == "eink/font.bold" end))
            ui.menu:hideToolbar()
        end)

        it("should open the existing menus from its links", function()
            for _, case in ipairs{
                { "more", _("Hyphenation") },
                { "more", _("Paragraph indent") },
                { "more", _("Paragraph spacing") },
                { "more", _("Style tweaks") },
            } do
                openPanel(ui)
                if case[1] == "more" then
                    openLayoutOptions(ui)
                end
                local link = find(ui.config.panel, function(w) return w.callback and w.dimen and (w.name == case[2] or (w.label and w.label.text == case[2])) end)
                assert.is_truthy(link, case[2])
                tapWidget(link)
                UIManager:forceRePaint()
                assert.is_nil(ui.config.panel)
                assert.is_nil(ui.menu.bars)
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

        it("should leave the original bottom bar's link with the panel and the bars closed", function()
            openPanel(ui)
            openLayoutOptions(ui)
            tapWidget(find(ui.config.panel, function(w) return w.callback and w.label and w.label.text == _("All layout options (original)") end))
            UIManager:forceRePaint()
            assert.is_nil(ui.config.panel)
            assert.is_nil(ui.menu.bars)
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

            ui:handleEvent(Event:new("SetViewMode", "scroll"))
            assert.is_false(inkInTopMargin())
            ui:handleEvent(Event:new("SetViewMode", "page"))
            assert.is_true(inkInTopMargin())

            ui.document.configurable.status_line = 0 -- crengine's own top status bar
            assert.is_false(inkInTopMargin())
            ui.document.configurable.status_line = 1

            ui:handleEvent(Event:new("SetPageTopMargin", 15))
            assert.is_false(inkInTopMargin())
            ui:handleEvent(Event:new("SetPageTopMargin", 44))
            runTasks()
        end)

        it("should draw the chapter header as WeChat Read: a circled ‹ and the title in ink, centered in the top margin", function()
            local header = ui.view.view_modules.chapter_header
            ui:handleEvent(Event:new("SetPageTopMargin", 44))
            runTasks()
            UIManager:forceRePaint()
            local margins = ui.document:getPageMargins()
            local w = Screen:getWidth()
            local bb = Screen.bb
            local x0, x1, y0, y1, darkest = w, -1, margins.top, -1, 0xFF
            for y = 0, margins.top - 1 do
                for x = 0, w - 1 do
                    local v = bb:getPixel(x, y):getColor8().a
                    if v ~= 0xFF then
                        x0, x1, y0, y1 = math.min(x0, x), math.max(x1, x), math.min(y0, y), math.max(y1, y)
                        darkest = math.min(darkest, v)
                    end
                end
            end
            -- ink, not the pencil gray (0x55) it used to be, from the text's left edge
            assert.is_true(darkest < 0x20, darkest)
            assert.is_true(x0 >= margins.left and x0 <= margins.left + 1, x0 .. " vs " .. margins.left)
            assert.is_true(x1 < w - margins.right)
            -- centered in the top margin, give or take the glyphs' own extents
            assert.is_true(math.abs((y0 + y1) / 2 - margins.top / 2) <= Screen:scaleBySize(3), y0 .. "-" .. y1)
            -- the circled ‹ comes first: a column of ink one icon wide, then a gap before the title
            local icon = Screen:scaleBySize(header.ICON)
            local function columnInked(x)
                for y = y0, y1 do
                    if bb:getPixel(x, y):getColor8().a ~= 0xFF then return true end
                end
                return false
            end
            assert.is_true(columnInked(x0 + math.floor(icon / 2)))
            assert.is_false(columnInked(x0 + icon + 1))
        end)

        it("should step the font size from an off-scale size to the next size below or above", function()
            ui.config:apply("font_size", 23, "SetFontSize")
            openPanel(ui)
            tapMinus(trackOf(ui, 1))
            assert.are.equal(22, ui.document.configurable.font_size)
            ui.config:apply("font_size", 23, "SetFontSize")
            ui.config:refreshPanel()
            UIManager:forceRePaint()
            tapPlus(trackOf(ui, 1))
            assert.are.equal(24, ui.document.configurable.font_size)
            runTasks()
            ui.menu:hideToolbar()
        end)

        it("should go back one layer at a time on Back: more layout settings, paragraphs, the panel, the bars", function()
            runTasks() -- a re-render left by the last font size change
            UIManager:forceRePaint()
            local page = ui:getCurrentPage()
            openPanel(ui)
            local bars = ui.menu.bars
            openLayoutOptions(ui)
            assert.are.equal("more", ui.config.page)
            back()
            assert.are.equal("paragraph", ui.config.page)
            assert.are.equal(ui.config.panel, ui.menu.panel)
            assert.is_false(bars.show_top)
            back()
            assert.are.equal("main", ui.config.page)
            assert.are.equal(ui.config.panel, ui.menu.panel)
            assert.is_false(bars.show_top)
            assert.are.equal(bars, topWidget())
            back()
            assert.is_nil(ui.config.panel)
            assert.are.equal(bars, topWidget())
            assert.is_true(bars.show_top) -- the toolbar, as before the panel
            back()
            assert.is_nil(ui.menu.bars)
            assert.are.equal(ui, topWidget())
            assert.are.equal(page, ui:getCurrentPage())
        end)

        it("should close only the panel on CloseConfigMenu", function()
            openPanel(ui)
            local bars = ui.menu.bars
            ui:handleEvent(Event:new("CloseConfigMenu"))
            UIManager:forceRePaint()
            assert.is_nil(ui.config.panel)
            assert.are.equal(bars, topWidget())
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
        end)

        it("should find the paragraph style tweaks by id, and fall back to all of them", function()
            local tweaks = ui.styletweak.tweaks_table
            local indent = ui.config:styleTweaks("paragraph_indent")
            assert.are_not.equal(tweaks, indent)
            assert.is_truthy(find(indent, function(w) return w.tweak_id == "paragraph_indent" end))
            assert.is_truthy(find(ui.config:styleTweaks("paragraph_whitespace"), function(w) return w.tweak_id == "paragraph_whitespace" end))
            assert.are.equal(tweaks, ui.config:styleTweaks("no_such_tweak"))
        end)

        it("should close a menu it opened on CloseConfigMenu", function()
            ui.config:showMenu(ui.typography.menu_table)
            UIManager:forceRePaint()
            assert.are.equal(ui.config.menu_container, topWidget())
            ui:handleEvent(Event:new("CloseConfigMenu"))
            UIManager:forceRePaint()
            assert.is_nil(ui.config.menu_container)
            assert.are.equal(ui, topWidget())
        end)

        it("keeps the same text through window rotation and an inset-only reflow", function()
            ui:handleEvent(Event:new("GotoPage", 20))
            UIManager:forceRePaint()
            -- The reader retains the navigation anchor; a rendered page starts before that passage.
            local anchor = ui.rolling:getBookLocation()
            local original_bb, original_size = Screen.bb, Screen.screen_size
            local function resize(w, h)
                if Screen.bb ~= original_bb then Screen.bb:free() end
                Screen.bb = Blitbuffer.new(w, h, original_bb:getType())
                Screen.screen_size = { w = w, h = h }
                -- This is the sequence shared by SDL size, pixel-size and safe
                -- area events. ReaderRolling must retain the original passage.
                local size = Screen:getSize()
                ui:handleEvent(Event:new("SetDimensions", size))
                ui:handleEvent(Event:new("ScreenResize", size))
                ui:handleEvent(Event:new("RedrawCurrentPage"))
                runTasks()
                UIManager:forceRePaint()
                assert.are.equal(anchor, ui.rolling:getBookLocation())
                assert.are.equal(ui.document:getCurrentPage(), ui.document:getPageFromXPointer(anchor))
            end
            local ok, err = pcall(function()
                resize(820, 390)
                resize(820, 366) -- same window orientation, changed safe-area height
                resize(390, 820)
            end)
            if Screen.bb ~= original_bb then Screen.bb:free() end
            Screen.bb, Screen.screen_size = original_bb, original_size
            ui:handleEvent(Event:new("SetDimensions", Screen:getSize()))
            runTasks()
            assert(ok, err)
        end)

        it("should keep the chosen margin across rotation, widened only to cap the line length", function()
            ui.config:setFontSize(15)
            runTasks()
            openPanel(ui)
            tapStop(trackOf(ui, 4), 3)
            runTasks()
            assert.are.same({ 18, 18 }, ui.document.configurable.h_page_margins)
            ui.menu:hideToolbar()

            ui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
            runTasks()
            local narrow = ui.config:marginsFor(18)
            assert.is_true(narrow > 18) -- a landscape line would hold more than 38 characters
            assert.are.same({ narrow, narrow }, ui.document.configurable.h_page_margins)
            openPanel(ui)
            assert.are.equal(3, trackOf(ui, 4).position)
            tapStop(trackOf(ui, 4), 7)
            runTasks()
            assert.are.equal(44, ui.doc_settings:readSetting("typeset_margin"))
            local wide = ui.config:marginsFor(44)
            assert.are.same({ wide, wide }, ui.document.configurable.h_page_margins)
            UIManager:forceRePaint()
            tapStop(trackOf(ui, 4), 5)
            runTasks()
            -- 28 and 44dp may widen to the same margins: the knob stays at the margin chosen
            assert.are.equal(5, trackOf(ui, 4).position)
            ui.menu:hideToolbar()

            ui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
            runTasks()
            assert.are.same({ 28, 28 }, ui.document.configurable.h_page_margins)

            -- margins set elsewhere are the user's own
            ui:handleEvent(Event:new("SetPageHorizMargins", { 15, 15 }))
            runTasks()
            assert.is_nil(ui.doc_settings:readSetting("typeset_margin"))
        end)
    end)

    describe("tracks", function()
        local C_ = function(...) return _.pgettext(...) end
        local DESIGN_VALUES = { copt_font_size = 19, copt_font_base_weight = 0, copt_line_spacing = 125, copt_h_page_margins = { 28, 28 } }
        local ui
        before_each(function()
            ui = openReader(sample_epub, DESIGN_VALUES)
            ui:handleEvent(Event:new("GotoPage", 20))
            UIManager:forceRePaint()
        end)
        after_each(function()
            if ui.menu.bars then ui.menu:hideToolbar(true) end
            runTasks()
            closeReader(ui)
        end)

        it("should show font size, weight, line spacing and margins in order, the knobs reading the real values", function()
            local panel = openPanel(ui)
            local t = tracks(panel)
            assert.are.equal(4, #t)
            assert.is_true(hasText(panel, _("Font settings")))
            -- the title row, as tall as the pill at its right
            local title = paragraphPill(panel)
            for i, case in ipairs{
                { C_("Typeset track", "Small"), C_("Typeset track", "Large"), "19", 5 },
                { C_("Typeset track", "Light"), C_("Typeset track", "Bold"), "3", 3 }, -- the engine's 0 ("Regular")
                { C_("Typeset track", "Tight"), C_("Typeset track", "Loose"), C_("Typeset panel", "Line spacing"), 5 },
                { C_("Typeset track", "Small"), C_("Typeset track", "Large"), _("Margins"), 5 },
            } do
                assert.are.same(case, { t[i].low_text.text, t[i].high_text.text, knobText(t[i]), t[i].position })
                assert.are.same({ INK, INK }, { buttonOutline(t[i], -1), buttonOutline(t[i], 1) })
                assert.are.equal(Panel.getContentWidth(), t[i].dimen.w)
                -- rows 44dp apart under the title row
                local above = i == 1 and title.dimen or t[i - 1].dimen
                assert.are.equal(above.y + above.h, t[i].dimen.y)
                assert.are.equal(Screen:scaleBySize(44), t[i].dimen.h)
            end
            -- opening the panel changes nothing
            assert.are.equal(19, ui.document.configurable.font_size)
            assert.are.same({ 28, 28 }, ui.document.configurable.h_page_margins)
            assert.is_nil(ui.doc_settings:readSetting("typeset_margin"))
        end)

        it("should step each track with − and + to the engine's next value, around the same text", function()
            openPanel(ui)
            for _, case in ipairs{
                { 1, "font_size", 20, 18, "20" },
                { 2, "font_base_weight", 0.5, -0.5, "4" },
                { 3, "line_spacing", 135, 115 },
                { 4, "h_page_margins", { 36, 36 }, { 23, 23 } },
            } do
                local i, name, up, down = case[1], case[2], case[3], case[4]
                local xpointer = ui.document:getXPointer()
                tapPlus(trackOf(ui, i))
                runTasks()
                assert.are.same(up, ui.document.configurable[name])
                if case[5] then assert.are.equal(case[5], knobText(trackOf(ui, i))) end
                assert.are.equal(ui.document:getCurrentPage(), ui.document:getPageFromXPointer(xpointer), name)
                tapMinus(trackOf(ui, i))
                tapMinus(trackOf(ui, i))
                runTasks()
                assert.are.same(down, ui.document.configurable[name])
                assert.are.equal(ui.document:getCurrentPage(), ui.document:getPageFromXPointer(xpointer), name)
            end
            runTasks()
            assert.are.equal(23, ui.doc_settings:readSetting("typeset_margin"))
            assert.are.equal(Screen:scaleBySize(23), ui.document:getPageMargins().left)
            assert.is_truthy(ui.config.panel)
        end)

        it("should stop at the ends of a track, with the button there disabled", function()
            openPanel(ui)
            -- at the last stop, + is outlined in rule gray with a rule-gray glyph, and does nothing
            tapStop(trackOf(ui, 4), 9)
            assert.are.same({ 70, 70 }, ui.document.configurable.h_page_margins)
            assert.are.same({ INK, RULE }, { buttonOutline(trackOf(ui, 4), -1), buttonOutline(trackOf(ui, 4), 1) })
            assert.are.same({ INK, RULE }, { buttonGlyph(trackOf(ui, 4), -1), buttonGlyph(trackOf(ui, 4), 1) })
            tapPlus(trackOf(ui, 4))
            assert.are.same({ 70, 70 }, ui.document.configurable.h_page_margins)
            tapStop(trackOf(ui, 3), 1)
            assert.are.equal(85, ui.document.configurable.line_spacing)
            assert.are.same({ RULE, INK }, { buttonOutline(trackOf(ui, 3), -1), buttonOutline(trackOf(ui, 3), 1) })
            assert.are.same({ RULE, INK }, { buttonGlyph(trackOf(ui, 3), -1), buttonGlyph(trackOf(ui, 3), 1) })
            tapStop(trackOf(ui, 1), 10)
            assert.are.equal(28, ui.document.configurable.font_size)
            assert.are.equal("28", knobText(trackOf(ui, 1)))
            assert.are.equal(RULE, buttonOutline(trackOf(ui, 1), 1))
            tapPlus(trackOf(ui, 1))
            assert.are.equal(28, ui.document.configurable.font_size)
            tapStop(trackOf(ui, 1), 1)
            assert.are.equal(15, ui.document.configurable.font_size)
            tapMinus(trackOf(ui, 1))
            assert.are.equal(15, ui.document.configurable.font_size)
            assert.are.same({ RULE, INK }, { buttonOutline(trackOf(ui, 1), -1), buttonOutline(trackOf(ui, 1), 1) })
            assert.are.equal(INK, buttonGlyph(trackOf(ui, 1), 1))
        end)

        it("should read back values past a track's ends there, with their own number, and go back onto it", function()
            ui:handleEvent(Event:new("ConfigChange", "font_size", 32))
            ui:handleEvent(Event:new("SetFontSize", 32))
            ui:handleEvent(Event:new("ConfigChange", "line_spacing", 70))
            ui:handleEvent(Event:new("SetLineSpace", 70))
            runTasks()
            openPanel(ui)
            assert.are.equal("32", knobText(trackOf(ui, 1)))
            assert.is_true(trackOf(ui, 1).position > 10)
            assert.is_true(trackOf(ui, 3).position < 1)
            -- the button leading further away is gray and does nothing
            assert.are.same({ INK, RULE }, { buttonOutline(trackOf(ui, 1), -1), buttonOutline(trackOf(ui, 1), 1) })
            assert.are.same({ RULE, INK }, { buttonOutline(trackOf(ui, 3), -1), buttonOutline(trackOf(ui, 3), 1) })
            tapPlus(trackOf(ui, 1))
            tapMinus(trackOf(ui, 3))
            assert.are.equal(32, ui.document.configurable.font_size)
            assert.are.equal(70, ui.document.configurable.line_spacing)
            -- the other goes back onto the track, to its end stop
            tapMinus(trackOf(ui, 1))
            assert.are.equal(28, ui.document.configurable.font_size)
            tapPlus(trackOf(ui, 3))
            assert.are.equal(85, ui.document.configurable.line_spacing)
            -- and so does a tap on the end stop, where the knob shows
            ui.config:apply("font_size", 32, "SetFontSize")
            ui.config:apply("line_spacing", 70, "SetLineSpace")
            ui.config:refreshPanel()
            UIManager:forceRePaint()
            tapStop(trackOf(ui, 1), 10)
            assert.are.equal(28, ui.document.configurable.font_size)
            tapStop(trackOf(ui, 3), 1)
            assert.are.equal(85, ui.document.configurable.line_spacing)
        end)

        it("should show fine values set elsewhere between two stops, without snapping them, and step from them", function()
            ui:handleEvent(Event:new("ConfigChange", "font_size", 19.5))
            ui:handleEvent(Event:new("SetFontSize", 19.5))
            ui:handleEvent(Event:new("ConfigChange", "font_base_weight", 0.25))
            ui:handleEvent(Event:new("SetFontBaseWeight", 0.25))
            ui:handleEvent(Event:new("ConfigChange", "line_spacing", 100))
            ui:handleEvent(Event:new("SetLineSpace", 100))
            ui:handleEvent(Event:new("ConfigChange", "h_page_margins", { 20, 20 }))
            ui:handleEvent(Event:new("SetPageHorizMargins", { 20, 20 }))
            runTasks()
            openPanel(ui)
            local t = tracks(ui.config.panel)
            assert.are.same({ "19.5", 5.5 }, { knobText(t[1]), t[1].position })
            assert.are.same({ _("Font Weight"), 3.5 }, { knobText(t[2]), t[2].position })
            assert.are.equal(2.5, t[3].position)
            assert.is_near(3.4, t[4].position, 1e-9)
            assert.are.equal(19.5, ui.document.configurable.font_size)
            assert.are.equal(0.25, ui.document.configurable.font_base_weight)
            assert.are.equal(100, ui.document.configurable.line_spacing)
            assert.are.same({ 20, 20 }, ui.document.configurable.h_page_margins)

            tapPlus(trackOf(ui, 1))
            assert.are.equal(20, ui.document.configurable.font_size)
            tapPlus(trackOf(ui, 2))
            assert.are.equal(0.5, ui.document.configurable.font_base_weight)
            tapMinus(trackOf(ui, 3))
            assert.are.equal(95, ui.document.configurable.line_spacing)
            tapMinus(trackOf(ui, 4))
            assert.are.same({ 18, 18 }, ui.document.configurable.h_page_margins)
        end)

        it("should leave margins set elsewhere alone when the font size changes, in landscape too", function()
            -- as the original bottom bar sets them; {10, 10} is also upstream's default
            ui:handleEvent(Event:new("ConfigChange", "h_page_margins", { 10, 10 }))
            ui:handleEvent(Event:new("SetPageHorizMargins", { 10, 10 }))
            ui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
            finally(function()
                ui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
                runTasks()
            end)
            runTasks()
            assert.is_true(ui.config:marginsFor(10) > 10) -- the panel's own 10dp would widen here
            openPanel(ui)
            assert.are.equal(1, trackOf(ui, 4).position) -- the knob still shows where they are
            tapPlus(trackOf(ui, 1))
            runTasks()
            assert.are.equal(20, ui.document.configurable.font_size)
            assert.are.same({ 10, 10 }, ui.document.configurable.h_page_margins)
            assert.are.equal(Screen:scaleBySize(10), ui.document:getPageMargins().left)
            assert.is_nil(ui.doc_settings:readSetting("typeset_margin"))
        end)

        it("should read a margin step saved by the first round as its margin", function()
            closeReader(ui)
            ui = openReader(sample_epub, { typeset_margin_step = 3 })
            assert.are.same({ 44, 44 }, ui.document.configurable.h_page_margins)
            assert.are.equal(44, ui.doc_settings:readSetting("typeset_margin"))
            assert.is_nil(ui.doc_settings:readSetting("typeset_margin_step"))
            openPanel(ui)
            assert.are.equal(7, trackOf(ui, 4).position)
        end)
    end)

    describe("paragraph panel", function()
        local TINT = require("ui/palette").tint:getColor8().a
        -- Two paragraphs of a speech in the sample, the first one with a line break.
        local SPEECH = "/body[1]/DocFragment[5]/body[1]/div[1]/div[1]/div[1]/blockquote[26]"
        local FIRST, SECOND = SPEECH .. "/p[1]/text()[1].0", SPEECH .. "/p[2]/em[1]/text()[1].0"
        local BROKEN_LINE = SPEECH .. "/p[1]/text()[2].1"
        local ui

        setup(function()
            ui = openReader(sample_epub)
        end)
        teardown(function()
            if ui.menu.bars then ui.menu:hideToolbar(true) end
            runTasks()
            closeReader(ui)
        end)

        -- How the page lays the speech out: the first-line indent of the second paragraph, from where the first one's
        -- line after its line break starts, and how far below the first paragraph's top the second one starts.
        local function layout()
            runTasks() -- the re-render follows BatchedUpdateDone
            UIManager:forceRePaint() -- crengine re-lays out the part of the book it draws (partial rerendering)
            ui:handleEvent(Event:new("GotoXPointer", FIRST))
            UIManager:forceRePaint()
            local y1 = ui.document:getScreenPositionFromXPointer(FIRST)
            local __, x1 = ui.document:getScreenPositionFromXPointer(BROKEN_LINE)
            local y2, x2 = ui.document:getScreenPositionFromXPointer(SECOND)
            return x2 - x1, y2 - y1
        end

        local function card(panel, label)
            return find(panel, function(w) return w.callback and w.label == label end)
        end
        local function flushCard(panel) return card(panel, _("First line flush")) end
        local function indentCard(panel) return card(panel, _("First line indented")) end
        local function spacingRow(panel) return find(panel, function(w) return w.toggle and w.callback end) end

        -- the painted fill of a card, inside its right edge: ink for the chosen mode, tint for the other
        local function fill(c)
            return gray(c.dimen.x + c.dimen.w - Screen:scaleBySize(4), c.dimen.y + Screen:scaleBySize(30))
        end
        local function fills(panel)
            return { fill(flushCard(panel)), fill(indentCard(panel)) }
        end
        -- whether the spacing toggle shows on: its knob at the right, unlike its middle
        local function toggleShowsOn(r)
            local t = r.toggle
            local y = t.dimen.y + math.floor(t.dimen.h / 2)
            return gray(t.dimen.x + t.dimen.w - math.floor(t.dimen.h / 2), y) ~= gray(t.dimen.x + math.floor(t.dimen.w / 2), y)
        end

        local function tapAndPaint(widget, x_ratio)
            tapWidget(widget, x_ratio)
            runTasks()
            UIManager:forceRePaint()
        end

        it("should name the book's own paragraphs on the pill, and open the two cards from it with only a back arrow below", function()
            local main = openPanel(ui)
            local bars = ui.menu.bars
            assert.are.equal(_("Paragraphs"), paragraphPill(main).text)
            local main_band = main:getRefreshRegion():combine(bars.bottom_rect)
            local refreshes = refreshesOf(function() openParagraph(main) end)
            local paragraph = ui.config.panel
            assert.are.equal("paragraph", ui.config.page)
            assert.are.equal(paragraph, ui.menu.panel)
            assert.are.equal(bars, topWidget())
            assert.is_false(bars.show_top)
            assert.is_truthy(backArrow(bars))
            assert.is_nil(find(bars.bottom, function(w) return w.callback and hasText(w, _("Progress")) end))
            assert.are.same({
                { mode = "ui", region = main_band:combine(paragraph:getRefreshRegion():combine(bars.bottom_rect)) },
            }, refreshes)
            -- two cards side by side, the spacing row at the foot of the second; none chosen: the book's own styles
            local flush, indent = flushCard(paragraph), indentCard(paragraph)
            assert.are.equal(flush.dimen.y, indent.dimen.y)
            assert.is_true(flush.dimen.x + flush.dimen.w < indent.dimen.x)
            assert.are.same({ TINT, TINT }, fills(paragraph))
            local spacing = spacingRow(paragraph)
            assert.is_true(spacing.dimen.y > indent.dimen.y)
            assert.are.equal(indent.dimen.y + indent.dimen.h, spacing.dimen.y + spacing.dimen.h)
            assert.is_false(toggleShowsOn(spacing))
            assert.is_true(row(paragraph, _("More layout options")).dimen.y > indent.dimen.y + indent.dimen.h)
            -- opening it changes nothing
            ui:saveSettings()
            assert.is_nil(ui.doc_settings:readSetting("style_tweaks"))

            tapWidget(backArrow(bars))
            UIManager:forceRePaint()
            assert.are.equal("main", ui.config.page)
            ui.menu:hideToolbar()
        end)

        it("should set first line flush or indented for this book from the cards, re-laying the page out under the open panel", function()
            local __, own_gap = layout()
            openPanel(ui)
            openParagraph(ui.config.panel)
            local paragraph = ui.config.panel
            local bars = ui.menu.bars
            local refreshes = refreshesOf(function()
                tapWidget(flushCard(paragraph), 0.25)
                runTasks()
            end)
            local modes = {}
            for _, r in ipairs(refreshes) do
                modes[r.mode] = true
                if r.mode == "ui" then
                    assert.are.same(paragraph:getRefreshRegion(), r.region)
                end
            end
            assert.is_nil(modes.full)
            assert.is_true(modes.partial) -- the re-laid out page, as for a page turn
            assert.is_true(modes.ui) -- the panel
            assert.are.equal(paragraph, ui.config.panel)
            assert.are.equal("paragraph", ui.config.page)
            assert.are.equal(bars, topWidget())
            assert.are.same({ INK, TINT }, fills(paragraph))
            local flush_indent, flush_gap = layout()
            assert.are.equal(0, flush_indent)
            assert.are.equal(own_gap, flush_gap)

            tapAndPaint(indentCard(paragraph))
            assert.are.same({ TINT, INK }, fills(paragraph))
            -- two characters wide, as Chinese text is indented
            local indent = layout()
            assert.is_true(math.abs(indent - 2 * ui.document:getFontSize()) <= 1, indent)
            -- the pill names it, back on the panel
            back()
            assert.are.equal(_("First line indented"), paragraphPill(ui.config.panel).text)
            ui.menu:hideToolbar()
        end)

        it("should switch paragraph spacing from the foot of the indent card, apart from the mode", function()
            local indent, gap = layout()
            openPanel(ui)
            openParagraph(ui.config.panel)
            local paragraph = ui.config.panel
            local before = fills(paragraph)
            -- a tap on its label switches it too
            local refreshes = refreshesOf(function()
                tapWidget(spacingRow(paragraph), 0.1)
                runTasks()
            end)
            local modes = {}
            for _, r in ipairs(refreshes) do
                modes[r.mode] = true
                if r.mode == "ui" then
                    assert.are.same(spacingRow(paragraph).toggle.dimen, r.region) -- only the toggle, on its gray card
                end
            end
            assert.is_nil(modes.full)
            assert.is_true(modes.ui) -- the toggle
            assert.is_true(modes.partial) -- the re-laid out page
            assert.is_true(toggleShowsOn(spacingRow(paragraph)))
            assert.are.same(before, fills(paragraph))
            local spaced_indent, spaced_gap = layout()
            assert.are.equal(indent, spaced_indent)
            assert.is_true(spaced_gap > gap)

            -- it stays on with the other mode
            tapAndPaint(flushCard(paragraph), 0.25)
            assert.are.same({ INK, TINT }, fills(paragraph))
            assert.are.equal(0, (layout())) -- from the indent of the last test
            assert.is_true(toggleShowsOn(spacingRow(paragraph)))
            assert.are.equal(spaced_gap, select(2, layout()))
            tapAndPaint(spacingRow(paragraph).toggle)
            assert.is_false(toggleShowsOn(spacingRow(paragraph)))
            assert.are.equal(gap, select(2, layout()))
            ui.menu:hideToolbar()
        end)

        it("should keep the paragraph settings after reopening the book, for this book only", function()
            openPanel(ui)
            openParagraph(ui.config.panel)
            tapAndPaint(indentCard(ui.config.panel))
            tapAndPaint(spacingRow(ui.config.panel), 0.1)
            ui.menu:hideToolbar()
            local indent, gap = layout()
            closeReader(ui)
            ui = openReader(sample_epub, nil, true)
            assert.are.same({ indent, gap }, { layout() })
            local main = openPanel(ui)
            assert.are.equal(_("First line indented"), paragraphPill(main).text)
            openParagraph(main)
            assert.are.same({ TINT, INK }, fills(ui.config.panel))
            assert.is_true(toggleShowsOn(spacingRow(ui.config.panel)))
            ui.menu:hideToolbar()
            for id in pairs(G_reader_settings:readSetting("style_tweaks") or {}) do
                assert.is_nil(id:match("^paragraph"), id)
            end
        end)

        it("should follow a global paragraph default, and override it for this book only", function()
            closeReader(ui)
            local global = G_reader_settings:readSetting("style_tweaks")
            G_reader_settings:saveSetting("style_tweaks", { paragraph_indent = true, paragraph_whitespace = true })
            ui = openReader(sample_epub)
            local main = openPanel(ui)
            assert.are.equal(_("First line indented"), paragraphPill(main).text)
            openParagraph(main)
            assert.are.same({ TINT, INK }, fills(ui.config.panel))
            assert.is_true(toggleShowsOn(spacingRow(ui.config.panel)))
            tapAndPaint(flushCard(ui.config.panel), 0.25)
            tapAndPaint(spacingRow(ui.config.panel), 0.1)
            assert.are.same({ INK, TINT }, fills(ui.config.panel))
            assert.is_false(toggleShowsOn(spacingRow(ui.config.panel)))
            ui:saveSettings()
            assert.are.same({ paragraph_indent = true, paragraph_whitespace = true }, G_reader_settings:readSetting("style_tweaks"))
            assert.are.same({ paragraph_indent = false, paragraph_no_indent = true, paragraph_whitespace = false },
                ui.doc_settings:readSetting("style_tweaks"))
            ui.menu:hideToolbar()
            closeReader(ui)
            G_reader_settings:saveSetting("style_tweaks", global)
            ui = openReader(sample_epub)
        end)

        it("should not claim a mode for a mix of paragraph styles, and leave other style tweaks alone", function()
            closeReader(ui)
            ui = openReader(sample_epub, { style_tweaks = {
                -- only the first paragraph of a block indented
                paragraph_indent = true, paragraph_following_no_indent = true,
                paragraph_whitespace_half = true, margin_body_0 = true,
            } })
            local main = openPanel(ui)
            assert.are.equal(_("Paragraphs"), paragraphPill(main).text)
            openParagraph(main)
            local paragraph = ui.config.panel
            assert.are.same({ TINT, TINT }, fills(paragraph))
            assert.is_true(toggleShowsOn(spacingRow(paragraph))) -- half a line of spacing is spacing too
            tapAndPaint(indentCard(paragraph))
            assert.are.same({ TINT, INK }, fills(paragraph))
            tapAndPaint(spacingRow(paragraph), 0.1)
            assert.is_false(toggleShowsOn(spacingRow(paragraph)))
            ui:saveSettings()
            -- the 2em indent in place of the mix, the other tweak kept
            assert.are.same({ paragraph_indent_2em = true, margin_body_0 = true }, ui.doc_settings:readSetting("style_tweaks"))
            ui.menu:hideToolbar()
        end)

        it("should say so with a toast and change nothing when style tweaks are off for this book", function()
            closeReader(ui)
            ui = openReader(sample_epub, { style_tweaks_enabled = false, style_tweaks = { paragraph_no_indent = true } })
            local indent, gap = layout()
            local main = openPanel(ui)
            assert.are.equal(_("Paragraphs"), paragraphPill(main).text) -- not applied
            openParagraph(main)
            local paragraph = ui.config.panel
            assert.are.same({ TINT, TINT }, fills(paragraph))
            local shown
            for __, target in ipairs{ indentCard(paragraph), spacingRow(paragraph) } do
                -- the toast of the first tap doesn't take the second one: it only closes
                tapAndPaint(target, 0.1)
                local toast = topWidget()
                assert.are_not.equal(shown, toast)
                assert.is_true(toast.toast)
                assert.are.equal(_("Style tweaks are disabled for this book."), toast.text)
                assert.are.equal("ui", toast.close_refresh_type) -- over the gray card
                assert.are.same({ TINT, TINT }, fills(ui.config.panel))
                assert.is_false(toggleShowsOn(spacingRow(ui.config.panel)))
                shown = toast
            end
            UIManager:close(shown)
            assert.are.same({ indent, gap }, { layout() })
            ui:saveSettings()
            assert.are.same({ paragraph_no_indent = true }, ui.doc_settings:readSetting("style_tweaks"))
            ui.menu:hideToolbar()
        end)

        it("should keep a global no-spacing default in effect after paragraph spacing goes on and off", function()
            closeReader(ui)
            local global = G_reader_settings:readSetting("style_tweaks")
            G_reader_settings:saveSetting("style_tweaks", { paragraph_no_whitespace = true })
            ui = openReader(sample_epub)
            local __, gap = layout()
            openPanel(ui)
            openParagraph(ui.config.panel)
            tapAndPaint(spacingRow(ui.config.panel), 0.1)
            assert.is_true(select(2, layout()) > gap)
            tapAndPaint(spacingRow(ui.config.panel), 0.1)
            assert.is_false(toggleShowsOn(spacingRow(ui.config.panel)))
            assert.are.equal(gap, select(2, layout()))
            ui:saveSettings()
            -- not left turned off for this book, as turning spacing on did
            assert.are.same({ paragraph_no_whitespace = true }, ui.doc_settings:readSetting("style_tweaks"))
            assert.are.same({ paragraph_no_whitespace = true }, G_reader_settings:readSetting("style_tweaks"))
            ui.menu:hideToolbar()
            closeReader(ui)
            G_reader_settings:saveSetting("style_tweaks", global)
            ui = openReader(sample_epub)
        end)

        it("should not claim a mode or spacing that the book's own style tweak may override", function()
            local tweaks = { paragraph_no_indent = true, paragraph_whitespace = true }
            local book_tweak = "p { text-indent: 2em !important; margin-top: 0 !important; }"
            closeReader(ui)
            ui = openReader(sample_epub, { style_tweaks = tweaks, book_style_tweak = book_tweak, book_style_tweak_enabled = true })
            -- the page shows it: the book's style tweak, last in the style sheet, indents
            assert.is_true(layout() > 0)
            local main = openPanel(ui)
            assert.are.equal(_("Paragraphs"), paragraphPill(main).text)
            openParagraph(main)
            assert.are.same({ TINT, TINT }, fills(ui.config.panel))
            assert.is_false(toggleShowsOn(spacingRow(ui.config.panel)))
            ui.menu:hideToolbar()
            -- turned off, it overrides nothing
            closeReader(ui)
            ui = openReader(sample_epub, { style_tweaks = tweaks, book_style_tweak = book_tweak, book_style_tweak_enabled = false })
            assert.are.equal(0, (layout()))
            main = openPanel(ui)
            assert.are.equal(_("First line flush"), paragraphPill(main).text)
            openParagraph(main)
            assert.is_true(toggleShowsOn(spacingRow(ui.config.panel)))
            ui.menu:hideToolbar()
        end)
    end)

    describe("closing the book with the panel or font panel open", function()
        it("should leave no bars, panel or font panel behind", function()
            for __, open_fonts in ipairs{ false, true } do
                local ui = openReader(sample_epub)
                local panel = openPanel(ui)
                local bars = ui.menu.bars
                assert.are.equal(panel, ui.menu.panel)
                if open_fonts then
                    tapWidget(fontCard(panel, _("View more") .. " ›"))
                    UIManager:forceRePaint()
                end
                local page = ui.config.panel
                local ok, err = pcall(function()
                    ui:onClose()
                    UIManager:forceRePaint()
                end)
                assert(ok, err)
                assert.is_nil(ui.menu.bars)
                assert.is_nil(ui.menu.panel)
                assert.is_nil(ui.config.panel)
                for _, window in ipairs(UIManager._window_stack) do
                    assert.are_not.equal(bars, window.widget)
                    assert.are_not.equal(page, window.widget)
                    assert.are_not.equal(ui, window.widget)
                end
            end
        end)
    end)

    describe("design defaults", function()
        it("should be written for a fresh book, but not over a defaults.lua customization", function()
            clearDefaults()
            G_defaults:saveSetting("DCREREADER_CONFIG_DEFAULT_FONT_SIZE", 25)
            local ui = openReader(sample_epub)
            G_defaults:delSetting("DCREREADER_CONFIG_DEFAULT_FONT_SIZE")
            assert.is_nil(G_reader_settings:readSetting("copt_font_size"))
            assert.are.equal(125, G_reader_settings:readSetting("copt_line_spacing"))
            assert.are.equal(44, G_reader_settings:readSetting("copt_t_page_margin"))
            assert.are.equal(125, ui.document.configurable.line_spacing)
            closeReader(ui)
        end)

        it("should not be written, and the original bar used, when the slot is empty", function()
            clearDefaults()
            Replacements.reader_config = nil
            local ui = openReader(sample_epub)
            ui:handleEvent(Event:new("ShowConfigMenu"))
            UIManager:forceRePaint()
            assert.is_truthy(ui.config.config_dialog)
            assert.are.equal(ui.config.config_dialog, topWidget())
            ui.config.config_dialog:closeDialog()
            UIManager:forceRePaint()
            for _, key in ipairs(DEFAULT_KEYS) do
                assert.is_nil(G_reader_settings:readSetting(key))
            end
            assert.is_nil(ui.view.view_modules.chapter_header)
            closeReader(ui)
            Replacements.reader_config = ReaderTypesetPanel
        end)
    end)

    describe("with regional font families", function()
        local ui, cre, available, paths, catalog, filenames, lang, recent, selected, setting_lang, metadata_path, metadata_info
        local coverage_stub, log_stub, font_dir
        local function add(face, real_face)
            paths[face] = { cre.getFontFaceFilenameAndFaceIndex(real_face or "Noto Sans CJK SC") }
            table.insert(available, face)
        end
        local function cards()
            local result, seen = {}, {}
            find(ui.config.panel, function(w)
                if w.name and w.callback and not seen[w] then
                    table.insert(result, w)
                    seen[w] = true
                end
                return false
            end)
            return result
        end
        before_each(function()
            cre = require("document/credocument"):engineInit()
            available, paths = cre.getFontFaces(), {}
            lang = _.current_lang
            setting_lang = G_reader_settings:readSetting("language")
            recent = G_reader_settings:readSetting("cre_fonts_recently_selected")
            selected = G_reader_settings:readSetting("cre_fonts_explicitly_selected")
        end)
        after_each(function()
            if ui then closeReader(ui); ui = nil end
            if catalog then catalog:revert(); catalog = nil end
            if filenames then filenames:revert(); filenames = nil end
            if coverage_stub then coverage_stub:revert(); coverage_stub = nil end
            if log_stub then log_stub:revert(); log_stub = nil end
            if font_dir then require("ffi/util").purgeDir(font_dir); font_dir = nil end
            _.changeLang(lang)
            G_reader_settings:saveSetting("language", setting_lang)
            if metadata_path then
                require("fontlist").fontinfo[metadata_path] = metadata_info
                metadata_path, metadata_info = nil, nil
            end
            G_reader_settings:saveSetting("cre_fonts_recently_selected", recent)
            G_reader_settings:saveSetting("cre_fonts_explicitly_selected", selected)
        end)
        local function openCatalog()
            local get_filename = cre.getFontFaceFilenameAndFaceIndex
            catalog = stub(cre, "getFontFaces", function() return require("util").tableDeepCopy(available) end)
            filenames = stub(cre, "getFontFaceFilenameAndFaceIndex", function(face, ...)
                if paths[face] then return unpack(paths[face]) end
                return get_filename(face, ...)
            end)
            local choices = {}
            for face in pairs(paths) do choices[face] = true end
            G_reader_settings:saveSetting("cre_fonts_recently_selected", available)
            G_reader_settings:saveSetting("cre_fonts_explicitly_selected", choices)
            ui = openReader(sample_epub)
            openPanel(ui)
        end

        it("should choose one regional face per UI language and leave Mono and other regions in More", function()
            local variants = {
                { "zh_CN", "SC", "Noto Sans" }, { "zh_TW", "TC", "Noto Serif" },
                { "ja", "JP", "FreeSans" }, { "ko", "KR", "FreeSerif" }, { "zh_HK", "HK", "Droid Sans Mono" },
            }
            for __, v in ipairs(variants) do
                add("Noto Serif CJK " .. v[2], v[3])
                add("Noto Sans CJK " .. v[2], v[3])
            end
            add("Source Han Serif SC")
            add("Noto Serif Mono CJK SC")
            openCatalog()
            for __, v in ipairs(variants) do
                _.current_lang = v[1]
                ui.config:refreshPanel()
                UIManager:forceRePaint()
                local count, sans_count = 0, 0
                for ___, card in ipairs(cards()) do
                    assert.is_nil(card.name:find("Mono", 1, true))
                    if card.name == _("System font") then
                        assert.are.equal(paths["Noto Sans CJK SC"][1], card.face.realname)
                    end
                    if card.name == _("Source Han Sans") then
                        sans_count = sans_count + 1
                        assert.are.equal(paths["Noto Sans CJK " .. v[2]][1], card.face.realname)
                    end
                    if card.name == _("Source Han Serif") then
                        count = count + 1
                        assert.are.equal(paths["Noto Serif CJK " .. v[2]][1], card.face.realname)
                    end
                end
                assert.are.equal(1, count)
                assert.are.equal(v[2] == "SC" and 0 or 1, sans_count)
            end
            tapWidget(fontCard(ui.config.panel, _("View more") .. " ›"))
            UIManager:forceRePaint()
            local page, present = ui.config.panel, {}
            for __ = 1, page.page_count do
                local function collect(w)
                    if w.font_face then present[w.font_face] = true end
                    return false
                end
                find(page, collect)
                if page.capsule then tapWidget(page.capsule, 0.75) end
                UIManager:forceRePaint()
            end
            for __, face in ipairs{ "Noto Serif CJK SC", "Noto Serif CJK TC", "Noto Serif Mono CJK SC", "Source Han Serif SC" } do
                assert.is_true(present[face])
            end
            back()
        end)

        it("should count real Chinese coverage and keep decorative and regional faces in All", function()
            available = { "Noto Sans CJK SC", "FreeSerif" }
            add("Noto Sans CJK TC")
            add("Dancing Script", "FreeSerif")
            openCatalog()
            assert.is_nil(fontCard(ui.config.panel, "Dancing Script"))
            tapWidget(fontCard(ui.config.panel, _("View more") .. " ›"))
            UIManager:forceRePaint()
            local page = ui.config.panel
            local T = require("ffi/util").template
            assert.are.same({ T(_("%1 (%2)"), _.pgettext("Font category", "All"), 4), T(_("%1 (%2)"), _("Chinese"), 2),
                T(_("%1 (%2)"), _("Western"), 2) }, page.tabs.labels)
            assert.is_truthy(fontCard(page, "Dancing Script"))
            assert.is_truthy(find(page, function(w) return w.font_face == "Noto Sans CJK TC" end))
            local refreshes = refreshesOf(function() tapWidget(page.tabs, 0.5) end)
            assert.are.same({ { mode = "ui", region = page:getRefreshRegion() } }, refreshes)
            assert.is_truthy(fontCard(page, _("System font")))
            assert.is_nil(fontCard(page, "FreeSerif"))
            tapWidget(page.tabs, 0.85)
            UIManager:forceRePaint()
            assert.is_nil(fontCard(page, _("System font")))
            assert.is_truthy(fontCard(page, "FreeSerif"))
            assert.is_truthy(fontCard(page, "Dancing Script"))
            back()
        end)

        it("should cache Chinese coverage without metadata and skip unreadable fonts on repeated visits", function()
            local FT = require("ffi/freetype")
            local FontList = require("fontlist")
            local lfs = require("libs/libkoreader-lfs")
            local ffiUtil = require("ffi/util")
            font_dir = require("datastorage"):getFullDataDir() .. "/font_panel_coverage"
            require("util").makePath(font_dir)
            available = { "Noto Sans CJK SC" }
            add("Uncached Chinese")
            add("Uncached Latin", "FreeSerif")
            add("Unreadable Font", "FreeSerif")
            local attempts, warnings = {}, {}
            for _, item in ipairs{ { "Uncached Chinese", "chinese.ttf" }, { "Uncached Latin", "latin.ttf" } } do
                local path = font_dir .. "/" .. item[2]
                assert(lfs.link(ffiUtil.realpath(paths[item[1]][1]), path, true))
                paths[item[1]][1] = path
                assert.is_nil(FontList.fontinfo[path])
            end
            local broken = font_dir .. "/missing.ttf"
            paths["Unreadable Font"] = { broken, 0 }
            local newFaceSize = FT.newFaceSize
            coverage_stub = stub(FT, "newFaceSize", function(file, size, index)
                if file:sub(1, #font_dir) == font_dir and size == 16 then
                    attempts[file] = (attempts[file] or 0) + 1
                end
                return newFaceSize(file, size, index)
            end)
            log_stub = stub(require("logger"), "warn", function(message, file)
                if file == broken then table.insert(warnings, message) end
            end)
            openCatalog()
            assert.is_nil(fontCard(ui.config.panel, "Unreadable Font"))
            local T = require("ffi/util").template
            for __ = 1, 2 do
                tapWidget(fontCard(ui.config.panel, _("View more") .. " ›"))
                UIManager:forceRePaint()
                local page = ui.config.panel
                assert.are.same({ T(_("%1 (%2)"), _.pgettext("Font category", "All"), 3),
                    T(_("%1 (%2)"), _("Chinese"), 2), T(_("%1 (%2)"), _("Western"), 1) }, page.tabs.labels)
                assert.is_nil(fontCard(page, "Unreadable Font"))
                assert.is_truthy(fontCard(page, "Uncached Chinese"))
                assert.is_truthy(fontCard(page, "Uncached Latin"))
                back()
            end
            assert.are.same({ [paths["Uncached Chinese"][1]] = 1, [paths["Uncached Latin"][1]] = 1,
                [broken] = 1 }, attempts)
            assert.are.same({ "Unable to check Chinese font coverage:" }, warnings)
        end)

        it("should paginate every face once with capsule boundaries and reset the category to its first page", function()
            available = { "Noto Sans CJK SC" }
            for i = 1, 80 do add("Reading Family " .. i, "FreeSerif") end
            openCatalog()
            tapWidget(fontCard(ui.config.panel, _("View more") .. " ›"))
            UIManager:forceRePaint()
            local page, seen = ui.config.panel, {}
            tapWidget(fontCard(page, _("System font")))
            runTasks()
            UIManager:forceRePaint()
            assert.is_true(page.page_count > 1)
            assert.is_false(page.capsule.prev_enabled)
            tapWidget(page.capsule, 0.25)
            UIManager:forceRePaint()
            assert.are.equal(1, page.page)
            for n = 1, page.page_count do
                local visible = {}
                find(page, function(w)
                    if w.font_face then visible[w.font_face] = true end
                    return false
                end)
                for face in pairs(visible) do
                    assert.is_nil(seen[face])
                    seen[face] = true
                end
                if page.capsule then tapWidget(page.capsule, 0.75) end
                UIManager:forceRePaint()
            end
            assert.is_false(page.capsule.next_enabled)
            assert.are.equal(page.page_count, page.page)
            local count = 0
            for __ in pairs(seen) do count = count + 1 end
            assert.are.equal(81, count)
            tapWidget(page.tabs, 0.5)
            UIManager:forceRePaint()
            assert.are.equal(1, page.page)
            assert.is_true(fontCard(page, _("System font")).selected)
            assert.is_nil(page.capsule)
            back()
        end)

        it("should page fonts with swipes in all four directions and hardware keys without moving the book", function()
            available = { "Noto Sans CJK SC" }
            for i = 1, 80 do add("Reading Family " .. i, "FreeSerif") end
            openCatalog()
            local anchor = ui.rolling:getBookLocation()
            tapWidget(fontCard(ui.config.panel, _("View more") .. " ›"))
            UIManager:forceRePaint()
            local fonts = ui.config.panel
            assert.is_true(fonts.capsule.width < require("ui/widget/einkcontrols").PageCapsule.width)
            for __, step in ipairs{ { "west", 2 }, { "north", 3 }, { "east", 2 }, { "south", 1 } } do
                local refreshes = refreshesOf(function()
                    UIManager:sendEvent(Event:new("Gesture", { ges = "swipe", direction = step[1],
                        pos = Geom:new{ x = fonts.dimen.w / 2, y = fonts.dimen.y + fonts.dimen.h / 2 } }))
                end)
                assert.are.equal(step[2], fonts.page)
                assert.are.same({ { mode = "ui", region = fonts:getRefreshRegion() } }, refreshes)
                assert.are.equal(anchor, ui.rolling:getBookLocation())
            end
            UIManager:sendEvent(Event:new("KeyPress", require("device/key"):new("LPgFwd", {})))
            UIManager:forceRePaint()
            assert.are.equal(2, fonts.page)
            UIManager:sendEvent(Event:new("KeyPress", require("device/key"):new("LPgBack", {})))
            UIManager:forceRePaint()
            assert.are.equal(1, fonts.page)
            assert.are.equal(anchor, ui.rolling:getBookLocation())
            back()
        end)

        it("should keep an empty category and blank space inert", function()
            available = { "Noto Sans CJK SC" }
            openCatalog()
            local anchor = ui.rolling:getBookLocation()
            tapWidget(fontCard(ui.config.panel, _("View more") .. " ›"))
            UIManager:forceRePaint()
            local page = ui.config.panel
            tapWidget(page.tabs, 0.85)
            UIManager:forceRePaint()
            assert.are.equal(require("ffi/util").template(_("%1 (%2)"), _("Western"), 0), page.tabs.labels[3])
            assert.is_nil(find(page, function(w) return w.font_face end))
            assert.is_nil(page.capsule)
            tap(page.dimen.w / 2, page.dimen.y + page.dimen.h / 2)
            UIManager:forceRePaint()
            assert.are.equal(page, ui.config.panel)
            back()
            assert.are.equal(anchor, ui.rolling:getBookLocation())
        end)

        it("should retain a user font's localized typographic family without its style suffix", function()
            _.changeLang("zh_CN")
            G_reader_settings:saveSetting("language", "zh_CN")
            add("Reader Family Regular", "FreeSerif")
            metadata_path = paths["Reader Family Regular"][1]
            local FontList = require("fontlist")
            metadata_info = FontList.fontinfo[metadata_path]
            FontList.fontinfo[metadata_path] = require("util").tableDeepCopy(metadata_info)
            local info = FontList.fontinfo[metadata_path][paths["Reader Family Regular"][2] + 1]
            info.names["zh-cn"] = { [1] = "旧字族名", [4] = "完整字体名", [16] = "示例字族 Medium" }
            openCatalog()
            local card = fontCard(ui.config.panel, "示例字族")
            assert.is_truthy(card)
            assert.are.equal(metadata_path, card.face.realname)
        end)

        it("should localize Chinese family names, remove styles and shrink before ellipsis", function()
            _.changeLang("zh_CN")
            local names = {
                { "FZLanTingHei-M-GB18030", "方正兰亭黑" }, { "FZZhunYuan_GB18030", "方正准圆" },
                { "FZKai-Z03", "方正楷体" }, { "FZShuSong-Z01", "方正书宋" },
                { "Noto Serif CJK SC", "思源宋体" }, { "Source Han Sans SC", "思源黑体" },
                { "Readable Family Medium Italic", "Readable Family" },
                { "An Extremely Long Reading Family Regular", "An Extremely Long Reading Family" },
            }
            for __, pair in ipairs(names) do add(pair[1]) end
            table.insert(available, 1, "Source Han Sans SC")
            openCatalog()
            for __, pair in ipairs(names) do
                local card = fontCard(ui.config.panel, pair[2])
                assert.is_truthy(card)
                local text = find(card, function(w) return w.text == pair[2] end)
                assert.are.equal(paths[pair[1]][1], text.face.realname)
                if pair[2] == "Readable Family" then
                    assert.is_true(text.face.orig_size < 14)
                    assert.is_false(text:isTruncated())
                elseif pair[2] == "An Extremely Long Reading Family" then
                    assert.are.equal(12, text.face.orig_size)
                    assert.is_true(text:isTruncated())
                else
                    assert.is_false(text:isTruncated())
                end
            end
            -- The actual bundled CJK face is still rendered as the system-font card on non-Android.
            assert.is_truthy(fontCard(ui.config.panel, _("System font")))
        end)
    end)

    describe("with a book without a language", function()
        local ui, lang
        setup(function()
            lang = _.current_lang
            _.current_lang = "zh_CN"
            G_reader_settings:makeTrue("typeset_serif_missing_shown")
            ui = openReader("spec/front/unit/data/sample.txt")
        end)
        teardown(function()
            closeReader(ui)
            _.current_lang = lang
            G_reader_settings:delSetting("typeset_serif_missing_shown")
        end)

        it("should follow the UI language for the default reading font", function()
            assert.is_truthy(ui.config:isCJK())
            assert.are.equal("Noto Sans CJK SC", ui.font.font_face)
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

        it("should offer a working system font fallback without an uninstalled card", function()
            local panel = openPanel(ui)
            assert.is_nil(fontCard(panel, "Source Han Serif · not installed"))
            local system = fontCard(panel, _("System font"))
            assert.is_truthy(system)
            tapWidget(fontCard(panel, "Noto Sans"))
            UIManager:forceRePaint()
            tapWidget(fontCard(ui.config.panel, _("System font")))
            UIManager:forceRePaint()
            assert.are.equal("Noto Sans CJK SC", ui.font.font_face)
            assert.is_true(fontCard(ui.config.panel, _("System font")).selected)
            assert.are.equal(ui.menu.bars, topWidget())
            ui.menu:hideToolbar(true)
        end)

    end)

    describe("with a PDF", function()
        local ui
        setup(function() ui = openReader(sample_pdf) end)
        teardown(function() closeReader(ui) end)

        it("should open the original bottom bar", function()
            ui:handleEvent(Event:new("ShowConfigMenu"))
            UIManager:forceRePaint()
            assert.is_nil(ui.config.panel)
            assert.is_truthy(ui.config.config_dialog)
            assert.are.equal(ui.config.config_dialog, topWidget())
            ui.config.config_dialog:closeDialog()
            UIManager:forceRePaint()
            assert.is_nil(ui.view.view_modules.chapter_header)
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
