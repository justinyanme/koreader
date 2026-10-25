describe("Reader without fork", function()
    local Device, DocumentRegistry, ReaderUI, UIManager, ffiutil
    local reader, saved_default

    setup(function()
        require("commonrequire")
        disable_plugins()
        Device = require("device")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        ffiutil = require("ffi/util")
    end)

    before_each(function()
        saved_default = G_reader_settings:readSetting("cre_partial_rerendering")
        G_reader_settings:makeTrue("cre_partial_rerendering")
        stub(Device, "canForkProcesses", function() return false end)
        stub(ffiutil, "runInSubProcess", function() error("unexpected fork") end)
        stub(ffiutil, "isSubProcessDone", function() error("unexpected child wait") end)
        reader = ReaderUI:new{
            dimen = Device.screen:getSize(),
            document = DocumentRegistry:openDocument("spec/front/unit/data/juliet.epub"),
        }
    end)

    after_each(function()
        reader:onClose()
        while UIManager._window_stack[1] do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end
        ffiutil.runInSubProcess:revert()
        ffiutil.isSubProcessDone:revert()
        Device.canForkProcesses:revert()
        G_reader_settings:saveSetting("cre_partial_rerendering", saved_default)
    end)

    it("fully renders font and line spacing changes in the foreground", function()
        local rolling, document = reader.rolling, reader.document
        local old_hash = document:getDocumentRenderingHash(true)
        reader.font:onSetFontSize(reader.font.configurable.font_size + 2)
        reader.font:onSetLineSpace(130)
        rolling:onUpdatePos(true)
        assert.is_false(document:isPartialRerenderingEnabled())
        assert.is_false(document:isRerenderingDelayed())
        assert.are_not.equal(old_hash, document:getDocumentRenderingHash(true))
        assert.is_true(document.info.number_of_pages > 0)
        assert.is_nil(rolling.rendering_state)
        assert.is_nil(rolling._stepRerenderingAutomation)
        assert.stub(ffiutil.runInSubProcess).was_not_called()
        assert.stub(ffiutil.isSubProcessDone).was_not_called()
    end)

    it("hides background rendering and page browser entries, preserving the saved preference", function()
        local items = {}
        reader.rolling:addToMainMenu(items)
        reader.thumbnail:addToMainMenu(items)
        assert.is_nil(items.partial_rerendering)
        assert.is_nil(items.page_browser)
        assert.is_truthy(items.book_map)
        reader.doc_settings:makeTrue("partial_rerendering")
        reader.rolling:onSaveSettings()
        assert.is_true(reader.doc_settings:isTrue("partial_rerendering"))
        assert.is_true(G_reader_settings:isTrue("cre_partial_rerendering"))
    end)

    it("does not launch background rendering even when called directly", function()
        reader.rolling:setupRerenderingAutomation()
        reader.rolling:_rerenderInBackground()
        assert.is_nil(reader.rolling._stepRerenderingAutomation)
        assert.stub(ffiutil.runInSubProcess).was_not_called()
    end)

    it("rejects thumbnail requests immediately without queuing work or showing a page browser", function()
        local result
        local delayed = reader.thumbnail:getPageThumbnail(1, 100, 150, "batch", function(tile, batch, async)
            result = { tile = tile, batch = batch, async = async }
        end)
        assert.is_false(delayed)
        assert.are.same({ batch = "batch", async = false }, result)
        assert.is_false(reader.thumbnail:startTileGeneration({ page = 1, width = 100, height = 150 }))
        local stack_size = #UIManager._window_stack
        reader.thumbnail:onShowPageBrowser()
        assert.are.equal(stack_size, #UIManager._window_stack)
        assert.stub(ffiutil.runInSubProcess).was_not_called()
    end)

    it("retains subprocess thumbnails when the device can fork", function()
        Device.canForkProcesses:revert()
        stub(Device, "canForkProcesses", function() return true end)
        ffiutil.runInSubProcess:revert()
        stub(ffiutil, "runInSubProcess", function() return 123, 456 end)
        local request = { page = 1, width = 100, height = 150 }
        assert.is_true(reader.thumbnail:startTileGeneration(request))
        assert.are.equal(123, request.pid)
        assert.are.equal(456, request.parent_read_fd)
        assert.stub(ffiutil.runInSubProcess).was_called(1)
        reader.rolling:_rerenderInBackground()
        assert.stub(ffiutil.runInSubProcess).was_called(2)
        reader.rolling._current_rerendering_pid = nil -- synthetic PID, no child was created
        local items = {}
        reader.rolling:addToMainMenu(items)
        reader.thumbnail:addToMainMenu(items)
        assert.is_truthy(items.partial_rerendering)
        assert.is_truthy(items.page_browser)
        Device.canForkProcesses:revert()
        stub(Device, "canForkProcesses", function() return false end)
    end)

    it("keeps book map tap and keyboard navigation available without opening thumbnails", function()
        local BookMapWidget = require("ui/widget/bookmapwidget")
        local Geom = require("ui/geometry")
        local saved = G_reader_settings:readSetting("book_map_overview_tap_to_page_browser")
        finally(function() G_reader_settings:saveSetting("book_map_overview_tap_to_page_browser", saved) end)
        local focus = { dimen = { y = 10 } }
        local events, locations = {}, 0
        local map = setmetatable({
            cropping_widget = { dimen = Geom:new{ x = 0, y = 0, w = 100, h = 100 } },
            title_bar_h = 0,
            overview_mode = true,
            enable_focus_navigation = true,
            cur_focused_widget = focus,
            getVGroupRowAtY = function()
                return { toc_item_page = 7, start_page = 7, focus_layout = { { focus } } }
            end,
            onClose = function() end,
            ui = {
                link = { addCurrentLocationToStack = function() locations = locations + 1 end },
                handleEvent = function(_, event) events[#events + 1] = event end,
            },
        }, { __index = BookMapWidget })
        map:onTap(nil, { pos = Geom:new{ x = 10, y = 10, w = 0, h = 0 } })
        G_reader_settings:makeFalse("book_map_overview_tap_to_page_browser")
        map:onGoToFocusedPage()
        assert.are.equal(2, locations)
        assert.are.equal(2, #events)
        for _, event in ipairs(events) do
            assert.are.equal("onGotoPage", event.handler)
            assert.are.equal(7, event.args[1])
        end
    end)
end)
