describe("Interface font size", function()
    local DataStorage, DocSettings, DocumentRegistry, EinkSettings, Event, FileManager, Font, Geom, Key, Palette
    local ReaderToolbar, ReaderUI, Replacements, UIFontSize, UIManager, Screen, _, C_
    local ffiUtil, lfs
    local home, saved_settings
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local sample_pdf = "spec/front/unit/data/sample.pdf"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DataStorage = require("datastorage")
        DocSettings = require("docsettings")
        DocumentRegistry = require("document/documentregistry")
        EinkSettings = require("apps/settings/einksettings")
        Event = require("ui/event")
        FileManager = require("apps/filemanager/filemanager")
        Font = require("ui/font")
        Geom = require("ui/geometry")
        Key = require("device/key")
        Palette = require("ui/palette")
        ReaderToolbar = require("apps/reader/modules/readertoolbar")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        UIFontSize = require("apps/settings/uifontsize")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        _ = require("gettext")
        C_ = _.pgettext
        require("apps/shelf/shelffilemanager") -- registers the replacement
        Replacements.reader_menu = ReaderToolbar
        Replacements.reader_config = require("apps/reader/modules/readertypesetpanel")

        saved_settings = {}
        for __, key in ipairs{ "home_dir", "lastdir", "ui_font_scale" } do
            saved_settings[key] = G_reader_settings:readSetting(key)
        end
        home = ffiUtil.realpath(DataStorage:getDataDir()) .. "/uifontsize_home"
        ffiUtil.purgeDir(home)
        lfs.mkdir(home)
        -- one book, without a cover image: the shelf draws a cover with its title
        ffiUtil.copyFile(sample_epub, home .. "/juliet.epub")
        G_reader_settings:saveSetting("home_dir", home)
    end)

    teardown(function()
        if FileManager.instance then FileManager.instance:onClose() end
        Font:setUIScale(1)
        for key in pairs{ home_dir = true, lastdir = true, ui_font_scale = true } do
            if saved_settings[key] == nil then
                G_reader_settings:delSetting(key)
            else
                G_reader_settings:saveSetting(key, saved_settings[key])
            end
        end
        Replacements.filemanager = nil
        Replacements.reader_menu = nil
        Replacements.reader_config = nil
        ffiUtil.purgeDir(home)
    end)

    after_each(function()
        Font:setUIScale(1)
    end)

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function isA(widget, class)
        return getmetatable(widget).__index == class
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
        for __, r in ipairs(refreshes) do set[r.mode] = true end
        return set
    end

    -- Input is sent the way it arrives, and the screen is repainted after it, as before the next input.
    local function tapAt(x, y)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
        UIManager:forceRePaint()
    end

    local function tap(rect)
        tapAt(rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2))
    end

    local function press(key_name)
        UIManager:sendEvent(Event:new("KeyPress", Key:new(key_name, {})))
        UIManager:forceRePaint()
    end

    -- the painted gray level at (x, y): 0 is ink, 255 is paper
    local function gray(x, y)
        return Screen.bb:getPixel(x, y):getColor8().a
    end

    -- the first text widget (TextWidget or TextBoxWidget) showing `text` in a widget tree
    local function findText(widget, text, seen)
        seen = seen or {}
        if type(widget) ~= "table" or seen[widget] then return end
        seen[widget] = true
        if widget.text == text and widget.face then return widget end
        for __, child in ipairs(widget) do
            local found = findText(child, text, seen)
            if found then return found end
        end
    end

    -- every text widget showing `text` in a widget tree
    local function findTexts(widget, text, found, seen)
        found, seen = found or {}, seen or {}
        if type(widget) ~= "table" or seen[widget] then return found end
        seen[widget] = true
        if widget.text == text and widget.face then table.insert(found, widget) end
        for __, child in ipairs(widget) do
            findTexts(child, text, found, seen)
        end
        return found
    end

    -- the shown settings row named `name`, turning list pages until found
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

    -- the first widget in a tree for which pred(widget) holds (a panel keeps its tiles in `content`)
    local function findWidget(widget, pred, seen)
        seen = seen or {}
        if type(widget) ~= "table" or seen[widget] then return end
        seen[widget] = true
        if pred(widget) then return widget end
        for __, child in ipairs(widget) do
            local found = findWidget(child, pred, seen)
            if found then return found end
        end
        for __, key in ipairs{ "content", "frame" } do
            local found = rawget(widget, key) and findWidget(widget[key], pred, seen)
            if found then return found end
        end
    end

    -- the tappable widget (a row, a tab) holding a child for which pred(child) holds
    local function tappable(widget, pred)
        return findWidget(widget, function(w) return w.callback ~= nil and findWidget(w, pred) ~= nil end)
    end

    -- the shelf's bottom band tab drawn with the icon `icon`
    local function tab(fm, icon)
        return tappable(fm.layout_group[2], function(w) return w.icon == "eink/" .. icon or w.icon == "eink/" .. icon .. ".bold" end)
    end

    -- The way a reader gets there: 我 → 设置 on the shelf, 更多 → 全部设置 in the reader.
    local function openSettings(ui)
        if ui.document then
            tap(Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }) -- the toolbars
            tap(findWidget(ui.menu.bars.top, function(w) return w.icon == "eink/more" and w.callback ~= nil end).dimen)
            tap(findWidget(ui.menu.panel, function(w) return w.label == _("All settings") and w.callback ~= nil end).dimen)
        else
            tap(tab(ui, "user").dimen)
            tap(tappable(ui.me_view, function(w) return w.text == _("Settings") end).dimen)
        end
        local page = topWidget()
        assert.is_true(isA(page, EinkSettings))
        return page
    end

    local LeftContainer, RightContainer, CenterContainer, TopContainer, BottomContainer
    setup(function()
        LeftContainer = require("ui/widget/container/leftcontainer")
        RightContainer = require("ui/widget/container/rightcontainer")
        CenterContainer = require("ui/widget/container/centercontainer")
        TopContainer = require("ui/widget/container/topcontainer")
        BottomContainer = require("ui/widget/container/bottomcontainer")
    end)

    -- Nothing in `widget` overflows the box it is laid out in: every aligning container holds its child.
    local function assertFits(widget)
        local boxes = { [LeftContainer] = true, [RightContainer] = true, [CenterContainer] = true,
            [TopContainer] = true, [BottomContainer] = true }
        local overflows = {}
        findWidget(widget, function(w)
            local class = getmetatable(w) and getmetatable(w).__index
            if boxes[class] and w.dimen and w[1] and w[1].getSize then
                local size = w[1]:getSize()
                if size.h > w.dimen.h or size.w > w.dimen.w then
                    local label = findWidget(w[1], function(c) return c.text ~= nil and c.face ~= nil end)
                    table.insert(overflows, string.format("%s: %dx%d in %dx%d",
                        label and label.text or "?", size.w, size.h, w.dimen.w, w.dimen.h))
                end
            end
            return false
        end)
        assert.are.same({}, overflows)
    end

    -- From the settings, taps the row and returns the interface font size page.
    local function openFontSize(settings)
        tap(row(settings, _("Interface font size")).rect)
        local page = topWidget()
        assert.is_true(isA(page, UIFontSize))
        return page
    end

    -- Taps the track of `page` on step `i`.
    local function tapSize(page, i)
        local control = page.control
        tapAt(control.dimen.x + control:stopX(i), control.track_rect.y + math.floor(control.track_rect.h / 2))
    end

    -- the size of a face of `role` (at its own size, or at `size`), as the interface font size makes it at `scale`
    local function roleSize(role, scale, size)
        return (size or Font.sizemap[role]) * scale
    end

    local names = {}
    setup(function()
        names = {
            C_("Interface font size", "Small"), _("Default"), C_("Interface font size", "Large"),
            C_("Interface font size", "Larger"), C_("Interface font size", "Largest"),
        }
    end)

    it("reads as WeChat Read's page in Chinese", function()
        local GetText = require("gettext")
        local dirname = GetText.dirname
        GetText.dirname = "l10n"
        local ok = GetText.changeLang("zh_CN")
        local texts = {
            _("Interface font size"), _("Tap the slider to set the interface font size"),
            _("The size of a book's text is set in the reader, and this setting does not change it."),
            C_("Interface font size", "Small"), _("Default"), C_("Interface font size", "Large"),
            C_("Interface font size", "Larger"), C_("Interface font size", "Largest"),
        }
        GetText.changeLang("C")
        GetText.dirname = dirname
        assert.is_true(ok)
        assert.are.same({ "字体大小", "点击滑块设置界面字体大小", "书籍正文的字体大小需要在阅读器内调节，不受本设置影响",
            "小", "默认", "大", "较大", "特大" }, texts)
    end)

    it("lets KOReader's widgets shrink a role's face to fit without scaling it twice", function()
        Font:setUIScale(1.35)
        local InfoMessage = require("ui/widget/infomessage")
        local face = Font:getFace("ui_label")
        assert.is_near(roleSize("ui_label", 1.35), face.orig_size, 1e-9)
        -- a one-line message too long for one line gets a smaller face, never a larger one
        local msg = InfoMessage:new{ text = string.rep("A long line of text that cannot fit. ", 6), face = face, force_one_line = true }
        assert.is_true(msg.face.size <= face.size)
        msg:free()
        -- getting the face again a step smaller, or bold, keeps to the scaled size
        assert.is_true(Font:getFace(face.orig_font, face.orig_size - 1).size < face.size)
        assert.are.equal(face.size, Font:getAdjustedFace(face, true).size)
    end)

    describe("from the shelf's settings", function()
        local fm
        before_each(function()
            FileManager:showFiles(home)
            UIManager:forceRePaint()
            fm = FileManager.instance
        end)
        after_each(function()
            while isA(topWidget(), UIFontSize) or isA(topWidget(), EinkSettings) do
                local page = topWidget()
                if page.closeMenu then page:closeMenu(true) else UIManager:close(page) end
            end
            fm:onClose()
        end)

        it("is the first row of the Reading group, shows the current size, and opens its page", function()
            local settings = openSettings(fm)
            local first
            for i, entry in ipairs(settings.home) do
                if entry.header and entry.group_id == "reading" then
                    first = settings.home[i + 1]
                    break
                end
            end
            assert.are.equal(_("Interface font size"), first.text)
            local spec = row(settings, _("Interface font size"))
            assert.are.equal("chevron", spec.kind)
            assert.are.equal(_("Default"), spec.value)
            local page
            local refreshes = refreshesOf(function() page = openFontSize(settings) end)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            assert.are.equal(_("Interface font size"), page.title)
            assert.is_truthy(findText(page, _("Tap the slider to set the interface font size")))
            assert.is_truthy(findText(page, _("The size of a book's text is set in the reader, and this setting does not change it.")))
            -- the default size, second of five, both buttons in ink; one page: the capsule is gray
            assert.are.equal(2, page.control.position)
            assert.are.equal(_("Default"), page.control.caption)
            assert.is_true(page.control.can_step[-1] and page.control.can_step[1])
            assert.is_false(page.bar.capsule.prev_enabled or page.bar.capsule.next_enabled)
            -- the track is ink up to the knob and gray after it, near the bottom bar
            local control = page.control
            local cy = control.track_rect.y + math.floor(control.track_rect.h / 2)
            assert.is_true(cy < page.bar.dimen.y and cy > page.bar.dimen.y - Screen:scaleBySize(60))
            local knob_x = control.dimen.x + control:stopX(2)
            assert.are.equal(Palette.ink:getColor8().a, gray(knob_x - Screen:scaleBySize(20), cy - Screen:scaleBySize(12)))
            assert.are.equal(Palette.mark:getColor8().a, gray(knob_x + Screen:scaleBySize(20), cy - Screen:scaleBySize(12)))
            assert.are.equal(Palette.paper:getColor8().a, gray(knob_x, cy))
        end)

        it("steps with − and +, picks the nearest size on the track, and applies each change at once", function()
            local page = openFontSize(openSettings(fm))
            local refreshes = refreshesOf(function() tap(page.control.plus_rect) end)
            assert.are.equal(1.1, Font:getUIScale())
            assert.are.equal(1.1, G_reader_settings:readSetting("ui_font_scale"))
            assert.are.equal(names[3], page.control.caption)
            -- the page itself is rebuilt in the new size, and repainted above its bottom bar with "ui"
            local heading = findText(page, _("Tap the slider to set the interface font size"))
            assert.is_near(roleSize("ui_title", 1.1), heading.face.orig_size, 1e-9)
            assert.are.equal(Screen:scaleBySize(roleSize("ui_title", 1.1)), heading.face.size)
            assert.are.same({ { mode = "ui", region = page.change_rect } }, refreshes)
            assert.are.equal(page.bar.dimen.y, page.change_rect.y + page.change_rect.h)
            -- the last size from the track; + is then gray and does nothing
            tapSize(page, 5)
            assert.are.equal(1.35, Font:getUIScale())
            assert.are.equal(names[5], page.control.caption)
            assert.is_false(page.control.can_step[1])
            refreshes = refreshesOf(function() tap(page.control.plus_rect) end)
            assert.are.same({}, refreshes)
            assert.are.equal(1.35, Font:getUIScale())
            -- a tap near a step picks it; a tap on the current one changes nothing
            local control = page.control
            tapAt(control.dimen.x + control:stopX(4) + Screen:scaleBySize(10), control.track_rect.y + 2)
            assert.are.equal(1.2, Font:getUIScale())
            refreshes = refreshesOf(function() tapSize(page, 4) end)
            assert.are.same({}, refreshes)
            -- − down to the smallest, where it is gray and does nothing
            tap(page.control.minus_rect)
            tap(page.control.minus_rect)
            tap(page.control.minus_rect)
            assert.are.equal(0.9, Font:getUIScale())
            assert.are.equal(names[1], page.control.caption)
            assert.is_false(page.control.can_step[-1])
            refreshes = refreshesOf(function() tap(page.control.minus_rect) end)
            assert.are.same({}, refreshes)
            assert.are.equal(0.9, G_reader_settings:readSetting("ui_font_scale"))
        end)

        it("comes back to settings and the shelf rebuilt in the new size, without a flash", function()
            local settings = openSettings(fm)
            local page = openFontSize(settings)
            local shelf_view = fm.shelf_view
            local refreshes = refreshesOf(function()
                tapSize(page, 5)
                tap(page.bar.back.dimen)
            end)
            assert.are.equal(settings, topWidget())
            -- all "ui": the change, the shelf rebuilt under the settings, and the page closing over the whole screen
            assert.are.same({ ui = true }, modes(refreshes))
            assert.are.same({ mode = "ui", region = page.change_rect }, refreshes[1])
            assert.are.same({ mode = "ui", region = page.dimen }, refreshes[#refreshes])
            -- the row shows the new size, and the settings use it
            assert.are.equal(names[5], row(settings, _("Interface font size")).value)
            local name = findText(settings, _("Interface font size"))
            assert.is_near(roleSize("ui_body", 1.35), name.face.orig_size, 1e-9)
            local title = findText(settings, _("Settings"))
            assert.is_near(roleSize("ui_title", 1.35), title.face.orig_size, 1e-9)
            assertFits(settings)
            -- the shelf under them was rebuilt in it too, on the 我 tab they were opened from
            assert.are_not.equal(shelf_view, fm.shelf_view)
            refreshes = refreshesOf(function() tap(settings.bar.back.dimen) end)
            assert.are.equal(fm, topWidget())
            assert.are.same({ { mode = "ui", region = settings.dimen } }, refreshes)
            local settings_row = findText(fm.me_view, _("Settings"))
            assert.is_near(roleSize("ui_body", 1.35), settings_row.face.orig_size, 1e-9)
            assertFits(fm.me_view)
            -- on 书架, the title, a role at a size of its own, follows; the cover's lettering keeps the cover's
            -- proportions; the grid still fits above the bottom band
            tap(tab(fm, "shelf").dimen)
            local shelf_title = findText(fm, _("Shelf"))
            assert.is_near(roleSize("ui_headword", 1.35, 22), shelf_title.face.orig_size, 1e-9)
            assertFits(fm.shelf_view)
            assert.is_true(fm.shelf_view[1]:getSize().h <= fm.content_dimen.h)
            local book = fm.shelf_view.shown[1]
            -- the cover's title is set on the cover's stock
            local function onCover(w) return type(w.bgcolor) == "cdata" and w.bgcolor == Palette.cover_stock end
            local function bookTexts()
                local cover_title, caption
                for __, w in ipairs(findTexts(fm, book.title)) do
                    if onCover(w) then cover_title = w else caption = w end
                end
                return cover_title, caption
            end
            local cover_title, caption = bookTexts()
            assert.is_near(roleSize("ui_label", 1.35), caption.face.orig_size, 1e-9)
            local cover_size = cover_title.face.orig_size
            -- back to the default size: the captions shrink back, the cover's lettering stays
            settings = openSettings(fm)
            page = openFontSize(settings)
            tapSize(page, 2)
            tap(page.bar.back.dimen)
            tap(settings.bar.back.dimen)
            tap(tab(fm, "shelf").dimen)
            cover_title, caption = bookTexts()
            assert.is_near(roleSize("ui_label", 1), caption.face.orig_size, 1e-9)
            assert.are.equal(cover_size, cover_title.face.orig_size)
        end)

        it("rebuilds the windows under it however it closes", function()
            local settings = openSettings(fm)
            local page = openFontSize(settings)
            local shelf_view = fm.shelf_view
            tapSize(page, 4)
            UIManager:close(page)
            UIManager:forceRePaint()
            assert.are.equal(settings, topWidget())
            assert.are.equal(names[4], row(settings, _("Interface font size")).value)
            assert.is_near(roleSize("ui_body", 1.2), findText(settings, _("Interface font size")).face.orig_size, 1e-9)
            assert.are_not.equal(shelf_view, fm.shelf_view)
        end)

        it("goes back with the Back key, and rebuilds nothing when the size did not change", function()
            local settings = openSettings(fm)
            local page = openFontSize(settings)
            local shelf_view = fm.shelf_view
            -- the page keys have no page to turn
            local refreshes = refreshesOf(function()
                press("RPgFwd")
                press("LPgBack")
            end)
            assert.are.same({}, refreshes)
            press("Back")
            assert.are.equal(settings, topWidget())
            assert.are.equal(shelf_view, fm.shelf_view)
            assert.are.equal(_("Default"), row(settings, _("Interface font size")).value)
            -- a change that is changed back is no change either
            page = openFontSize(settings)
            tap(page.control.plus_rect)
            tap(page.control.minus_rect)
            press("Back")
            assert.are.equal(shelf_view, fm.shelf_view)
            assert.are.equal(1, Font:getUIScale())
        end)

        it("keeps every touch target at the largest size", function()
            local settings = openSettings(fm)
            local page = openFontSize(settings)
            tapSize(page, 5)
            local touch = Screen:scaleBySize(44)
            for __, rect in ipairs{ page.control.minus_rect, page.control.plus_rect, page.control.track_rect,
                    page.bar.capsule.prev_rect, page.bar.capsule.next_rect, page.bar.back.dimen } do
                assert.is_true(rect.w >= touch and rect.h >= touch)
            end
            -- the texts fit the page: the intro ends above the size's name, which is above the track
            local note = findText(page, _("The size of a book's text is set in the reader, and this setting does not change it."))
            assert.is_true(note.dimen.y + note.dimen.h < page.control.dimen.y)
            assertFits(page)
            tap(page.bar.back.dimen)
            -- every settings row keeps its height, and its name fits in it
            for p = 1, #settings.pages do
                settings:goToPage(p)
                UIManager:forceRePaint()
                for __, spec in ipairs(settings.shown) do
                    assert.is_true(spec.is_header or spec.rect.h >= touch)
                    local widget = findText(settings, spec.name)
                    if widget and not spec.is_header then
                        assert.is_true(widget:getSize().h < spec.rect.h)
                    end
                end
            end
        end)

        it("is saved, and used again at the next start", function()
            local settings = openSettings(fm)
            local page = openFontSize(settings)
            tapSize(page, 4)
            tap(page.bar.back.dimen)
            tap(settings.bar.back.dimen)
            assert.are.equal(1.2, G_reader_settings:readSetting("ui_font_scale"))
            -- a fresh start reads it before any face is made; other fonts keep their sizes
            local font_path = package.searchpath("ui/font", package.path)
            local fresh = dofile(font_path)
            assert.are.equal(1.2, fresh:getUIScale())
            assert.is_near(roleSize("ui_body", 1.2), fresh:getFace("ui_body").orig_size, 1e-9)
            for __, name in ipairs{ "cfont", "infofont", "smallinfofont" } do
                assert.are.equal(Screen:scaleBySize(fresh.sizemap[name]), fresh:getFace(name).size)
            end
            -- a value that is not one of the five sizes means the default size, at start and when set
            for __, bad in ipairs{ "large", -1, 0, 3, 1.05, 1.3 } do
                G_reader_settings:saveSetting("ui_font_scale", bad)
                fresh = dofile(font_path)
                assert.are.equal(1, fresh:getUIScale())
                assert.are.equal(Screen:scaleBySize(Font.sizemap.ui_body), fresh:getFace("ui_body").size)
            end
            Font:setUIScale(3)
            assert.are.equal(1, Font:getUIScale())
            assert.are.equal(1, G_reader_settings:readSetting("ui_font_scale"))
            -- so the row reads 默认, and − goes to 小
            settings = openSettings(fm)
            assert.are.equal(_("Default"), row(settings, _("Interface font size")).value)
            page = openFontSize(settings)
            tap(page.control.minus_rect)
            assert.are.equal(0.9, Font:getUIScale())
        end)

        it("lays the 文件 tab out at 较大 and 特大", function()
            for __, step in ipairs{ 4, 5 } do
                local settings = openSettings(fm)
                local page = openFontSize(settings)
                tapSize(page, step)
                tap(page.bar.back.dimen)
                tap(settings.bar.back.dimen)
                tap(tab(fm, "folder").dimen)
                assert.are.equal(fm.files_ui, fm.content[1])
                local title = findText(fm.files_ui, _("Files"))
                assert.is_near(roleSize("ui_headline", Font.ui_scales[step]), title.face.orig_size, 1e-9)
                assertFits(fm.files_ui)
            end
        end)
    end)

    describe("in the reader", function()
        local function openBook(file)
            DocSettings:open(file):purge()
            local ui = ReaderUI:new{ dimen = Screen:getSize(), document = DocumentRegistry:openDocument(file) }
            UIManager:show(ui)
            UIManager:forceRePaint()
            return ui
        end

        local function closeBook(ui)
            while isA(topWidget(), UIFontSize) or isA(topWidget(), EinkSettings) do
                local page = topWidget()
                if page.closeMenu then page:closeMenu(true) else UIManager:close(page) end
            end
            ui:closeDocument()
            UIManager:close(ui)
            ui:onClose()
        end

        -- Sets the largest size from the reader's settings and goes back to the book.
        local function setLargestFromReader(ui)
            local settings = openSettings(ui)
            local page = openFontSize(settings)
            local refreshes = refreshesOf(function()
                tapSize(page, 5)
                tap(page.bar.back.dimen)
                tap(settings.bar.back.dimen)
            end)
            assert.are.equal(ui, topWidget())
            assert.are.same({ ui = true }, modes(refreshes))
            return settings
        end

        it("leaves the book's text, its pages and the DPI alone, and the new UI follows it", function()
            local ui = openBook(sample_epub)
            ui:handleEvent(Event:new("GotoPage", 5))
            UIManager:forceRePaint()
            local font_size = ui.document.configurable.font_size
            local page_no, page_count = ui:getCurrentPage(), ui.document:getPageCount()
            local xpointer = ui.rolling:getBookLocation()
            local dpi, dp100 = Screen:getDPI(), Screen:scaleBySize(100)
            setLargestFromReader(ui)
            assert.are.equal(1.35, Font:getUIScale())
            assert.are.equal(font_size, ui.document.configurable.font_size)
            assert.are.equal(page_no, ui:getCurrentPage())
            assert.are.equal(page_count, ui.document:getPageCount())
            assert.are.equal(xpointer, ui.rolling:getBookLocation())
            assert.are.equal(dpi, Screen:getDPI())
            assert.are.equal(dp100, Screen:scaleBySize(100))
            -- KOReader's own fonts keep their sizes: the footer, built again now, and the original menus and dialogs
            local footer = ui.view.footer
            footer:updateFooterFont()
            assert.are.equal(Screen:scaleBySize(footer.settings.text_font_size), footer.footer_text.face.size)
            for __, name in ipairs{ "smallinfofont", "x_smallinfofont", "ffont", "cfont", "tfont", "infofont" } do
                assert.are.equal(Screen:scaleBySize(Font.sizemap[name]), Font:getFace(name).size)
            end
            -- what the new UI builds next uses the new size, and fits: the settings, the contents page
            local settings = openSettings(ui)
            assert.are.equal(names[5], row(settings, _("Interface font size")).value)
            assert.is_near(roleSize("ui_body", 1.35), findText(settings, _("Interface font size")).face.orig_size, 1e-9)
            assertFits(settings)
            settings:closeMenu(true)
            -- the toolbar's labels, and its panels: more, progress, brightness and the typeset panel
            tap(Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
            assert.are.equal(Screen:scaleBySize(roleSize("ui_caption", 1.35)), findText(ui.menu.bars, _("Progress")).face.size)
            for __, icon in ipairs{ "eink/more", "eink/progress", "eink/light", "eink/font" } do
                local entry = findWidget(ui.menu.bars, function(w) return w.icon == icon and w.callback ~= nil end)
                tap(entry.dimen)
                assert.is_truthy(ui.menu.panel)
                assertFits(ui.menu.panel)
            end
            ui.menu:hideToolbar()
            UIManager:forceRePaint()
            ui:handleEvent(Event:new("ShowToc"))
            UIManager:forceRePaint()
            local contents = topWidget()
            assert.is_true(isA(contents, require("apps/reader/modules/readertocpage")))
            assertFits(contents)
            assert.is_true(contents[1]:getSize().h <= Screen:getHeight())
            contents:goBack()
            UIManager:forceRePaint()
            closeBook(ui)
        end)

        it("leaves a PDF's zoom and page alone", function()
            local ui = openBook(sample_pdf)
            ui:handleEvent(Event:new("GotoPage", 2))
            UIManager:forceRePaint()
            local zoom, page_no = ui.view.state.zoom, ui:getCurrentPage()
            setLargestFromReader(ui)
            assert.are.equal(1.35, Font:getUIScale())
            assert.are.equal(zoom, ui.view.state.zoom)
            assert.are.equal(page_no, ui:getCurrentPage())
            closeBook(ui)
        end)
    end)
end)
