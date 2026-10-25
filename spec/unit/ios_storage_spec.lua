-- B3 (#91): the iOS sandbox layout, the container moving, and books coming in as copies, with temporary
-- containers and the fake native bridge (seam C).
describe("iOS storage and imports", function()
    local BookImport, Device, FakeBridge, IosStorage, LuaSettings, UIManager
    local DataStorage, ffiUtil, lfs, util, T, _, N_
    local tmp
    local saved = {}

    local function write(path, content)
        util.makePath(ffiUtil.dirname(path))
        local f = assert(io.open(path, "wb"))
        f:write(content)
        f:close()
        return path
    end

    local function read(path)
        local f = io.open(path, "rb")
        if not f then return end
        local content = f:read("*a")
        f:close()
        return content
    end

    local function book(path, source)
        util.makePath(ffiUtil.dirname(path))
        ffiUtil.copyFile("spec/front/unit/data/" .. (source or "juliet.epub"), path)
        return path
    end

    local function exists(path)
        return lfs.attributes(path, "mode") ~= nil
    end

    -- a fresh folder under the spec's temporary one
    local n = 0
    local function fresh(name)
        n = n + 1
        local dir = string.format("%s/%s%d", tmp, name, n)
        util.makePath(dir)
        return ffiUtil.realpath(dir)
    end

    local function settingsIn(dir)
        return LuaSettings:open(dir .. "/settings.reader.lua")
    end

    setup(function()
        require("commonrequire")
        BookImport = require("apps/shelf/bookimport")
        DataStorage = require("datastorage")
        Device = require("device")
        FakeBridge = require("iosbridge")
        IosStorage = require("device/sdl/iosstorage")
        LuaSettings = require("luasettings")
        UIManager = require("ui/uimanager")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        util = require("util")
        T = ffiUtil.template
        _ = require("gettext")
        N_ = _.ngettext
        tmp = ffiUtil.realpath(DataStorage:getDataDir()) .. "/ios_storage_spec"
        ffiUtil.purgeDir(tmp)
        lfs.mkdir(tmp)
        for __, key in ipairs{ "bridge", "hasSandboxedHome" } do saved[key] = rawget(Device, key) end
        BookImport.poll_interval = 0
    end)

    teardown(function()
        for key in pairs{ bridge = true, hasSandboxedHome = true } do rawset(Device, key, saved[key]) end
        BookImport.poll_interval = 0.2
        ffiUtil.purgeDir(tmp)
    end)

    describe("layout", function()
        it("keeps the data in KO_HOME and links its cache into KO_CACHE_HOME, made again when purged", function()
            local container = fresh("container")
            local ko_home = container .. "/Library/Application Support/koreader"
            local cache_home = container .. "/Library/Caches/koreader"
            util.makePath(ko_home)
            util.makePath(container .. "/Library/Caches")
            local env = { KO_HOME = ko_home, KO_CACHE_HOME = cache_home }
            stub(os, "getenv", function(name) return env[name] end)
            local ok, err = pcall(function()
                local storage = dofile("datastorage.lua")
                assert.are.equal(ko_home, storage:getDataDir())
                assert.are.equal("link", lfs.symlinkattributes(ko_home .. "/cache", "mode"))
                assert.are.equal("directory", lfs.attributes(ko_home .. "/cache", "mode"))
                assert.are.equal("directory", lfs.attributes(ko_home .. "/settings", "mode"))
                write(ko_home .. "/cache/cr3cache/x", "rebuildable")
                assert.is_true(exists(cache_home .. "/cr3cache/x"))
                -- the system empties Library/Caches: the next start makes the target again, the data stays
                write(ko_home .. "/settings/notes.lua", "return {}")
                ffiUtil.purgeDir(cache_home)
                dofile("datastorage.lua")
                assert.are.equal("directory", lfs.attributes(ko_home .. "/cache", "mode"))
                assert.is_false(exists(ko_home .. "/cache/cr3cache/x"))
                assert.are.equal("return {}", read(ko_home .. "/settings/notes.lua"))
            end)
            os.getenv:revert()
            assert(ok, err)
        end)

        it("roots the file browser at Documents, keeps sidecars out of it, and records the container", function()
            local container = fresh("container")
            local settings = settingsIn(container)
            local home = IosStorage.setup(settings, container, container .. "/data")
            assert.are.equal(container .. "/Documents", home)
            assert.are.equal("directory", lfs.attributes(home, "mode"))
            assert.are.equal(home, settings:readSetting("home_dir"))
            assert.is_true(settings:isTrue("lock_home_folder"))
            assert.are.equal("dir", settings:readSetting("document_metadata_folder"))
            assert.are.same(IosStorage.roots(container), settings:readSetting("ios_container_roots"))
            -- flushed: the record survives a crash right after
            assert.are.same(IosStorage.roots(container), settingsIn(container):readSetting("ios_container_roots"))
            -- every start: a changed home or lock is set back; a chosen sidecar location is kept
            settings:saveSetting("home_dir", "/elsewhere")
            settings:makeFalse("lock_home_folder")
            settings:saveSetting("document_metadata_folder", "hash")
            IosStorage.setup(settings, container, container .. "/data")
            assert.are.equal(home, settings:readSetting("home_dir"))
            assert.is_true(settings:isTrue("lock_home_folder"))
            assert.are.equal("hash", settings:readSetting("document_metadata_folder"))
        end)

        it("lists no folder above the home folder in 文件, and won't go up from it", function()
            local FileChooser = require("ui/widget/filechooser")
            local home = fresh("home")
            local saved_home, saved_lock = G_reader_settings:readSetting("home_dir"), G_reader_settings:readSetting("lock_home_folder")
            G_reader_settings:saveSetting("home_dir", home)
            G_reader_settings:makeTrue("lock_home_folder")
            lfs.mkdir(home .. "/sub")
            local chooser = FileChooser:extend{ is_fm = false, refreshPath = function() end }
            chooser:changeToPath(home)
            for __, item in ipairs(chooser:genItemTableFromPath(home)) do
                assert.is_falsy(item.is_go_up)
            end
            chooser:onFolderUp()
            assert.are.equal(home, chooser.path)
            assert.is_true(chooser:genItemTableFromPath(home .. "/sub")[1].is_go_up) -- below home, as before
            G_reader_settings:saveSetting("home_dir", saved_home)
            G_reader_settings:saveSetting("lock_home_folder", saved_lock)
        end)
    end)

    describe("the container moving", function()
        -- an install in container `old` with a book, its sidecar, history, a collection, a plugin keyed by path
        -- and a cover row, then a start in container `new` with the same data (the system moved it)
        local function install()
            local old, new = fresh("old"), fresh("new")
            local data = fresh("data")
            local old_book = old .. "/Documents/sub/juliet.epub"
            write(data .. "/docsettings" .. old .. "/Documents/sub/juliet.sdr/metadata.epub.lua", "return { percent_finished = 0.5 }")
            write(data .. "/history.lua", "return " .. require("dump")({ { time = 1, file = old_book } }))
            write(data .. "/settings/collection.lua", "return " .. require("dump")({
                favorites = { [old_book] = { file = old_book, order = 1 } } }))
            write(data .. "/settings/bookshortcuts.lua", "return " .. require("dump")({ shortcuts = { [old_book] = "Juliet" } }))
            write(data .. "/settings/unrelated.lua", "return { text = 'kept', other = '/var/elsewhere' }")
            local SQ3 = require("lua-ljsqlite3/init")
            local db = SQ3.open(data .. "/settings/bookinfo_cache.sqlite3")
            db:exec("CREATE TABLE bookinfo (bcid INTEGER PRIMARY KEY, directory TEXT NOT NULL, filename TEXT NOT NULL);"
                .. "CREATE UNIQUE INDEX dir_filename ON bookinfo(directory, filename);"
                .. "INSERT INTO bookinfo (directory, filename) VALUES ('" .. old .. "/Documents/sub/', 'juliet.epub');")
            db:close()
            local settings = settingsIn(data)
            settings:saveSetting("ios_container_roots", { old })
            settings:saveSetting("lastfile", old_book)
            settings:saveSetting("lastdir", old .. "/Documents/sub")
            settings:saveSetting("download_dir", old .. "/Documents")
            settings:saveSetting("folder_shortcuts", { [old .. "/Documents/sub"] = { text = "Sub" } })
            return old, new, data, settings
        end

        local function assertMoved(old, new, data, settings)
            local new_book = new .. "/Documents/sub/juliet.epub"
            assert.are.equal("return { percent_finished = 0.5 }",
                read(data .. "/docsettings" .. new .. "/Documents/sub/juliet.sdr/metadata.epub.lua"))
            assert.is_false(exists(data .. "/docsettings" .. old .. "/Documents"))
            assert.are.same({ { time = 1, file = new_book } }, dofile(data .. "/history.lua"))
            assert.are.same({ favorites = { [new_book] = { file = new_book, order = 1 } } },
                dofile(data .. "/settings/collection.lua"))
            assert.are.same({ shortcuts = { [new_book] = "Juliet" } }, dofile(data .. "/settings/bookshortcuts.lua"))
            assert.are.same({ text = "kept", other = "/var/elsewhere" }, dofile(data .. "/settings/unrelated.lua"))
            assert.are.equal(new_book, settings:readSetting("lastfile"))
            assert.are.equal(new .. "/Documents/sub", settings:readSetting("lastdir"))
            assert.are.equal(new .. "/Documents", settings:readSetting("home_dir"))
            assert.are.same({ [new .. "/Documents/sub"] = { text = "Sub" } }, settings:readSetting("folder_shortcuts"))
            local db = require("lua-ljsqlite3/init").open(data .. "/settings/bookinfo_cache.sqlite3")
            assert.are.equal(new .. "/Documents/sub/", db:rowexec("SELECT directory FROM bookinfo;"))
            db:close()
        end

        it("moves every stored path to the new container, and records it", function()
            local old, new, data, settings = install()
            IosStorage.setup(settings, new, data)
            assertMoved(old, new, data, settings)
            assert.are.same(IosStorage.roots(new), settingsIn(data):readSetting("ios_container_roots"))
        end)

        it("leaves paths outside the container alone, and paths that only start like it", function()
            local old, new, data, settings = install()
            settings:saveSetting("screensaver_dir", old .. "-other/pictures")
            IosStorage.setup(settings, new, data)
            assert.are.equal(old .. "-other/pictures", settings:readSetting("screensaver_dir"))
        end)

        it("can run again after stopping halfway: what was moved stays, the rest follows", function()
            local old, new, data, settings = install()
            -- the first start moved this sidecar and saved a newer one, then stopped before recording the container
            write(data .. "/docsettings" .. new .. "/Documents/sub/juliet.sdr/metadata.epub.lua", "return { percent_finished = 0.5 }")
            write(data .. "/docsettings" .. old .. "/Documents/other.sdr/metadata.epub.lua", "return { percent_finished = 0.1 }")
            IosStorage.migrate(settings, { old }, { new }, data)
            IosStorage.setup(settings, new, data) -- the record still names the old container: all of it again
            assertMoved(old, new, data, settings)
            assert.are.equal("return { percent_finished = 0.1 }",
                read(data .. "/docsettings" .. new .. "/Documents/other.sdr/metadata.epub.lua"))
        end)

        it("moves each recorded form of the container (/var and /private/var) to its new form", function()
            local __, new, data, settings = install()
            local moved = {}
            stub(IosStorage, "migrate", function(__, old_roots, new_roots) moved = { old_roots, new_roots } end)
            settings:saveSetting("ios_container_roots", { "/var/mobile/A", "/private/var/mobile/A" })
            IosStorage.setup(settings, new, data)
            IosStorage.migrate:revert()
            assert.are.same({ "/var/mobile/A", "/private/var/mobile/A" }, moved[1])
            assert.are.same(IosStorage.roots(new), moved[2])
            settings = settingsIn(fresh("data"))
            settings:saveSetting("lastfile", "/private/var/mobile/A/Documents/b.epub")
            settings:saveSetting("lastdir", "/var/mobile/A/Documents")
            IosStorage.migrate(settings, { "/var/mobile/A", "/private/var/mobile/A" },
                { "/var/mobile/B", "/private/var/mobile/B" }, fresh("data"))
            assert.are.equal("/private/var/mobile/B/Documents/b.epub", settings:readSetting("lastfile"))
            assert.are.equal("/var/mobile/B/Documents", settings:readSetting("lastdir"))
        end)

        it("does nothing on the first start, or when the container stayed", function()
            local container = fresh("container")
            local settings = settingsIn(container)
            stub(IosStorage, "migrate")
            IosStorage.setup(settings, container, container .. "/data")
            IosStorage.setup(settings, container, container .. "/data")
            assert.stub(IosStorage.migrate).was.called(1) -- the second start, with nothing to move
            IosStorage.migrate:revert()
        end)
    end)

    describe("imports", function()
        local home, inbox
        before_each(function()
            home = fresh("Documents")
            inbox = fresh("Inbox")
        end)

        it("moves the system's copy into the home folder, leaving nothing behind", function()
            local src = book(inbox .. "/juliet.epub")
            local result = BookImport.receive(src, home)
            assert.are.same({ name = "juliet.epub", status = "imported", dest = home .. "/juliet.epub" }, result)
            assert.is_true(exists(home .. "/juliet.epub"))
            assert.is_false(exists(src))
        end)

        it("keeps the book already there when the same one comes again", function()
            book(home .. "/juliet.epub")
            local src = book(inbox .. "/juliet.epub")
            local result = BookImport.receive(src, home)
            assert.are.equal("duplicate", result.status)
            assert.are.equal(home .. "/juliet.epub", result.dest)
            assert.is_false(exists(src))
            assert.is_false(exists(home .. "/juliet (2).epub"))
        end)

        it("never overwrites a different book of the same name: the new one gets the first free number", function()
            local original = book(home .. "/juliet.epub", "leaves.epub")
            local before = read(original)
            book(home .. "/juliet (2).epub", "leaves.epub")
            local result = BookImport.receive(book(inbox .. "/juliet.epub"), home)
            assert.are.equal("renamed", result.status)
            assert.are.equal(home .. "/juliet (3).epub", result.dest)
            assert.are.equal(before, read(original))
            assert.are.equal(read("spec/front/unit/data/juliet.epub"), read(home .. "/juliet (3).epub"))
        end)

        it("refuses files it can't open, and says why", function()
            local src = write(inbox .. "/notes.xyz", "x")
            local result = BookImport.receive(src, home)
            assert.are.equal("failed", result.status)
            assert.are.equal(_("This type of file can't be opened."), result.reason)
            assert.is_false(exists(src))
            assert.is_false(exists(home .. "/notes.xyz"))
        end)

        it("says when a cloud file isn't on the device", function()
            local src = write(inbox .. "/.juliet.epub.icloud", "placeholder")
            local result = BookImport.receive(src, home)
            assert.are.same({ name = "juliet.epub", status = "failed",
                reason = _("It isn't downloaded to this device. Download it in the Files app, then try again.") }, result)
            assert.is_false(exists(home .. "/juliet.epub"))
        end)

        it("sweeps the inboxes into the home folder, and removes the emptied ones", function()
            local container = fresh("container")
            book(container .. "/Documents/Inbox/juliet.epub")
            book(container .. "/tmp/me.justinyan.justreader-Inbox/leaves.epub", "leaves.epub")
            local documents = container .. "/Documents"
            local results = BookImport.sweep(IosStorage.inboxes(container), documents)
            assert.are.equal(2, #results)
            assert.is_true(exists(documents .. "/juliet.epub"))
            assert.is_true(exists(documents .. "/leaves.epub"))
            assert.is_false(exists(container .. "/Documents/Inbox"))
            assert.is_false(exists(container .. "/tmp/me.justinyan.justreader-Inbox"))
        end)

        it("reports plainly when all went in, and names what was renamed, already there, or failed", function()
            local shown = {}
            stub(UIManager, "show", function(__, widget) table.insert(shown, widget) end)
            BookImport.report{ { name = "a.epub", status = "imported", dest = "/h/a.epub" } }
            BookImport.report{
                { name = "a.epub", status = "imported", dest = "/h/a.epub" },
                { name = "b.epub", status = "renamed", dest = "/h/b (2).epub" },
                { name = "c.epub", status = "duplicate", dest = "/h/c.epub" },
                { name = "d.epub", status = "failed", reason = "offline" },
            }
            BookImport.report{}
            UIManager.show:revert()
            assert.are.equal(2, #shown)
            assert.is_true(shown[1].toast)
            assert.are.equal(T(N_("Imported 1 book", "Imported %1 books", 1), 1), shown[1].text)
            local text = shown[2].text
            for __, part in ipairs{ T(N_("Imported 1 book.", "Imported %1 books.", 2), 2),
                    T(_("A different book named %1 is already here, so this one was saved as %2."), "b.epub", "b (2).epub"),
                    T(_("%1 is already here."), "c.epub"), T(_("Could not import %1: %2"), "d.epub", "offline") } do
                assert.is_truthy(text:find(part, 1, true), part)
            end
        end)
    end)

    describe("the document picker", function()
        local home, inbox, shown, broadcast

        before_each(function()
            home, inbox = fresh("Documents"), fresh("tmp-Inbox")
            shown, broadcast = {}, {}
            stub(UIManager, "show", function(__, widget) table.insert(shown, widget) end)
            stub(UIManager, "broadcastEvent", function(__, event) table.insert(broadcast, event.handler) end)
        end)

        after_each(function()
            UIManager.show:revert()
            UIManager.broadcastEvent:revert()
            rawset(Device, "bridge", saved.bridge)
        end)

        local function pickWith(picks)
            local bridge = FakeBridge.new{ picks = picks }
            rawset(Device, "bridge", bridge)
            BookImport.pick(home)
            UIManager:_checkTasks()
            return bridge
        end

        it("asks for the extensions that open, then moves the picked copies in and refreshes the shelf", function()
            local picked = book(inbox .. "/juliet.epub")
            local bridge = pickWith{ {
                { state = "pending" },
                { state = "picked", paths = { picked }, errors = { ["far.epub"] = "The file couldn't be downloaded." } },
            } }
            local extensions = bridge.picker_requests[1].extensions
            assert.is_truthy(util.arrayContains(extensions, "epub"))
            assert.is_truthy(util.arrayContains(extensions, "pdf"))
            assert.is_true(exists(home .. "/juliet.epub"))
            assert.is_false(exists(picked))
            assert.are.same({ "BooksImported" }, broadcast)
            assert.are.equal(1, #shown)
            assert.is_truthy(shown[1].text:find(T(_("Could not import %1: %2"), "far.epub",
                "The file couldn't be downloaded."), 1, true))
            assert.are.same({ state = "idle" }, bridge.pickFilesPoll())
        end)

        it("does nothing when cancelled, and says why when the picker fails", function()
            pickWith{ { { state = "pending" }, { state = "cancelled" } } }
            assert.are.same({}, shown)
            assert.are.same({}, broadcast)
            pickWith{ { { state = "failed", error = "no window" } } }
            assert.are.equal(T(_("Could not import: %1"), "no window"), shown[1].text)
        end)

        it("says so when no picker can be shown", function()
            rawset(Device, "bridge", require("device/sdl/iosbridge").new())
            BookImport.pick(home)
            assert.are.equal(T(_("Could not show the file picker: %1"), "unsupported"), shown[1].text)
        end)
    end)

    describe("Open with", function()
        local home, inbox, opened
        before_each(function()
            home, inbox = fresh("Documents"), fresh("Inbox")
            opened = {}
            stub(require("apps/reader/readerui"), "doShowReader", function(__, file) table.insert(opened, file) end)
        end)
        after_each(function()
            require("apps/reader/readerui").doShowReader:revert()
        end)

        it("moves the system's copy into the home folder and opens it there", function()
            local src = book(inbox .. "/juliet.epub")
            BookImport.open(src, home)
            assert.are.same({ home .. "/juliet.epub" }, opened)
            assert.is_false(exists(src))
        end)

        it("opens the book swept in already when its event comes late, and the same book again as it is", function()
            local src = book(inbox .. "/juliet.epub")
            BookImport.sweep({ inbox }, home)
            BookImport.open(src, home)
            BookImport.open(book(inbox .. "/juliet.epub"), home)
            assert.are.same({ home .. "/juliet.epub", home .. "/juliet.epub" }, opened)
            assert.is_false(exists(home .. "/juliet (2).epub"))
        end)
    end)
end)
