describe("BookInfoManager without fork", function()
    local BookInfoManager, Device, UIManager, ffiutil
    local manager, tasks, extracted, extraction_stub

    setup(function()
        require("commonrequire")
        Device = require("device")
        UIManager = require("ui/uimanager")
        ffiutil = require("ffi/util")
        BookInfoManager = dofile("plugins/coverbrowser.koplugin/bookinfomanager.lua")
    end)

    before_each(function()
        tasks, extracted = {}, {}
        manager = setmetatable({}, { __index = BookInfoManager })
        manager:init()
        stub(Device, "canForkProcesses", function() return false end)
        stub(UIManager, "nextTick", function(_, action) tasks[#tasks + 1] = action end)
        stub(UIManager, "scheduleIn", function(_, delay, action)
            assert.is_true(delay > 0)
            tasks[#tasks + 1] = action
        end)
        stub(UIManager, "unschedule", function(_, action)
            for i = #tasks, 1, -1 do
                if tasks[i] == action then table.remove(tasks, i) end
            end
        end)
        stub(UIManager, "preventStandby")
        stub(UIManager, "allowStandby")
        stub(ffiutil, "runInSubProcess", function() error("unexpected fork") end)
        extraction_stub = stub(manager, "extractBookInfo", function(_, file)
            extracted[#extracted + 1] = file
            return true
        end)
    end)

    after_each(function()
        manager:terminateBackgroundJobs()
        if extraction_stub then extraction_stub:revert() end
        ffiutil.runInSubProcess:revert()
        UIManager.nextTick:revert()
        UIManager.scheduleIn:revert()
        UIManager.unschedule:revert()
        UIManager.preventStandby:revert()
        UIManager.allowStandby:revert()
        Device.canForkProcesses:revert()
    end)

    local function step()
        assert.is_truthy(tasks[1])
        table.remove(tasks, 1)()
    end

    it("extracts 105 books one at a time with an input interval between books", function()
        local files, completed = {}, {}
        for i = 1, 105 do files[i] = { filepath = tostring(i) } end
        assert.is_true(manager:extractInBackground(files, function(file)
            completed[#completed + 1] = file
        end))
        assert.are.equal(0, #extracted)
        assert.is_true(manager:isExtractingInBackground())
        for i = 1, 105 do
            step() -- nextTick only arms the delayed extraction
            assert.are.equal(i - 1, #extracted)
            step() -- one book, never the rest of the batch
            assert.are.equal(i, #extracted)
            assert.are.equal(tostring(i), completed[i])
        end
        assert.is_false(manager:isExtractingInBackground())
        assert.are.equal(0, #tasks)
        assert.stub(UIManager.preventStandby).was_called(1)
        assert.stub(UIManager.allowStandby).was_called(1)
        assert.stub(ffiutil.runInSubProcess).was_not_called()
    end)

    it("cancels queued work and ignores an obsolete callback after replacement", function()
        manager:extractInBackground({ { filepath = "old" }, { filepath = "never" } })
        step()
        local obsolete = tasks[1]
        manager:terminateBackgroundJobs()
        assert.is_false(manager:isExtractingInBackground())
        assert.are.equal(0, #tasks)
        manager:extractInBackground({ { filepath = "new" } })
        obsolete()
        assert.are.equal(0, #extracted)
        step()
        step()
        assert.are.same({ "new" }, extracted)
        assert.stub(UIManager.preventStandby).was_called(2)
        assert.stub(UIManager.allowStandby).was_called(2)
    end)

    it("continues after a failed book and reports its failure", function()
        extraction_stub:revert()
        extraction_stub = stub(manager, "extractBookInfo", function(_, file)
            if file == "bad" then error("bad book") end
            extracted[#extracted + 1] = file
            return true
        end)
        local results = {}
        manager:extractInBackground({ { filepath = "bad" }, { filepath = "good" } }, function(file, success)
            results[file] = success
        end)
        while #tasks > 0 do step() end
        assert.are.same({ "good" }, extracted)
        assert.is_false(results.bad)
        assert.is_true(results.good)
        assert.is_false(manager:isExtractingInBackground())
        assert.stub(UIManager.allowStandby).was_called(1)
    end)

    it("keeps the subprocess path on devices that can fork", function()
        Device.canForkProcesses:revert()
        stub(Device, "canForkProcesses", function() return true end)
        ffiutil.runInSubProcess:revert()
        stub(ffiutil, "runInSubProcess", function() return 123 end)
        stub(manager, "closeDbConnection")
        stub(Device, "enableCPUCores")
        finally(function()
            manager.subprocesses_pids = {}
            manager.closeDbConnection:revert()
            Device.enableCPUCores:revert()
        end)
        assert.is_true(manager:extractInBackground({ { filepath = "book" } }))
        assert.stub(ffiutil.runInSubProcess).was_called(1)
        assert.are.equal(0, #extracted)
        assert.is_true(manager:isExtractingInBackground())
        manager.subprocesses_pids = {}
    end)

    it("stops cleanly when the completion callback cancels the current batch", function()
        manager:extractInBackground({ { filepath = "one" }, { filepath = "two" } }, function()
            manager:terminateBackgroundJobs()
        end)
        step()
        step()
        assert.are.same({ "one" }, extracted)
        assert.are.equal(0, #tasks)
        assert.is_false(manager:isExtractingInBackground())
        assert.stub(UIManager.allowStandby).was_called(1)
    end)

    local function realExtraction()
        extraction_stub:revert()
        extraction_stub = nil
        local CreDocument = require("document/credocument")
        local cre = CreDocument:engineInit()
        local paths = {}
        local init_cache = cre.initCache
        stub(cre, "initCache", function(path, ...)
            paths[#paths + 1] = path
            return init_cache(path, ...)
        end)
        manager.db_location = os.tmpname()
        os.remove(manager.db_location)
        manager.tmpcr3cache = manager.db_location .. "_cr3cache"
        finally(function()
            cre.initCache:revert()
            manager:closeDbConnection()
            ffiutil.purgeDir(manager.tmpcr3cache)
            for _, suffix in ipairs({ "", "-wal", "-shm" }) do os.remove(manager.db_location .. suffix) end
        end)
        return paths
    end

    it("stores a real cover and restores the normal CRE cache after the timed extraction", function()
        local paths = realExtraction()
        local file = "spec/front/unit/data/juliet.epub"
        local time = require("ui/time")
        local logger = require("logger")
        stub(time, "since", function() return time.ms(125) end)
        spy.on(logger, "info")
        finally(function()
            time.since:revert()
            logger.info:revert()
        end)
        assert.is_true(manager:extractBookInfo(file, { max_cover_w = 100, max_cover_h = 150 }))
        local info = manager:getBookInfo(file)
        assert.is_truthy(info)
        assert.are.equal("Y", info.cover_fetched)
        assert.are.equal(manager.tmpcr3cache, paths[1])
        assert.are.equal(require("datastorage"):getDataDir() .. "/cache/cr3cache", paths[#paths])
        assert.is_nil(manager.cre_cache_overriden)
        assert.spy(logger.info).was_called_with("BookInfoManager: in-process extraction", file,
            "took", 125, "ms", "success:", true)
    end)

    it("closes a failed document, restores the cache, and can retry the book", function()
        local paths = realExtraction()
        local BookInfo = require("apps/filemanager/filemanagerbookinfo")
        local file = "spec/front/unit/data/juliet.epub"
        stub(BookInfo, "getCoverImage", function() error("cover decode failure") end)
        local ok, err = pcall(manager.extractBookInfo, manager, file, { max_cover_w = 100, max_cover_h = 150 })
        BookInfo.getCoverImage:revert()
        assert.is_false(ok)
        assert.is_truthy(err:find("cover decode failure", 1, true))
        assert.is_nil(require("document/documentregistry").registry[file])
        assert.is_nil(manager.cre_cache_overriden)
        assert.are.equal(require("datastorage"):getDataDir() .. "/cache/cr3cache", paths[#paths])
        assert.is_true(manager:extractBookInfo(file, { max_cover_w = 100, max_cover_h = 150 }))
        assert.is_truthy(manager:getBookInfo(file))
    end)
end)
