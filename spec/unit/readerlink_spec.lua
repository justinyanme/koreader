describe("ReaderLink module", function()
    local DocumentRegistry, ReaderUI, sample_epub, sample_pdf, Event, Screen

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        Event = require("ui/event")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        sample_epub = "spec/front/unit/data/leaves.epub"
        sample_pdf = "spec/front/unit/data/paper.pdf"
    end)

    local readerui

    after_each(function()
        readerui:closeDocument()
        readerui:onClose()
        readerui = nil
    end)

    describe("with epub", function()

        before_each(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }
        end)

        it("should jump to links", function()
            readerui.rolling:onGotoPage(5)
            readerui.link:onTap(nil, {pos = {x = 320, y = 190}})
            assert.is.same(37, readerui.rolling.current_page)
        end)

        it("should be able to go back after link jump", function()
            readerui.rolling:onGotoPage(5)
            readerui.link:onTap(nil, {pos = {x = 320, y = 190}})
            assert.is.same(37, readerui.rolling.current_page)
            readerui.link:onGoBackLink()
            assert.is.same(5, readerui.rolling.current_page)
        end)

    end)

    describe("with pdf", function()

        before_each(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
        end)

        it("should jump to links in page mode", function()
            readerui:handleEvent(Event:new("SetScrollMode", false))
            readerui:handleEvent(Event:new("SetZoomMode", "page"))
            readerui.paging:onGotoPage(1)
            readerui.link:onTap(nil, {pos = {x = 363, y = 565}})
            fastforward_ui_events()
            assert.is.same(22, readerui.paging.current_page)
        end)

        it("should jump to links in scroll mode", function()
            readerui:handleEvent(Event:new("SetScrollMode", true))
            readerui:handleEvent(Event:new("SetZoomMode", "page"))
            readerui.paging:onGotoPage(1)
            assert.is.same(1, readerui.paging.current_page)
            readerui.link:onTap(nil, {pos = {x = 228, y = 534}})
            fastforward_ui_events()
            -- its really hard to get the exact page number in scroll mode
            -- page positions may have unexpected impact on page number
            assert.truthy(readerui.paging.current_page == 21
                or readerui.paging.current_page == 20)
        end)

        it("should be able to go back after link jump in page mode", function()
            readerui:handleEvent(Event:new("SetScrollMode", false))
            readerui:handleEvent(Event:new("SetZoomMode", "page"))
            readerui.paging:onGotoPage(1)
            readerui.link:onTap(nil, {pos = {x = 363, y = 565}})
            fastforward_ui_events()
            assert.is.same(22, readerui.paging.current_page)
            readerui.link:onGoBackLink()
            assert.is.same(1, readerui.paging.current_page)
        end)

        it("should be able to go back after link jump in scroll mode", function()
            readerui:handleEvent(Event:new("SetScrollMode", true))
            readerui:handleEvent(Event:new("SetZoomMode", "page"))
            readerui.paging:onGotoPage(1)
            assert.is.same(1, readerui.paging.current_page)
            readerui.link:onTap(nil, {pos = {x = 228, y = 534}})
            fastforward_ui_events()
            assert.truthy(readerui.paging.current_page == 21
                or readerui.paging.current_page == 20)
            readerui.link:onGoBackLink()
            assert.is.same(1, readerui.paging.current_page)
        end)

    end)

    describe("with pdf", function()

        before_each()

        it("should be able to go back to the same position after link jump in scroll mode", function()
            local expected_page_states = {
                {
                    gamma = 1,
                    offset = {x = 17, y = 0},
                    page = 3,
                    page_area = {
                        x = 0, y = 0,
                        h = 800, w = 566,
                    },
                    rotation = 0,
                    saturation = 1,
                    visible_area = {
                        x = 0, y = 694,
                        h = 106, w = 566,
                    },
                    zoom = 0.95032191328269044472,
                },
                {
                    gamma = 1,
                    offset = {x = 17, y = 0},
                    page = 4,
                    page_area = {
                        h = 800, w = 566,
                        x = 0, y = 0,
                    },
                    rotation = 0,
                    saturation = 1,
                    visible_area = {
                        h = 686, w = 566,
                        x = 0, y = 0,
                    },
                    zoom = 0.95032191328269044472,
                },
            }
            -- disable footer
            G_reader_settings:saveSetting("reader_footer_mode", 0)
            require("docsettings"):open(sample_pdf):purge()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            readerui:handleEvent(Event:new("SetZoomMode", "page"))
            assert.is.falsy(readerui.view.footer_visible)
            readerui.paging:onGotoPage(1)
            assert.is.same(1, readerui.paging.current_page)
            readerui.view:onSetScrollMode(true)
            assert.is.same(true, readerui.view.page_scroll)
            assert.is.same(1, readerui.paging.current_page)

            readerui.paging:onGotoViewRel(1)
            assert.is.same(2, readerui.paging.current_page)

            readerui.paging:onGotoViewRel(-1)
            assert.is.same(1, readerui.paging.current_page)

            readerui.paging:onGotoViewRel(1)
            readerui.paging:onGotoViewRel(1)
            assert.is.same(3, readerui.paging.current_page)

            readerui.paging:onGotoViewRel(-1)
            assert.is.same(2, readerui.paging.current_page)

            readerui.paging:onGotoViewRel(1)
            readerui.paging:onGotoViewRel(1)
            assert.is.same(4, readerui.paging.current_page)
            assert.are.same(expected_page_states, readerui.view.page_states)

            readerui.link:onTap(nil, {pos = {x = 164, y = 366}})
            fastforward_ui_events()
            assert.is.same(22, readerui.paging.current_page)
            readerui.link:onGoBackLink()
            assert.is.same(3, readerui.paging.current_page)
            assert.are.same(expected_page_states, readerui.view.page_states)
        end)

    end)

    describe("external links on the injected iOS device", function()
        local Device, UIManager, bridge, _

        before_each(function()
            Device = require("device")
            UIManager = require("ui/uimanager")
            _ = require("gettext")
            bridge = require("iosbridge").new()
            local ios = require("device/sdl/device"):createVariant{ platform = "iOS", native_bridge = bridge }
            stub(Device, "canOpenLink", ios.canOpenLink)
            stub(Device, "openLink", function(_self, link) return ios:openLink(link) end)
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }
        end)

        after_each(function()
            Device.canOpenLink:revert()
            Device.openLink:revert()
        end)

        local function button(url, text)
            for _i, row in ipairs(readerui.link:getButtonsForExternalLinkDialog(url)) do
                for _j, b in ipairs(row) do
                    if b.text == text then return b end
                end
            end
        end

        local function isShown(widget)
            for _i, w in ipairs(UIManager._window_stack) do
                if w.widget == widget then return true end
            end
            return false
        end

        it("opens them with the system, and cancelling leaves the reading position alone", function()
            local url = "https://example.org/page"
            readerui.rolling:onGotoPage(5)
            local stack = #readerui.link.location_stack

            readerui.link:onGotoLink({ xpointer = url })
            local dialog = readerui.link.external_link_dialog
            assert.is_true(isShown(dialog))
            button(url, _("Open in browser")).callback()
            assert.are.same({ url }, bridge.opened)
            assert.is_false(isShown(dialog))
            assert.are.equal(5, readerui.rolling.current_page)

            readerui.link:onGotoLink({ xpointer = url })
            dialog = readerui.link.external_link_dialog
            button(url, _("Cancel")).callback()
            assert.is_false(isShown(dialog))
            assert.are.same({ url }, bridge.opened)
            assert.are.equal(5, readerui.rolling.current_page)
            assert.are.equal(stack, #readerui.link.location_stack)
        end)
    end)
end)
