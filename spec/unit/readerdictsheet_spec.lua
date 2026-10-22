describe("ReaderDictSheet module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderDictionary, ReaderDictSheet, ReaderHighlightBubble
    local DictQuickLookup, NetworkMgr, Replacements, UIManager, Event, Geom, Screen
    local sample_epub = "spec/front/unit/data/juliet.epub"

    -- Demo StarDict entries, as sdcv returns them
    local DICT = {
        sojourner = "/ˈsɒdʒənə(r)/\nn. a person who stays in a place for a while and then moves on\n旅居者；暂住者",
        stop = "/stɒp/\nv. to end a movement\nn. a place where buses stop",
        ["经典"] = "[jīng diǎn]\nn. 具有典范性、权威性的著作",
    }
    local sdcv_words -- words passed to the last sdcv run

    local function stubSdcv(dictionary, any)
        dictionary.enabled_dict_names = { "Demo" } -- the test environment has no dictionaries
        stub(dictionary, "rawSdcv").invokes(function(_, words)
            sdcv_words = words
            local results = {}
            for i, w in ipairs(words) do
                local def = DICT[w] or (any and i == 1 and "n. a demo sense")
                results[i] = def and { { dict = "Demo", word = w, definition = def } } or {}
            end
            return false, results
        end)
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("vocabbuilder.koplugin")
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderDictionary = require("apps/reader/modules/readerdictionary")
        ReaderDictSheet = require("apps/reader/modules/readerdictsheet")
        ReaderHighlightBubble = require("apps/reader/modules/readerhighlightbubble")
        DictQuickLookup = require("ui/widget/dictquicklookup")
        NetworkMgr = require("ui/network/manager")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Screen = require("device").screen
        ReaderHighlightBubble.register()
        ReaderDictSheet.register()
    end)

    teardown(function()
        Replacements.reader_highlight = nil
        Replacements.reader_dictionary = nil
        DocSettings:open(sample_epub):purge()
    end)

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function tap(x, y)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
    end

    local function tapWidget(widget)
        tap(widget.dimen.x + math.floor(widget.dimen.w / 2), widget.dimen.y + math.floor(widget.dimen.h / 2))
    end

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

    local function assertNoFullScreen(refreshes)
        for _, r in ipairs(refreshes) do
            assert.is_truthy(r.region)
            assert.is_false(r.region.w >= Screen:getWidth() and r.region.h >= Screen:getHeight())
        end
    end

    local function hasRefresh(refreshes, mode, region)
        for _, r in ipairs(refreshes) do
            if r.mode == mode and r.region and r.region.x == region.x and r.region.y == region.y
                    and r.region.w == region.w and r.region.h == region.h then
                return true
            end
        end
    end

    local function find(widget, pred)
        if type(widget) ~= "table" then return end
        if pred(widget) then return widget end
        for _, child in ipairs(widget) do
            local found = find(child, pred)
            if found then return found end
        end
        for _, key in ipairs{ "frame", "content" } do
            local found = rawget(widget, key) and find(widget[key], pred)
            if found then return found end
        end
    end

    local function hasText(widget, text)
        return find(widget, function(w) return w.text == text end) ~= nil
    end

    -- the tappable widget holding `text`
    local function button(widget, text)
        return find(widget, function(w)
            return w.callback and w.dimen and find(w, function(c) return c.text == text end) ~= nil
        end)
    end

    local function sheet()
        local top = topWidget()
        return getmetatable(top) and top.dictionary and top or nil
    end

    describe("candidates", function()
        it("should try simple English lemmas after the word", function()
            local function has(word, lemma)
                for _, w in ipairs(ReaderDictSheet.candidates(word)) do
                    if w == lemma then return true end
                end
            end
            assert.are.equal("Stopped", ReaderDictSheet.candidates("Stopped")[1])
            assert.is_true(has("Stopped", "stop"))
            assert.is_true(has("running", "run"))
            assert.is_true(has("studies", "study"))
            assert.is_true(has("boxes", "box"))
            assert.is_true(has("horses", "horse"))
            assert.is_true(has("making", "make"))
            assert.is_true(has("singing", "sing"))
            local c = ReaderDictSheet.candidates("used")
            assert.are.same({ "used", "use", "us" }, c)
        end)

        it("should list CJK sub-words longest first, and nothing more past 20 characters", function()
            local c = ReaderDictSheet.candidates("读经典")
            assert.are.same({ "读经典", "读经", "经典" }, c)
            assert.are.same({ "经典，读" }, { ReaderDictSheet.candidates("经典，读")[1] })
            assert.are.equal(2, #ReaderDictSheet.candidates("经典，读")) -- the selection and 经典
            assert.are.equal(1, #ReaderDictSheet.candidates(string.rep("经", 21)))
        end)

        it("should parse the phonetic and part-of-speech senses", function()
            local phonetic, senses = ReaderDictSheet.parseEntry{ { dict = "Demo", word = "sojourner", definition = DICT.sojourner } }
            assert.are.equal("/ˈsɒdʒənə(r)/", phonetic)
            assert.are.equal(2, #senses)
            assert.are.equal("n.", senses[1].pos)
            assert.are.equal("a person who stays in a place for a while and then moves on", senses[1].text)
            assert.is_nil(senses[2].pos)
            phonetic, senses = ReaderDictSheet.parseEntry{ { dict = "Demo", word = "x", definition = "*[ə'baut] prep. 关于" } }
            assert.are.equal("[ə'baut]", phonetic)
            assert.are.same({ pos = "prep.", text = "关于", dict = "Demo" }, senses[1])
        end)
    end)

    describe("with an EPUB", function()
        local ui
        before_each(function()
            DocSettings:open(sample_epub):purge()
            ui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }
            UIManager:show(ui)
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()
        end)
        after_each(function()
            if ui.dictionary.dict_window then ui.dictionary.dict_window:onClose() end
            for i = #DictQuickLookup.window_list, 1, -1 do
                DictQuickLookup.window_list[i]:onClose()
            end
            UIManager:close(ui.highlight.highlight_dialog)
            ui.dictionary.rawSdcv:revert()
            ui:onClose()
            UIManager:quit()
        end)

        local function selectAndLookUp()
            ui.highlight:onHold(nil, { pos = Geom:new{ x = 400, y = 110 } })
            UIManager:forceRePaint()
            ui.highlight:onHoldRelease()
            UIManager:forceRePaint()
            local text = ui.highlight.selected_text.text
            local refreshes = refreshesOf(function()
                tapWidget(button(ui.highlight.highlight_dialog, "Look up"))
            end)
            return refreshes, text
        end

        it("should show the sheet on top after Look up, refreshing only the sheet; closing refreshes only the sheet", function()
            stubSdcv(ui.dictionary, true)
            local refreshes = selectAndLookUp()
            local s = sheet()
            assert.is_truthy(s)
            assert.are.equal(ui.dictionary.dict_window, s)
            assert.is_true(hasRefresh(refreshes, "ui", s:getRefreshRegion()))
            assertNoFullScreen(refreshes)
            for _, r in ipairs(refreshes) do
                assert.are_not.equal("full", r.mode)
            end
            assert.is_true(hasText(s, "a demo sense"))
            assert.is_true(hasText(s, "n."))

            local region = s:getRefreshRegion()
            refreshes = refreshesOf(function() tap(5, 5) end) -- the scrim
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.dictionary.dict_window)
            assert.is_true(hasRefresh(refreshes, "ui", region))
            assertNoFullScreen(refreshes)
        end)

        it("should add the word with its context to the vocabulary builder", function()
            stubSdcv(ui.dictionary, true)
            local _, text = selectAndLookUp()
            local s = sheet()
            local word = s.headword
            assert.are.equal(text, word)
            local vocab = ui.vocabbuilder
            vocab:removeWord(word)
            UIManager:setDirty(s, "ui")
            UIManager:forceRePaint()
            tapWidget(button(s, "Add to vocabulary builder"))
            UIManager:forceRePaint()
            assert.is_true(vocab:hasWord(word))
            local item = package.loaded["db"]:hasWord(word)
            assert.is_truthy(item.prev_context or item.next_context)
            assert.is_true(hasText(s, "In vocabulary builder"))
            -- a second tap removes it
            UIManager:forceRePaint()
            tapWidget(button(s, "In vocabulary builder"))
            assert.is_false(vocab:hasWord(word))
        end)

        it("should show the empty state for an unknown word, not an error or the fuzzy search dialog", function()
            stubSdcv(ui.dictionary)
            ui.dictionary:onLookupWord("qwxzv")
            UIManager:forceRePaint()
            local s = sheet()
            assert.is_truthy(s)
            assert.is_true(hasText(s, 'No "qwxzv" in local dictionaries'))
            assert.is_nil(button(s, "Add to vocabulary builder"))
            assert.is_nil(button(s, "Full entry"))
        end)

        it("should look up the longest word in a long Chinese selection", function()
            stubSdcv(ui.dictionary)
            ui.dictionary:onLookupWord("我们读经典常谈")
            UIManager:forceRePaint()
            local s = sheet()
            assert.are.equal("经典", s.headword)
            assert.are.equal("[jīng diǎn]", s.phonetic)
            assert.is_true(hasText(s, 'Selected "我们读经典常谈", found "经典" by longest match'))

            s:onClose()
            ui.dictionary:onLookupWord(string.rep("读", 21))
            UIManager:forceRePaint()
            assert.are.equal(1, #sdcv_words)
            assert.is_true(hasText(sheet(), "Selection too long to look up"))
        end)

        it("should look up the lemma of an English word", function()
            stubSdcv(ui.dictionary)
            ui.dictionary:onLookupWord("Stopped")
            UIManager:forceRePaint()
            assert.are.equal("stop", sheet().headword)
            assert.are.equal("/stɒp/", sheet().phonetic)
        end)

        it("should show the offline state for Wikipedia, refreshing only the sheet", function()
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(false)
            ui.dictionary:onLookupWord("sojourner")
            UIManager:forceRePaint()
            local s = sheet()
            local region = s:getRefreshRegion()
            local refreshes = refreshesOf(function() tapWidget(button(s, "Wikipedia")) end)
            NetworkMgr.isOnline:revert()
            assert.is_true(hasText(s, "Needs a network connection"))
            assert.are.same({ { mode = "ui", region = region } }, refreshes)
            -- and back
            refreshes = refreshesOf(function() tapWidget(button(s, "Dictionary")) end)
            assert.is_true(hasText(s, "旅居者；暂住者"))
            assert.are.same({ { mode = "ui", region = region } }, refreshes)
        end)

        it("should show the Wikipedia intro when online, with the full article behind Full entry", function()
            local Wikipedia = require("ui/wikipedia")
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            stub(Wikipedia, "searchAndGetIntros").returns({ [7] = { title = "Sojourner", extract = "A sojourner is a traveller.", index = 0 } })
            ui.dictionary:onLookupWord("sojourner")
            UIManager:forceRePaint()
            local s = sheet()
            local region = s:getRefreshRegion()
            local refreshes = refreshesOf(function() tapWidget(button(s, "Wikipedia")) end)
            NetworkMgr.isOnline:revert()
            Wikipedia.searchAndGetIntros:revert()
            assert.is_true(hasText(s, "A sojourner is a traveller."))
            assertNoFullScreen(refreshes)
            for _, r in ipairs(refreshes) do
                assert.are.same(region, r.region)
            end
            tapWidget(button(s, "Full entry"))
            UIManager:forceRePaint()
            assert.is_true(topWidget().is_wiki)
            assert.are.equal("Sojourner", topWidget().results[1].word)
        end)

        it("should search the book for the headword", function()
            stubSdcv(ui.dictionary)
            stub(ui.search, "searchCallback")
            ui.dictionary:onLookupWord("sojourner")
            UIManager:forceRePaint()
            tapWidget(button(sheet(), "Search book"))
            assert.stub(ui.search.searchCallback).was_called_with(match.is_ref(ui.search), nil, "sojourner")
            assert.is_nil(ui.dictionary.dict_window)
            ui.search.searchCallback:revert()
        end)

        it("should open the upstream popup with the same results from Full entry", function()
            stubSdcv(ui.dictionary)
            ui.dictionary:onLookupWord("sojourner")
            UIManager:forceRePaint()
            tapWidget(button(sheet(), "Full entry"))
            UIManager:forceRePaint()
            local top = topWidget()
            assert.are.equal(DictQuickLookup.window_list[#DictQuickLookup.window_list], top)
            assert.are.equal("sojourner", top.results[1].word)
        end)
    end)

    it("should keep the upstream dictionary when the slot is empty", function()
        Replacements.reader_dictionary = nil
        local ui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        assert.are.equal(ReaderDictionary.showDict, ui.dictionary.showDict)
        ui:onClose()
        ReaderDictSheet.register()
        assert.are.equal(ReaderDictSheet, Replacements.reader_dictionary)
    end)
end)
