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

    local function find(widget, pred)
        if type(widget) ~= "table" then return end
        if pred(widget) then return widget end
        for __, child in ipairs(widget) do
            local found = find(child, pred)
            if found then return found end
        end
    end

    -- the painted text widget saying `str`
    local function findText(widget, str)
        return find(widget, function(w) return w.text == str and w.face ~= nil end)
    end

    -- The bands of rows of `rect` with ink in the left half of the screen, as { y, h }.
    local function inkLines(rect)
        local lines, inked = {}, false
        for y = rect.y, rect.y + rect.h - 1 do
            local ink = false
            for x = rect.x, math.floor(Screen:getWidth() / 2) do
                if gray(x, y) < 128 then ink = true break end
            end
            if ink and not inked then
                table.insert(lines, { y = y, h = 1 })
            elseif ink then
                lines[#lines].h = lines[#lines].h + 1
            end
            inked = ink
        end
        return lines
    end

    -- whether the toggle of a row spec shows on: its knob, at the right, unlike its middle
    local function toggleShowsOn(spec)
        local r = spec.toggle_rect
        local y = r.y + math.floor(r.h / 2)
        return gray(r.x + r.w - math.floor(r.h / 2), y) ~= gray(r.x + math.floor(r.w / 2), y)
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

    -- the reading preferences, WeChat Read's list (13-reading-preferences/02-settings.png): name, subtitle and kind
    local function expectedPreferences()
        return {
            { _("Tap left side for next page"), _("When on, taps on the left side also turn to the next page"), "toggle" },
            { _("Indent first lines of body text"), _("When on, the body text of books is indented on first lines"), "toggle" },
            { _("Show time while reading"), _("When on, the current system time shows while reading"), "toggle" },
            { _("Interface font size"), _("Default"), "chevron" },
        }
    end

    local expected_groups = {
        { "reading", "Reading", { "Page turns and tap zones", "Full refresh rate", "Status bar",
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

        it("shows exactly six groups with the issues' rows, after the reading preferences", function()
            local page = openSettings(fm)
            local groups = {}
            for __, entry in ipairs(page.home) do
                if entry.group_id == "preferences" then
                    assert.is_nil(next(groups)) -- first
                elseif entry.header then
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
            local spec = row(page, _("Refresh and ghosting"))
            refreshes = refreshesOf(function() tap(spec.rect) end)
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

        it("opens from 我 on the reading preferences: two-line rows above the groups, without a header", function()
            fm:switchTab("me")
            UIManager:forceRePaint()
            local settings_row = find(fm.me_view, function(w)
                return w.callback and w.dimen and find(w, function(c) return c.text == _("Settings") end) ~= nil
            end)
            tap(settings_row.dimen)
            local page = topWidget()
            assert.is_true(isSettings(page))
            assert.are.equal(1, page.page)
            local shown = {}
            for i = 1, 4 do
                local spec = page.shown[i]
                table.insert(shown, { spec.name, spec.subtitle, spec.kind })
                -- the name in bold over the subtitle, both in ink, the toggle or chevron at the right
                assert.are.equal(Screen:scaleBySize(92), spec.rect.h)
                assert.is_true(spec.enabled)
                local name, subtitle = findText(page, spec.name), findText(page, spec.subtitle)
                assert.is_true(name.face.orig_size > subtitle.face.orig_size)
                assert.is_truthy(name.face.realname:find("Bold"))
                assert.are.equal(Palette.ink, subtitle.fgcolor)
                -- two lines of ink in the row, left of its toggle or chevron
                assert.are.equal(2, #inkLines(spec.rect))
            end
            assert.are.same(expectedPreferences(), shown)
            assert.are.equal(page.content_rect.y, page.shown[1].rect.y) -- right under the title
            -- the groups follow, from their headers
            assert.are.same({ "header", C_("Settings group", "Reading") }, { page.shown[5].kind, page.shown[5].name })
            -- the toggles read the settings they switch
            assert.are.equal(G_reader_settings:isTrue("page_turns_left_tap_forward"), toggleShowsOn(page.shown[1]))
            local footer = G_reader_settings:readSetting("footer") or require("apps/reader/modules/readerfooter").default_settings
            assert.are.equal(footer.time == true, toggleShowsOn(page.shown[3]))
        end)

        it("switches 点击左侧翻到下一页 for every book, refreshing only its toggle, and dims it without a left side", function()
            local saved = { G_reader_settings:readSetting("page_turns_left_tap_forward"),
                G_reader_settings:readSetting("page_turns_tap_zones"), G_reader_settings:readSetting("page_turns_disable_tap") }
            local ok, err = pcall(function()
                G_reader_settings:delSetting("page_turns_left_tap_forward")
                local page = openSettings(fm)
                local spec = row(page, _("Tap left side for next page"))
                assert.is_false(toggleShowsOn(spec))
                local refreshes = refreshesOf(function() tap(spec.rect) end)
                assert.is_true(G_reader_settings:isTrue("page_turns_left_tap_forward"))
                spec = row(page, _("Tap left side for next page"))
                assert.is_true(toggleShowsOn(spec))
                assert.are.same({ { mode = "fast", region = spec.toggle_rect } }, refreshes)
                tap(spec.rect)
                assert.is_false(G_reader_settings:isTrue("page_turns_left_tap_forward"))
                page:closeMenu(true)
                -- no left side to change: page turn taps off, or zones stacked top and bottom
                for __, setting in ipairs{ { "page_turns_disable_tap", true }, { "page_turns_tap_zones", "top_bottom" } } do
                    G_reader_settings:delSetting("page_turns_disable_tap")
                    G_reader_settings:delSetting("page_turns_tap_zones")
                    G_reader_settings:saveSetting(setting[1], setting[2])
                    page = openSettings(fm)
                    spec = row(page, _("Tap left side for next page"))
                    assert.is_false(spec.enabled)
                    refreshes = refreshesOf(function() tap(spec.rect) end)
                    assert.are.same({}, refreshes)
                    assert.is_nil(G_reader_settings:readSetting("page_turns_left_tap_forward"))
                    page:closeMenu(true)
                end
            end)
            G_reader_settings:saveSetting("page_turns_left_tap_forward", saved[1])
            G_reader_settings:saveSetting("page_turns_tap_zones", saved[2])
            G_reader_settings:saveSetting("page_turns_disable_tap", saved[3])
            assert(ok, err)
        end)

        it("switches the global first-line indent, keeping the other global style tweaks and the defaults", function()
            local CssTweaks = require("ui/data/css_tweaks")
            local defaults = require("util").tableDeepCopy(CssTweaks.DEFAULT_GLOBAL_STYLE_TWEAKS)
            local saved = G_reader_settings:readSetting("style_tweaks")
            local ok, err = pcall(function()
                -- a new installation: the defaults, no first-line tweak
                G_reader_settings:delSetting("style_tweaks")
                local page = openSettings(fm)
                local name = _("Indent first lines of body text")
                assert.is_false(toggleShowsOn(row(page, name)))
                tap(row(page, name).rect)
                assert.is_true(toggleShowsOn(row(page, name)))
                local expected = require("util").tableDeepCopy(defaults)
                expected.paragraph_indent_2em = true
                assert.are.same(expected, G_reader_settings:readSetting("style_tweaks"))
                assert.are.same(defaults, CssTweaks.DEFAULT_GLOBAL_STYLE_TWEAKS)
                tap(row(page, name).rect)
                assert.is_false(toggleShowsOn(row(page, name)))
                assert.are.same(defaults, G_reader_settings:readSetting("style_tweaks"))
                page:closeMenu(true)
                -- first lines set globally from the original style tweak menu: flush reads off, KOReader's own
                -- indent reads on; turning it on makes the 2em indent the only global first-line tweak
                G_reader_settings:saveSetting("style_tweaks", { paragraph_no_indent = true, paragraph_whitespace = true })
                page = openSettings(fm)
                assert.is_false(toggleShowsOn(row(page, name)))
                tap(row(page, name).rect)
                assert.are.same({ paragraph_indent_2em = true, paragraph_whitespace = true },
                    G_reader_settings:readSetting("style_tweaks"))
                page:closeMenu(true)
                G_reader_settings:saveSetting("style_tweaks", { paragraph_indent = true })
                page = openSettings(fm)
                assert.is_true(toggleShowsOn(row(page, name)))
                tap(row(page, name).rect)
                assert.are.same({}, G_reader_settings:readSetting("style_tweaks"))
                -- a long press says what happens to books with their own setting
                UIManager:sendEvent(Event:new("Gesture", { ges = "hold", pos = row(page, name).rect:center() }))
                UIManager:forceRePaint()
                local info = topWidget()
                assert.are.equal(_("A book whose first lines you set in its paragraph panel keeps that setting."), info.text)
                UIManager:close(info)
            end)
            G_reader_settings:saveSetting("style_tweaks", saved)
            assert(ok, err)
        end)

        it("switches the time of the reader's footer", function()
            local saved = G_reader_settings:readSetting("footer")
            local ok, err = pcall(function()
                require("apps/reader/modules/readertoolbar").applyFooterDefaults()
                local footer = G_reader_settings:readSetting("footer")
                local before = require("util").tableDeepCopy(footer)
                local page = openSettings(fm)
                local name = _("Show time while reading")
                assert.is_true(toggleShowsOn(row(page, name)))
                tap(row(page, name).rect)
                assert.is_false(toggleShowsOn(row(page, name)))
                assert.is_false(G_reader_settings:readSetting("footer").time)
                -- only the time
                before.time = false
                assert.are.same(before, G_reader_settings:readSetting("footer"))
                tap(row(page, name).rect)
                assert.is_true(G_reader_settings:readSetting("footer").time)
                page:closeMenu(true)

                -- no footer setting yet: only the time is saved, and the default footer still comes at the next start
                G_reader_settings:delSetting("footer")
                require("apps/reader/modules/readertoolbar").applyFooterDefaults()
                local default_footer = require("util").tableDeepCopy(G_reader_settings:readSetting("footer"))
                G_reader_settings:delSetting("footer")
                page = openSettings(fm)
                assert.is_true(toggleShowsOn(row(page, name)))
                tap(row(page, name).rect)
                assert.is_false(toggleShowsOn(row(page, name)))
                assert.are.same({ time = false }, G_reader_settings:readSetting("footer"))
                require("apps/reader/modules/readertoolbar").applyFooterDefaults()
                default_footer.time = false
                assert.are.same(default_footer, G_reader_settings:readSetting("footer"))
            end)
            G_reader_settings:saveSetting("footer", saved)
            assert(ok, err)
        end)

        it("has the reading preferences' names and subtitles in Chinese", function()
            local preferences = require("ui/elements/eink_settings_order")[1]
            assert.are.equal("preferences", preferences.id)
            local msgids, untranslated = {}, {}
            for __, r in ipairs(preferences.rows) do
                table.insert(msgids, r.text)
                if r.subtitle then table.insert(msgids, r.subtitle) end
            end
            assert.are.equal(7, #msgids) -- four names, three subtitles
            local ok, err = pcall(function()
                _.changeLang("zh_CN")
                for __, msgid in ipairs(msgids) do
                    if _(msgid) == msgid then table.insert(untranslated, msgid) end
                end
            end)
            _.changeLang("C")
            assert(ok, err)
            assert.are.same({}, untranslated)
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

    describe("in the reader, the reading preferences", function()
        -- Two paragraphs of a speech in the sample, the first one with a line break (as in readertypesetpanel_spec).
        local SPEECH = "/body[1]/DocFragment[5]/body[1]/div[1]/div[1]/div[1]/blockquote[26]"
        local FIRST, SECOND = SPEECH .. "/p[1]/text()[1].0", SPEECH .. "/p[2]/em[1]/text()[1].0"
        local BROKEN_LINE = SPEECH .. "/p[1]/text()[2].1"
        local KEYS = { "footer", "reader_footer_mode", "style_tweaks", "page_turns_left_tap_forward" }
        local ui, saved

        setup(function()
            saved = {}
            for __, key in ipairs(KEYS) do saved[key] = G_reader_settings:readSetting(key) end
            G_reader_settings:delSetting("footer")
            ReaderToolbar.applyFooterDefaults() -- the reader's footer, as the app starts
            G_reader_settings:delSetting("style_tweaks")
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
            for __, key in ipairs(KEYS) do G_reader_settings:saveSetting(key, saved[key]) end
            DocSettings:open(sample_epub):purge()
        end)
        -- the toast shown, if any
        local function toast()
            for i = #UIManager._window_stack, 1, -1 do
                local w = UIManager._window_stack[i].widget
                if w.toast then return w end
            end
        end

        after_each(function()
            while isSettings(topWidget()) do topWidget():closeMenu(true) end
            while toast() do UIManager:close(toast()) end
            UIManager:forceRePaint()
        end)

        -- Runs the tasks scheduled by the reader (the re-render after a style change).
        local function runTasks()
            for __ = 1, 3 do UIManager:_checkTasks() end
        end

        local function tapAt(x, y)
            tap(Geom:new{ x = math.floor(x), y = math.floor(y), w = 0, h = 0 })
        end

        -- The first-line indent of the speech's second paragraph, from where the first one's line after its line
        -- break starts.
        local function indent()
            runTasks()
            UIManager:forceRePaint() -- crengine re-lays out the part of the book it draws (partial rerendering)
            ui:handleEvent(Event:new("GotoXPointer", FIRST))
            UIManager:forceRePaint()
            local x1 = select(2, ui.document:getScreenPositionFromXPointer(BROKEN_LINE))
            local x2 = select(2, ui.document:getScreenPositionFromXPointer(SECOND))
            return x2 - x1
        end

        -- the sum of the painted gray levels in `rect`
        local function grayTotal(rect)
            local sum = 0
            for y = rect.y, rect.y + rect.h - 1, 2 do
                for x = rect.x, rect.x + rect.w - 1, 2 do sum = sum + gray(x, y) end
            end
            return sum
        end

        it("turns to the next page from a tap on the left once 点击左侧翻到下一页 is on, the right still going forward", function()
            -- from the toolbar's 更多 → 设置, as a reader gets there
            tap(findListRow(openMorePanel(ui), _("Settings")).dimen)
            local page = topWidget()
            assert.is_true(isSettings(page))
            local name = _("Tap left side for next page")
            assert.is_false(toggleShowsOn(row(page, name)))
            tap(row(page, name).rect)
            assert.is_true(toggleShowsOn(row(page, name)))
            tap(page.bar.back.dimen)
            assert.are.equal(ui, topWidget())
            local w, h = Screen:getWidth(), Screen:getHeight()
            local p = ui:getCurrentPage()
            tapAt(w * 0.1, h / 2)
            assert.are.equal(p + 1, ui:getCurrentPage())
            tapAt(w * 0.9, h / 2)
            assert.are.equal(p + 2, ui:getCurrentPage())
            -- the middle still shows the toolbar
            tapAt(w / 2, h / 2)
            assert.is_truthy(ui.menu.bars)
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
            -- 更多 → 点击区域 shows the next page on both sides
            tap(findListRow(openMorePanel(ui), _("Tap zones")).dimen)
            local zones = topWidget()
            local next_pages, previous_pages = 0, 0
            for __, z in ipairs(zones.zones) do
                if findText(z.widget, C_("Tap zones", "Next page")) then next_pages = next_pages + 1 end
                if findText(z.widget, C_("Tap zones", "Previous page")) then previous_pages = previous_pages + 1 end
            end
            assert.are.same({ 2, 0 }, { next_pages, previous_pages })
            zones:onTapClose()
            UIManager:forceRePaint()
            -- off again, the left goes back, as before
            page = openSettings(ui)
            tap(row(page, name).rect)
            assert.is_false(G_reader_settings:isTrue("page_turns_left_tap_forward"))
            tap(page.bar.back.dimen)
            tapAt(w * 0.1, h / 2)
            assert.are.equal(p + 1, ui:getCurrentPage())
        end)

        it("indents first lines of the open book at once; a book with its own first lines keeps them and says so", function()
            local styletweak = ui.styletweak
            local own = indent()
            assert.is_true(own < ui.document:getFontSize()) -- the sample's own styles hardly indent
            local page = openSettings(ui)
            local name = _("Indent first lines of body text")
            -- only the toggle: the book, hidden under the page, is laid out again when the page closes
            local refreshes = refreshesOf(function()
                tap(row(page, name).rect)
                runTasks()
            end)
            assert.is_true(toggleShowsOn(row(page, name)))
            assert.are.same({ { mode = "fast", region = row(page, name).toggle_rect } }, refreshes)
            assert.is_nil(toast())
            refreshes = refreshesOf(function()
                tap(page.bar.back.dimen)
                runTasks()
            end)
            local modes = {}
            for __, r in ipairs(refreshes) do modes[r.mode] = true end
            assert.are.same({ ui = true, partial = true }, modes) -- the page closing, the book laid out again
            local two_chars = 2 * ui.document:getFontSize()
            assert.is_true(math.abs(indent() - two_chars) <= 1)
            -- one global default, the one the book saves when it closes
            assert.is_true(G_reader_settings:readSetting("style_tweaks").paragraph_indent_2em)
            assert.are.equal(G_reader_settings:readSetting("style_tweaks"), styletweak.global_tweaks)
            assert.is_nil(styletweak.doc_tweaks.paragraph_indent_2em)

            -- this book's own first lines, flush (as its paragraph panel's 首行顶格 sets them)
            ui:handleEvent(Event:new("ToggleStyleTweak", "paragraph_no_indent", styletweak.tweaks_by_id.paragraph_no_indent, true))
            assert.are.equal(0, indent())
            -- off: nothing to say, the book looks as the default would leave it
            page = openSettings(ui)
            tap(row(page, name).rect)
            assert.is_false(toggleShowsOn(row(page, name)))
            assert.is_nil(toast())
            -- on: the book keeps its own, and says so at once
            tap(row(page, name).rect)
            assert.is_true(toggleShowsOn(row(page, name)))
            local shown = toast()
            assert.is_truthy(shown)
            assert.are.equal(_("This book keeps its own first-line setting."), shown.text)
            UIManager:close(shown)
            tap(page.bar.back.dimen)
            assert.are.equal(0, indent())
            assert.is_true(styletweak.doc_tweaks.paragraph_no_indent)
            assert.is_true(G_reader_settings:readSetting("style_tweaks").paragraph_indent_2em)

            -- off again: the default goes, the book's own first lines stay
            page = openSettings(ui)
            tap(row(page, name).rect)
            assert.is_nil(toast())
            tap(page.bar.back.dimen)
            assert.are.equal(0, indent())
            assert.is_nil(G_reader_settings:readSetting("style_tweaks").paragraph_indent_2em)
            assert.is_true(styletweak.doc_tweaks.paragraph_no_indent)
        end)

        it("shows or hides the footer's time at once, without painting the footer over the settings", function()
            local footer = ui.view.footer
            local function showsTime()
                return footer.footer_text.text:find(footer.textGeneratorMap.time(footer), 1, true) ~= nil
            end
            assert.is_true(ui.view.footer_visible)
            assert.is_true(showsTime())
            local page = openSettings(ui)
            local name = _("Show time while reading")
            assert.is_true(toggleShowsOn(row(page, name)))
            local band = grayTotal(page.bar.dimen)
            local refreshes = refreshesOf(function() tap(row(page, name).rect) end)
            assert.are.same({ { mode = "fast", region = row(page, name).toggle_rect } }, refreshes)
            assert.are.equal(band, grayTotal(page.bar.dimen))
            assert.is_false(showsTime())
            -- the footer's own setting, which its status bar menu shows
            assert.is_false(footer.settings.time)
            assert.is_false(G_reader_settings:readSetting("footer").time)
            refreshes = refreshesOf(function() tap(page.bar.back.dimen) end)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            assert.is_false(showsTime())
            page = openSettings(ui)
            tap(row(page, name).rect)
            assert.is_true(showsTime())
            tap(page.bar.back.dimen)
            assert.is_true(G_reader_settings:readSetting("footer").time)
        end)
    end)

    describe("in the reader, with a footer showing one item at a time", function()
        local ui, saved

        setup(function()
            saved = { footer = G_reader_settings:readSetting("footer"), mode = G_reader_settings:readSetting("reader_footer_mode") }
            G_reader_settings:delSetting("footer")
            ReaderToolbar.applyFooterDefaults()
            -- the user's own footer: one item at a time (time, then the page), now on the time
            local footer = G_reader_settings:readSetting("footer")
            footer.all_at_once, footer.dynamic_filler = false, false
            G_reader_settings:saveSetting("reader_footer_mode", 1) -- the order's first item, the time
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
            G_reader_settings:saveSetting("footer", saved.footer)
            G_reader_settings:saveSetting("reader_footer_mode", saved.mode)
            DocSettings:open(sample_epub):purge()
        end)

        it("moves the footer on to its next item when the time it shows is turned off, and keeps that item after", function()
            local footer = ui.view.footer
            local time_text = footer.textGeneratorMap.time(footer)
            assert.are.equal(footer.mode_list.time, footer.mode)
            assert.are.equal(time_text, footer.footer_text.text)
            local page = openSettings(ui)
            local name = _("Show time while reading")
            local band = 0
            for x = page.bar.dimen.x, page.bar.dimen.x + page.bar.dimen.w - 1, 3 do
                band = band + gray(x, page.bar.dimen.y + math.floor(page.bar.dimen.h / 2))
            end
            local refreshes = refreshesOf(function() tap(row(page, name).rect) end)
            assert.are.same({ { mode = "fast", region = row(page, name).toggle_rect } }, refreshes)
            -- the next item shows, saved as the footer's mode, without painting over the page
            assert.are.equal(footer.mode_list.page_progress, footer.mode)
            assert.are.equal(footer.mode, G_reader_settings:readSetting("reader_footer_mode"))
            assert.are.equal(footer.textGeneratorMap.page_progress(footer), footer.footer_text.text)
            local after = 0
            for x = page.bar.dimen.x, page.bar.dimen.x + page.bar.dimen.w - 1, 3 do
                after = after + gray(x, page.bar.dimen.y + math.floor(page.bar.dimen.h / 2))
            end
            assert.are.equal(band, after)
            tap(page.bar.back.dimen)
            assert.are.equal(ui, topWidget())
            assert.is_true(ui.view.footer_visible)
            -- on again: the time is an item again, the footer stays on the page
            page = openSettings(ui)
            tap(row(page, name).rect)
            assert.is_true(footer.settings.time)
            assert.are.equal(footer.mode_list.page_progress, footer.mode)
            assert.are.equal(footer.textGeneratorMap.page_progress(footer), footer.footer_text.text)
            tap(page.bar.back.dimen)
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
