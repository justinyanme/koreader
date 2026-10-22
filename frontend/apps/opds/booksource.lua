--[[--
A 书源 (see CONTEXT.md): an OPDS server the user added, browsed as a remote shelf.

Data only, no widgets. Sources are the OPDS plugin's server records, with the
redesign's own fields:

    access_client_id, access_client_secret  Cloudflare Access service token, sent with every request
    download_dir                            where books land, defaults to the home folder
    downloaded                              { [entry id or acquisition href] = local path }

Every request (feeds, thumbnails, downloads) goes through the plugin's
OPDSClient with the source's cookies, Basic auth and token; the client sends the
credentials to the source's own origin only. Feeds are parsed by the original
browser's parser (opdsbrowser.lua), which stays untouched.

The OPDS plugin's modules are required lazily: this module loads even when the
plugin is disabled.
]]

local BookList = require("ui/widget/booklist")
local DataStorage = require("datastorage")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local md5 = require("ffi/sha2").md5
local socketutil = require("socketutil")
local url = require("socket.url")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local BookSource = {
    thumb_dir = DataStorage:getDataDir() .. "/cache/opds-thumbs",
    thumb_cache_limit = 50 * 1024 * 1024,
    -- download format preference; other formats come after these
    formats = { "epub", "azw3", "mobi", "fb2", "pdf" },
    -- feed requests give up quickly, so a dead tunnel shows "unreachable" instead of a hang
    block_timeout = 10,
    total_timeout = 30,
}

local SORT_NEW = "http://opds-spec.org/sort/new"
local clients = {} -- by source URL: one cookie jar per source for the session

local function browser()
    return require("opdsbrowser")
end

--- The source's host, shown in gray beside its name.
function BookSource.host(source)
    local parsed = url.parse(source.url or "")
    return parsed and parsed.host or source.url
end

function BookSource.hasLogin(source)
    return source.username ~= nil or source.access_client_id ~= nil
end

--- The URL as typed, with https:// when it has no scheme.
function BookSource.normalizeUrl(str)
    str = util.trim(str)
    return str:match("^%a[%w+.-]*://") and str or "https://" .. str
end

function BookSource.downloadDir(source)
    return source.download_dir or G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
end

--- Writes the plugin's settings file now, so sources and downloads survive a crash.
function BookSource.save(opds)
    opds.settings:saveSetting("servers", opds.servers)
    opds.settings:flush()
    opds.updated = nil
end

--- Request fields for `source`: Basic auth and the Access token headers (see OPDSClient).
function BookSource.authorize(source, request)
    request.username = source.username
    request.password = source.password
    if source.access_client_id then
        request.auth_headers = {
            ["CF-Access-Client-Id"] = source.access_client_id,
            ["CF-Access-Client-Secret"] = source.access_client_secret,
        }
    end
    return request
end

function BookSource.request(source, request)
    local client = clients[source.url]
    if not client then
        client = require("opdsclient"):new{ cookie_jar = require("cookiejar"):new() }
        clients[source.url] = client
    end
    return client:request(BookSource.authorize(source, request))
end

--- Sorts an HTTP outcome into the states the page shows:
-- "ok", "unreachable" (no answer), "auth" (401/403), "http" (other status) or "not_opds".
function BookSource.failure(code, status, block_timeout, total_timeout)
    if code == 401 or code == 403 then
        return { state = "auth", code = code }
    elseif type(code) ~= "number" then
        return { state = "unreachable", detail = socketutil.describe_error(code, block_timeout, total_timeout) or status or code }
    end
    return { state = "http", code = code, detail = status }
end

--- GETs and parses a feed: { state = "ok", catalog } or a failure state.
function BookSource.fetch(source, feed_url)
    local sink = {}
    local block_timeout, total_timeout = socketutil:set_timeout(BookSource.block_timeout, BookSource.total_timeout)
    local code, _headers, status = BookSource.request(source, {
        url = feed_url,
        headers = { ["Accept-Encoding"] = "identity", ["Accept"] = browser().opds20_feed },
        sink = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.info("BookSource: cannot get", feed_url, code, status)
        return BookSource.failure(code, status, block_timeout, total_timeout)
    end
    local body = table.concat(sink)
    local ok, catalog
    if body:match("^%s*{") then
        ok, catalog = pcall(require("json").decode, body)
        if ok and type(catalog) == "table" then catalog.is_opds2 = true end
    else
        ok, catalog = pcall(require("opdsparser").parse, require("opdsparser"), body)
    end
    if not ok or type(catalog) ~= "table" or not (catalog.is_opds2 or catalog.feed or catalog.OpenSearchDescription) then
        return { state = "not_opds" }
    end
    return { state = "ok", catalog = catalog }
end

local function textOf(value)
    if type(value) == "table" then
        value = value.div or value[1]
    end
    return type(value) == "string" and value ~= "" and value or nil
end

local function filetype(link)
    local ext = browser().getFiletype(link)
    return ext and ext:lower()
end

-- Downloadable formats of an item, preferred first: { ext, href, type, size }.
local function formatsOf(item, lengths)
    local formats = {}
    for _, acquisition in ipairs(item.acquisitions or {}) do
        local ext = acquisition.href and filetype(acquisition)
        if ext and not acquisition.count then -- not a PSE stream
            table.insert(formats, { ext = ext, href = acquisition.href, type = acquisition.type,
                size = tonumber(lengths[acquisition.href]) })
        end
    end
    local rank = {}
    for i, ext in ipairs(BookSource.formats) do rank[ext] = i end
    table.sort(formats, function(a, b)
        local ra, rb = rank[a.ext] or #BookSource.formats + 1, rank[b.ext] or #BookSource.formats + 1
        if ra ~= rb then return ra < rb end
        return a.href < b.href
    end)
    return formats
end

--- Loads a feed as a page: { state = "ok", title, books, navs, next, search_url, facets, sort_new } or a failure state.
-- books: { key, title, author, summary, thumbnail, formats, language, year }
-- navs: { title, url, summary, acquisition } -- acquisition: the link says the feed is a book list
function BookSource.load(source, feed_url)
    local result = BookSource.fetch(source, feed_url)
    if result.state ~= "ok" then return result end
    local catalog = result.catalog
    -- the original parser, with feeds it needs (the search description) fetched the same way
    local parser = setmetatable({
        parseFeed = function(_, u) return BookSource.fetch(source, u).catalog end,
    }, { __index = browser() })
    local items
    if catalog.is_opds2 then
        items = browser().genItemTableFromCatalog2(parser, catalog, feed_url)
    else
        items = browser().genItemTableFromCatalog(parser, catalog, feed_url)
    end
    local feed = catalog.feed or {}
    -- genItemTableFromCatalog makes exactly one item per feed entry, in order (OPDS 1.x only)
    local entries = not catalog.is_opds2 and feed.entry or {}
    local page = {
        state = "ok",
        url = feed_url,
        title = textOf(feed.title) or catalog.metadata and catalog.metadata.title,
        books = {},
        navs = {},
        next = items.hrefs and items.hrefs.next,
        search_url = parser.search_url,
        facets = parser.facet_groups,
        sort_new = items.hrefs and items.hrefs[SORT_NEW],
    }
    for i, item in ipairs(items) do
        local entry = entries[i] or {}
        local lengths, kind_acquisition = {}, false
        for _, link in ipairs(entry.link or {}) do
            local href = link.href and url.absolute(feed_url, link.href)
            if href then
                lengths[href] = link.length
                if link.rel == SORT_NEW then page.sort_new = page.sort_new or href end
                if link.type and link.type:find("kind=acquisition", 1, true) then kind_acquisition = true end
            end
        end
        local formats = formatsOf(item, lengths)
        local summary = textOf(item.content)
        summary = summary and util.htmlToPlainTextIfHtml(summary)
        if #formats > 0 then
            local issued = textOf(entry["dcterms:issued"]) or textOf(entry.published)
            local author = item.author ~= _("Unknown Author") and item.author or nil
            table.insert(page.books, {
                key = textOf(entry.id) or formats[1].href,
                title = item.title or _("Unknown"),
                author = author,
                authors = author, -- for the typographic cover
                summary = summary,
                thumbnail = item.thumbnail or item.image,
                formats = formats,
                language = textOf(entry["dc:language"]) or textOf(entry["dcterms:language"]),
                year = issued and issued:match("^(%d%d%d%d)"),
            })
        elseif item.url then
            table.insert(page.navs, { title = item.title or item.text, url = item.url, summary = summary,
                acquisition = kind_acquisition })
        end
    end
    return page
end

--- The feed shown as a source's home: its "newest" list, else its first book list.
-- nil when the root has neither: the root is then shown as a list of categories.
function BookSource.homeUrl(root)
    if root.sort_new then return root.sort_new end
    if #root.books > 0 then return root.url end
    for _, nav in ipairs(root.navs) do
        if nav.acquisition then return nav.url end
    end
end

--- The search URL for `query`, or nil when the source has no search.
function BookSource.searchUrl(page, query)
    if not page.search_url then return end
    local encoded = util.urlEncode(query)
    return (page.search_url:gsub("%%s", function() return encoded end))
end

--- "Author - Title.ext", without characters file systems refuse.
function BookSource.fileName(book, format, dir)
    local name = book.author and book.author .. " - " .. book.title or book.title
    return util.getSafeFilename(name .. "." .. format.ext, dir)
end

--- The local file of a book downloaded from this source, while it exists.
function BookSource.localFile(source, book)
    local file = source.downloaded and source.downloaded[book.key]
    return file and lfs.attributes(file, "mode") == "file" and file or nil
end

--- Reading state of a local file: nil (never opened), or { status, percent }.
function BookSource.progress(file)
    local info = BookList.getBookInfo(file)
    if info.been_opened then
        return { status = info.status, percent = info.percent_finished or 0 }
    end
end

function BookSource.recordDownload(opds, source, book, file)
    source.downloaded = source.downloaded or {}
    source.downloaded[book.key] = file
    BookSource.save(opds)
end

-- Thumbnails: a disk cache keyed by URL, trimmed to its size limit oldest first.

function BookSource.thumbPath(thumb_url)
    return BookSource.thumb_dir .. "/" .. md5(thumb_url)
end

--- The cached thumbnail of `thumb_url`, marked as recently used; nil when not cached.
function BookSource.cachedThumb(thumb_url)
    local path = BookSource.thumbPath(thumb_url)
    if lfs.attributes(path, "mode") == "file" then
        lfs.touch(path)
        return path
    end
end

--- Downloads thumbnails into the cache (meant for a subprocess); one that fails is skipped.
function BookSource.fetchThumbs(source, thumb_urls)
    util.makePath(BookSource.thumb_dir)
    for _, thumb_url in ipairs(thumb_urls) do
        local path = BookSource.thumbPath(thumb_url)
        local file = io.open(path .. ".part", "wb")
        if file then
            socketutil:set_timeout(BookSource.block_timeout, BookSource.total_timeout)
            local code = BookSource.request(source, { url = thumb_url, sink = ltn12.sink.file(file) })
            socketutil:reset_timeout()
            if code == 200 then
                os.rename(path .. ".part", path)
            else
                os.remove(path .. ".part")
            end
        end
    end
end

function BookSource.trimThumbs()
    local files, total = {}, 0
    local ok, iter, dir_obj = pcall(lfs.dir, BookSource.thumb_dir)
    if not ok then return end
    for name in iter, dir_obj do
        local path = BookSource.thumb_dir .. "/" .. name
        local attr = lfs.attributes(path)
        if attr and attr.mode == "file" then
            table.insert(files, { path = path, size = attr.size, time = attr.modification })
            total = total + attr.size
        end
    end
    table.sort(files, function(a, b) return a.time < b.time end)
    for _, f in ipairs(files) do
        if total <= BookSource.thumb_cache_limit then break end
        os.remove(f.path)
        total = total - f.size
    end
end

--- Downloads `format` to `part` (meant for a subprocess). Calls `on_size(bytes or nil, server_name)`
-- once the size is known (from a HEAD request), and returns the HTTP code and status.
function BookSource.downloadTo(source, format, part, on_size)
    local parser_headers
    local parser = setmetatable({
        fetchFeed = function(_, u)
            local _code, headers = BookSource.request(source, { url = u, method = "HEAD",
                headers = { ["Accept-Encoding"] = "identity" } })
            parser_headers = headers
            return headers
        end,
    }, { __index = browser() })
    local server_name = browser().getServerFileName(parser, format.href, format.ext)
    local length = parser_headers and tonumber(parser_headers["content-length"])
    on_size(length or format.size, server_name)
    local file = io.open(part, "wb")
    if not file then return nil, "cannot write " .. part end
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _headers, status = BookSource.request(source, {
        url = format.href,
        headers = { ["Accept-Encoding"] = "identity" },
        sink = ltn12.sink.file(file),
    })
    socketutil:reset_timeout()
    return code, status
end

--- What a failed request means for the reader, in one line.
function BookSource.failureText(result)
    if result.state == "auth" then
        return _("Login failed. Check the source's username, password or Access token.")
    elseif result.state == "unreachable" then
        return _("Cannot reach the source. Check the NAS and the network.")
    elseif result.state == "not_opds" then
        return _("The server's answer is not an OPDS catalog. Check the address.")
    elseif result.state == "offline" then
        return _("Not connected.")
    end
    return T(_("The server answered with status %1."), result.code)
end

return BookSource
