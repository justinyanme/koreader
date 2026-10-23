-- 书源: the OPDS plugin's redesigned page, driven through its real entries against a fake Calibre-Web server.
describe("书源 (OPDS as a remote shelf)", function()
    local BookSource, BookSourceView, BottomSheet, EinkSettings, Event, FileManager, Geom, InputDialog, LuaSettings
    local ReaderUI, Replacements, Screen, UIManager, ffiUtil, lfs, T, _
    local home, tmp, settings_file, log_file, saved_settings, saved_thumb_dir
    local server -- the fake server's state, read by the stubbed socket.http.request (also in forked children)
    local opened -- files the reader was asked to open
    local http_stub, online_stub, reader_stub

    local ORIGIN = "https://nas.example"
    local ROOT = ORIGIN .. "/opds"
    local PNG = "resources/koreader.png"

    local function xmlFeed(title, links, entries)
        return table.concat{
            '<?xml version="1.0" encoding="UTF-8"?>\n',
            '<feed xmlns="http://www.w3.org/2005/Atom" xmlns:dcterms="http://purl.org/dc/terms/" ',
            'xmlns:opds="http://opds-spec.org/2010/catalog">',
            "<title>", title, "</title>", links or "", table.concat(entries or {}), "</feed>",
        }
    end

    local function navEntry(title, href, rel, kind)
        return table.concat{
            "<entry><title>", title, "</title><id>", href, "</id>",
            '<link href="', href, '"', rel and (' rel="' .. rel .. '"') or "",
            ' type="application/atom+xml;profile=opds-catalog', kind and (";kind=" .. kind) or "", '"/></entry>',
        }
    end

    -- Book i: PDF and AZW3 listed before EPUB, so the preference order is what picks EPUB.
    local function bookEntry(i, formats)
        local links = {}
        for _, f in ipairs(formats or { "pdf", "azw3", "epub" }) do
            local mime = ({ pdf = "application/pdf", epub = "application/epub+zip", azw3 = "application/x-mobi8-ebook",
                mobi = "application/x-mobipocket-ebook" })[f]
            table.insert(links, string.format('<link rel="http://opds-spec.org/acquisition" href="/opds/download/%d/%s/" '
                .. 'length="%d" title="%s" type="%s"/>', i, f, 2048, f:upper(), mime))
        end
        return table.concat{
            "<entry><title>Book ", i, "</title><id>urn:uuid:book-", i, "</id>",
            "<author><name>Author ", i, "</name></author>",
            "<dcterms:language>fr</dcterms:language><published>1925-04-10T00:00:00+00:00</published>",
            '<content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">Summary of book ', i, "</div></content>",
            '<link type="image/png" href="/opds/cover/', i, '" rel="http://opds-spec.org/image"/>',
            '<link type="image/png" href="/opds/cover_240_240/', i, '" rel="http://opds-spec.org/image/thumbnail"/>',
            table.concat(links), "</entry>",
        }
    end

    local function books(from, to)
        local entries = {}
        for i = from, to do table.insert(entries, bookEntry(i, i == 2 and { "pdf", "mobi" } or nil)) end
        return entries
    end

    local SEARCH_LINKS = '<link rel="search" href="/opds/osd" type="application/opensearchdescription+xml"/>'
    -- as Calibre-Web's index.xml: no entry carries a rel or a kind
    local ROOT_NAVS = {
        navEntry("Alphabetical Books", "/opds/books"),
        navEntry("Recently added Books", "/opds/new"),
        navEntry("Authors", "/opds/author"),
    }

    -- path -> code, headers, body
    local function route(method, path)
        local mode = server.mode
        if mode == "timeout" then return nil end
        if mode == "auth" then return 401, {}, "Unauthorized" end
        if mode == "500" then return 500, {}, "boom", "HTTP/1.1 500 Internal Server Error" end
        if mode == "html" then return 200, {}, "<html><body>Login</body></html>" end
        if mode == "json" and path == "/opds" then return 200, {}, '{"error": "not a feed"}' end
        if mode == "osd_timeout" and path == "/opds/osd" then return nil end
        if mode == "osd_auth" and path == "/opds/osd" then return 401, {}, "Unauthorized" end
        local atom = { ["content-type"] = "application/atom+xml" }
        if path == "/opds" and server.cookie then atom["set-cookie"] = "CF_Authorization=old; Path=/" end
        if path == "/opds" then
            if mode == "no_new" then
                return 200, atom, xmlFeed("Calibre-Web", SEARCH_LINKS, {
                    navEntry("Authors", "/opds/author"),
                    navEntry("Alphabetical Books", "/opds/books", nil, "acquisition"),
                })
            elseif mode == "foreign" then
                -- links off the source's origin: another host, and plain http on its own host
                return 200, atom, xmlFeed("Calibre-Web", "", {
                    navEntry("Elsewhere", "https://other.example/opds/x"),
                    navEntry("Plain", "http://nas.example/opds/plain"),
                })
            elseif mode == "sort_new" then
                return 200, atom, xmlFeed("Calibre-Web", "", {
                    navEntry("Alphabetical Books", "/opds/books", "http://opds-spec.org/sort/new"),
                    navEntry("Recently added Books", "/opds/new"),
                })
            elseif mode == "marked_and_new" then
                -- a book list the feed marks, and an entry known only by its address
                return 200, atom, xmlFeed("Calibre-Web", "", {
                    navEntry("Recently added Books", "/opds/new"),
                    navEntry("Alphabetical Books", "/opds/books", nil, "acquisition"),
                })
            elseif mode == "categories" then
                return 200, atom, xmlFeed("Calibre-Web", "", { navEntry("Authors", "/opds/author") })
            elseif mode == "mixed" then
                -- a navigation entry, an entry without links, then a book: items must stay matched to their entries
                return 200, atom, xmlFeed("Calibre-Web", "", {
                    navEntry("Authors", "/opds/author"),
                    "<entry><title>About this library</title><id>urn:about</id></entry>",
                    bookEntry(7),
                })
            end
            return 200, atom, xmlFeed("Calibre-Web", SEARCH_LINKS, ROOT_NAVS)
        elseif path == "/opds/osd" then
            return 200, {}, '<?xml version="1.0"?><OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">'
                .. '<Url type="application/atom+xml" template="' .. ROOT .. '/search/{searchTerms}"/></OpenSearchDescription>'
        elseif path == "/opds/new" then
            if mode == "empty" then return 200, atom, xmlFeed("Recently added Books") end
            return 200, atom, xmlFeed("Recently added Books",
                '<link rel="next" href="/opds/new?offset=40" type="application/atom+xml;profile=opds-catalog"/>', books(1, 40))
        elseif path == "/opds/new?offset=40" and server.fail_next then
            return 500, {}, "boom"
        elseif path == "/opds/new?offset=40" then
            return 200, atom, xmlFeed("Recently added Books", "", books(41, 42))
        elseif path == "/opds/books" then
            return 200, atom, xmlFeed("Alphabetical Books", "", books(1, 3))
        elseif path == "/opds/author" then
            return 200, atom, xmlFeed("Authors", "", { navEntry("Author 5", "/opds/author/5"), navEntry("Author 6", "/opds/author/6") })
        elseif path == "/opds/author/5" then
            return 200, atom, xmlFeed("Author 5", "", books(5, 5))
        elseif path:match("^/opds/search/") then
            local q = path:match("^/opds/search/(.*)$")
            return 200, atom, xmlFeed("Search", "", q == "Book%201" and books(1, 1) or {})
        elseif path:match("^/opds/cover") then
            if server.html_thumbs then return 200, { ["content-type"] = "text/html" }, "<html>login</html>" end
            local f = io.open(PNG, "rb")
            local png = f:read("*a")
            f:close()
            -- server.thumb_type: what the server calls its covers ("" for no Content-Type)
            local thumb_type = server.thumb_type or "image/png"
            return 200, thumb_type ~= "" and { ["content-type"] = thumb_type } or {}, png
        elseif path == "/opds/download/3/epub/" then
            return 302, { location = "https://cdn.example/files/book3.epub" }, ""
        elseif path == "/opds/download/4/epub/" then
            return 302, { location = ORIGIN .. "/files/book4.epub" }, ""
        elseif server.fail_downloads and path:match("^/opds/download/") then
            return 500, {}, "boom"
        elseif server.html_downloads and path:match("^/opds/download/") then
            return 200, { ["content-type"] = "text/html; charset=utf-8" }, "<html><body>Sign in</body></html>"
        elseif path:match("^/opds/download/") or path:match("^/files/") then
            -- the slow one is large enough to get past stdio buffering before it stalls
            local body = "BOOK " .. path .. string.rep(".", path == "/opds/download/9/epub/" and 40000 or 900)
            return 200, { ["content-length"] = tostring(#body),
                ["content-disposition"] = 'attachment; filename="server_name.epub"' }, body, nil,
                path == "/opds/download/9/epub/" -- slow: lets the test cancel it
        end
        return 404, {}, "not found"
    end

    local function logRequest(request)
        local headers = {}
        for k, v in pairs(request.headers or {}) do headers[k] = v end
        local f = io.open(log_file, "a")
        f:write(require("dump")({ url = request.url, method = request.method or "GET", user = request.user,
            password = request.password, headers = headers }, nil, true):gsub("\n", " "), "\n")
        f:close()
    end

    local function requests()
        local list = {}
        local f = io.open(log_file, "r")
        if not f then return list end
        for line in f:lines() do table.insert(list, loadstring("return " .. line)()) end
        f:close()
        return list
    end

    -- requests for feeds only: thumbnails come from a background process, at their own pace
    local function feedRequests()
        local list = {}
        for _, r in ipairs(requests()) do
            if not r.url:find("/opds/cover", 1, true) then table.insert(list, r) end
        end
        return list
    end

    local function requestsTo(url_prefix)
        local list = {}
        for _, r in ipairs(requests()) do
            if r.url:sub(1, #url_prefix) == url_prefix then table.insert(list, r) end
        end
        return list
    end

    local function fakeRequest(request)
        logRequest(request)
        local parsed = require("socket.url").parse(request.url)
        local path = parsed.path .. (parsed.query and "?" .. parsed.query or "")
        if parsed.host == "cdn.example" then
            path = "/files/book3.epub"
        elseif parsed.host ~= "nas.example" then
            return nil, "host not found"
        end
        local code, headers, body, status, slow = route(request.method, path)
        if not code then return nil, "timeout" end
        -- as socket.http: no body when the response_headers callback says to skip it (redirects)
        local skip = request.response_headers and request.response_headers(code, headers)
        if request.sink and request.method ~= "HEAD" and body and not skip then
            if slow then
                request.sink(body:sub(1, 20000))
                ffiUtil.sleep(5)
                body = body:sub(20001)
            end
            request.sink(body)
            request.sink(nil)
        end
        return 1, code, headers, status or ("HTTP/1.1 " .. code)
    end

    -- the text of every TextWidget/TextBoxWidget under `widget`
    local function texts(widget, out)
        out = out or {}
        if type(widget) ~= "table" then return out end
        if widget.text and widget.face then table.insert(out, widget.text) end
        for _, child in ipairs(widget) do texts(child, out) end
        if widget.frame then
            texts(widget.frame, out) -- a sheet: its header and content
        elseif widget.content then
            texts(widget.content, out)
        end
        return out
    end

    local function has(widget, str)
        for _, t in ipairs(texts(widget)) do
            if t == str then return true end
        end
        return false
    end

    -- taps the tappable (Tappable or PillButton) around the first text or icon equal to `label`
    local function tap(widget, label, hold)
        local function find(node, tappable)
            if type(node) ~= "table" then return end
            if node.callback or node.hold_callback or node.onTapSelect then tappable = node end
            if (node.text == label and node.face) or node.icon == label then return tappable end
            for _, child in ipairs(node) do
                local found = find(child, tappable)
                if found then return found end
            end
            if node.content then return find(node.content, tappable) end
        end
        local target = find(widget)
        assert(target, "nothing to tap: " .. label)
        if hold then
            target.hold_callback()
        elseif target.onTapSelect and not target.onTap then
            target:onTapSelect()
        else
            target.callback()
        end
    end

    -- the innermost Tappable around the first text or icon equal to `label`, once painted: for taps on screen
    local function tappableAround(widget, label)
        local function find(node, tappable)
            if type(node) ~= "table" then return end
            if node.callback then tappable = node end
            if (node.text == label and node.face) or node.icon == label then return tappable end
            for _, child in ipairs(node) do
                local found = find(child, tappable)
                if found then return found end
            end
        end
        return assert(find(widget), "nothing to tap: " .. label)
    end

    -- a point a quarter into `target`'s width, halfway down
    local function pointIn(target)
        local d = target.dimen
        return d.x + math.floor(d.w / 4), d.y + math.floor(d.h / 2)
    end

    -- a finger on the screen at x, y: a tap, or `ges`
    local function touch(x, y, ges)
        UIManager:sendEvent(Event:new("Gesture", { ges = ges or "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
    end

    -- the top widget, under any toast
    -- whether the grid tile titled `title` carries the gray "downloaded" check
    local function marked(view, title)
        local function tile(node, found)
            if type(node) ~= "table" then return end
            if node.hold_callback then found = node end
            if node.text == title and node.face then return found end
            for _, child in ipairs(node) do
                local t = tile(child, found)
                if t then return t end
            end
        end
        local function check(node)
            if type(node) ~= "table" then return false end
            if node.icon == "eink/check" then return true end
            for _, child in ipairs(node) do
                if check(child) then return true end
            end
            return false
        end
        return check(tile(view))
    end

    local function topWidget()
        local Notification = require("ui/widget/notification")
        for i = #UIManager._window_stack, 1, -1 do
            local widget = UIManager._window_stack[i].widget
            if getmetatable(widget).__index ~= Notification then return widget end
        end
    end

    local function flush()
        UIManager:shiftScheduledTasksBy(-1e9)
        UIManager:_checkTasks()
    end

    local function waitFor(cond, what)
        for _ = 1, 400 do
            flush()
            if cond() then return end
            ffiUtil.usleep(25000)
        end
        local urls = {}
        for _, r in ipairs(requests()) do table.insert(urls, r.method .. " " .. r.url) end
        error("timed out waiting for " .. what .. "; requests: " .. table.concat(urls, ", "))
    end

    local function spyRefreshes()
        local refreshes = {}
        local orig_setDirty = UIManager.setDirty
        UIManager.setDirty = function(self, widget, refreshtype, region, ...)
            if refreshtype then table.insert(refreshes, { widget = widget, type = refreshtype, region = region }) end
            return orig_setDirty(self, widget, refreshtype, region, ...)
        end
        return refreshes, function() UIManager.setDirty = orig_setDirty end
    end

    local function writeSources(servers)
        os.remove(settings_file)
        local s = LuaSettings:open(settings_file)
        s:saveSetting("servers", servers)
        s:flush()
    end

    local function nas(extra)
        local source = { title = "NAS at home", url = ROOT, username = "reader", password = "secret",
            access_client_id = "id.access", access_client_secret = "token" }
        for k, v in pairs(extra or {}) do source[k] = v end
        return source
    end

    local function openFM()
        if FileManager.instance then FileManager.instance:onClose() end
        FileManager:showFiles(home)
        local fm = FileManager.instance
        fm.opds.settings_file = settings_file
        fm.opds.settings = nil
        return fm
    end

    --- Opens the page from the shelf's 书源 icon and waits for the first feed.
    local function openSources(fm)
        tap(fm.shelf_view, "eink/source")
        local view = topWidget()
        assert.are.equal(BookSourceView, getmetatable(view).__index)
        waitFor(function() return view:top().result.state ~= "loading" end, "the feed")
        return view
    end

    local function bookTitles(view)
        local titles = {}
        for _, cell in ipairs(view.cells) do table.insert(titles, cell.book.title) end
        return titles
    end

    local function savedSources()
        return LuaSettings:open(settings_file):readSetting("servers")
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("opds.koplugin")
        package.path = "plugins/opds.koplugin/?.lua;" .. package.path
        require("document/canvascontext"):init(require("device"))
        BookSource = require("apps/opds/booksource")
        BottomSheet = require("ui/widget/bottomsheet")
        EinkSettings = require("apps/settings/einksettings")
        Event = require("ui/event")
        FileManager = require("apps/filemanager/filemanager")
        Geom = require("ui/geometry")
        InputDialog = require("ui/widget/inputdialog")
        LuaSettings = require("luasettings")
        ReaderUI = require("apps/reader/readerui")
        Replacements = require("apps/replacements")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        T = ffiUtil.template
        _ = require("gettext")
        require("apps/shelf/shelffilemanager") -- registers the replacements
        BookSourceView = require("apps/opds/booksourceview")

        local data_dir = ffiUtil.realpath(require("datastorage"):getDataDir())
        tmp = data_dir .. "/booksource_spec"
        ffiUtil.purgeDir(tmp)
        lfs.mkdir(tmp)
        home = tmp .. "/home"
        lfs.mkdir(home)
        settings_file = tmp .. "/opds.lua"
        saved_thumb_dir = BookSource.thumb_dir
        saved_settings = {}
        for _, key in ipairs{ "home_dir", "lastdir", "download_dir", "file_ask_to_open" } do
            saved_settings[key] = G_reader_settings:readSetting(key)
        end
        G_reader_settings:saveSetting("home_dir", home)
        G_reader_settings:delSetting("file_ask_to_open")

        http_stub = stub(require("socket.http"), "request", fakeRequest)
        online_stub = stub(require("ui/network/manager"), "isOnline", function() return true end)
        reader_stub = stub(ReaderUI, "showReader", function(_, file) table.insert(opened, file) end)
    end)

    teardown(function()
        http_stub:revert()
        online_stub:revert()
        reader_stub:revert()
        if FileManager.instance then FileManager.instance:onClose() end
        for key, value in pairs(saved_settings) do
            G_reader_settings:saveSetting(key, value)
        end
        BookSource.thumb_dir = saved_thumb_dir
        Replacements.filemanager = nil
        Replacements.opds_catalog = nil
        ffiUtil.purgeDir(tmp)
    end)

    local run = 0
    before_each(function()
        server = { mode = "ok" }
        opened = {}
        -- a child forked by the previous test may still be fetching: it keeps the paths it was forked with
        run = run + 1
        log_file = tmp .. "/requests" .. run .. ".log"
        BookSource.thumb_dir = tmp .. "/thumbs" .. run
        writeSources{ nas() }
    end)

    after_each(function()
        while UIManager._window_stack[2] do -- leave only the file manager
            local widget = topWidget()
            if widget.close then widget:close(true) else UIManager:close(widget) end
            flush()
        end
    end)

    describe("entries", function()
        it("opens the page from the shelf icon, the OPDS event, and the settings row", function()
            local fm = openFM()
            local view = openSources(fm)
            view:close()

            fm:handleEvent(Event:new("ShowOPDSCatalog"))
            assert.are.equal(BookSourceView, getmetatable(topWidget()).__index)
            topWidget():close(true)

            local settings = EinkSettings.show(fm, fm.menu, "transfer")
            local entry
            for __, item in ipairs(settings.item_table) do
                if item.text == _("Book sources (OPDS)") then entry = item end
            end
            settings:select(entry)
            assert.are.equal(BookSourceView, getmetatable(topWidget()).__index)
        end)

        it("keeps the original browser on the original menu item", function()
            local fm = openFM()
            local items = {}
            fm.opds:addToMainMenu(items)
            items.opds.callback()
            local browser = topWidget()
            assert.are.equal(require("opdsbrowser"), getmetatable(browser).__index)
            browser.close_callback()
        end)

        it("lists the sources first when there are several", function()
            writeSources{ nas(), { title = "Gutenberg", url = "https://gutenberg.example/opds" } }
            local fm = openFM()
            tap(fm.shelf_view, "eink/source")
            local view = topWidget()
            assert.are.equal("manage", view:top().kind)
            assert.is_true(has(view, "NAS at home"))
            assert.is_true(has(view, "nas.example"))
            assert.is_true(has(view, "gutenberg.example"))
            assert.are.same({}, requests())
            tap(view, "NAS at home")
            waitFor(function() return view:top().result.state == "ok" end, "the home feed")
            assert.are.equal("home", view:top().kind)
        end)

        it("taps on screen: the row enters the source, its ⋯ only opens the actions", function()
            writeSources{ nas(), { title = "Gutenberg", url = "https://gutenberg.example/opds" } }
            local fm = openFM()
            tap(fm.shelf_view, "eink/source")
            local view = topWidget()
            view:paintTo(Screen.bb, 0, 0)
            touch(pointIn(tappableAround(view, "eink/more")))
            assert.are.equal(BottomSheet, getmetatable(topWidget()).__index)
            assert.is_true(has(topWidget(), _("Edit")))
            topWidget():onClose()
            flush()

            view:paintTo(Screen.bb, 0, 0)
            touch(pointIn(tappableAround(view, "NAS at home")))
            assert.are.equal(view, topWidget())
            waitFor(function() return view:top().result.state == "ok" end, "the home feed")
            assert.are.equal("home", view:top().kind)
        end)

        it("leaves a long-press on a nested tappable without a hold action to the one around it", function()
            local HorizontalGroup = require("ui/widget/horizontalgroup")
            local Tappable = require("apps/shelf/shelfwidgets").Tappable
            local Widget = require("ui/widget/widget")
            local calls = {}
            local outer = Tappable:new{
                callback = function() table.insert(calls, "outer tap") end,
                hold_callback = function() table.insert(calls, "outer hold") end,
                HorizontalGroup:new{
                    Widget:new{ dimen = Geom:new{ w = 100, h = 40 } },
                    Tappable:new{
                        callback = function() table.insert(calls, "inner tap") end,
                        Widget:new{ dimen = Geom:new{ w = 40, h = 40 } },
                    },
                },
            }
            outer:paintTo(Screen.bb, 0, 0)
            local function gesture(ges, x)
                outer:handleEvent(Event:new("Gesture", { ges = ges, pos = Geom:new{ x = x, y = 20, w = 0, h = 0 } }))
            end
            gesture("hold", 120)
            gesture("tap", 120)
            gesture("tap", 20)
            assert.are.same({ "outer hold", "inner tap", "outer tap" }, calls)
        end)
    end)

    describe("home", function()
        it("shows the newest books as a cover grid, titles and authors under the covers", function()
            local fm = openFM()
            local refreshes, restore = spyRefreshes()
            local view = openSources(fm)
            restore()
            assert.are.equal("NAS at home", view:top().title)
            assert.are.equal(ROOT .. "/new", view:top().result.url)
            local titles = bookTitles(view)
            assert.is_true(#titles >= 6)
            for i, title in ipairs(titles) do assert.are.equal("Book " .. i, title) end
            assert.is_true(has(view, "Author 1"))
            assert.is_true(has(view, "Recently added Books"))
            -- the grid is the shelf's grid
            local grid = require("apps/shelf/shelfwidgets").gridGeometry(view.dimen.w, 1000)
            assert.are.equal(grid.cols, view.grid.cols)
            -- the server has more: "n / …"
            assert.is_true(has(view, "1 / …"))
            for _, r in ipairs(refreshes) do assert.are.equal("ui", r.type) end
        end)

        it("prefers the sort/new link, then the first book list, then an entry at …/new, then the categories", function()
            server.mode = "sort_new"
            local view = openSources(openFM())
            assert.are.equal(ROOT .. "/books", view:top().result.url)
            view:close(true)

            server.mode = "no_new"
            view = openSources(FileManager.instance)
            assert.are.equal(ROOT .. "/books", view:top().result.url)
            assert.are.same({ "Book 1", "Book 2", "Book 3" }, bookTitles(view))
            view:close(true)

            server.mode = "marked_and_new"
            view = openSources(FileManager.instance)
            assert.are.equal(ROOT .. "/books", view:top().result.url)
            view:close(true)

            server.mode = "categories"
            view = openSources(FileManager.instance)
            assert.are.same({}, view.cells)
            assert.is_true(has(view, "Authors"))
        end)

        it("matches parsed items to their own entries in a mixed feed", function()
            server.mode = "mixed"
            local view = openSources(openFM())
            local result = view:top().result
            assert.are.equal(1, #result.books)
            local book = result.books[1]
            assert.are.equal("Book 7", book.title)
            assert.are.equal("urn:uuid:book-7", book.key)
            assert.are.equal("fr", book.language)
            assert.are.equal("1925", book.year)
            assert.are.equal("Summary of book 7", book.summary)
            assert.are.same({ "Authors" }, { result.navs[1].title })
        end)

        it("pages through every book exactly once, fetching the next batch before a page it cannot fill", function()
            local view = openSources(openFM())
            local page = view:top()
            local seen, order = {}, {}
            local refreshes, restore = spyRefreshes()
            for _ = 1, 20 do
                for _, cell in ipairs(view.cells) do
                    seen[cell.book.key] = (seen[cell.book.key] or 0) + 1
                    table.insert(order, cell.book.title)
                end
                local before = page.page_no
                view:turnPage(before + 1)
                flush()
                if page.page_no == before then break end
            end
            restore()
            assert.are.equal(42, #order)
            for i = 1, 42 do
                assert.are.equal(1, seen["urn:uuid:book-" .. i])
                assert.are.equal("Book " .. i, order[i])
            end
            assert.are.equal(1, #requestsTo(ROOT .. "/new?offset=40"))
            assert.is_nil(page.result.next)
            -- the pager says it is fetching ("fast"), then the batch repaints everything under the nav bar ("ui")
            local fetching, landed
            for i, r in ipairs(refreshes) do
                if r.type == "fast" and r.region == view.pager_rect then fetching = i end
                if fetching and not landed and r.type == "ui" and r.region == view.content_rect then landed = i end
            end
            assert.is_not_nil(fetching)
            assert.is_not_nil(landed)
            assert.is_true(has(view, "42 books"))
        end)

        it("asks once and says so once when the next batch fails", function()
            server.fail_next = true
            local view = openSources(openFM())
            local page = view:top()
            local toasts = {}
            local orig_show = UIManager.show
            UIManager.show = function(self, widget, ...)
                if getmetatable(widget).__index == require("ui/widget/notification") then table.insert(toasts, widget.text) end
                return orig_show(self, widget, ...)
            end
            -- forward until a page the device cannot fill
            for _ = 1, 20 do
                view:turnPage(page.page_no + 1)
                flush()
                if #requestsTo(ROOT .. "/new?offset=40") > 0 then break end
            end
            for _ = 1, 5 do flush() end
            UIManager.show = orig_show
            assert.are.equal(1, #requestsTo(ROOT .. "/new?offset=40"))
            assert.are.equal(1, #toasts)
            assert.are.equal(40, #page.result.books)
        end)

        it("repaints under the nav bar once a feed arrives, so the search row and caption show", function()
            local fm = openFM()
            local refreshes, restore = spyRefreshes()
            local view = openSources(fm)
            restore()
            local last = refreshes[#refreshes]
            assert.are.equal("ui", last.type)
            assert.are.same(view.content_rect, last.region)
            assert.are.equal(view.dimen.h - view.content_rect.y, view.content_rect.h)
        end)

        it("repaints the grid for the covers of the page shown only, not of a page left", function()
            local view = openSources(openFM())
            view:turnPage(2) -- page 1's covers may still be on their way
            local refreshes, restore = spyRefreshes()
            waitFor(function() return #refreshes > 0 end, "page 2's covers")
            for _ = 1, 40 do ffiUtil.usleep(25000) flush() end
            restore()
            assert.are.equal(1, #refreshes)
            assert.are.same(view.body_rect, refreshes[1].region)
        end)

        it("fetches the page's thumbnails with the source's auth, then repaints the grid once", function()
            local view = openSources(openFM())
            local refreshes, restore = spyRefreshes()
            waitFor(function()
                return #refreshes > 0
            end, "the covers")
            -- give a late second repaint the chance to show up
            for _ = 1, 8 do ffiUtil.usleep(25000) flush() end
            restore()
            assert.are.equal(1, #refreshes)
            assert.are.equal("ui", refreshes[1].type)
            assert.are.same(view.body_rect, refreshes[1].region)
            local thumbs = requestsTo(ROOT .. "/cover_240_240/")
            assert.are.equal(#view.cells, #thumbs)
            assert.are.equal("reader", thumbs[1].user)
            assert.are.equal("token", thumbs[1].headers["CF-Access-Client-Secret"])
            assert.is_not_nil(view.thumbs[ROOT .. "/cover_240_240/1"])
            -- cached: the next visit draws them without asking again
            view:close(true)
            os.remove(log_file)
            view = openSources(FileManager.instance)
            assert.are.same({}, requestsTo(ROOT .. "/cover_240_240/"))
            assert.is_not_nil(view.thumbs[ROOT .. "/cover_240_240/1"])
        end)
    end)

    describe("browsing", function()
        it("opens 分类 as a sheet, goes down to books, and comes back without new requests", function()
            local view = openSources(openFM())
            tap(view, "eink/grid")
            local sheet = topWidget()
            assert.are.equal(BottomSheet, getmetatable(sheet).__index)
            assert.is_true(has(sheet, "Recently added Books"))
            tap(sheet, "Authors")
            assert.are.equal(view, topWidget())
            waitFor(function() return view:top().result.state == "ok" end, "authors")
            assert.are.equal("Authors", view:top().title)
            assert.is_true(has(view, "Author 6"))
            tap(view, "Author 5")
            waitFor(function() return view:top().result.state == "ok" end, "a book list")
            assert.are.same({ "Book 5" }, bookTitles(view))
            local count = #feedRequests()
            view:pop()
            view:pop()
            assert.are.equal("home", view:top().kind)
            assert.are.equal(count, #feedRequests())
        end)

        it("searches the source and clears back to the home feed", function()
            local view = openSources(openFM())
            tap(view, _("Search this source"))
            local dialog = topWidget()
            assert.are.equal(InputDialog, getmetatable(dialog).__index)
            dialog:setInputText("Book 1")
            dialog.buttons[1][2].callback()
            waitFor(function() return view:top().result.state == "ok" end, "results")
            assert.are.equal(1, #requestsTo(ROOT .. "/search/Book%201"))
            assert.are.same({ "Book 1" }, bookTitles(view))
            assert.is_true(has(view, "Book 1"))
            local count = #feedRequests()
            tap(view, "eink/close")
            assert.are.equal(ROOT .. "/new", view:top().result.url)
            assert.are.equal(count, #feedRequests())

            view:search("nothing")
            waitFor(function() return view:top().result.state == "ok" end, "results")
            assert.is_true(has(view, "Nothing found for “nothing”"))
        end)

        it("clears the search from the grown edge of its ×, not opening the field around it", function()
            local view = openSources(openFM())
            view:search("Book 1")
            waitFor(function() return view:top().result.state == "ok" end, "results")
            view:paintTo(Screen.bb, 0, 0)
            local clear = tappableAround(view, "eink/close").dimen
            touch(clear.x + math.floor(clear.w / 2), clear.y - 1) -- above the drawn ×: in its 44dp target
            assert.are.equal(view, topWidget())
            assert.are.equal(ROOT .. "/new", view:top().result.url)
        end)
    end)

    describe("downloading", function()
        it("downloads the preferred format on tap, names it, records it and marks the tile, opening nothing", function()
            local view = openSources(openFM())
            local refreshes, restore = spyRefreshes()
            tap(view, "Book 1")
            tap(view, "Book 4") -- at the same time: the first to finish must not cut the other off
            assert.is_not_nil(view.downloads["urn:uuid:book-1"])
            waitFor(function() return next(view.downloads) == nil end, "both downloads")
            restore()
            local file = home .. "/Author 1 - Book 1.epub"
            assert.are.same({}, opened)
            assert.is_true(UIManager:isWidgetShown(view))
            local f = io.open(file, "rb")
            assert.are.equal("BOOK /opds/download/1/epub/", f:read("*a"):sub(1, 27))
            f:close()
            assert.are.equal("file", lfs.attributes(home .. "/Author 4 - Book 4.epub", "mode"))
            assert.are.equal(file, savedSources()[1].downloaded["urn:uuid:book-1"])
            assert.is_nil(G_reader_settings:readSetting("download_dir"))
            for _, r in ipairs(refreshes) do
                assert.is_true(r.type == "ui" or r.type == "fast")
            end
            local downloads = requestsTo(ROOT .. "/download/1/")
            assert.are.equal(ROOT .. "/download/1/epub/", downloads[#downloads].url)
            assert.are.equal("id.access", downloads[#downloads].headers["CF-Access-Client-Id"])

            -- downloaded: a gray check before the title, and a tap opens the file without a request
            assert.is_true(marked(view, "Book 1"))
            assert.is_false(marked(view, "Book 2"))
            os.remove(log_file)
            tap(view, "Book 1")
            assert.are.same({ file }, opened)
            assert.are.same({}, requestsTo(ROOT .. "/download/"))
        end)

        it("keeps the page answering taps while a download runs on a tile not shown", function()
            local view = openSources(openFM())
            view:turnPage(2) -- Book 9 may be on page 2 on small screens
            if not view:cellOf({ key = "urn:uuid:book-9" }) then view:turnPage(1) end
            tap(view, "Book 9")
            tap(view, "eink/grid")
            tap(topWidget(), "Authors")
            waitFor(function() return view:top().result.state == "ok" end, "authors")
            view:paintTo(Screen.bb, 0, 0)
            local x, y = pointIn(tappableAround(view, "Author 5"))
            -- its progress and its end land while the tile is off screen: nothing is painted for them
            waitFor(function() return view.downloads["urn:uuid:book-9"] == nil end, "the download")
            touch(x, y)
            assert.are.equal("Author 5", view:top().title)
            waitFor(function() return view:top().result.state == "ok" end, "a book list")
        end)

        it("keeps the server's file name when the source asks for it", function()
            writeSources{ nas{ raw_names = true } }
            local view = openSources(openFM())
            tap(view, "Book 2") -- PDF and MOBI: MOBI is preferred
            waitFor(function() return view.downloads["urn:uuid:book-2"] == nil end, "the download")
            assert.are.equal(home .. "/server_name.epub", savedSources()[1].downloaded["urn:uuid:book-2"])
            local downloads = requestsTo(ROOT .. "/download/2/")
            assert.are.equal(ROOT .. "/download/2/mobi/", downloads[#downloads].url)
        end)

        it("cancels a download on a second tap and removes the partial file", function()
            local view = openSources(openFM())
            view:turnPage(2) -- Book 9 may be on page 2 on small screens
            if not view:cellOf({ key = "urn:uuid:book-9" }) then view:turnPage(1) end
            local refreshes, restore = spyRefreshes()
            tap(view, "Book 9")
            local dl = view.downloads["urn:uuid:book-9"]
            local tick
            waitFor(function()
                for _, r in ipairs(refreshes) do
                    if r.type == "fast" then tick = r end
                end
                return tick ~= nil
            end, "a progress tick")
            restore()
            -- progress repaints the tile's band and caption only
            assert.are.same(view:cellOf({ key = "urn:uuid:book-9" }).tick_rect, tick.region)
            local downloading = false
            for _, t in ipairs(texts(view)) do
                if t:match("^Downloading %d+%%$") then downloading = true end
            end
            assert.is_true(downloading)
            assert.is_true(lfs.attributes(dl.part, "mode") == "file")
            tap(view, "Book 9")
            assert.is_nil(view.downloads["urn:uuid:book-9"])
            assert.is_nil(lfs.attributes(dl.part, "mode"))
            assert.is_false(has(view, _("Downloading…")))
            assert.are.same({}, opened)
        end)

        it("puts the tile back and says why when a download fails", function()
            server.fail_downloads = true
            local view = openSources(openFM())
            tap(view, "Book 5")
            waitFor(function() return view.downloads["urn:uuid:book-5"] == nil end, "the failure")
            local toast = UIManager._window_stack[#UIManager._window_stack].widget
            assert.are.equal(T(_("Download failed: %1"), T(_("The server answered with status %1."), 500)), toast.text)
            assert.is_true(has(view, "Author 5"))
            assert.are.same({}, opened)
            assert.is_nil(lfs.attributes(home .. "/Author 5 - Book 5.epub", "mode"))
        end)

        it("sends the credentials to the source's origin only", function()
            local view = openSources(openFM())
            view:download(view:top(), view:top().result.books[3], view:top().result.books[3].formats[1])
            waitFor(function() return next(view.downloads) == nil end, "book 3")
            local cdn = requestsTo("https://cdn.example/")
            assert.is_true(#cdn > 0)
            for _, r in ipairs(cdn) do
                assert.is_nil(r.user)
                assert.is_nil(r.password)
                assert.is_nil(r.headers["CF-Access-Client-Id"])
                assert.is_nil(r.headers["CF-Access-Client-Secret"])
            end

            view:download(view:top(), view:top().result.books[4], view:top().result.books[4].formats[1])
            waitFor(function() return next(view.downloads) == nil end, "book 4")
            local same = requestsTo(ORIGIN .. "/files/book4.epub")
            assert.is_true(#same > 0)
            for _, r in ipairs(same) do
                assert.are.equal("reader", r.user)
                assert.are.equal("id.access", r.headers["CF-Access-Client-Id"])
            end
        end)

        it("shows formats, size and description on long-press, and re-download once downloaded", function()
            local view = openSources(openFM())
            tap(view, "Book 1", true)
            local sheet = topWidget()
            assert.are.equal(BottomSheet, getmetatable(sheet).__index)
            assert.is_true(has(sheet, "EPUB · 2.0 kB · fr · 1925"))
            assert.is_true(has(sheet, "Download EPUB · 2.0 kB"))
            assert.is_true(has(sheet, _("Other formats")))
            assert.is_true(has(sheet, "PDF · 2.0 kB"))
            tap(sheet, "Summary of book 1")
            assert.are.equal("text", view:top().kind)
            assert.is_true(has(view, "Summary of book 1"))
            view:pop()

            local file = home .. "/Author 1 - Book 1.epub"
            io.open(file, "w"):close()
            view:top().source.downloaded = { ["urn:uuid:book-1"] = file }
            tap(view, "Book 1", true)
            sheet = topWidget()
            assert.is_true(has(sheet, _("Read")))
            assert.is_true(has(sheet, _("Download again, replacing this copy")))
            tap(sheet, _("Download again, replacing this copy"))
            waitFor(function() return next(view.downloads) == nil end, "the new copy")
            local f = io.open(file, "rb")
            assert.are.equal("BOOK", f:read(4))
            f:close()
        end)
    end)

    describe("credentials and answers", function()
        it("sends no credentials to a feed link off the source's origin", function()
            server.mode = "foreign"
            local view = openSources(openFM())
            assert.is_true(has(view, "Elsewhere"))
            tap(view, "Elsewhere")
            waitFor(function() return view:top().result.state ~= "loading" end, "the other host")
            view:pop()
            tap(view, "Plain")
            waitFor(function() return view:top().result.state ~= "loading" end, "the http link")
            local off = requestsTo("https://other.example/")
            for _, r in ipairs(requestsTo("http://nas.example/")) do table.insert(off, r) end
            assert.are.equal(2, #off)
            for _, r in ipairs(off) do
                assert.is_nil(r.user)
                assert.is_nil(r.password)
                assert.is_nil(r.headers["CF-Access-Client-Id"])
                assert.is_nil(r.headers["CF-Access-Client-Secret"])
            end
            -- the source's own origin still gets them
            assert.are.equal("reader", requestsTo(ROOT)[1].user)
        end)

        it("drops the source's cookies once its credentials change", function()
            server.cookie = true
            local view = openSources(openFM())
            assert.are.equal("CF_Authorization=old", requestsTo(ROOT .. "/new")[1].headers.Cookie)
            tap(view, "eink/more")
            tap(topWidget(), _("Edit source"))
            view.save_button:onTapSelect()
            local count = #feedRequests()
            view:retry()
            waitFor(function() return view:top().result.state == "ok" end, "the reload")
            assert.is_nil(feedRequests()[count + 1].headers.Cookie)
        end)

        it("keeps the feed and turns search off when the search description times out, asking nothing more", function()
            server.mode = "osd_timeout"
            local view = openSources(openFM())
            assert.are.equal("ok", view:top().result.state)
            assert.is_true(has(view, "Recently added Books")) -- the root's entries, as categories
            assert.is_nil(view:top().root.search_url)
            assert.are.equal(1, #requestsTo(ROOT .. "/osd"))
            assert.are.same({}, requestsTo(ROOT .. "/new"))
            assert.is_true(has(view, _("Search this source")))
            assert.has_error(function() tap(view, _("Search this source")) end) -- shown, but nothing to tap
        end)

        it("keeps the feed and turns search off when the search description is refused", function()
            server.mode = "osd_auth"
            local view = openSources(openFM())
            assert.are.equal("ok", view:top().result.state)
            assert.are.equal(ROOT .. "/new", view:top().result.url)
            assert.is_false(has(view, _("Login failed")))
            assert.is_nil(view:top().root.search_url)
            assert.are.equal(1, #requestsTo(ROOT .. "/osd"))
        end)

        it("says a JSON answer that is not OPDS is not a catalog", function()
            server.mode = "json"
            local view = openSources(openFM())
            assert.are.equal("not_opds", view:top().result.state)
            assert.is_true(has(view, _("Not an OPDS catalog")))
        end)

        it("does not save a web page as a book", function()
            server.html_downloads = true
            local view = openSources(openFM())
            tap(view, "Book 6")
            waitFor(function() return view.downloads["urn:uuid:book-6"] == nil end, "the download")
            local toast = UIManager._window_stack[#UIManager._window_stack].widget
            assert.are.equal(T(_("Download failed: %1"), BookSource.failureText{ state = "not_book" }), toast.text)
            assert.is_nil(lfs.attributes(home .. "/Author 6 - Book 6.epub", "mode"))
            assert.is_nil(savedSources()[1].downloaded)
            assert.are.same({}, opened)
        end)

        it("caches covers sent as octet-stream or without a type", function()
            for _, thumb_type in ipairs{ "application/octet-stream", "" } do
                server.thumb_type = thumb_type
                BookSource.thumb_dir = tmp .. "/thumbs-" .. (thumb_type == "" and "none" or "octet")
                local view = openSources(openFM())
                waitFor(function() return view.thumbs[ROOT .. "/cover_240_240/1"] ~= nil end, thumb_type .. " covers")
                view:close(true)
            end
        end)

        it("does not cache a thumbnail that is not an image", function()
            server.html_thumbs = true
            local view = openSources(openFM())
            waitFor(function() return #requestsTo(ROOT .. "/cover_240_240/") == #view.cells end, "the thumbnails")
            for _ = 1, 20 do ffiUtil.usleep(25000) flush() end
            local cached = 0
            if lfs.attributes(BookSource.thumb_dir, "mode") then
                for name in lfs.dir(BookSource.thumb_dir) do
                    if name ~= "." and name ~= ".." then cached = cached + 1 end
                end
            end
            assert.are.equal(0, cached)
        end)

        it("says so when the download folder cannot be written", function()
            local missing = tmp .. "/no-such-folder"
            writeSources{ nas{ download_dir = missing } }
            local view = openSources(openFM())
            tap(view, "Book 1")
            local toast = UIManager._window_stack[#UIManager._window_stack].widget
            assert.are.equal(T(_("Download failed: %1"), BookSource.failureText{ state = "nowrite", detail = missing }),
                toast.text)
            assert.is_nil(view.downloads["urn:uuid:book-1"])
            assert.are.same({}, requestsTo(ROOT .. "/download/"))
        end)

        it("leaves a keyboard dialog alone when a download finishes, and closes it with the page", function()
            local view = openSources(openFM())
            tap(view, "Book 1")
            tap(view, "eink/more")
            tap(topWidget(), _("Edit source"))
            view.edit_rows.username.callback()
            local dialog = topWidget()
            assert.are.equal(InputDialog, getmetatable(dialog).__index)
            waitFor(function() return view.downloads["urn:uuid:book-1"] == nil end, "the download")
            assert.are.equal(dialog, topWidget())
            view:close(true)
            for _, entry in ipairs(UIManager._window_stack) do
                local class = getmetatable(entry.widget).__index
                assert.is_true(class ~= InputDialog and class ~= BottomSheet and class ~= BookSourceView)
            end
        end)

        it("closes its sheets with the page, and says a running download was canceled", function()
            local view = openSources(openFM())
            tap(view, "Book 1", true)
            local sheet = topWidget()
            assert.are.equal(BottomSheet, getmetatable(sheet).__index)
            view:close()
            assert.is_false(UIManager:isWidgetShown(sheet))

            view = openSources(FileManager.instance)
            view:turnPage(2)
            if not view:cellOf({ key = "urn:uuid:book-9" }) then view:turnPage(1) end
            tap(view, "Book 9")
            local dl = view.downloads["urn:uuid:book-9"]
            waitFor(function() return lfs.attributes(dl.part, "mode") == "file" end, "the partial file")
            view:close()
            local toast = UIManager._window_stack[#UIManager._window_stack].widget
            assert.are.equal(_("Download canceled"), toast.text)
            assert.is_nil(lfs.attributes(dl.part, "mode"))
        end)
    end)

    describe("sources", function()
        local function fill(view, key, value)
            view.edit_rows[key].callback()
            local dialog = topWidget()
            assert.are.equal(InputDialog, getmetatable(dialog).__index)
            dialog:setInputText(value)
            dialog.buttons[1][2].callback()
        end

        it("adds a source with its Access token, and puts https:// before a bare address", function()
            writeSources{}
            local fm = openFM()
            tap(fm.shelf_view, "eink/source")
            local view = topWidget()
            assert.is_true(has(view, _("No sources yet")))
            tap(view, "eink/plus")
            assert.is_false(view.save_button.enabled)
            fill(view, "title", "Library")
            fill(view, "url", "books.example/opds")
            fill(view, "access_client_id", "abc.access")
            fill(view, "access_client_secret", "s3cret")
            assert.is_true(view.save_button.enabled)
            view.save_button:onTapSelect()
            assert.are.same({ { title = "Library", url = "https://books.example/opds",
                access_client_id = "abc.access", access_client_secret = "s3cret" } }, savedSources())
            assert.is_true(has(view, "Library"))
            assert.is_true(has(view, "books.example"))
        end)

        it("edits and deletes a source from its row's ⋯ button, after a confirmation", function()
            writeSources{ nas(), { title = "Gutenberg", url = "https://gutenberg.example/opds" } }
            local fm = openFM()
            tap(fm.shelf_view, "eink/source")
            local view = topWidget()
            tap(view, "eink/more") -- the first row's
            tap(topWidget(), _("Edit"))
            fill(view, "username", "someone")
            view.save_button:onTapSelect()
            local saved = savedSources()
            assert.are.equal("someone", saved[1].username)
            assert.are.equal("token", saved[1].access_client_secret)
            assert.are.equal("NAS at home", saved[1].title)

            tap(view, "eink/more")
            tap(topWidget(), _("Delete"))
            local confirm = topWidget()
            assert.is_true(has(confirm, _("Delete source")))
            tap(confirm, _("Delete"))
            saved = savedSources()
            assert.are.equal(1, #saved)
            assert.are.equal("Gutenberg", saved[1].title)
        end)
    end)

    describe("errors", function()
        it("explains an unreachable source in the grid, and retries", function()
            server.mode = "timeout"
            local view = openSources(openFM())
            assert.is_true(has(view, _("Cannot reach the source")))
            assert.are.same({}, view.cells)
            server.mode = "ok"
            tap(view, _("Retry"))
            waitFor(function() return view:top().result.state == "ok" end, "the retry")
            assert.are.equal("Book 1", bookTitles(view)[1])
        end)

        it("offers to edit the source when the login fails", function()
            server.mode = "auth"
            local view = openSources(openFM())
            assert.is_true(has(view, _("Login failed")))
            assert.is_true(has(view, "HTTP 401 · nas.example"))
            tap(view, _("Edit source"))
            local sheet = topWidget()
            assert.are.equal(BottomSheet, getmetatable(sheet).__index)
            assert.is_true(has(sheet, _("Client Secret")))
        end)

        it("says when the answer is not OPDS, a server error, or an empty list", function()
            server.mode = "html"
            local view = openSources(openFM())
            assert.is_true(has(view, _("Not an OPDS catalog")))
            view:close(true)
            server.mode = "500"
            view = openSources(FileManager.instance)
            assert.is_true(has(view, "Server error 500"))
            view:close(true)
            server.mode = "empty"
            view = openSources(FileManager.instance)
            assert.is_true(has(view, _("No books here yet")))
        end)
    end)
end)
