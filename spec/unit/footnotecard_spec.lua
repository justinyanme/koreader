describe("Footnote card through ReaderUI", function()
    local DocumentRegistry, DocSettings, ReaderUI, UIManager, Event, Geom, Screen, Key
    local ui, book

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Screen = require("device").screen
        Key = require("device/key")
        book = require("datastorage"):getDataDir() .. "/footnote-card.epub"
        local epub = require("ffi/archiver").Writer:new{}
        assert(epub:open(book, "epub"))
        epub:setZipCompression("store")
        epub:addFileFromMemory("mimetype", "application/epub+zip", os.time())
        epub:setZipCompression("deflate")
        local files = {
            ["META-INF/container.xml"] = '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
            ["content.opf"] = '<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Footnote card</dc:title><dc:identifier id="id">footnote-card</dc:identifier><dc:language>en</dc:language></metadata><manifest><item id="body" href="body.xhtml" media-type="application/xhtml+xml"/><item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="body"/><itemref idref="notes"/></spine></package>',
            ["body.xhtml"] = '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><p>Short footnote <a epub:type="noteref" href="notes.xhtml#short">[1]</a>.</p><p>Long footnote <a epub:type="noteref" href="notes.xhtml#long">[2]</a>. Empty footnote <a epub:type="noteref" href="notes.xhtml#empty">[3]</a>.</p></body></html>',
            ["notes.xhtml"] = '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><aside epub:type="footnote" id="short"><p>Short note, kept at the bottom of the reading page.</p></aside><aside epub:type="footnote" id="long"><p>' .. string.rep('Long note text for paging. ', 150) .. '</p></aside><aside epub:type="footnote" id="empty"><p> </p></aside></body></html>',
        }
        for name, contents in pairs(files) do epub:addFileFromMemory(name, contents, os.time()) end
        epub:close()
    end)

    local function top()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function gesture(ges, x, y, direction)
        UIManager:sendEvent(Event:new("Gesture", {
            ges = ges, pos = Geom:new{ x = x, y = y, w = 0, h = 0 }, direction = direction,
            time = require("ui/time").now(), distance = Screen:getWidth() / 2,
        }))
        UIManager:forceRePaint()
    end

    local function openFootnote(index)
        local link = ui.document:getPageLinks()[index]
        assert.is_not_nil(link)
        local rect = link.segments[1]
        gesture("tap", math.floor((rect.x0 + rect.x1) / 2), math.floor((rect.y0 + rect.y1) / 2))
        assert.are_not.equal(ui, top())
        return top()
    end

    before_each(function()
        G_reader_settings:saveSetting("footnote_link_in_popup", true)
        DocSettings:open(book):purge()
        ui = ReaderUI:new{ dimen = Screen:getSize(), document = DocumentRegistry:openDocument(book) }
        UIManager:show(ui)
        UIManager:forceRePaint()
    end)

    after_each(function()
        while top() ~= ui do UIManager:close(top()) end
        ui:closeDocument()
        ui:onClose()
        UIManager:forceRePaint()
        DocSettings:open(book):purge()
        G_reader_settings:delSetting("footnote_link_in_popup")
    end)

    teardown(function() os.remove(book) end)

    it("shows a short note in an outlined rounded white card and dismisses without moving", function()
        local page = ui.document:getCurrentPage()
        local popup = openFootnote(1)
        local frame = popup.container
        assert.are.equal(1, frame.bordersize)
        assert.are.equal(Screen:scaleBySize(14), frame.radius)
        assert.are.equal(Screen:getWidth(), frame.dimen.w)
        assert.are.equal(Screen:getHeight(), frame.dimen.y + frame.dimen.h)
        assert.is_true(frame.dimen.h < Screen:getHeight() / 3)
        assert.are.equal(frame.dimen.h, popup.height)
        assert.are.equal(255, Screen.bb:getPixel(math.floor(Screen:getWidth() / 2), frame.dimen.y + 2):getColor8().a)
        assert.are.equal(0, Screen.bb:getPixel(math.floor(Screen:getWidth() / 2), Screen:getHeight() - 1):getColor8().a)
        gesture("tap", Screen:getWidth() / 2, frame.dimen.y - 20)
        assert.are.equal(ui, top())
        assert.are.equal(page, ui.document:getCurrentPage())
    end)

    it("pages a long note with gestures and keys, then returns without moving the reader", function()
        local page = ui.document:getCurrentPage()
        local popup = openFootnote(2)
        local box = popup.htmlwidget.htmlbox_widget
        assert.is_true(box.page_count > 1)
        assert.are.equal(math.floor(Screen:getHeight() / 3), popup.container.dimen.h)
        gesture("swipe", Screen:getWidth() / 2, Screen:getHeight() - 40, "north")
        assert.are.equal(2, box.page_number)
        gesture("swipe", Screen:getWidth() / 2, Screen:getHeight() - 40, "south")
        assert.are.equal(1, box.page_number)
        UIManager:sendEvent(Event:new("KeyPress", Key:new("RPgFwd", {})))
        UIManager:forceRePaint()
        assert.are.equal(2, box.page_number)
        UIManager:sendEvent(Event:new("KeyPress", Key:new("Back", {})))
        UIManager:forceRePaint()
        assert.are.equal(ui, top())
        assert.are.equal(page, ui.document:getCurrentPage())
    end)

    it("follows the note in the book on a left swipe and returns to the source", function()
        local page = ui.document:getCurrentPage()
        openFootnote(1)
        gesture("swipe", Screen:getWidth() / 2, Screen:getHeight() - 40, "west")
        assert.are.equal(ui, top())
        assert.is_true(ui.document:getCurrentPage() > page)
        UIManager:sendEvent(Event:new("KeyPress", Key:new("Back", {})))
        UIManager:forceRePaint()
        assert.are.equal(page, ui.document:getCurrentPage())
    end)

    it("keeps an empty footnote drawable and dismissible", function()
        local page = ui.document:getCurrentPage()
        local popup = openFootnote(3)
        assert.is_true(popup.container.dimen.h > 0)
        assert.is_true(popup.container.dimen.h <= Screen:getHeight() / 3)
        UIManager:sendEvent(Event:new("KeyPress", Key:new("Back", {})))
        UIManager:forceRePaint()
        assert.are.equal(ui, top())
        assert.are.equal(page, ui.document:getCurrentPage())
    end)
end)
