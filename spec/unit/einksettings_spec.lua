describe("Reorganized settings", function()
    local DataStorage, DocSettings, DocumentRegistry, EinkSettings, Event, FileManager, Geom, Key, Palette, ReaderToolbar, ReaderUI
    local Replacements, UIManager, Screen, _, C_
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
        Key = require("device/key")
        Palette = require("ui/palette")
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

    -- Input is sent the way it arrives, and the screen is repainted after it, as before the next input.
    local function tap(rect)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap",
            pos = Geom:new{ x = rect.x + math.floor(rect.w / 2), y = rect.y + math.floor(rect.h / 2), w = 0, h = 0 } }))
        UIManager:forceRePaint()
    end

    local function swipe(direction)
        UIManager:sendEvent(Event:new("Gesture", { ges = "swipe", direction = direction, distance = 200, time = 0,
            pos = Geom:new{ x = Screen:getWidth() / 2, y = Screen:getHeight() / 2, w = 0, h = 0 } }))
        UIManager:forceRePaint()
    end

    local function press(key_name)
        UIManager:sendEvent(Event:new("KeyPress", Key:new(key_name, {})))
        UIManager:forceRePaint()
    end

    -- the painted gray level at (x, y): 0 is ink, 255 is paper
    local function gray(x, y)
        return Screen.bb:getPixel(x, y):getColor8().a
    end

    -- the page capsule in the bottom bar of the shown list page
    local function capsule(page)
        return page.bar.capsule
    end

    -- Opens the reader toolbar's 更多 panel as a reader does: a tap in the middle, then 更多 in the top bar.
    local function openMorePanel(ui)
        tap(Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
        local function moreButton(w)
            if type(w) ~= "table" then return end
            if w.icon == "eink/more" and w.callback then return w end
            for __, c in ipairs(w) do
                local f = moreButton(c)
                if f then return f end
            end
        end
        tap(moreButton(ui.menu.bars.top).dimen)
        return ui.menu.panel
    end

    -- the row labelled `label` in the 更多 panel's list, faded or not
    local function findListRow(w, label)
        if type(w) ~= "table" then return end
        if w.text == label and w.ges_events then return w end
        for __, c in ipairs(w) do
            local f = findListRow(c, label)
            if f then return f end
        end
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
        { "reading", "Reading", { "Interface font size", "Page turns and tap zones", "Full refresh rate", "Status bar",
            "After finishing a book", "Highlight style" } },
        { "screen", "Screen", { "Refresh and ghosting", "Sleep screen", "Night mode" } },
        { "network", "Network & sync", { "Wi-Fi", "Progress sync", "Wireless transfer and library" } },
        { "device", "Device", { "Physical buttons", "Gestures", "Power and sleep" } },
        { "shelf", "Shelf", { "Sort by" } },
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

        it("shows exactly six groups with the issues' rows", function()
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
                -- 书架 reuses the shelf tab's own name
                translated[i] = { g[1], g[1] == "shelf" and _("Shelf") or C_("Settings group", g[2]), rows }
            end
            assert.are.same(translated, groups)
            assert.are.equal(_("Settings"), page.title)
        end)

        it("is a full-screen page: the title on top, back at the bottom left and the page capsule at the bottom right", function()
            local page = openSettings(fm)
            local screen = Screen:getSize()
            local back, pager = page.bar.back, capsule(page)
            -- the bar is the bottom band, under the list, with a rule on top
            assert.are.equal(screen.h, page.body_rect.y + page.body_rect.h)
            assert.are.equal(page.content_rect.y + page.content_rect.h, page.bar.dimen.y)
            assert.are.equal(screen.h, page.bar.dimen.y + page.bar.dimen.h)
            assert.are.equal(Palette.rule:getColor8().a, gray(math.floor(screen.w / 2), page.bar.dimen.y))
            -- no back in the title band any more: the title sits alone above the list
            assert.are.equal(page.title_rect.y + page.title_rect.h, page.content_rect.y)
            assert.is_true(back.dimen.x < screen.w / 4 and back.dimen.y >= page.bar.dimen.y)
            assert.is_true(pager.dimen.x > screen.w / 2 and pager.dimen.y > page.bar.dimen.y)
            assert.is_true(pager.dimen.x + pager.dimen.w <= screen.w and pager.dimen.y + pager.dimen.h <= screen.h)
            -- both halves of the capsule are at least the 44dp touch target
            for __, half in ipairs{ pager.prev_rect, pager.next_rect } do
                assert.is_true(half.w >= Screen:scaleBySize(44) and half.h >= Screen:scaleBySize(44))
            end
        end)

        it("opens with a ui refresh, and goes into a group row and back out from the bottom-left arrow with ui refreshes", function()
            local page
            local refreshes = refreshesOf(function() page = openSettings(fm) end)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            refreshes = refreshesOf(function() tap(row(page, _("Refresh and ghosting")).rect) end)
            assert.are.equal(_("Refresh and ghosting"), page.title)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            refreshes = refreshesOf(function() tap(page.bar.back.dimen) end)
            assert.are.equal(_("Settings"), page.title)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            refreshes = refreshesOf(function() tap(page.bar.back.dimen) end)
            assert.is_false(isSettings(topWidget()))
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
        end)

        it("turns list pages from the capsule; a half at the boundary is gray and does nothing", function()
            local page = openSettings(fm)
            assert.is_true(#page.pages > 1)
            local pager = capsule(page)
            local top = pager.dimen.y
            local left_x, right_x = pager.dimen.x + math.floor(pager.dimen.w / 4), pager.dimen.x + math.floor(pager.dimen.w * 3 / 4)
            -- first page: up is gray, down is ink
            assert.is_false(pager.prev_enabled)
            assert.is_true(pager.next_enabled)
            assert.are.equal(Palette.rule:getColor8().a, gray(left_x, top))
            assert.are.equal(Palette.ink:getColor8().a, gray(right_x, top))
            assert.are.equal(Palette.ink:getColor8().a, gray(pager.next_rect.x, top + math.floor(pager.dimen.h / 2)))
            local refreshes = refreshesOf(function() tap(pager.prev_rect) end)
            assert.are.equal(1, page.page)
            assert.are.same({}, refreshes)
            -- a page turn repaints the list and the bar, not the title
            refreshes = refreshesOf(function() tap(capsule(page).next_rect) end)
            assert.are.equal(2, page.page)
            assert.are.same({ { mode = "ui", region = page.body_rect } }, refreshes)
            assert.are.equal(page.content_rect.y, page.body_rect.y)
            -- last page: down is gray and does nothing, up goes back
            for __ = 3, #page.pages do
                tap(capsule(page).next_rect)
            end
            assert.are.equal(#page.pages, page.page)
            pager = capsule(page)
            assert.is_true(pager.prev_enabled)
            assert.is_false(pager.next_enabled)
            assert.are.equal(Palette.ink:getColor8().a, gray(left_x, top))
            assert.are.equal(Palette.rule:getColor8().a, gray(right_x, top))
            refreshes = refreshesOf(function() tap(pager.next_rect) end)
            assert.are.equal(#page.pages, page.page)
            assert.are.same({}, refreshes)
            tap(pager.prev_rect)
            assert.are.equal(#page.pages - 1, page.page)
        end)

        it("grays the whole capsule on a list of one page", function()
            local page = openSettings(fm)
            tap(row(page, C_("Settings", "Full refresh rate")).rect)
            assert.are.equal(C_("Settings", "Full refresh rate"), page.title)
            assert.are.equal(1, #page.pages)
            local pager = capsule(page)
            assert.is_false(pager.prev_enabled)
            assert.is_false(pager.next_enabled)
            local divider_x = pager.next_rect.x
            for __, x in ipairs{ pager.dimen.x + math.floor(pager.dimen.w / 4), divider_x, pager.dimen.x + math.floor(pager.dimen.w * 3 / 4) } do
                assert.are.equal(Palette.rule:getColor8().a, gray(x, pager.dimen.y))
            end
            assert.are.equal(Palette.rule:getColor8().a, gray(divider_x, pager.dimen.y + math.floor(pager.dimen.h / 2)))
            local refreshes = refreshesOf(function()
                tap(pager.prev_rect)
                tap(pager.next_rect)
            end)
            assert.are.same({}, refreshes)
            -- the back arrow still works
            tap(page.bar.back.dimen)
            assert.are.equal(_("Settings"), page.title)
        end)

        it("turns list pages with swipes and page keys, and goes back with the Back key", function()
            local page = openSettings(fm)
            local refreshes = refreshesOf(function() swipe("west") end)
            assert.are.equal(2, page.page)
            assert.are.same({ { mode = "ui", region = page.body_rect } }, refreshes)
            swipe("east")
            assert.are.equal(1, page.page)
            -- vertical swipes too: up for the next page, down for the previous one
            swipe("north")
            assert.are.equal(2, page.page)
            swipe("south")
            assert.are.equal(1, page.page)
            press("RPgFwd")
            assert.are.equal(2, page.page)
            press("LPgBack")
            assert.are.equal(1, page.page)
            refreshes = refreshesOf(function() press("LPgBack") end)
            assert.are.equal(1, page.page)
            assert.are.same({}, refreshes)
            tap(row(page, _("Refresh and ghosting")).rect)
            assert.are.equal(_("Refresh and ghosting"), page.title)
            press("Back")
            assert.are.equal(_("Settings"), page.title)
            press("Back")
            assert.is_false(isSettings(topWidget()))
        end)

        it("keeps its rows, title band and back arrow working after a tap that changes nothing, which refreshes nothing", function()
            G_reader_settings:saveSetting("full_refresh_count", 6)
            G_reader_settings:saveSetting("night_full_refresh_count", 6)
            UIManager:setRefreshRate(6, 6)
            local page = openSettings(fm)
            tap(row(page, C_("Settings", "Full refresh rate")).rect)
            local six = row(page, _("Every 6 pages"))
            assert.is_true(six.checked)
            local refreshes = refreshesOf(function() tap(six.rect) end)
            assert.are.same({}, refreshes)
            -- the title band selects nothing, the rows still answer where they are
            refreshes = refreshesOf(function() tap(page.title_rect) end)
            assert.are.same({}, refreshes)
            assert.are.equal(6, G_reader_settings:readSetting("full_refresh_count"))
            tap(row(page, _("Every page")).rect)
            assert.are.equal(1, G_reader_settings:readSetting("full_refresh_count"))
            refreshes = refreshesOf(function() tap(row(page, _("Every page")).rect) end)
            assert.are.same({}, refreshes)
            tap(page.bar.back.dimen)
            assert.are.equal(_("Settings"), page.title)
            assert.are.equal(_("Every page"), row(page, C_("Settings", "Full refresh rate")).value)
            UIManager:setRefreshRate(6, 6)
        end)

        it("lets a long diagonal swipe through to the screenshot", function()
            local page = openSettings(fm)
            local shots = 0
            fm.screenshot.onSwipeDiagonal = function() shots = shots + 1 return true end
            local diagonal = math.sqrt(Screen:getWidth() ^ 2 + Screen:getHeight() ^ 2)
            UIManager:sendEvent(Event:new("Gesture", { ges = "swipe", direction = "northeast", time = require("ui/time").now(),
                distance = diagonal - Screen:scaleBySize(100),
                pos = Geom:new{ x = 10, y = Screen:getHeight() - 10, w = 0, h = 0 } }))
            fm.screenshot.onSwipeDiagonal = nil
            assert.are.equal(1, shots)
            assert.are.equal(page, topWidget())
            assert.are.equal(1, page.page)
        end)

        it("comes back to the list page it left from", function()
            local page = openSettings(fm)
            local spec = row(page, _("Plugins"))
            local on_page = page.page
            assert.is_true(on_page > 1)
            tap(spec.rect)
            assert.are.equal(_("Plugins"), page.title)
            assert.are.equal(1, page.page)
            tap(page.bar.back.dimen)
            assert.are.equal(_("Settings"), page.title)
            assert.are.equal(on_page, page.page)
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
                    assert.is_true(r.region.h < page.body_rect.h) -- the rows whose check mark moved
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

        it("dims rows that need a book, and says which ones this device lacks instead", function()
            local page = openSettings(fm)
            for __, name in ipairs{ _("Page turns and tap zones"), C_("Settings", "Status bar"), C_("Settings", "Progress sync") } do
                local spec = row(page, name)
                assert.is_false(spec.enabled)
                assert.are.equal(_("Open a book first"), spec.value)
            end
            page:closeMenu(true)
            -- an item of the file browser's menu that this device lacks (Android's battery optimizations on the
            -- emulator, as the sleep screen on Android): a book would not bring it
            assert.is_nil(fm.menu.menu_items.ignore_battery_optimizations)
            page = EinkSettings:new{ ui = fm, menu = fm.menu, groups = { { id = "power", text = "Power", rows = {
                { id = "battery", text = "Battery", items = { "ignore_battery_optimizations" } },
            } } } }
            UIManager:show(page)
            UIManager:forceRePaint()
            local spec = row(page, "Battery")
            assert.is_false(spec.enabled)
            assert.are.equal(_("Not available"), spec.value)
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

        it("keeps refresh and ghosting out of the toolbar's 更多 list, whose last entry is the original menu", function()
            local list = openMorePanel(ui)
            assert.is_nil(findListRow(list, _("Refresh and ghosting")))
            assert.is_nil(findListRow(list, _("All settings")))
            tap(findListRow(list, _("All settings (original)")).dimen)
            assert.is_nil(ui.menu.panel)
            assert.is_nil(ui.menu.bars)
            assert.is_truthy(ui.menu.menu_container)
            assert.are.equal(ui.menu.menu_container, topWidget())
            ui.menu:onCloseReaderMenu()
            -- 刷新与残影 is a row of 设置 → 屏幕
            local page = openSettings(ui, "screen")
            assert.is_truthy(row(page, _("Refresh and ghosting")))
        end)

        it("backs its rows with the reader's items and previews the tap zones", function()
            local page = openSettings(ui)
            for __, name in ipairs{ _("Page turns and tap zones"), C_("Settings", "Status bar"), C_("Settings", "Progress sync") } do
                assert.is_true(row(page, name).enabled)
            end
            page:select(row(page, _("Page turns and tap zones")).item)
            UIManager:forceRePaint()
            local preview = row(page, _("Preview tap zones"))
            assert.are.equal(page.content_rect.y, preview.rect.y) -- first on the page
            tap(preview.rect)
            assert.is_false(isSettings(topWidget()))
            assert.are.equal(require("apps/reader/modules/readertoolbarpanels").TapZones, getmetatable(topWidget()).__index)
            topWidget():onTapClose()
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

    describe("in the reader of a PDF", function()
        local sample_pdf = "spec/front/unit/data/sample.pdf"
        local ui
        setup(function()
            DocSettings:open(sample_pdf):purge()
            ui = ReaderUI:new{ dimen = Screen:getSize(), document = DocumentRegistry:openDocument(sample_pdf) }
            UIManager:show(ui)
            UIManager:forceRePaint()
        end)
        teardown(function()
            while isSettings(topWidget()) do topWidget():closeMenu(true) end
            ui:closeDocument()
            UIManager:close(ui)
            ui:onClose()
        end)

        it("opens the same page from the toolbar's 更多, pages it, and goes back to the book", function()
            local page_no = ui:getCurrentPage()
            local list = openMorePanel(ui)
            local page
            local refreshes = refreshesOf(function()
                tap(findListRow(list, _("Settings")).dimen)
                page = topWidget()
            end)
            assert.is_true(isSettings(page))
            assert.is_true(UIManager:isWidgetShown(page))
            assert.are.equal(_("Settings"), page.title)
            assert.is_truthy(refreshes[1])
            assert.are.equal("ui", refreshes[#refreshes].mode)
            assert.are.same(page.dimen, refreshes[#refreshes].region)
            assert.is_true(row(page, _("Page turns and tap zones")).enabled)
            assert.are.equal(1, page.page)
            tap(capsule(page).next_rect)
            assert.are.equal(2, page.page)
            refreshes = refreshesOf(function() tap(page.bar.back.dimen) end)
            assert.is_false(UIManager:isWidgetShown(page))
            assert.are.equal(ui, topWidget())
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            assert.are.equal(page_no, ui:getCurrentPage())
        end)
    end)
end)
