describe("Readerdictionary module", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen

    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("japanese.koplugin")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
    end)

    local readerui, dictionary
    setup(function()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument("spec/front/unit/data/sample.txt"),
        }
        dictionary = readerui.dictionary
    end)
    teardown(function()
        ReaderUI.instance = readerui
        readerui:closeDocument()
        readerui:onClose()
    end)
    before_each(function()
        ReaderUI.instance = readerui
        UIManager:show(readerui)
    end)
    after_each(function()
        UIManager:close(dictionary.dict_window)
        UIManager:close(readerui)
        UIManager:quit()
        UIManager._exit_code = nil
    end)
    it("should show quick lookup window", function()
        dictionary:onLookupWord("test")
        fastforward_ui_events()
        screenshot(Screen, "reader_dictionary.png")
    end)
    it("should attempt to deinflect (Japanese) word on lookup", function()

        local word = "喋っている"
        local s = spy.on(readerui.languagesupport, "extraDictionaryFormCandidates")

        -- We can't use onLookupWord because we need to check whether
        -- extraDictionaryFormCandidates was called synchronously.
        dictionary:stardictLookup(word)
        fastforward_ui_events()
        screenshot(Screen, "reader_dictionary_japanese.png")

        assert.spy(s).was_called()
        assert.spy(s).was_called_with(match.is_ref(readerui.languagesupport), word)
        if readerui.languagesupport.plugins["japanese_support"] then
            --- @todo This should probably check against a set or sorted list
            --       of the candidates we'd expect.
            assert.spy(s).was_returned_with(match.is_not_nil())
        end
        readerui.languagesupport.extraDictionaryFormCandidates:revert()
    end)

    describe("where child processes cannot run (iOS)", function()
        local Device, Trapper
        local FIXTURES = "spec/front/unit/fixtures/stardict"
        local data_dir
        local APPLE_DEMO = { dict = "Demo", word = "apple", definition = "\nn. a round fruit of a tree of the rose family" }
        local APPLE_OTHER = { dict = "Other", word = "apple", definition = "\n[ˈæpl]\na fruit\n[x] <b>" }
        local RUN_DEMO = { dict = "Demo", word = "run", definition = "\nv. to move swiftly on foot" }

        setup(function()
            Device = require("device")
            Trapper = require("ui/trapper")
        end)
        before_each(function()
            data_dir = dictionary.data_dir
            dictionary.data_dir = FIXTURES
            stub(Device, "canForkProcesses").returns(false)
            spy.on(Trapper, "dismissablePopen")
        end)
        after_each(function()
            dictionary.data_dir = data_dir
            Device.canForkProcesses:revert()
            Trapper.dismissablePopen:revert()
        end)

        it("should read the dictionaries in process, as sdcv -u: the named ones in their order, per word", function()
            local cancelled, results = dictionary:rawSdcv({ "apple", "ran", "nothing" }, { "Other", "Demo" }, false)
            assert.is_false(cancelled)
            assert.are.same({ { APPLE_OTHER, APPLE_DEMO }, { RUN_DEMO }, {} }, results)
            assert.spy(Trapper.dismissablePopen).was_not_called()

            results = select(2, dictionary:rawSdcv({ "apple" }, { "Demo" }, false))
            assert.are.same({ { APPLE_DEMO } }, results)
        end)

        it("should read all the usable dictionaries when none is named", function()
            local results = select(2, dictionary:rawSdcv({ "apple" }, nil, false))
            assert.are.equal(2, #results[1])
            local by_dict = {}
            for _, r in ipairs(results[1]) do by_dict[r.dict] = r end
            assert.are.same({ Demo = APPLE_DEMO, Other = APPLE_OTHER }, by_dict)
        end)

        it("should try the case variants of a word only with fuzzy search", function()
            local results = select(2, dictionary:rawSdcv({ "APPLE" }, { "Demo" }, false))
            assert.are.same({ {} }, results)
            results = select(2, dictionary:rawSdcv({ "APPLE" }, { "Demo" }, true))
            assert.are.same({ { APPLE_DEMO } }, results)
        end)

        it("should find dictionaries added while the app runs, once none was found", function()
            local DataStorage = require("datastorage")
            local ffiUtil = require("ffi/util")
            local dir = DataStorage:getDataDir() .. "/dict_spec"
            require("util").makePath(dir)
            G_defaults:saveSetting("STARDICT_DATA_DIR", dir)
            local ok, err = pcall(function()
                dictionary:rescanDictionaries()
                assert.are.equal(0, (dictionary:getNumberOfDictionaries()))
                spy.on(dictionary, "rescanDictionaries")
                dictionary:rescanIfNoDictionaries() -- still nothing there
                assert.spy(dictionary.rescanDictionaries).was_not_called()
                -- added through Files
                require("util").makePath(dir .. "/demo")
                for _, ext in ipairs{ ".ifo", ".idx", ".syn", ".dict.dz" } do
                    ffiUtil.copyFile(FIXTURES .. "/demo/demo" .. ext, dir .. "/demo/demo" .. ext)
                end
                dictionary:rescanIfNoDictionaries()
                assert.spy(dictionary.rescanDictionaries).was_called(1)
                assert.are.equal(1, (dictionary:getNumberOfDictionaries()))
                assert.are.same({ "Demo" }, dictionary.enabled_dict_names)
                dictionary:rescanIfNoDictionaries() -- found: no more scans
                assert.spy(dictionary.rescanDictionaries).was_called(1)
                dictionary.rescanDictionaries:revert()
            end)
            G_defaults:delSetting("STARDICT_DATA_DIR")
            ffiUtil.purgeDir(dir)
            dictionary:rescanDictionaries() -- back to the test environment's dictionaries
            assert(ok, err)
        end)

        it("should still run sdcv where child processes can run", function()
            Device.canForkProcesses:revert()
            stub(Device, "canForkProcesses").returns(true)
            Trapper.dismissablePopen:revert()
            stub(Trapper, "dismissablePopen").returns(true, "[]\n")
            spy.on(dictionary, "lookupInProcess")
            local cancelled, results = dictionary:rawSdcv({ "apple" }, { "Demo" }, false)
            assert.is_false(cancelled)
            assert.are.same({ {} }, results)
            assert.stub(Trapper.dismissablePopen).was_called()
            assert.spy(dictionary.lookupInProcess).was_not_called()
            dictionary.lookupInProcess:revert()
        end)
    end)
end)
