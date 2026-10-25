describe("atomic settings persistence", function()
    local LuaSettings, DocSettings, ffiutil, lfs, util
    local directory, path, original_open, original_rename, original_sync, original_location

    local function revertStub(object, key)
        local value = rawget(object, key)
        if type(value) == "table" and value.revert then value:revert() end
    end

    setup(function()
        require("commonrequire")
        LuaSettings = require("luasettings")
        DocSettings = require("docsettings")
        ffiutil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        util = require("util")
    end)

    before_each(function()
        original_location = G_reader_settings:readSetting("document_metadata_folder")
        G_reader_settings:saveSetting("document_metadata_folder", "doc")
        directory = os.tmpname()
        os.remove(directory)
        assert(lfs.mkdir(directory))
        path = directory .. "/settings.lua"
        original_open, original_rename = io.open, os.rename
        original_sync = ffiutil.fsyncOpenedFile
    end)

    after_each(function()
        G_reader_settings:saveSetting("document_metadata_folder", original_location)
        revertStub(io, "open")
        revertStub(os, "rename")
        revertStub(ffiutil, "fsyncOpenedFile")
        revertStub(ffiutil, "fsyncDirectory")
        ffiutil.purgeDir(directory)
    end)

    local function seed()
        local settings = LuaSettings:open(path):saveSetting("position", 10)
        assert(settings:flush())
        return settings
    end

    it("replaces a complete version and retains the 60-second backup policy", function()
        local settings = seed()
        settings:saveSetting("position", 20)
        assert(settings:flush())
        assert.is_nil(lfs.attributes(path .. ".old"))
        assert(lfs.touch(path, os.time() - 120, os.time() - 120))
        settings:saveSetting("position", 30)
        assert(settings:flush())
        assert.are.equal(30, LuaSettings:open(path):readSetting("position"))
        assert.are.equal(20, LuaSettings:open(path .. ".old"):readSetting("position"))
        settings:saveSetting("position", 40)
        assert(settings:flush())
        assert.are.equal(20, LuaSettings:open(path .. ".old"):readSetting("position"))
    end)

    for _, stage in ipairs{ "open", "write", "flush", "fsync", "close" } do
        it("preserves the target when temporary file " .. stage .. " fails", function()
            local settings = seed()
            assert(lfs.touch(path, os.time() - 120, os.time() - 120))
            local bytes = util.readFromFile(path)
            local proxy, backing
            stub(io, "open", function(filename, mode)
                if filename ~= path .. ".tmp" then return original_open(filename, mode) end
                if stage == "open" then return nil, "disk full" end
                backing = assert(original_open(filename, mode))
                proxy = {
                    write = function(_, data)
                        if stage == "write" then
                            backing:write(data:sub(1, 8))
                            return nil, "disk full"
                        end
                        return backing:write(data)
                    end,
                    flush = function()
                        if stage == "flush" then return nil, "disk full" end
                        return backing:flush()
                    end,
                    close = function()
                        local ok, err = backing:close()
                        if stage == "close" then return nil, "close failed" end
                        return ok, err
                    end,
                }
                return proxy
            end)
            stub(ffiutil, "fsyncOpenedFile", function(file, metadata)
                if stage == "fsync" then return false, "sync failed" end
                return original_sync(file == proxy and backing or file, metadata)
            end)
            settings:saveSetting("position", 20)
            local ok, err = settings:flush()
            assert.is_nil(ok)
            assert.is_string(err)
            assert.are.equal(bytes, util.readFromFile(path))
            assert.are.equal(10, LuaSettings:open(path):readSetting("position"))
            assert.is_nil(lfs.attributes(path .. ".old"))
            assert.is_nil(lfs.attributes(path .. ".tmp"))
        end)
    end

    for _, aged in ipairs{ false, true } do
        it("restores the previous target on replacement failure (aged=" .. tostring(aged) .. ")", function()
            local settings = seed()
            if aged then assert(lfs.touch(path, os.time() - 120, os.time() - 120)) end
            local bytes = util.readFromFile(path)
            stub(os, "rename", function(from, to)
                if from == path .. ".tmp" then return nil, "rename denied" end
                return original_rename(from, to)
            end)
            local ok, err = settings:saveSetting("position", 20):flush()
            assert.is_nil(ok)
            assert.matches("rename denied", err)
            assert.are.equal(bytes, util.readFromFile(path))
            assert.is_nil(lfs.attributes(path .. ".tmp"))
        end)
    end

    it("does not replace the target if the backup rename fails", function()
        local settings = seed()
        assert(lfs.touch(path, os.time() - 120, os.time() - 120))
        stub(os, "rename", function() return nil, "backup denied" end)
        assert.is_nil(settings:saveSetting("position", 20):flush())
        assert.are.equal(10, LuaSettings:open(path):readSetting("position"))
    end)

    it("retains a readable backup if both replacement and rollback fail", function()
        local settings = seed()
        assert(lfs.touch(path, os.time() - 120, os.time() - 120))
        stub(os, "rename", function(from, to)
            if to == path then return nil, "rename denied" end
            return original_rename(from, to)
        end)
        local ok, err = settings:saveSetting("position", 20):flush()
        assert.is_nil(ok)
        assert.matches("backup retained", err)
        assert.are.equal(10, LuaSettings:open(path):readSetting("position"))
    end)

    it("can reopen the backup if interrupted between the two renames", function()
        seed()
        assert(os.rename(path, path .. ".old"))
        assert(util.writeToFile("unfinished", path .. ".tmp"))
        assert.are.equal(10, LuaSettings:open(path):readSetting("position"))
        assert(LuaSettings:open(path):saveSetting("position", 20):flush())
        assert.are.equal(20, LuaSettings:open(path):readSetting("position"))
        assert.is_nil(lfs.attributes(path .. ".tmp"))
    end)

    it("accepts a committed replacement when directory sync is unsupported", function()
        local settings = seed()
        stub(ffiutil, "fsyncDirectory", function() return false, "directory sync failed" end)
        local ok, err = settings:saveSetting("position", 20):flush()
        assert.are.equal(settings, ok)
        assert.is_nil(err)
        assert.are.equal(20, LuaSettings:open(path):readSetting("position"))
    end)

    it("keeps sidecar candidates on failure and reads .old after an interrupted backup", function()
        local book = directory .. "/book.epub"
        local settings = DocSettings:open(book)
        assert(settings:saveSetting("position", 10):flush())
        local sidecar = settings.doc_sidecar_dir .. "/" .. settings.sidecar_filename
        local original_bytes = util.readFromFile(sidecar)
        stub(os, "rename", function(from, to)
            if from == sidecar .. ".tmp" or to:match("metadata%.epub%.lua$") then
                return nil, "storage unavailable"
            end
            return original_rename(from, to)
        end)
        local ok, err = settings:saveSetting("position", 20):flush()
        assert.is_nil(ok)
        assert.is_string(err)
        assert.are.equal(original_bytes, util.readFromFile(sidecar))
        os.rename:revert()
        assert(os.rename(sidecar, sidecar .. ".old"))
        assert.are.equal(10, DocSettings:open(book):readSetting("position"))
        settings:purge()
    end)

    it("purges old candidates after a committed sidecar even if directory sync fails", function()
        local book = directory .. "/book.epub"
        local settings = DocSettings:open(book)
        assert(settings:saveSetting("position", 10):flush())
        settings = DocSettings:open(book)
        local old_sidecar = settings.doc_sidecar_dir .. "/" .. settings.sidecar_filename
        G_reader_settings:saveSetting("document_metadata_folder", "dir")
        stub(ffiutil, "fsyncDirectory", function() return false, "directory sync failed" end)
        assert.are.equal(settings.dir_sidecar_dir, settings:saveSetting("position", 20):flush())
        assert.is_nil(lfs.attributes(old_sidecar))
        assert.is_nil(lfs.attributes(old_sidecar .. ".old"))
        assert.are.equal(20, DocSettings:open(book):readSetting("position"))
        DocSettings:open(book):purge()
    end)

    for _, has_candidate in ipairs{ false, true } do
        it("purges interrupted sidecar temporaries (candidate=" .. tostring(has_candidate) .. ")", function()
            local book = directory .. "/book.epub"
            local settings = DocSettings:open(book)
            if has_candidate then assert(settings:saveSetting("position", 10):flush()) end
            local sidecar_dir = settings.doc_sidecar_dir
            util.makePath(sidecar_dir)
            local temporary = sidecar_dir .. "/" .. settings.sidecar_filename .. ".tmp"
            assert(util.writeToFile("unfinished", temporary))
            DocSettings:open(book):purge()
            assert.is_nil(lfs.attributes(temporary))
            assert.is_nil(lfs.attributes(sidecar_dir))
        end)
    end

    it("preserves the 60-second sidecar backup and rejects a failed file sync", function()
        local book = directory .. "/book.epub"
        local settings = DocSettings:open(book)
        assert(settings:saveSetting("position", 10):flush())
        local sidecar = settings.doc_sidecar_dir .. "/" .. settings.sidecar_filename
        assert(lfs.touch(sidecar, os.time() - 120, os.time() - 120))
        assert(settings:saveSetting("position", 20):flush())
        assert.are.equal(10, LuaSettings:open(sidecar .. ".old"):readSetting("position"))
        stub(ffiutil, "fsyncOpenedFile", function() return false, "sync failed" end)
        local ok, err = settings:saveSetting("position", 30):flush()
        assert.is_nil(ok)
        assert.matches("sync failed", err)
        assert.are.equal(20, DocSettings:open(book):readSetting("position"))
        assert.are.equal(10, LuaSettings:open(sidecar .. ".old"):readSetting("position"))
        settings:purge()
    end)
end)
