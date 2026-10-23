describe("Image preview", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderToolbar, ReaderHighlightBubble, Replacements, UIManager
    local Event, Geom, Key, ImagePreview, Input, Screen, ffiUtil, lfs
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local dir, book
    local W, H

    local bit = require("bit")

    local function u32(n)
        return string.char(bit.band(bit.rshift(n, 24), 0xFF), bit.band(bit.rshift(n, 16), 0xFF),
            bit.band(bit.rshift(n, 8), 0xFF), bit.band(n, 0xFF))
    end

    local crc_table = {}
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            c = bit.band(c, 1) == 1 and bit.bxor(0xEDB88320, bit.rshift(c, 1)) or bit.rshift(c, 1)
        end
        crc_table[i] = c
    end

    local function crc32(s)
        local c = 0xFFFFFFFF
        for i = 1, #s do
            c = bit.bxor(crc_table[bit.band(bit.bxor(c, s:byte(i)), 0xFF)], bit.rshift(c, 8))
        end
        return bit.bxor(c, 0xFFFFFFFF)
    end

    -- PNG data of a w x h gray and alpha image (Blitbuffer writes no alpha), stored uncompressed:
    -- pixel(x, y) returns the gray and the opacity.
    local function png(w, h, pixel)
        local rows = {}
        for y = 0, h - 1 do
            local row = { "\0" } -- no filter
            for x = 0, w - 1 do
                row[#row + 1] = string.char(pixel(x, y))
            end
            rows[#rows + 1] = table.concat(row)
        end
        local raw = table.concat(rows)
        local zlib = { "\120\1" }
        for i = 1, #raw, 65535 do
            local block = raw:sub(i, i + 65534)
            local len, nlen = #block, bit.bnot(#block)
            zlib[#zlib + 1] = string.char(i + 65535 > #raw and 1 or 0, bit.band(len, 0xFF), bit.rshift(len, 8),
                bit.band(nlen, 0xFF), bit.band(bit.rshift(nlen, 8), 0xFF)) .. block
        end
        local a, b = 1, 0
        for i = 1, #raw do
            a = (a + raw:byte(i)) % 65521
            b = (b + a) % 65521
        end
        zlib[#zlib + 1] = u32(b * 65536 + a)
        local function chunk(kind, data) return u32(#data) .. kind .. data .. u32(crc32(kind .. data)) end
        return "\137PNG\r\n\26\n" .. chunk("IHDR", u32(w) .. u32(h) .. "\8\4\0\0\0")
            .. chunk("IDAT", table.concat(zlib)) .. chunk("IEND", "")
    end

    -- PNG data of a w x h image inside a 4px ink frame: paper inside, or with `clear` transparent
    -- (as such images usually are: black, with no opacity); with `stripe`, a 4px ink line from x = stripe.
    local function framedPng(w, h, clear, stripe)
        return png(w, h, function(x, y)
            if x < 4 or y < 4 or x >= w - 4 or y >= h - 4 then return 0, 0xFF end
            if stripe and x >= stripe and x < stripe + 4 then return 0, 0xFF end
            if clear then return 0, 0 end
            return 0xFF, 0xFF
        end)
    end

    local function xhtml(body)
        return [[<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Images</title></head><body>]] .. body .. "</body></html>"
    end

    -- An EPUB of six pages: text around a wide image, an image in a link to the fourth page,
    -- a transparent image, the link's target, a list item with a small bullet image, and an SVG image.
    local function makeBook(path)
        local Archiver = require("ffi/archiver")
        local epub = Archiver.Writer:new{}
        assert(epub:open(path, "epub"))
        local mtime = os.time()
        epub:setZipCompression("store")
        epub:addFileFromMemory("mimetype", "application/epub+zip", mtime)
        epub:setZipCompression("deflate")
        epub:addFileFromMemory("META-INF/container.xml", [[<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>]], mtime)
        epub:addFileFromMemory("OEBPS/content.opf", [[<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="id" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Images</dc:title><dc:identifier id="id">image-preview-spec</dc:identifier><dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
    <item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/>
    <item id="c4" href="c4.xhtml" media-type="application/xhtml+xml"/>
    <item id="c5" href="c5.xhtml" media-type="application/xhtml+xml"/>
    <item id="c6" href="c6.xhtml" media-type="application/xhtml+xml"/>
    <item id="bullet" href="bullet.png" media-type="image/png"/>
    <item id="svg" href="framed.svg" media-type="image/svg+xml"/>
    <item id="wide" href="wide.png" media-type="image/png"/>
    <item id="linked" href="linked.png" media-type="image/png"/>
    <item id="clear" href="clear.png" media-type="image/png"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/><itemref idref="c4"/><itemref idref="c5"/><itemref idref="c6"/></spine>
</package>]], mtime)
        epub:addFileFromMemory("OEBPS/c1.xhtml", xhtml([[
<p>The text before the picture.</p>
<p style="text-align: center"><img src="wide.png" alt=""/></p>
<p>The text after the picture.</p>]]), mtime)
        epub:addFileFromMemory("OEBPS/c2.xhtml", xhtml([[
<p style="text-align: center"><a href="c4.xhtml#end"><img src="linked.png" alt=""/></a></p>]]), mtime)
        epub:addFileFromMemory("OEBPS/c3.xhtml", xhtml([[
<p style="text-align: center"><img src="clear.png" alt=""/></p>]]), mtime)
        epub:addFileFromMemory("OEBPS/c4.xhtml", xhtml([[<p id="end">The end.</p>]]), mtime)
        epub:addFileFromMemory("OEBPS/c5.xhtml", xhtml([[
<p><img src="bullet.png" alt=""/> An item of a list, after its bullet.</p>]]), mtime)
        epub:addFileFromMemory("OEBPS/c6.xhtml", xhtml([[
<p style="text-align: center"><img src="framed.svg" alt=""/></p>]]), mtime)
        epub:addFileFromMemory("OEBPS/wide.png", framedPng(400, 100, false, 80), mtime)
        epub:addFileFromMemory("OEBPS/linked.png", framedPng(300, 80), mtime)
        epub:addFileFromMemory("OEBPS/bullet.png", png(50, 50, function() return 0, 0xFF end), mtime)
        epub:addFileFromMemory("OEBPS/framed.svg", [[<svg xmlns="http://www.w3.org/2000/svg" width="400" height="100">
<rect x="2" y="2" width="396" height="96" fill="white" stroke="black" stroke-width="4"/></svg>]], mtime)
        epub:addFileFromMemory("OEBPS/clear.png", framedPng(200, 100, true), mtime)
        epub:close()
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderToolbar = require("apps/reader/modules/readertoolbar")
        ReaderHighlightBubble = require("apps/reader/modules/readerhighlightbubble")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Key = require("device/key")
        ImagePreview = require("ui/widget/imagepreview")
        Input = require("device").input
        Screen = require("device").screen
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        W, H = Screen:getWidth(), Screen:getHeight()
        Replacements.reader_menu = ReaderToolbar
        ReaderHighlightBubble.register()
        dir = ffiUtil.realpath(require("datastorage"):getDataDir()) .. "/imagepreview_spec"
        ffiUtil.purgeDir(dir)
        lfs.mkdir(dir)
        book = dir .. "/images.epub"
        makeBook(book)
    end)

    teardown(function()
        Replacements.reader_menu = nil
        Replacements.reader_highlight = nil
        DocSettings:open(sample_pdf):purge()
        if book then DocSettings:open(book):purge() end
        if dir then ffiUtil.purgeDir(dir) end
    end)

    local function openReader(file)
        DocSettings:open(file):purge()
        local ui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(file),
        }
        UIManager:show(ui)
        UIManager:forceRePaint()
        return ui
    end

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function isPreview(widget)
        return getmetatable(widget) == ImagePreview
    end

    local function gesture(ges, x, y, extra)
        local ev = { ges = ges, pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }
        for k, v in pairs(extra or {}) do ev[k] = v end
        UIManager:sendEvent(Event:new("Gesture", ev))
    end

    local function tap(x, y) gesture("tap", x, y) end
    local function doubleTap(x, y) gesture("double_tap", x, y) end

    -- gray level of a screen pixel, 0 (ink) to 255 (paper)
    local function gray(x, y)
        return Screen.bb:getPixel(math.floor(x), math.floor(y)):getColor8().a
    end

    local function isInk(x, y) return gray(x, y) < 0x40 end
    local function isPaper(x, y) return gray(x, y) > 0xC0 end

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

    -- Neither flashing nor full: the preview only asks for "ui" over the screen.
    local function assertScreenUiRefreshes(refreshes)
        local screen = false
        for _, r in ipairs(refreshes) do
            assert.is_falsy(r.mode == "full" or r.mode:find("^flash"), r.mode)
            if r.mode == "ui" and r.region and r.region.w >= W and r.region.h >= H then
                screen = true
            end
        end
        assert.is_true(screen)
    end

    -- The screen rect of the framed image on the page, whose frame is its only long run of ink.
    local function imageRect(ui)
        UIManager:forceRePaint()
        local rect
        for y = 0, H - ui.view.footer:getHeight() - 1 do
            local run, best, best_end = 0, 0, nil
            for x = 0, W - 1 do
                run = isInk(x, y) and run + 1 or 0
                if run > best then best, best_end = run, x end
            end
            if best >= 50 then
                if not rect then
                    rect = { x = best_end - best + 1, y = y, w = best }
                end
                rect.h = y - rect.y + 1
            end
        end
        assert.is_truthy(rect)
        return rect
    end

    local function center(rect)
        return rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2)
    end

    -- The screen rect of an image of w x h fitted to the screen in the preview.
    local function fitted(w, h)
        local scale = math.min(W / w, H / h)
        local fw, fh = math.floor(w * scale), math.floor(h * scale)
        return { x = math.floor((W - fw) / 2), y = math.floor((H - fh) / 2), w = fw, h = fh }
    end

    describe("with an EPUB", function()
        local ui
        before_each(function()
            ui = openReader(book)
        end)
        after_each(function()
            while topWidget() ~= ui do UIManager:close(topWidget()) end
            ui:onClose()
        end)

        it("should open a tapped image centered on an ink ground, without the bars or a page turn", function()
            local page, location = ui:getCurrentPage(), ui.rolling:getBookLocation()
            local refreshes = refreshesOf(function() tap(center(imageRect(ui))) end)
            assert.is_true(isPreview(topWidget()))
            assert.is_nil(ui.menu.bars)
            assert.are.equal(page, ui:getCurrentPage())
            assert.are.equal(location, ui.rolling:getBookLocation())
            assertScreenUiRefreshes(refreshes)
            -- the image fits the screen's width, in the middle; nothing else but the ground: no title or buttons
            local r = fitted(400, 100)
            assert.are.equal(0, r.x)
            assert.is_true(isInk(2, r.y + r.h / 2)) -- its frame
            assert.is_true(isPaper(W / 4, r.y + r.h / 2))
            assert.is_true(isPaper(W * 3 / 4, r.y + r.h / 2))
            for _, y in ipairs{ 2, r.y - 10, r.y + r.h + 10, H - 3 } do
                for x = 2, W - 3, 20 do
                    assert.is_true(isInk(x, y))
                end
            end
        end)

        it("should go back to the same place on a tap, with no flashing refresh, and let the reader's taps be single again", function()
            local location = ui.rolling:getBookLocation()
            tap(center(imageRect(ui)))
            UIManager:forceRePaint()
            assert.is_true(isPreview(topWidget()))
            assert.is_false(Input.disable_double_tap) -- for its double tap
            local refreshes = refreshesOf(function() tap(W / 2, H / 2) end)
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.menu.bars)
            assert.are.equal(location, ui.rolling:getBookLocation())
            assert.is_true(Input.disable_double_tap)
            assertScreenUiRefreshes(refreshes)
            -- the page is back
            local r = imageRect(ui)
            assert.is_true(r.w < W)
        end)

        it("should go back to the same place on Back, and on a swipe down while fitted", function()
            local location = ui.rolling:getBookLocation()
            tap(center(imageRect(ui)))
            UIManager:forceRePaint()
            UIManager:sendEvent(Event:new("KeyPress", Key:new("Back", {})))
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())
            assert.are.equal(location, ui.rolling:getBookLocation())

            tap(center(imageRect(ui)))
            UIManager:forceRePaint()
            gesture("swipe", W / 2, H / 4, { direction = "south", distance = H / 2, time = require("ui/time").now() })
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())
            assert.are.equal(location, ui.rolling:getBookLocation())
        end)

        it("should zoom in twice the fitting size on a double tap, keeping the point tapped, and fit on the next one", function()
            tap(center(imageRect(ui)))
            UIManager:forceRePaint()
            local r = fitted(400, 100)
            local above = r.y - 10 -- the ground above the fitted image

            local refreshes = refreshesOf(function() doubleTap(W / 2, H / 2) end)
            assert.is_true(isPreview(topWidget()))
            assertScreenUiRefreshes(refreshes)
            -- twice as tall, and twice as wide: the screen's width shows its middle, past its frame
            assert.is_true(isPaper(W / 2 + 20, above))
            assert.is_true(isPaper(W / 2 + 20, H / 2 - r.h + 20))
            assert.is_true(isInk(W / 2 + 20, H / 2 - r.h - 10)) -- the ground, past twice the height
            assert.is_true(isPaper(5, H / 2))
            assert.is_true(isPaper(W - 5, H / 2))

            doubleTap(W / 2, H / 2)
            UIManager:forceRePaint()
            assert.is_true(isInk(W / 2, above))
            assert.is_true(isInk(2, H / 2))

            -- the stripe a fifth of the way in stays under the finger, the left frame out of view
            local stripe = math.floor(82 * W / 400)
            assert.is_true(isInk(stripe, H / 2))
            doubleTap(stripe, H / 2)
            UIManager:forceRePaint()
            assert.is_true(isInk(stripe, H / 2))
            assert.is_true(isPaper(stripe - 20, H / 2))
            assert.is_true(isPaper(5, H / 2))
            assert.is_true(isPaper(W / 2, above))
        end)

        it("should pan a zoomed image with a drag", function()
            tap(center(imageRect(ui)))
            UIManager:forceRePaint()
            doubleTap(W / 2, H / 2)
            UIManager:forceRePaint()
            assert.is_true(isPaper(5, H / 2))
            -- drag to the right: the left part comes into view, up to its frame
            gesture("pan", W / 4, H / 2, { relative = { x = W / 2, y = 0 }, direction = "east", distance = W / 2 })
            gesture("pan_release", W * 3 / 4, H / 2)
            UIManager:forceRePaint()
            assert.is_true(isPreview(topWidget()))
            assert.is_true(isInk(5, H / 2))
        end)

        it("should show a transparent image on paper", function()
            ui.rolling:onGotoPage(3)
            UIManager:forceRePaint()
            tap(center(imageRect(ui)))
            UIManager:forceRePaint()
            assert.is_true(isPreview(topWidget()))
            local r = fitted(200, 100)
            assert.is_true(isPaper(W / 2, H / 2))
            assert.is_true(isPaper(r.x + 30, r.y + 30))
            assert.is_true(isInk(r.x + 2, H / 2)) -- its frame
            assert.is_true(isInk(W / 2, r.y - 10)) -- the ground
        end)

        it("should zoom an SVG image, drawn at each size", function()
            ui.rolling:onGotoPage(6)
            UIManager:forceRePaint()
            tap(center(imageRect(ui)))
            UIManager:forceRePaint()
            assert.is_true(isPreview(topWidget()))
            local r = fitted(400, 100)
            assert.is_true(isInk(2, H / 2)) -- its frame
            assert.is_true(isPaper(W / 4, H / 2))
            assert.is_true(isInk(W / 2, r.y - 10))
            doubleTap(W / 2, H / 2)
            UIManager:forceRePaint()
            assert.is_true(isPaper(W / 2 + 20, r.y - 10))
            assert.is_true(isPaper(5, H / 2))
        end)

        it("should leave a tap on a bullet-sized image to the page", function()
            ui.rolling:onGotoPage(5)
            UIManager:forceRePaint()
            -- the bullet is solid ink, the longest run on the page
            local bullet
            for y = 0, H - ui.view.footer:getHeight() - 1 do
                local run = 0
                for x = 0, W / 3 do
                    run = isInk(x, y) and run + 1 or 0
                    if run >= 20 then
                        bullet = { x = x - 10, y = y + 10 }
                        break
                    end
                end
                if bullet then break end
            end
            assert.is_truthy(bullet)
            assert.is_true(bullet.x < W / 3) -- in the third that turns pages back
            tap(bullet.x, bullet.y)
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())
            assert.are.equal(4, ui:getCurrentPage())
        end)

        it("should leave taps to the page in select mode", function()
            G_reader_settings:saveSetting("default_highlight_action", "select")
            local ok, err = pcall(function()
                -- the first line of text, above the image
                local y0, x0, x1
                for y = 0, H - 1 do
                    for x = 0, W - 1 do
                        if isInk(x, y) then
                            y0, x0, x1 = y0 or y, x0 or x, x
                        end
                    end
                    if y0 and y > y0 + 4 then break end
                end
                ui.highlight:onHold(nil, { pos = Geom:new{ x = x0 + 2, y = y0 + 2 } })
                ui.highlight:onHoldPan(nil, { pos = Geom:new{ x = x1 - 2, y = y0 + 2 } })
                ui.highlight:onHoldRelease()
                UIManager:forceRePaint()
                assert.is_true(ui.highlight.select_mode)
                tap(center(imageRect(ui)))
                UIManager:forceRePaint()
                assert.is_false(isPreview(topWidget()))
                assert.is_true(ui.highlight.select_mode)
            end)
            G_reader_settings:delSetting("default_highlight_action")
            assert(ok, err)
        end)

        it("should follow a link around an image instead of opening it", function()
            ui.rolling:onGotoPage(2)
            UIManager:forceRePaint()
            tap(center(imageRect(ui)))
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())
            assert.are.equal(4, ui:getCurrentPage())
        end)

        it("should keep the bars and page turns for taps beside the image", function()
            local r = imageRect(ui)
            local page = ui:getCurrentPage()
            tap(W / 2, r.y + r.h + 40) -- the text after the picture, in the middle third
            UIManager:forceRePaint()
            assert.is_truthy(ui.menu.bars)
            assert.are.equal(ui.menu.bars, topWidget())
            tap(W / 2, H / 2)
            UIManager:forceRePaint()
            assert.is_nil(ui.menu.bars)
            tap(W - 10, r.y + r.h + 40)
            assert.are.equal(page + 1, ui:getCurrentPage())
            assert.are.equal(ui, topWidget())
        end)
    end)

    it("should take the taps on a page-sized image, such as a cover, while swipes and page keys still turn the page", function()
        local ui = openReader("spec/front/unit/data/juliet.epub")
        local ok, err = pcall(function()
            assert.are.equal(1, ui:getCurrentPage()) -- the cover image, as tall as the page
            tap(W * 0.7, H / 2) -- in the third that turns pages forward
            UIManager:forceRePaint()
            assert.is_true(isPreview(topWidget()))
            tap(W / 2, H / 2)
            UIManager:forceRePaint()
            assert.are.equal(ui, topWidget())
            assert.are.equal(1, ui:getCurrentPage())
            gesture("swipe", W * 3 / 4, H / 2, { direction = "west", distance = W / 2, time = require("ui/time").now() })
            UIManager:forceRePaint()
            assert.are.equal(2, ui:getCurrentPage())
            assert.are.equal(ui, topWidget())
            ui.rolling:onGotoPage(1)
            UIManager:forceRePaint()
            UIManager:sendEvent(Event:new("KeyPress", Key:new("RPgFwd", {})))
            UIManager:forceRePaint()
            assert.are.equal(2, ui:getCurrentPage())
        end)
        while topWidget() ~= ui do UIManager:close(topWidget()) end
        ui:onClose()
        assert(ok, err)
    end)

    it("should turn the pages of a PDF on taps, as its pages are no images to preview", function()
        local ui = openReader(sample_pdf)
        local ok, err = pcall(function()
            local page = ui:getCurrentPage()
            tap(W - 10, H / 2)
            assert.are.equal(page + 1, ui:getCurrentPage())
            assert.are.equal(ui, topWidget())
            tap(W / 2, H / 2)
            UIManager:forceRePaint()
            assert.is_truthy(ui.menu.bars)
            assert.is_false(isPreview(topWidget()))
            tap(W / 2, H / 2)
            UIManager:forceRePaint()
        end)
        while topWidget() ~= ui do UIManager:close(topWidget()) end
        ui:onClose()
        assert(ok, err)
    end)
end)
