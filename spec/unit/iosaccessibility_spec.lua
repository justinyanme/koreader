describe("iOS VoiceOver regions (C3)", function()
    -- Seams: A (ReaderUI), B (the shelf through FileManager), C (the iOS device with a fake bridge).
    local A11y, DataStorage, Event, FakeBridge, FileManager, ReaderUI, Replacements, Screen, SDLDevice, UIManager
    local ffiUtil, lfs, T, _
    local saved_home, old_menu, home, bridge, a11y

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function publish()
        a11y:publish()
        return bridge.accessibility_sets[#bridge.accessibility_sets]
    end

    -- Each element's label, or its value when it has none (the page capsule).
    local function names(set)
        local list = {}
        for i, e in ipairs(set.elements) do
            list[i] = e.label ~= "" and e.label or e.value
        end
        return list
    end

    local function indexOf(set, name)
        for i, n in ipairs(names(set)) do
            if n == name then return i end
        end
    end

    -- What a VoiceOver gesture on the element does: queued by the overlay, taken by the next poll.
    local function act(name, action)
        local set = publish()
        local index = assert(indexOf(set, name), name .. " is not published")
        bridge.queueAccessibility(set.generation, index, action or "activate")
        assert.is_true(a11y:dispatch())
        UIManager:_checkTasks()
        UIManager:forceRePaint()
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        A11y = require("device/sdl/iosaccessibility")
        DataStorage = require("datastorage")
        Event = require("ui/event")
        FakeBridge = require("iosbridge")
        FileManager = require("apps/filemanager/filemanager")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        Screen = require("device").screen
        SDLDevice = require("device/sdl/device")
        UIManager = require("ui/uimanager")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        T = ffiUtil.template
        _ = require("gettext")
        require("apps/shelf/shelffilemanager") -- registers the replacement
        old_menu = Replacements.reader_menu
        Replacements.reader_menu = require("apps/reader/modules/readertoolbar")
        saved_home = G_reader_settings:readSetting("home_dir")
        home = ffiUtil.realpath(DataStorage:getDataDir()) .. "/a11y_home"
        ffiUtil.purgeDir(home)
        lfs.mkdir(home)
        ffiUtil.copyFile("spec/front/unit/data/juliet.epub", home .. "/juliet.epub")
        ffiUtil.copyFile("spec/front/unit/data/sample.pdf", home .. "/sample.pdf")
        G_reader_settings:saveSetting("home_dir", home)
    end)

    teardown(function()
        if ReaderUI.instance then ReaderUI.instance:onClose() end
        if FileManager.instance then FileManager.instance:onClose() end
        Replacements.reader_menu = old_menu
        Replacements.filemanager = nil
        G_reader_settings:saveSetting("home_dir", saved_home)
        ffiUtil.purgeDir(home)
    end)

    before_each(function()
        local device = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new() }
        device.screen = Screen -- constructed, not initialized: lend it the test screen
        bridge = device.bridge
        a11y = A11y.new(device, UIManager)
        FileManager:showFiles(home)
        UIManager:forceRePaint()
    end)

    after_each(function()
        if ReaderUI.instance then ReaderUI.instance:onClose() end
        if FileManager.instance then FileManager.instance:onClose() end
        UIManager:forceRePaint()
    end)

    local function openBook(title)
        act(title)
        assert.is_truthy(ReaderUI.instance)
        assert.are.equal(ReaderUI.instance, topWidget())
        return ReaderUI.instance
    end

    local function juliet()
        for __, book in ipairs(FileManager.instance.shelf_view.books) do
            if book.file:match("juliet%.epub$") then return book.title end
        end
    end

    it("publishes the shelf's books in grid order, then the page capsule, as a new screen", function()
        local set = publish()
        local expected = {}
        for i, book in ipairs(FileManager.instance.shelf_view.books) do expected[i] = book.title end
        table.insert(expected, T(_("Page %1 of %2"), 1, 1))
        assert.are.same(expected, names(set))
        assert.is_true(set.screen_changed)
        assert.is_true(set.elements[#set.elements].adjustable)
        assert.is_false(set.elements[1].adjustable)
        assert.are.equal(Screen:getRawSize().w, set.pixel_width)
    end)

    it("publishes again only when something changed", function()
        publish()
        local count = #bridge.accessibility_sets
        a11y:publish()
        assert.are.equal(count, #bridge.accessibility_sets)
    end)

    it("opens a book from the shelf and turns its pages", function()
        local ui = openBook(juliet())
        local set = publish()
        assert.are.same({ ui.doc_props.display_title }, names(set))
        assert.is_true(set.screen_changed)
        assert.is_true(set.elements[1].adjustable)
        local page = ui:getCurrentPage()
        assert.are.equal(T(_("Page %1 of %2"), page, ui.document:getPageCount()), set.elements[1].value)
        act(ui.doc_props.display_title, "increment")
        assert.is_true(ui:getCurrentPage() > page)
        act(ui.doc_props.display_title, "decrement")
        assert.are.equal(page, ui:getCurrentPage())
    end)

    it("shows the toolbar from the page, in reading order, without starting a new screen", function()
        local ui = openBook(juliet())
        act(ui.doc_props.display_title)
        assert.is_truthy(ui.menu.bars)
        local set = publish()
        assert.are.same({ ui.doc_props.display_title, _("Back"), _("Table of contents"), _("Notes"), _("Progress"), _("Font") },
            names(set))
        assert.is_false(set.screen_changed)
    end)

    it("enters the progress and font panels and the notes page from the toolbar", function()
        local ui = openBook(juliet())
        act(ui.doc_props.display_title)
        act(_("Progress"))
        assert.are.equal("progress", ui.menu.panel_name)
        act(_("Font"))
        assert.is_truthy(ui.config.panel or ui.menu.panel)
        ui.menu:hideToolbar()
        UIManager:forceRePaint()
        act(ui.doc_props.display_title)
        act(_("Notes"))
        assert.is_truthy(ui.menu.drawer)
        -- the notes page declares only its back arrow, which leaves it
        local set = publish()
        assert.is_truthy(indexOf(set, _("Back")))
        act(_("Back"))
        assert.is_nil(ui.menu.drawer)
    end)

    it("picks a chapter on the contents page", function()
        local ui = openBook(juliet())
        act(ui.doc_props.display_title)
        act(_("Table of contents"))
        local page = ui.menu.drawer
        assert.is_truthy(page)
        local set = publish()
        assert.is_true(set.screen_changed)
        -- the rows in the page's order, then its bottom bar
        local rows, target = {}, nil
        local function walk(w)
            if type(w) ~= "table" then return end
            if w.toc_index and w.a11y then
                table.insert(rows, w.a11y.label)
                if not w.is_current then target = w.a11y.label end -- the last other chapter
            end
            for __, child in ipairs(w) do walk(child) end
        end
        walk(page)
        assert.is_true(#rows > 2)
        local published = names(set)
        for i, label in ipairs(rows) do
            assert.are.equal(label, published[i])
        end
        assert.are.equal(_("Back"), published[#rows + 1])
        act(target)
        assert.is_nil(ui.menu.drawer) -- the row's jump closes the page
    end)

    it("goes back to the shelf from the toolbar", function()
        local ui = openBook(juliet())
        act(ui.doc_props.display_title)
        act(_("Back"))
        assert.is_nil(ReaderUI.instance)
        assert.are.equal(FileManager.instance, topWidget())
        assert.is_truthy(indexOf(publish(), juliet()))
    end)

    it("drops activations of an older set", function()
        local set = publish()
        bridge.queueAccessibility(set.generation - 1, 1, "activate")
        a11y:dispatch()
        UIManager:_checkTasks()
        assert.is_nil(ReaderUI.instance)
    end)

    it("publishes an empty set over a page that declares nothing", function()
        local Widget = require("ui/widget/widget")
        local blank = Widget:new{ dimen = Screen:getSize(), covers_fullscreen = true }
        UIManager:show(blank)
        UIManager:forceRePaint()
        local set = publish()
        assert.are.same({}, set.elements)
        assert.is_true(set.screen_changed)
        UIManager:close(blank)
    end)

    it("publishes before each input wait and runs the activations it woke for", function()
        local C = require("ffi").C
        local device = SDLDevice:createVariant{ platform = "iOS", native_bridge = FakeBridge.new() }
        local calls, acted = {}, true
        device.input = { modifiers = {}, input = {
            waitForEvent = function() table.insert(calls, "wait") return false, C.EINTR end,
        } }
        device.accessibility = {
            publish = function() table.insert(calls, "publish") end,
            dispatch = function() table.insert(calls, "dispatch") return acted end,
        }
        device:initKeyboard()
        local ok, err = device.input.input.waitForEvent()
        assert.are.same({ "publish", "wait", "dispatch" }, calls)
        assert.is_false(ok)
        assert.are.equal(C.ETIME, err) -- so UIManager runs them before waiting again
        acted = false
        ok, err = device.input.input.waitForEvent()
        assert.are.equal(C.EINTR, err)
    end)

    it("stops after the bridge says it has no overlay", function()
        local device = SDLDevice:createVariant{ platform = "iOS", native_bridge = require("device/sdl/iosbridge").new() }
        device.screen = Screen
        local plain = A11y.new(device, UIManager)
        assert.is_false(plain:publish())
        assert.is_false(plain:dispatch())
    end)
end)
