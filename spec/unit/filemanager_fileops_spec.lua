describe("FileManager in-process file operations", function()
    local Device, FileManager, FileManagerUtil, UIManager, ffiUtil, lfs
    local root

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        Device = require("device")
        FileManager = require("apps/filemanager/filemanager")
        FileManagerUtil = require("apps/filemanager/filemanagerutil")
        UIManager = require("ui/uimanager")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
    end)

    before_each(function()
        root = os.tmpname()
        os.remove(root)
        assert(lfs.mkdir(root))
        root = ffiUtil.realpath(root)
        stub(Device, "canForkProcesses", function() return false end)
        stub(ffiUtil, "execute", function() error("unexpected exec") end)
        stub(ffiUtil, "fsyncOpenedFile", function() return true end)
        stub(ffiUtil, "fsyncDirectory", function() return true end)
    end)

    after_each(function()
        Device.canForkProcesses:revert()
        ffiUtil.execute:revert()
        ffiUtil.fsyncOpenedFile:revert()
        ffiUtil.fsyncDirectory:revert()
        -- purgeDir follows symlinks, so remove these fixtures before their targets.
        os.remove(root .. "/.koreader-fileop-1-5")
        os.remove(root .. "/.koreader-fileop-1-6/.owner")
        os.remove(root .. "/link")
        os.remove(root .. "/dangling")
        os.remove(root .. "/tree/loop")
        ffiUtil.purgeDir(root)
    end)

    local function write(path, content)
        local file = assert(io.open(root .. "/" .. path, "wb"))
        assert(file:write(content))
        assert(file:close())
        return root .. "/" .. path
    end

    local function read(path)
        local file = assert(io.open(root .. "/" .. path, "rb"))
        local content = file:read("*a")
        assert(file:close())
        return content
    end

    local function entries(path)
        local names = {}
        for name in lfs.dir(root .. (path and "/" .. path or "")) do
            if name ~= "." and name ~= ".." then names[#names + 1] = name end
        end
        table.sort(names)
        return names
    end

    local function ownership(path)
        local fullpath = root .. "/" .. path
        local attr = assert(lfs.symlinkattributes(fullpath))
        return "KOReader FileManager staging v1\n" .. fullpath .. "\n" .. string.format("%.0f:%.0f\n", attr.dev, attr.ino)
    end

    it("copies a binary file in chunks and preserves its modification time", function()
        local content = string.rep("book\0\255", 40000)
        local source = write("source", content)
        assert(lfs.touch(source, 1234567890, 1234567890))
        assert.is_true(FileManager:copyFileFromTo(source, root .. "/copy"))
        assert.are.equal(content, read("copy"))
        assert.are.equal(1234567890, lfs.attributes(root .. "/copy", "modification"))
        assert.are.same({ "copy", "source" }, entries())
        assert.stub(ffiUtil.execute).was_not_called()
    end)

    it("atomically replaces an existing file only after its contents are complete", function()
        local source = write("source", "new book")
        write("target", "old book")
        local rename = os.rename
        local replace = stub(os, "rename", function(from, to)
            if to == root .. "/target" then
                assert.are.equal("old book", read("target"))
                local file = assert(io.open(from, "rb"))
                assert.are.equal("new book", file:read("*a"))
                file:close()
            end
            return rename(from, to)
        end)
        finally(function() replace:revert() end)
        assert.is_true(FileManager:copyFileFromTo(source, root .. "/target"))
        assert.are.equal("new book", read("target"))
        assert.are.same({ "source", "target" }, entries())
    end)

    it("keeps the old file and removes temporary output if publication fails", function()
        local source = write("source", "new")
        write("target", "old")
        local rename = stub(os, "rename", function() return nil, "rename failed" end)
        finally(function() rename:revert() end)
        assert.is_false(FileManager:copyFileFromTo(source, root .. "/target"))
        assert.are.equal("old", read("target"))
        assert.are.equal("new", read("source"))
        assert.are.same({ "source", "target" }, entries())
    end)

    it("moves files by rename and resolves a destination directory like mv", function()
        local source = write("source", "book")
        assert(lfs.mkdir(root .. "/dest"))
        assert.is_true(FileManager:moveFile(source, root .. "/dest"))
        assert.is_nil(lfs.attributes(source))
        assert.are.equal("book", read("dest/source"))
    end)

    it("copies then deletes a file when rename fails across filesystems", function()
        local source = write("source", "book")
        write("target", "old")
        local rename = os.rename
        local fail_source_rename = stub(os, "rename", function(from, to)
            if from == source then return nil, "cross-device link" end
            return rename(from, to)
        end)
        finally(function() fail_source_rename:revert() end)
        assert.is_true(FileManager:moveFile(source, root .. "/target"))
        assert.is_nil(lfs.attributes(source))
        assert.are.equal("book", read("target"))
        assert.are.same({ "target" }, entries())
    end)

    it("syncs every copied file, the tree and its published parent before deleting a moved source", function()
        assert(lfs.mkdir(root .. "/source"))
        assert(lfs.mkdir(root .. "/source/nested"))
        write("source/a", "first")
        write("source/nested/b", "second")
        local synced_files, synced_dirs, published = 0, {}, false
        ffiUtil.fsyncOpenedFile:revert()
        stub(ffiUtil, "fsyncOpenedFile", function(file, metadata)
            assert.is_true(metadata)
            assert.is_truthy(file:seek()) -- The writable file is still open.
            synced_files = synced_files + 1
            return true
        end)
        ffiUtil.fsyncDirectory:revert()
        stub(ffiUtil, "fsyncDirectory", function(path)
            synced_dirs[path] = true
            if path == root then assert.is_true(published) end
            return true
        end)
        local rename, remove = os.rename, os.remove
        local publish = stub(os, "rename", function(from, to)
            if from == root .. "/source" then return nil, "cross-device link" end
            assert.are.equal(2, synced_files)
            assert.is_true(synced_dirs[from])
            assert.is_true(synced_dirs[from .. "/nested"])
            local ok, err = rename(from, to)
            published = ok == true
            return ok, err
        end)
        local delete = stub(os, "remove", function(path)
            if path:sub(1, #root + 8) == root .. "/source/" then
                assert.is_true(published)
                assert.is_true(synced_dirs[root])
            end
            return remove(path)
        end)
        finally(function()
            publish:revert()
            delete:revert()
        end)
        assert.is_true(FileManager:moveFile(root .. "/source", root .. "/target"))
        assert.is_nil(lfs.attributes(root .. "/source"))
        assert.are.equal("first", read("target/a"))
        assert.are.equal("second", read("target/nested/b"))
    end)

    it("keeps the source and old destination when syncing copied data fails", function()
        local source = write("source", "new book")
        write("target", "old book")
        ffiUtil.fsyncOpenedFile:revert()
        stub(ffiUtil, "fsyncOpenedFile", function() return false, "fsync failed" end)
        local rename = os.rename
        local cross_volume = stub(os, "rename", function(from, to)
            if from == source then return nil, "cross-device link" end
            return rename(from, to)
        end)
        finally(function() cross_volume:revert() end)
        assert.is_false(FileManager:moveFile(source, root .. "/target"))
        assert.are.equal("new book", read("source"))
        assert.are.equal("old book", read("target"))
        assert.are.same({ "source", "target" }, entries())
    end)

    it("does not publish a directory if syncing its copied entries fails", function()
        assert(lfs.mkdir(root .. "/source"))
        write("source/book", "book")
        ffiUtil.fsyncDirectory:revert()
        stub(ffiUtil, "fsyncDirectory", function() return false, "directory fsync failed" end)
        local rename = os.rename
        local cross_volume = stub(os, "rename", function(from, to)
            if from == root .. "/source" then return nil, "cross-device link" end
            return rename(from, to)
        end)
        finally(function() cross_volume:revert() end)
        assert.is_false(FileManager:moveFile(root .. "/source", root .. "/target"))
        assert.are.equal("book", read("source/book"))
        assert.are.same({ "source" }, entries())
    end)

    it("retains both complete copies if syncing the published parent fails", function()
        local source = write("source", "book")
        ffiUtil.fsyncDirectory:revert()
        stub(ffiUtil, "fsyncDirectory", function() return false, "directory fsync failed" end)
        local rename = os.rename
        local cross_volume = stub(os, "rename", function(from, to)
            if from == source then return nil, "cross-device link" end
            return rename(from, to)
        end)
        finally(function() cross_volume:revert() end)
        assert.is_false(FileManager:moveFile(source, root .. "/target"))
        assert.are.equal("book", read("source"))
        assert.are.equal("book", read("target"))
        assert.are.same({ "source", "target" }, entries())
    end)

    it("cleans marked abandoned stages but preserves namesakes, symlinks and foreign entries", function()
        local stale = ".koreader-fileop-1-1"
        assert(lfs.mkdir(root .. "/" .. stale))
        write(stale .. "/.owner", ownership(stale))
        write(stale .. "/payload", "partial")
        local namesake = ".koreader-fileop-1-2"
        assert(lfs.mkdir(root .. "/" .. namesake))
        write(namesake .. "/payload", "user data")
        local wrong_marker = ".koreader-fileop-1-3"
        assert(lfs.mkdir(root .. "/" .. wrong_marker))
        write(wrong_marker .. "/.owner", "not ours")
        local foreign = ".koreader-fileop-1-4"
        assert(lfs.mkdir(root .. "/" .. foreign))
        write(foreign .. "/.owner", ownership(foreign))
        write(foreign .. "/user-book", "keep")
        assert(lfs.mkdir(root .. "/user"))
        write("user/.owner", ownership("user"))
        write("user/payload", "keep")
        assert(lfs.link(root .. "/user", root .. "/.koreader-fileop-1-5", true))
        assert(lfs.mkdir(root .. "/.koreader-fileop-1-6"))
        assert(lfs.link(root .. "/user/.owner", root .. "/.koreader-fileop-1-6/.owner", true))
        local source = write("source", "book")
        assert.is_true(FileManager:copyFileFromTo(source, root .. "/target"))
        assert.is_nil(lfs.symlinkattributes(root .. "/" .. stale))
        assert.are.equal("user data", read(namesake .. "/payload"))
        assert.are.equal("not ours", read(wrong_marker .. "/.owner"))
        assert.are.equal("keep", read(foreign .. "/user-book"))
        assert.are.equal("link", lfs.symlinkattributes(root .. "/.koreader-fileop-1-5", "mode"))
        assert.are.equal("link", lfs.symlinkattributes(root .. "/.koreader-fileop-1-6/.owner", "mode"))
        assert.are.equal("keep", read("user/payload"))
    end)

    it("never reaps its source when it happens to look like an abandoned stage", function()
        local source = ".koreader-fileop-1-1"
        assert(lfs.mkdir(root .. "/" .. source))
        write(source .. "/.owner", ownership(source))
        write(source .. "/payload", "book")
        assert.is_true(FileManager:copyRecursive(root .. "/" .. source, root .. "/target"))
        assert.are.equal("book", read(source .. "/payload"))
        assert.are.equal("book", read("target/payload"))
    end)

    it("does not reap a completed user copy containing a copied ownership marker", function()
        local source = ".koreader-fileop-1-1"
        assert(lfs.mkdir(root .. "/" .. source))
        write(source .. "/.owner", ownership(source))
        write(source .. "/payload", "user book")
        assert(lfs.mkdir(root .. "/dest"))
        assert.is_true(FileManager:copyRecursive(root .. "/" .. source, root .. "/dest"))
        local other = write("other", "other book")
        assert.is_true(FileManager:copyFileFromTo(other, root .. "/dest/other"))
        assert.are.equal("user book", read("dest/" .. source .. "/payload"))
        assert.are.equal(ownership(source), read("dest/" .. source .. "/.owner"))
        assert.are.same({ source, "other" }, entries("dest"))
    end)

    it("does not reap another active file operation in the same directory", function()
        local source = write("source", "outer book")
        local other = write("other", "inner book")
        local rename = os.rename
        local nested_copy = stub(os, "rename", function(from, to)
            if to == root .. "/target" then
                assert.is_true(FileManager:copyFileFromTo(other, root .. "/inner"))
                assert.is_truthy(lfs.attributes(from))
            end
            return rename(from, to)
        end)
        finally(function() nested_copy:revert() end)
        assert.is_true(FileManager:copyFileFromTo(source, root .. "/target"))
        assert.are.equal("outer book", read("target"))
        assert.are.equal("inner book", read("inner"))
        assert.are.same({ "inner", "other", "source", "target" }, entries())
    end)

    it("copies nested and empty directories, including hidden files and modification times", function()
        assert(lfs.mkdir(root .. "/source"))
        assert(lfs.mkdir(root .. "/source/nested"))
        assert(lfs.mkdir(root .. "/source/empty"))
        write("source/nested/.book", "nested book")
        assert(lfs.touch(root .. "/source/nested/.book", 1234567890, 1234567890))
        assert(lfs.touch(root .. "/source", 1234567890, 1234567890))
        assert.is_true(FileManager:copyRecursive(root .. "/source", root .. "/copy"))
        assert.are.equal("nested book", read("copy/nested/.book"))
        assert.are.same({}, entries("copy/empty"))
        assert.are.equal(1234567890, lfs.attributes(root .. "/copy", "modification"))
        assert.are.equal(1234567890, lfs.attributes(root .. "/copy/nested/.book", "modification"))
        assert.are.same({ "copy", "source" }, entries())
        assert.is_false(FileManager:copyFileFromTo(root .. "/source", root .. "/nonrecursive"))
        assert.is_nil(lfs.attributes(root .. "/nonrecursive"))
    end)

    it("publishes a new directory only once its whole tree has been copied", function()
        assert(lfs.mkdir(root .. "/source"))
        write("source/a", "first")
        write("source/b", "second")
        local rename = os.rename
        local publish = stub(os, "rename", function(from, to)
            assert.is_nil(lfs.attributes(root .. "/target"))
            assert.are.equal(5, lfs.attributes(from .. "/a", "size"))
            assert.are.equal(6, lfs.attributes(from .. "/b", "size"))
            return rename(from, to)
        end)
        finally(function() publish:revert() end)
        assert.is_true(FileManager:copyRecursive(root .. "/source", root .. "/target"))
        assert.are.same({ "a", "b" }, entries("target"))
    end)

    it("cleans an entire unpublished directory and preserves the source after a read failure", function()
        assert(lfs.mkdir(root .. "/source"))
        write("source/a", "first")
        write("source/b", "second")
        local open = io.open
        local fail_read = stub(io, "open", function(path, mode)
            if path == root .. "/source/b" and mode == "rb" then
                return { read = function() return nil, "read failed" end, close = function() return true end }
            end
            return open(path, mode)
        end)
        finally(function() fail_read:revert() end)
        assert.is_false(FileManager:copyRecursive(root .. "/source", root .. "/target"))
        assert.are.same({ "source" }, entries())
        assert.are.same({ "a", "b" }, entries("source"))
    end)

    it("merges into the same-named directory and preserves unrelated existing files", function()
        assert(lfs.mkdir(root .. "/source"))
        write("source/book", "new book")
        assert(lfs.mkdir(root .. "/dest"))
        assert(lfs.mkdir(root .. "/dest/source"))
        write("dest/source/book", "old book")
        write("dest/source/unrelated", "keep")
        assert.is_true(FileManager:copyRecursive(root .. "/source", root .. "/dest"))
        assert.are.equal("new book", read("dest/source/book"))
        assert.are.equal("keep", read("dest/source/unrelated"))
        assert.are.same({ "book", "unrelated" }, entries("dest/source"))
    end)

    it("keeps completed atomic replacements when a later merge entry fails", function()
        assert(lfs.mkdir(root .. "/source"))
        write("source/a", "new a")
        write("source/b", "new b")
        assert(lfs.mkdir(root .. "/dest"))
        assert(lfs.mkdir(root .. "/dest/source"))
        write("dest/source/a", "old a")
        write("dest/source/b", "old b")
        write("dest/source/unrelated", "keep")
        local rename = os.rename
        local fail_second = stub(os, "rename", function(from, to)
            if to == root .. "/dest/source/b" then return nil, "rename failed" end
            return rename(from, to)
        end)
        finally(function() fail_second:revert() end)
        assert.is_false(FileManager:copyRecursive(root .. "/source", root .. "/dest"))
        assert.are.equal("new a", read("dest/source/a"))
        assert.are.equal("old b", read("dest/source/b"))
        assert.are.equal("keep", read("dest/source/unrelated"))
        assert.are.same({ "a", "b", "unrelated" }, entries("dest/source"))
        assert.are.same({ "dest", "source" }, entries())
    end)

    it("moves a whole directory by rename and by a verified copy fallback", function()
        assert(lfs.mkdir(root .. "/source"))
        write("source/book", "book")
        assert.is_true(FileManager:moveFile(root .. "/source", root .. "/renamed"))
        local rename = os.rename
        local cross_volume = stub(os, "rename", function(from, to)
            if from == root .. "/renamed" then return nil, "cross-device link" end
            return rename(from, to)
        end)
        finally(function() cross_volume:revert() end)
        assert.is_true(FileManager:moveFile(root .. "/renamed", root .. "/moved"))
        assert.are.equal("book", read("moved/book"))
        assert.are.same({ "moved" }, entries())
    end)

    it("refuses to merge a moved directory into a nonempty effective destination", function()
        assert(lfs.mkdir(root .. "/source"))
        write("source/book", "book")
        assert(lfs.mkdir(root .. "/dest"))
        assert(lfs.mkdir(root .. "/dest/source"))
        write("dest/source/other", "keep")
        assert.is_false(FileManager:moveFile(root .. "/source", root .. "/dest"))
        assert.are.equal("book", read("source/book"))
        assert.are.same({ "other" }, entries("dest/source"))
    end)

    it("replaces an empty same-named directory when moving", function()
        assert(lfs.mkdir(root .. "/source"))
        write("source/book", "book")
        assert(lfs.mkdir(root .. "/dest"))
        assert(lfs.mkdir(root .. "/dest/source"))
        assert.is_true(FileManager:moveFile(root .. "/source", root .. "/dest"))
        assert.are.equal("book", read("dest/source/book"))
        assert.is_nil(lfs.attributes(root .. "/source"))
    end)

    it("cleans unpublished directories when creating a nested directory fails", function()
        assert(lfs.mkdir(root .. "/source"))
        assert(lfs.mkdir(root .. "/source/nested"))
        local mkdir = lfs.mkdir
        local fail_nested = stub(lfs, "mkdir", function(path)
            if path:sub(-7) == "/nested" then return nil, "mkdir failed" end
            return mkdir(path)
        end)
        finally(function() fail_nested:revert() end)
        assert.is_false(FileManager:copyRecursive(root .. "/source", root .. "/target"))
        assert.are.same({ "source" }, entries())
    end)

    it("does not publish a copy if its source changes during the read", function()
        local source = write("source", "book")
        write("target", "old")
        local open = io.open
        local change_source = stub(io, "open", function(path, mode)
            local file = assert(open(path, mode))
            if path ~= source or mode ~= "rb" then return file end
            local changed = false
            return {
                read = function(_, size)
                    local chunk = file:read(size)
                    if not changed then
                        changed = true
                        local writer = assert(open(source, "ab"))
                        assert(writer:write(" changed"))
                        assert(writer:close())
                    end
                    return chunk
                end,
                close = function() return file:close() end,
            }
        end)
        finally(function() change_source:revert() end)
        assert.is_false(FileManager:copyFileFromTo(source, root .. "/target"))
        assert.are.equal("old", read("target"))
        assert.are.same({ "source", "target" }, entries())
    end)

    it("retains the complete destination if source deletion fails partway through a move", function()
        assert(lfs.mkdir(root .. "/source"))
        write("source/a", "first")
        write("source/b", "second")
        local rename, remove = os.rename, os.remove
        local cross_volume = stub(os, "rename", function(from, to)
            if from == root .. "/source" then return nil, "cross-device link" end
            return rename(from, to)
        end)
        local fail_delete = stub(os, "remove", function(path)
            if path == root .. "/source/b" then return nil, "delete failed" end
            return remove(path)
        end)
        finally(function()
            cross_volume:revert()
            fail_delete:revert()
        end)
        assert.is_false(FileManager:moveFile(root .. "/source", root .. "/dest"))
        assert.are.equal("first", read("dest/a"))
        assert.are.equal("second", read("dest/b"))
        assert.is_nil(lfs.attributes(root .. "/source/a"))
        assert.are.equal("second", read("source/b"))
        assert.are.same({ "dest", "source" }, entries())
    end)

    for __, failure in ipairs{ "open", "write", "flush", "input close", "output close", "short read", "read error", "touch", "size" } do
        it("preserves source and old destination after " .. failure .. " failure", function()
            local source = write("source", "new book")
            write("target", "old book")
            local open, rename, touch, attributes = io.open, os.rename, lfs.touch, lfs.attributes
            local injected
            if failure == "touch" then
                injected = stub(lfs, "touch", function() return nil, "touch failed" end)
            elseif failure == "size" then
                injected = stub(lfs, "attributes", function(path, field)
                    if field == "size" and path:find("/.koreader-fileop-", 1, true) then return 1 end
                    return attributes(path, field)
                end)
            else
                injected = stub(io, "open", function(path, mode)
                    if path ~= source and path:sub(-8) ~= "/payload" then return open(path, mode) end
                    if mode == "wb" and failure == "open" then return nil, "open failed" end
                    local file = assert(open(path, mode))
                    return {
                        read = function(_, size)
                            if failure == "short read" then return nil end
                            if failure == "read error" then return nil, "read failed" end
                            return file:read(size)
                        end,
                        write = function(_, chunk)
                            if failure == "write" then
                                file:write(chunk:sub(1, 2))
                                return nil, "write failed"
                            end
                            return file:write(chunk)
                        end,
                        flush = function()
                            if failure == "flush" then return nil, "flush failed" end
                            return file:flush()
                        end,
                        close = function()
                            local result = file:close()
                            if (mode == "rb" and failure == "input close")
                                or (mode == "wb" and failure == "output close") then return nil, "close failed" end
                            return result
                        end,
                    }
                end)
            end
            local cross_volume = stub(os, "rename", function(from, to)
                if from == source then return nil, "cross-device link" end
                return rename(from, to)
            end)
            finally(function()
                if injected then injected:revert() end
                cross_volume:revert()
            end)
            assert.is_false(FileManager:moveFile(source, root .. "/target"))
            injected:revert()
            injected = nil
            assert.are.equal("new book", read("source"))
            assert.are.equal("old book", read("target"))
            assert.are.same({ "source", "target" }, entries())
        end)
    end

    it("rejects missing sources, type conflicts, self copies and descendant destinations", function()
        local source = write("book", "book")
        assert(lfs.mkdir(root .. "/folder"))
        assert(lfs.mkdir(root .. "/folder/child"))
        write("folder/book", "keep")
        assert.is_false(FileManager:copyRecursive(root .. "/missing", root .. "/copy"))
        assert.is_false(FileManager:copyFileFromTo(source, source))
        assert.is_false(FileManager:moveFile(source, root))
        assert.is_false(FileManager:copyRecursive(root .. "/folder", root .. "/folder/child"))
        assert.is_false(FileManager:moveFile(root .. "/folder", source))
        assert.is_true(FileManager:copyFileFromTo(source, root .. "/folder"))
        assert.are.equal("book", read("folder/book"))
    end)

    it("rejects symlinks, including links in trees and dangling destination links", function()
        local source = write("source", "book")
        assert(lfs.link(source, root .. "/link", true))
        assert(lfs.link(root .. "/missing", root .. "/dangling", true))
        assert.is_false(FileManager:copyRecursive(root .. "/link", root .. "/copy"))
        assert.is_false(FileManager:moveFile(root .. "/link", root .. "/moved"))
        assert.is_false(FileManager:copyFileFromTo(source, root .. "/dangling"))
        assert(lfs.mkdir(root .. "/tree"))
        assert(lfs.link(root .. "/tree", root .. "/tree/loop", true))
        assert.is_false(FileManager:copyRecursive(root .. "/tree", root .. "/copy"))
        assert.are.equal("link", lfs.symlinkattributes(root .. "/dangling", "mode"))
        assert.are.same({ "dangling", "link", "source", "tree" }, entries())
    end)

    it("does not delete a source if destination size verification fails after publication", function()
        local source = write("source", "book")
        local rename, attributes = os.rename, lfs.symlinkattributes
        local cross_volume = stub(os, "rename", function(from, to)
            if from == source then return nil, "cross-device link" end
            return rename(from, to)
        end)
        local bad_size = stub(lfs, "symlinkattributes", function(path, field)
            local attr = attributes(path, field)
            if path == root .. "/target" and type(attr) == "table" then attr.size = 1 end
            return attr
        end)
        finally(function()
            cross_volume:revert()
            bad_size:revert()
        end)
        assert.is_false(FileManager:moveFile(source, root .. "/target"))
        assert.are.equal("book", read("source"))
        assert.are.equal("book", read("target"))
        assert.are.same({ "source", "target" }, entries())
    end)

    it("rejects special files before copying or moving them", function()
        local source = write("source", "book")
        local attributes = lfs.symlinkattributes
        local special = stub(lfs, "symlinkattributes", function(path, field)
            local attr = attributes(path, field)
            if path == source and type(attr) == "table" then attr.mode = "named pipe" end
            return attr
        end)
        finally(function() special:revert() end)
        assert.is_false(FileManager:copyFileFromTo(source, root .. "/target"))
        assert.is_false(FileManager:moveFile(source, root .. "/target"))
        assert.are.same({ "source" }, entries())
    end)

    it("keeps the existing overwrite confirmation when pasting a file", function()
        local source = write("book.txt", "new book")
        assert(lfs.mkdir(root .. "/dest"))
        write("dest/book.txt", "old book")
        local filemanager = FileManager:new{
            dimen = Device.screen:getSize(),
            root_path = root .. "/dest",
        }
        finally(function() filemanager:onClose() end)
        filemanager:copyFile(source)
        filemanager:pasteFileFromClipboard()
        local confirmation = UIManager._window_stack[#UIManager._window_stack].widget
        assert.are.equal("Overwrite", confirmation.ok_text)
        assert.are.equal("old book", read("dest/book.txt"))
        UIManager:close(confirmation)
        confirmation.ok_callback()
        assert.are.equal("new book", read("dest/book.txt"))
        assert.are.equal("new book", read("book.txt"))
        assert.is_nil(filemanager.clipboard)
    end)

    it("pastes copied and cut directories through the file page", function()
        assert(lfs.mkdir(root .. "/source"))
        write("source/book.txt", "book")
        assert(lfs.mkdir(root .. "/dest"))
        assert(lfs.mkdir(root .. "/moved"))
        local filemanager = FileManager:new{
            dimen = Device.screen:getSize(),
            root_path = root .. "/dest",
        }
        finally(function() filemanager:onClose() end)
        filemanager:copyFile(root .. "/source")
        filemanager:pasteFileFromClipboard()
        assert.are.equal("book", read("dest/source/book.txt"))
        assert.are.equal("book", read("source/book.txt"))
        filemanager:cutFile(root .. "/source")
        filemanager:pasteFileFromClipboard(root .. "/moved")
        assert.are.equal("book", read("moved/source/book.txt"))
        assert.is_nil(lfs.attributes(root .. "/source"))
        assert.is_nil(filemanager.clipboard)
    end)

    it("retains the original cp and mv command arguments and exit-status handling when forking is allowed", function()
        Device.canForkProcesses:revert()
        stub(Device, "canForkProcesses", function() return true end)
        ffiUtil.execute:revert()
        local exit_status = 0
        stub(ffiUtil, "execute", function() return exit_status end)
        assert.is_true(FileManager:moveFile("from", "to"))
        assert.stub(ffiUtil.execute).was_called_with(FileManager.mv_bin, "from", "to")
        assert.is_true(FileManager:copyFileFromTo("from", "to"))
        assert.stub(ffiUtil.execute).was_called_with(FileManager.cp_bin, "from", "to")
        assert.is_true(FileManager:copyRecursive("from", "to"))
        assert.stub(ffiUtil.execute).was_called_with(FileManager.cp_bin, "-r", "from", "to")
        exit_status = 1
        assert.is_false(FileManager:moveFile("from", "to"))
        assert.is_false(FileManager:copyFileFromTo("from", "to"))
        assert.is_false(FileManager:copyRecursive("from", "to"))
        assert.is_table(FileManagerUtil.genExecuteScriptButton("script.sh"))
        assert.is_true(Device:canExecuteScript("script.sh"))
        assert.is_true(Device:canExecuteScript("script.PY"))
        assert.is_nil(Device:canExecuteScript("book.epub"))
    end)

    it("hides script execution and blocks direct shortcuts without side effects", function()
        local execute = stub(os, "execute", function() error("unexpected shell") end)
        local show = stub(UIManager, "show")
        local schedule = stub(UIManager, "scheduleIn")
        finally(function()
            execute:revert()
            show:revert()
            schedule:revert()
        end)
        assert.is_nil(FileManagerUtil.genExecuteScriptButton("book.sh"))
        -- All three file dialog callers and bookshortcuts consult this first.
        assert.is_nil(Device:canExecuteScript("book.sh"))
        assert.is_nil(Device:canExecuteScript("book.py"))
        FileManagerUtil.executeScript("book.sh", function() error("unexpected callback") end)
        assert.stub(execute).was_not_called()
        assert.stub(show).was_not_called()
        assert.stub(schedule).was_not_called()
    end)
end)
