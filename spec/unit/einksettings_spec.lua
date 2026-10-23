describe("Reorganized settings", function()
    local DataStorage, DocSettings, DocumentRegistry, EinkSettings, Event, FileManager, Geom, ReaderToolbar, ReaderUI, Replacements, UIManager
    local Screen, _, C_
    local ffiUtil, lfs
    local home, saved_settings
    local sample_epub = "spec/front/unit/data/juliet.epub"

    setup(function()
        require("commonrequire")
        disable_plugins()
        -- plugins that back settings rows
        for __, name in ipairs{ "autosuspend", "calibre", "cloudstorage", "kosync", "opds" } do
            load_plugin(name .. ".koplugin")
        end
        require("document/canvascontext"):init(require("device"))
        DataStorage = require("datastorage")
        DocSettings = require("docsettings")
        DocumentRegistry = require("document/documentregistry")
        EinkSettings = require("apps/settings/einksettings")
        Event = require("ui/event")
        FileManager = require("apps/filemanager/filemanager")
        Geom = require("ui/geometry")
        ReaderToolbar = require("apps/reader/modules/readertoolbar")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        _ = require("gettext")
        C_ = _.pgettext
        require("apps/shelf/shelffilemanager") -- registers the replacement
        Replacements.reader_menu = ReaderToolbar

        saved_settings = {}
        for __, key in ipairs{ "home_dir", "lastdir", "low_pan_rate", "full_refresh_count", "night_full_refresh_count" } do
            saved_settings[key] = G_reader_settings:readSetting(key)
        end
        home = ffiUtil.realpath(DataStorage:getDataDir()) .. "/einksettings_home"
        ffiUtil.purgeDir(home)
        lfs.mkdir(home)
        G_reader_settings:saveSetting("home_dir", home)
    end)

    teardown(function()
        if FileManager.instance then FileManager.instance:onClose() end
        for key, value in pairs(saved_settings) do
            G_reader_settings:saveSetting(key, value)
        end
        Replacements.filemanager = nil
        Replacements.reader_menu = nil
        ffiUtil.purgeDir(home)
    end)

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function isSettings(widget)
        return getmetatable(widget).__index == EinkSettings
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

    local function tap(rect)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap",
            pos = Geom:new{ x = rect.x + math.floor(rect.w / 2), y = rect.y + math.floor(rect.h / 2), w = 0, h = 0 } }))
    end

    -- the shown row spec named `name`, turning list pages until found
    local function row(page, name)
        for p = 1, #page.pages do
            if p ~= page.page then
                page:goToPage(p)
                UIManager:forceRePaint()
            end
            for __, spec in ipairs(page.shown) do
                if spec.name == name then return spec end
            end
        end
    end

    local function openFM()
        FileManager:showFiles(home)
        UIManager:forceRePaint()
        return FileManager.instance
    end

    local function openSettings(ui, target)
        ui:handleEvent(Event:new("ShowEinkSettings", target))
        UIManager:forceRePaint()
        local page = topWidget()
        assert.is_true(isSettings(page))
        return page
    end

    -- ids of every menu item reachable from `items`, following sub_item_table and sub_item_table_func
    local function collectIds(items, ids, seen)
        ids, seen = ids or {}, seen or {}
        if seen[items] then return ids end
        seen[items] = true
        for __, item in ipairs(items) do
            if type(item) == "table" then
                if item.id then ids[item.id] = true end
                local sub = item.sub_item_table
                if not sub and item.sub_item_table_func then
                    local ok, res = pcall(item.sub_item_table_func)
                    sub = ok and res or nil
                end
                if type(sub) == "table" then collectIds(sub, ids, seen) end
            end
        end
        return ids
    end

    local function originalIds(menu)
        local ids, seen = {}, {}
        for __, tab in ipairs(menu.tab_item_table) do
            collectIds(tab, ids, seen)
        end
        return ids
    end

    -- Every item of the original menu is in the new settings or in the original menu the last row opens.
    local function assertCoverage(ui, menu)
        local page = openSettings(ui)
        local expected = originalIds(menu)
        local in_settings = collectIds(page.home)
        page:select(row(page, _("All settings (original)")).item)
        assert.is_truthy(menu.menu_container)
        local reached = {}
        for __, tab in ipairs(menu.menu_container[1].tab_item_table) do
            collectIds(tab, reached)
        end
        local missing = {}
        for id in pairs(expected) do
            if not in_settings[id] and not reached[id] then table.insert(missing, id) end
        end
        assert.are.same({}, missing)
        return page, in_settings
    end

    local expected_groups = {
        { "reading", "Reading", { "Page turns and tap zones", "Full refresh rate", "Status bar", "After finishing a book", "Highlight style" } },
        { "screen", "Screen", { "Refresh and ghosting", "Sleep screen", "Night mode" } },
        { "network", "Network & sync", { "Wi-Fi", "Progress sync", "Wireless transfer and library" } },
        { "device", "Device", { "Physical buttons", "Gestures", "Power and sleep" } },
        { "advanced", "Advanced", { "Plugins", "All settings (original)" } },
    }

    describe("in the file manager", function()
        local fm
        before_each(function() fm = openFM() end)
        after_each(function()
            if fm.menu.menu_container then fm.menu:onCloseFileManagerMenu() end
            while isSettings(topWidget()) do topWidget():closeMenu(true) end
            fm:onClose()
        end)

        it("shows exactly five groups with the issue's rows", function()
            local page = openSettings(fm)
            local groups = {}
            for __, entry in ipairs(page.home) do
                if entry.header then
                    table.insert(groups, { entry.group_id, entry.text, {} })
                else
                    table.insert(groups[#groups][3], entry.text)
                end
            end
            local translated = {}
            for i, g in ipairs(expected_groups) do
                local rows = {}
                for __, name in ipairs(g[3]) do
                    local ctx = ({ ["Full refresh rate"] = "Settings", ["Status bar"] = "Settings", ["Sleep screen"] = "Settings", ["Progress sync"] = "Settings",
                        ["Highlight style"] = "Settings" })[name]
                    table.insert(rows, ctx and C_(ctx, name) or _(name))
                end
                translated[i] = { g[1], C_("Settings group", g[2]), rows }
            end
            assert.are.same(translated, groups)
            assert.are.equal(_("Settings"), page.title)
        end)

        it("opens with a ui refresh, and goes into and back from a group row with ui refreshes", function()
            local page
            local refreshes = refreshesOf(function() page = openSettings(fm) end)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            refreshes = refreshesOf(function() tap(row(page, _("Refresh and ghosting")).rect) end)
            assert.are.equal(_("Refresh and ghosting"), page.title)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            refreshes = refreshesOf(function() page:onBack() end)
            assert.are.equal(_("Settings"), page.title)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            refreshes = refreshesOf(function() page:onBack() end)
            assert.is_false(isSettings(topWidget()))
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
        end)

        it("pages its lists with ui refreshes of the list only", function()
            local page = openSettings(fm)
            assert.is_true(#page.pages > 1)
            local refreshes = refreshesOf(function() page:goToPage(2) end)
            assert.are.same({ { mode = "ui", region = page.list_rect } }, refreshes)
        end)

        it("opens on a group or a row", function()
            local page = openSettings(fm, "advanced")
            local found
            for __, spec in ipairs(page.shown) do
                if spec.kind == "header" and spec.name == C_("Settings group", "Advanced") then found = true end
            end
            assert.is_true(found)
            page:closeMenu(true)
            page = openSettings(fm, "refresh")
            assert.are.equal(_("Refresh and ghosting"), page.title)
            page:onBack()
            assert.are.equal(_("Settings"), page.title)
        end)

        it("refreshes only the toggle when switching it", function()
            local page = openSettings(fm, "refresh")
            local spec = row(page, _("Use smaller panning rate"))
            assert.are.equal("toggle", spec.kind)
            local before = Screen.low_pan_rate
            local refreshes = refreshesOf(function() tap(spec.rect) end)
            assert.are_not.equal(before, Screen.low_pan_rate)
            local toggle_rect = row(page, _("Use smaller panning rate")).toggle_rect
            assert.are.same({ { mode = "fast", region = toggle_rect } }, refreshes)
            tap(row(page, _("Use smaller panning rate")).rect)
            assert.are.equal(before, Screen.low_pan_rate)
        end)

        it("shows the full refresh rate as one choice with a check mark", function()
            local page = openSettings(fm)
            local home_row = row(page, C_("Settings", "Full refresh rate"))
            G_reader_settings:saveSetting("full_refresh_count", 6)
            G_reader_settings:saveSetting("night_full_refresh_count", 6)
            UIManager:setRefreshRate(6, 6)
            page:select(home_row.item)
            UIManager:forceRePaint()
            assert.are.equal(C_("Settings", "Full refresh rate"), page.title)
            local never, every_page, six = row(page, _("Never")), row(page, _("Every page")), row(page, _("Every 6 pages"))
            for __, spec in ipairs{ never, every_page, six, row(page, _("Every chapter")) } do
                assert.are.equal("check", spec.kind)
            end
            assert.is_true(six.checked)
            assert.are.equal("toggle", row(page, _("Always flash on chapter boundaries")).kind)
            local refreshes = refreshesOf(function() tap(every_page.rect) end)
            assert.are.equal(1, G_reader_settings:readSetting("full_refresh_count"))
            -- the two rows whose check mark moved (UIManager may also merge them into one region)
            local both = every_page.rect:combine(six.rect)
            assert.is_true(#refreshes >= 2)
            for __, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
                assert.is_true(r.region.y >= both.y and r.region.y + r.region.h <= both.y + both.h)
            end
            page:onBack()
            assert.are.equal(_("Every page"), row(page, C_("Settings", "Full refresh rate")).value)
            UIManager:setRefreshRate(6, 6)
        end)

        it("chooses the default style of new highlights: a line until one is saved", function()
            local saved = G_reader_settings:readSetting("highlight_drawing_style")
            local ok, err = pcall(function()
                G_reader_settings:delSetting("highlight_drawing_style")
                local page = openSettings(fm)
                local home_row = row(page, C_("Settings", "Highlight style"))
                assert.is_true(home_row.enabled) -- no book needed
                assert.are.equal(C_("Highlight style", "Underline"), home_row.value)
                page:select(home_row.item)
                UIManager:forceRePaint()
                assert.are.equal(C_("Settings", "Highlight style"), page.title)
                local names = {}
                for __, spec in ipairs(page.shown) do
                    assert.are.equal("check", spec.kind)
                    table.insert(names, spec.name)
                end
                assert.are.same({ C_("Highlight style", "Underline"), C_("Highlight style", "Marker"), _("Wavy underline") }, names)
                assert.is_true(row(page, C_("Highlight style", "Underline")).checked)
                assert.is_nil(G_reader_settings:readSetting("highlight_drawing_style")) -- shown, not saved
                local refreshes = refreshesOf(function() tap(row(page, C_("Highlight style", "Marker")).rect) end)
                assert.are.equal("lighten", G_reader_settings:readSetting("highlight_drawing_style"))
                assert.is_true(row(page, C_("Highlight style", "Marker")).checked)
                assert.is_false(row(page, C_("Highlight style", "Underline")).checked)
                for __, r in ipairs(refreshes) do
                    assert.are.equal("ui", r.mode)
                    assert.is_true(r.region.h < page.list_rect.h)
                end
                page:onBack()
                assert.are.equal(C_("Highlight style", "Marker"), row(page, C_("Settings", "Highlight style")).value)
                page:closeMenu(true)

                -- a default saved in another style from the original menu shows, checked
                G_reader_settings:saveSetting("highlight_drawing_style", "strikeout")
                page = openSettings(fm, "highlight_style")
                local strikeout = row(page, _("Strikethrough"))
                assert.is_truthy(strikeout)
                assert.is_true(strikeout.checked)
                page:onBack()
                assert.are.equal(_("Strikethrough"), row(page, C_("Settings", "Highlight style")).value)
            end)
            G_reader_settings:saveSetting("highlight_drawing_style", saved)
            assert(ok, err)
        end)

        it("dims rows that need a book", function()
            local page = openSettings(fm)
            for __, name in ipairs{ _("Page turns and tap zones"), C_("Settings", "Status bar"), C_("Settings", "Progress sync") } do
                local spec = row(page, name)
                assert.is_false(spec.enabled)
                assert.are.equal(_("Open a book first"), spec.value)
            end
        end)

        it("opens the original full menu from its last row, and keeps every original item reachable", function()
            local page = assertCoverage(fm, fm.menu)
            assert.are.equal(fm.menu.tab_item_table, fm.menu.menu_container[1].tab_item_table)
            -- the settings stay underneath the original menu
            fm.menu:onCloseFileManagerMenu()
            assert.are.equal(page, topWidget())
        end)
    end)

    describe("in the reader", function()
        local ui
        setup(function()
            DocSettings:open(sample_epub):purge()
            ui = ReaderUI:new{ dimen = Screen:getSize(), document = DocumentRegistry:openDocument(sample_epub) }
            UIManager:show(ui)
            UIManager:forceRePaint()
        end)
        teardown(function()
            while isSettings(topWidget()) do topWidget():closeMenu(true) end
            ui:closeDocument()
            UIManager:close(ui)
            ui:onClose()
        end)
        after_each(function()
            if ui.menu.menu_container then ui.menu:onCloseReaderMenu() end
            while isSettings(topWidget()) do topWidget():closeMenu(true) end
        end)

        it("opens from the toolbar's more panel: refresh and ghosting, and all settings", function()
            ui.menu:openPanel("more")
            local Panels = require("apps/reader/modules/readertoolbarpanels")
            assert.is_truthy(Panels)
            local tile
            local function findTile(w, label)
                if type(w) ~= "table" then return end
                if w.label == label and w.callback then return w end
                for __, c in ipairs(w) do
                    local f = findTile(c, label)
                    if f then return f end
                end
                for __, k in ipairs{ "content", "frame" } do
                    local f = rawget(w, k) and findTile(w[k], label)
                    if f then return f end
                end
            end
            tile = findTile(ui.menu.sheet, _("Refresh and ghosting"))
            tile:onTapSelect()
            local page = topWidget()
            assert.is_true(isSettings(page))
            assert.are.equal(_("Refresh and ghosting"), page.title)
            page:closeMenu(true)
            ui.menu:openPanel("more")
            findTile(ui.menu.sheet, _("All settings")):onTapSelect()
            page = topWidget()
            assert.is_true(isSettings(page))
            assert.are.equal(_("Settings"), page.title)
        end)

        it("backs its rows with the reader's items and previews the tap zones", function()
            local page = openSettings(ui)
            for __, name in ipairs{ _("Page turns and tap zones"), C_("Settings", "Status bar"), C_("Settings", "Progress sync") } do
                assert.is_true(row(page, name).enabled)
            end
            page:select(row(page, _("Page turns and tap zones")).item)
            UIManager:forceRePaint()
            local preview = row(page, _("Preview tap zones"))
            assert.are.equal(page.list_rect.y, preview.rect.y) -- first on the page
            tap(preview.rect)
            assert.is_false(isSettings(topWidget()))
            assert.are.equal(require("apps/reader/modules/readertoolbarpanels").TapZones, getmetatable(topWidget()).__index)
            topWidget():onTapClose()
        end)

        it("gives the open book's next highlight the style chosen", function()
            local saved = G_reader_settings:readSetting("highlight_drawing_style")
            local ok, err = pcall(function()
                G_reader_settings:delSetting("highlight_drawing_style")
                local page = openSettings(ui, "highlight_style")
                tap(row(page, _("Wavy underline")).rect)
                page:closeMenu(true)
                -- what saveHighlight() gives new highlights
                assert.are.equal("wave", ui.view.highlight.saved_drawer)
            end)
            G_reader_settings:saveSetting("highlight_drawing_style", saved)
            assert(ok, err)
        end)

        it("keeps every original item reachable, and names only items of the original menus", function()
            local __, in_settings = assertCoverage(ui, ui.menu)
            assert.is_truthy(in_settings.status_bar)
            -- device-specific items don't exist on the emulator: check the ids against the menus' order instead
            local ordered = {}
            for __, order in ipairs{ require("ui/elements/reader_menu_order"), require("ui/elements/filemanager_menu_order") } do
                for __, ids in pairs(order) do
                    for __, id in ipairs(ids) do ordered[id] = true end
                end
            end
            local unknown = {}
            for __, group in ipairs(require("ui/elements/eink_settings_order")) do
                for __, r in ipairs(group.rows) do
                    for __, id in ipairs(r.items or {}) do
                        if not ordered[id] then table.insert(unknown, id) end
                    end
                end
            end
            assert.are.same({}, unknown)
        end)
    end)
end)
