describe("ReaderDictSheet module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderDictionary, ReaderDictSheet, ReaderHighlightBubble
    local DictQuickLookup, NetworkMgr, Replacements, Translator, Trapper, UIManager, Event, Geom, Screen
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local vocab_settings = { enabled = false, with_context = true }

    local epub_prev_context = "thou\n hadst been poor John. Draw thy tool! here comes\n two of the house of the "
    local epub_next_context = ".\nSAMPSON\nMy naked weapon is out: quarrel, I will back thee.\nGREGORY\nHow! turn thy back"

    -- Demo StarDict entries, as sdcv returns them, by dictionary
    local DICT = {
        sojourner = {
            Demo = "/ˈsɒdʒənə(r)/\nn. a person who stays in a place for a while and then moves on\n旅居者；暂住者",
            Other = "sojourner: someone who lives somewhere for a short time",
        },
        stop = { Demo = "/stɒp/\nv. to end a movement\nn. a place where buses stop" },
        ["经典"] = { Demo = "[jīng diǎn]\nn. 具有典范性、权威性的著作" },
    }
    local sdcv_words -- words passed to the last sdcv run

    -- any: the first word has a "Demo" sense when it has no entry
    local function stubSdcv(dictionary, any)
        dictionary.enabled_dict_names = { "Demo", "Other" } -- the test environment has no dictionaries
        stub(dictionary, "rawSdcv").invokes(function(_, words)
            sdcv_words = words
            local results = {}
            for i, w in ipairs(words) do
                results[i] = {}
                for _, dict in ipairs{ "Demo", "Other" } do
                    local def = DICT[w] and DICT[w][dict]
                    if def then table.insert(results[i], { dict = dict, word = w, definition = def }) end
                end
                if #results[i] == 0 and any and i == 1 then
                    results[i] = { { dict = "Demo", word = w, definition = "n. a demo sense" } }
                end
            end
            return false, results
        end)
    end

    setup(function()
        require("commonrequire")
        G_reader_settings:saveSetting("vocabulary_builder", vocab_settings)
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
        Translator = require("ui/translator")
        Trapper = require("ui/trapper")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Screen = require("device").screen
        ReaderHighlightBubble.register()
        ReaderDictSheet.register()
        Replacements.reader_search = require("apps/reader/modules/readerfulltextsearch")
    end)

    teardown(function()
        Replacements.reader_highlight = nil
        Replacements.reader_dictionary = nil
        Replacements.reader_search = nil
        G_reader_settings:delSetting("vocabulary_builder")
        DocSettings:open(sample_epub):purge()
        DocSettings:open(sample_pdf):purge()
    end)

    -- Phrase lookup starts from a temporary selection with the explicit legacy Ask action.
    before_each(function() G_reader_settings:saveSetting("default_highlight_action", "ask") end)
    after_each(function() G_reader_settings:delSetting("default_highlight_action") end)

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function tap(x, y)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
    end

    local function tapWidget(widget)
        tap(widget.dimen.x + math.floor(widget.dimen.w / 2), widget.dimen.y + math.floor(widget.dimen.h / 2))
        UIManager:forceRePaint()
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

    local function assertNoFull(refreshes)
        for _, r in ipairs(refreshes) do
            assert.is_truthy(r.region)
            assert.is_false(r.mode == "full" or r.mode == "flashui" or r.mode == "flashpartial", r.mode)
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

    local function hasTextLike(widget, pattern)
        return find(widget, function(w) return type(w.text) == "string" and w.text:find(pattern) ~= nil end) ~= nil
    end

    -- the tappable widget (a card or a pill) holding `text`
    local function button(widget, text)
        return find(widget, function(w)
            return w.callback and w.dimen and find(w, function(c) return c.text == text end) ~= nil
        end)
    end

    -- whether `phonetic` is on the headword's row
    local function besideHeadword(page, headword, phonetic)
        return find(page, function(w)
            return w[1] and w[1].text == headword and find(w, function(c) return c.text == phonetic end) ~= nil
        end) ~= nil
    end

    -- the lookup page on top, if any
    local function lookupPage()
        local top = topWidget()
        -- (the upstream popup's `dictionary` is the name of the shown dictionary)
        return type(top.dictionary) == "table" and top.ui and top.ui.dictionary == top.dictionary and top or nil
    end

    local function back(page)
        tapWidget(page.bar.back)
    end

    local function nextPage(page)
        local r = page.bar.capsule.next_rect
        tap(r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2))
        UIManager:forceRePaint()
    end

    -- the tappable widget holding `text` on whichever page, turning pages with the capsule
    local function seek(page, text)
        while page.bar.capsule.prev_enabled do
            local r = page.bar.capsule.prev_rect
            tap(r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2))
            UIManager:forceRePaint()
        end
        while true do
            local found = button(page, text)
            if found or not page.bar.capsule.next_enabled then return found end
            nextPage(page)
        end
    end

    -- runs the translation request in-process, with a controlled response; `during(trap)` runs while it waits.
    -- Returns the stub of the request.
    local function stubTranslator(response, during)
        stub(Trapper, "dismissableRunInSubprocess").invokes(function(_, task, trap)
            if during then
                local go_on = during(trap)
                if go_on == false then return false end
            end
            return true, task()
        end)
        return stub(Translator, "loadPage").invokes(function(_, text)
            if type(response) == "function" then return response(text) end
            return response
        end)
    end

    local function revertTranslator()
        Trapper.dismissableRunInSubprocess:revert()
        Translator.loadPage:revert()
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

        it("should try language plugin candidates first, and lowercase any capitalized word", function()
            local c = ReaderDictSheet.candidates("食べた", { "食べる" })
            assert.are.same({ "食べた", "食べる" }, { c[1], c[2] })
            assert.are.equal("être", ReaderDictSheet.candidates("Être")[2])
            assert.are.equal("привет", ReaderDictSheet.candidates("Привет")[2])
        end)

        it("should parse the phonetic and part-of-speech senses", function()
            local phonetic, senses = ReaderDictSheet.parseEntry{ { dict = "Demo", word = "sojourner", definition = DICT.sojourner.Demo } }
            assert.are.equal("/ˈsɒdʒənə(r)/", phonetic)
            assert.are.equal(2, #senses)
            assert.are.equal("n.", senses[1].pos)
            assert.are.equal("a person who stays in a place for a while and then moves on", senses[1].text)
            assert.is_nil(senses[2].pos)
            phonetic, senses = ReaderDictSheet.parseEntry{ { dict = "Demo", word = "x", definition = "*[ə'baut] prep. 关于" } }
            assert.are.equal("[ə'baut]", phonetic)
            assert.are.same({ pos = "prep.", text = "关于", dict = "Demo" }, senses[1])
        end)

        it("should parse an HTML entry's blocks as senses, without its style and scripts", function()
            local phonetic, senses = ReaderDictSheet.parseEntry{ {
                dict = "Html", word = "x", is_html = true,
                definition = "<style>b { color: red }</style><div>[ʃi]</div><div><b>n.</b> 一种演示</div>"
                    .. "<p>adj. 另一种 &amp; 别的</p><script>alert(1)</script><ul><li>例句一</li></ul>",
            } }
            assert.are.equal("[ʃi]", phonetic)
            assert.are.same({
                { pos = "n.", text = "一种演示", dict = "Html" },
                { pos = "adj.", text = "另一种 & 别的", dict = "Html" },
                { text = "例句一", dict = "Html" },
            }, senses)
        end)
    end)

    describe("with an EPUB", function()
        local ui
        before_each(function()
            vocab_settings.with_context = true
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
            if type(ui.dictionary.rawSdcv) == "table" then ui.dictionary.rawSdcv:revert() end
            ui:onClose()
            UIManager:quit()
        end)

        -- Long-press at pos0, drag to pos1 (if any), release, then Translate (the text is Latin) in the popover.
        local function selectAndLookUp(pos0, pos1)
            ui.highlight:onHold(nil, { pos = pos0 or Geom:new{ x = 400, y = 110 } })
            if pos1 then
                ui.highlight:onHoldPan(nil, { pos = pos1 })
            end
            UIManager:forceRePaint()
            ui.highlight:onHoldRelease()
            UIManager:forceRePaint()
            local text = require("util").cleanupSelectedText(ui.highlight.selected_text.text)
            local refreshes = refreshesOf(function()
                tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
            end)
            return refreshes, text
        end

        local function selectPhrase()
            return selectAndLookUp(Geom:new{ x = 400, y = 110 }, Geom:new{ x = 400, y = 170 })
        end

        local clock = 0 -- gesture times, a second apart: past any rate limit
        local function gesture(kind, pos)
            clock = clock + 1
            UIManager:sendEvent(Event:new("Gesture", {
                ges = kind, pos = Geom:new{ x = pos.x, y = pos.y, w = 0, h = 0 }, time = require("ui/time").s(clock),
            }))
        end

        -- A long-press at `from`, dragged through the other positions if any, then released.
        local function longPress(from, ...)
            local last = from
            gesture("hold", from)
            for _, pos in ipairs{ ... } do
                gesture("hold_pan", pos)
                last = pos
            end
            UIManager:forceRePaint()
            gesture("hold_release", last)
            UIManager:forceRePaint()
        end

        local SAMPSON = { x = 100, y = 160 } -- a speaker's name alone on its line
        -- from SAMPSON down to the next lines: without a selection preference, this drag saves a highlight
        local PHRASE = { { x = 300, y = 200 }, { x = 300, y = 230 }, { x = 300, y = 260 } }

        -- A long-press near the page foot dragged into its bottom right corner (the page scrolls on) and back out:
        -- a selection across two pages.
        local function selectAcrossPages()
            local w, h = Screen:getWidth(), Screen:getHeight()
            longPress({ x = 100, y = 740 }, { x = 300, y = 745 }, { x = w - 5, y = h - 5 }, { x = w - 150, y = h - 150 })
        end

        -- The card (a rounded frame) holding `text`, such as its heading.
        local function cardOf(page, text)
            return find(page, function(w) return w.radius == Screen:scaleBySize(14) and hasText(w, text) end)
        end

        it("should open a full-screen stack of cards, one per dictionary named on it, without source chips", function()
            stubSdcv(ui.dictionary, true)
            local refreshes, text = selectAndLookUp()
            local page = lookupPage()
            assert.is_truthy(page)
            assert.are.equal(ui.dictionary.dict_window, page)
            assert.is_true(page.covers_fullscreen)
            -- opened whole with "ui", as full-screen pages are; nothing flashes
            assert.is_true(hasRefresh(refreshes, "ui", page.dimen))
            assertNoFull(refreshes)
            -- the headword card, then the dictionary's card, named
            assert.is_true(hasText(page, text))
            local card = button(page, "Demo")
            assert.is_truthy(card)
            assert.is_true(hasText(card, "a demo sense"))
            assert.is_true(hasText(card, "n."))
            -- a centered column of cards, not a bottom sheet with chips
            assert.are.equal(Screen:getWidth() - card.dimen.x - card.dimen.w, card.dimen.x)
            assert.is_true(card.dimen.y + card.dimen.h < page.bar.dimen.y)
            assert.is_nil(button(page, "Dictionary"))
            assert.is_nil(find(page, function(w) return w.text == "Look up" end))
            -- the card for 维基百科 and the actions on the book's word follow
            assert.is_truthy(button(page, "Encyclopedia definition"))
            assert.is_truthy(button(page, "Add to vocabulary builder"))
            assert.is_truthy(button(page, "Search in this book"))
        end)

        it("should name every dictionary on its own card, with its senses", function()
            stubSdcv(ui.dictionary)
            ui:handleEvent(Event:new("LookupWord", "sojourner", false, nil, ui.highlight))
            UIManager:forceRePaint()
            local page = lookupPage()
            assert.is_true(besideHeadword(page, "sojourner", "/ˈsɒdʒənə(r)/"))
            local demo, other = button(page, "Demo"), button(page, "Other")
            assert.is_true(hasText(demo, "旅居者；暂住者"))
            assert.is_false(hasText(demo, "sojourner: someone who lives somewhere for a short time"))
            assert.is_true(hasText(other, "sojourner: someone who lives somewhere for a short time"))
            assert.is_true(demo.dimen.y < other.dimen.y)
            assert.is_false(hasText(demo, "/ˈsɒdʒənə(r)/")) -- not again

            -- the headword takes the first phonetic any dictionary has, wherever it is
            back(page)
            DICT.sojourner.Demo, DICT.sojourner.Other = DICT.sojourner.Other, DICT.sojourner.Demo
            ui:handleEvent(Event:new("LookupWord", "sojourner"))
            UIManager:forceRePaint()
            DICT.sojourner.Demo, DICT.sojourner.Other = DICT.sojourner.Other, DICT.sojourner.Demo
            page = lookupPage()
            assert.is_true(besideHeadword(page, "sojourner", "/ˈsɒdʒənə(r)/"))
            assert.is_false(hasText(button(page, "Other"), "/ˈsɒdʒənə(r)/"))
        end)

        it("should show a card per dictionary read in process where child processes cannot run (iOS)", function()
            local Device = require("device")
            stub(Device, "canForkProcesses").returns(false)
            spy.on(Trapper, "dismissablePopen")
            ui.dictionary.data_dir = "spec/front/unit/fixtures/stardict"
            ui.dictionary.enabled_dict_names = { "Other", "Demo" }
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("LookupWord", "apple", false, nil, ui.highlight))
                UIManager:forceRePaint()
                local page = lookupPage()
                assert.is_truthy(page)
                local other, demo = button(page, "Other"), button(page, "Demo")
                assert.is_truthy(other)
                assert.is_truthy(demo)
                assert.is_true(other.dimen.y < demo.dimen.y)
                assert.is_true(hasTextLike(other, "a fruit"))
                assert.is_true(hasTextLike(demo, "round fruit of a tree"))
                assert.is_true(besideHeadword(page, "apple", "[ˈæpl]"))
                assert.spy(Trapper.dismissablePopen).was_not_called()
            end)
            Device.canForkProcesses:revert()
            Trapper.dismissablePopen:revert()
            assert(ok, err)
        end)

        it("should go back to the selection's page with the back arrow, the selection staying a moment", function()
            stubSdcv(ui.dictionary, true)
            local mock_time = require("mock_time")
            mock_time:install()
            UIManager:_checkTasks() -- the clock is now the mock's
            local ok, err = pcall(function()
                local xp = ui.rolling:getBookLocation()
                selectAndLookUp()
                local page = lookupPage()
                local refreshes = refreshesOf(function() back(page) end)
                assert.are.equal(ui, topWidget())
                assert.is_nil(ui.dictionary.dict_window)
                assert.is_false(UIManager:isWidgetShown(page))
                assert.is_true(hasRefresh(refreshes, "ui", page.dimen))
                assertNoFull(refreshes)
                assert.are.same(xp, ui.rolling:getBookLocation())
                -- the selection is still where it was, then goes
                assert.is_truthy(ui.highlight.selected_text)
                mock_time:increase(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S") + 0.1)
                UIManager:_checkTasks()
                assert.is_nil(ui.highlight.selected_text)
                assert.are.equal(0, #ui.annotation.annotations)
            end)
            mock_time:uninstall()
            assert(ok, err)
        end)

        it("should call the close callback once when going back", function()
            stubSdcv(ui.dictionary)
            local closed = spy.new(function() end)
            ui:handleEvent(Event:new("LookupWord", "sojourner", false, nil, nil, nil, closed))
            UIManager:forceRePaint()
            back(lookupPage())
            assert.is_nil(ui.dictionary.dict_window)
            assert.spy(closed).was_called(1)
        end)

        it("should look up an English word in the local dictionaries, not online", function()
            stubSdcv(ui.dictionary, true)
            local load = stubTranslator({})
            local _, text = selectAndLookUp()
            revertTranslator()
            assert.is_nil(text:find("%s"))
            assert.are.equal(text, sdcv_words[1])
            assert.stub(load).was_not_called()
            assert.is_falsy(lookupPage().translation)
            assert.is_false(hasText(lookupPage(), "Online translation"))
        end)

        it("should translate a phrase online when no local dictionary has it, saying it needs the network", function()
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            local waiting
            local load = stubTranslator({ { { "一个演示短语。", "a demo phrase." } }, nil, "en" }, function(trap)
                -- while the request runs: the page is up, the translation card waits
                waiting = trap == lookupPage() and hasText(trap, "Looking up…") and hasText(trap, "Online translation")
            end)
            local refreshes, text = selectPhrase()
            NetworkMgr.isOnline:revert()
            revertTranslator()
            assert.is_truthy(text:find("%S%s+%S"))
            assert.are.equal(text, sdcv_words[1]) -- the dictionaries first
            assert.stub(load).was_called_with(match.is_ref(Translator), text, match._, match._)
            assert.is_true(waiting)
            local page = lookupPage()
            assert.is_true(hasText(page, "Online translation"))
            assert.is_true(hasText(page, "Needs a network connection"))
            assert.is_true(hasText(page, "一个演示短语。"))
            assert.is_false(hasText(page, "Looking up…"))
            -- no "not in the dictionaries" card, and no vocabulary for a phrase; Wikipedia, as for any selection
            assert.is_false(hasTextLike(page, "in local dictionaries"))
            assert.is_truthy(button(page, "Encyclopedia definition"))
            assert.is_nil(button(page, "Add to vocabulary builder"))
            assert.is_truthy(button(page, "Search in this book"))
            assertNoFull(refreshes)
        end)

        it("should translate into the interface language unless the translator has its own", function()
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            local load = stubTranslator({ { { "x", "x" } } })
            local GetText = require("gettext")
            local targets = {}
            local function target(ui_lang, setting)
                G_reader_settings:saveSetting("translator_to_language", setting)
                GetText.current_lang = ui_lang -- as from the system's LANG, the language setting being unset
                ui:handleEvent(Event:new("LookupWord", "a demo phrase"))
                UIManager:forceRePaint()
                back(lookupPage())
                table.insert(targets, load.calls[#load.calls].vals[3])
            end
            local ok, err = pcall(function()
                target("zh_CN")
                target("zh_TW")
                target("fr_FR")
                target("C")
                target("zh_CN", "ja")
                -- the same as the translator's own (its menu, the upstream popup's Translate button)
                G_reader_settings:delSetting("translator_to_language")
                GetText.current_lang = "zh_CN"
                assert.are.equal("zh", Translator:getTargetLanguage())
            end)
            GetText.current_lang = "C"
            G_reader_settings:delSetting("translator_to_language")
            NetworkMgr.isOnline:revert()
            revertTranslator()
            assert(ok, err)
            assert.are.same({ "zh", "zh-TW", "fr", "en", "ja" }, targets)
        end)

        it("should show the offline state of the translation, and translate once Wi-Fi is on", function()
            stubSdcv(ui.dictionary)
            local online = false -- Wi-Fi off
            stub(NetworkMgr, "isOnline").invokes(function() return online end)
            stub(NetworkMgr, "isConnected").invokes(function() return online end)
            stub(NetworkMgr, "runWhenOnline").invokes(function(_, callback) online = true callback() end)
            local load = stubTranslator({ { { "离线之后", "x" } } })
            selectPhrase()
            local page = lookupPage()
            assert.stub(load).was_not_called()
            assert.is_true(hasText(page, "Needs a network connection"))
            assert.is_true(hasText(page, "Online translation needs Wi-Fi. Turn it on and try again."))
            local region = page.body_rect
            local refreshes = refreshesOf(function() tapWidget(button(page, "Turn on Wi-Fi")) end)
            NetworkMgr.isOnline:revert()
            NetworkMgr.isConnected:revert()
            NetworkMgr.runWhenOnline:revert()
            revertTranslator()
            assert.is_true(hasText(page, "离线之后"))
            assertNoFull(refreshes)
            assert.is_true(hasRefresh(refreshes, "ui", region))
        end)

        it("should show a failure with Retry when the translation service fails, and retry", function()
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            local fail = true
            stubTranslator(function()
                if fail then error("network unreachable") end
                return { { { "重试成功", "x" } } }
            end)
            selectPhrase()
            local page = lookupPage()
            assert.is_true(hasText(page, "Translation failed."))
            assert.is_true(hasText(page, "Check the network connection and try again."))
            fail = false
            tapWidget(button(page, "Retry"))
            NetworkMgr.isOnline:revert()
            revertTranslator()
            assert.is_true(hasText(page, "重试成功"))
            assert.is_false(hasText(page, "Translation failed."))
        end)

        it("should abandon the translation when going back while it runs", function()
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            local dismissed = spy.new(function() end)
            stubTranslator({ { { "太晚了", "x" } } }, function(trap)
                trap.dismiss_callback = dismissed
                back(trap)
                return false -- not completed: dismissed
            end)
            local closed = spy.new(function() end)
            ui.highlight:onHold(nil, { pos = Geom:new{ x = 400, y = 110 } })
            ui.highlight:onHoldPan(nil, { pos = Geom:new{ x = 400, y = 170 } })
            ui.highlight:onHoldRelease()
            UIManager:forceRePaint()
            local text = require("util").cleanupSelectedText(ui.highlight.selected_text.text)
            ui.highlight:closeBubble()
            ui:handleEvent(Event:new("LookupWord", text, false, nil, ui.highlight, nil, closed))
            NetworkMgr.isOnline:revert()
            revertTranslator()
            assert.spy(dismissed).was_called(1)
            assert.spy(closed).was_called(1)
            assert.is_nil(lookupPage())
            assert.is_nil(ui.dictionary.dict_window)
        end)

        it("should keep a long-pressed word local and translate a dragged phrase, without a selection preference", function()
            G_reader_settings:delSetting("default_highlight_action")
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            local load = stubTranslator({ { { "我的武器出鞘了。", "x" } } })
            local xp = ui.rolling:getBookLocation()
            -- a word stays a temporary selection, and goes to the local dictionaries only
            longPress(SAMPSON)
            tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
            assert.are.equal("SAMPSON", sdcv_words[1])
            assert.stub(load).was_not_called()
            assert.is_truthy(button(lookupPage(), "Translate online"))
            back(lookupPage())
            -- a phrase dragged over three lines is saved, then translated online after the dictionaries
            longPress(SAMPSON, unpack(PHRASE))
            assert.are.equal(1, #ui.annotation.annotations)
            local refreshes = refreshesOf(function()
                tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
            end)
            NetworkMgr.isOnline:revert()
            revertTranslator()
            local phrase = "SAMPSON\nMy naked weapon is out: quarrel, I will back thee.\nGREGORY"
            assert.are.equal(phrase, sdcv_words[1])
            assert.stub(load).was_called(1)
            assert.stub(load).was_called_with(match.is_ref(Translator), phrase, match._, match._)
            local page = lookupPage()
            assert.is_true(hasText(cardOf(page, "Online translation"), "Needs a network connection"))
            assert.is_true(hasText(cardOf(page, "Online translation"), "我的武器出鞘了。"))
            assertNoFull(refreshes)
            -- back to the book where it was, under the phrase's one highlight, with nothing left over it
            refreshes = refreshesOf(function() back(page) end)
            assert.are.equal(1, #UIManager._window_stack)
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.dictionary.dict_window)
            assert.is_nil(ui.highlight.highlight_dialog)
            assert.are.same(xp, ui.rolling:getBookLocation())
            assert.are.equal(1, #ui.annotation.annotations)
            assert.is_true(hasRefresh(refreshes, "ui", page.dimen))
            assertNoFull(refreshes)
        end)

        for _, preference in ipairs{ "none", "ask" } do
            it("should come back to the first page of a phrase selected across pages after translating it ("
                    .. preference .. ")", function()
                if preference == "none" then G_reader_settings:delSetting("default_highlight_action") end
                local mock_time = require("mock_time")
                mock_time:install()
                UIManager:_checkTasks() -- the clock is now the mock's
                local ok, err = pcall(function()
                    stubSdcv(ui.dictionary)
                    stub(NetworkMgr, "isOnline").returns(true)
                    local load = stubTranslator({ { { "跨页的译文", "x" } } })
                    local first, xp = ui.view.state.page, ui.rolling:getBookLocation()
                    selectAcrossPages()
                    -- a saved highlight's popover comes once the page has turned back, a few ticks later
                    for _ = 1, 3 do UIManager:_checkTasks() end
                    UIManager:forceRePaint()
                    tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
                    NetworkMgr.isOnline:revert()
                    revertTranslator()
                    local text = load.calls[1].vals[2]
                    assert.is_truthy(text:find("^SAMPSON")) -- from the page foot…
                    assert.is_truthy(text:find("ABRAHAM$")) -- …into the text the corner scrolled to
                    local page = lookupPage()
                    assert.is_true(hasText(page, "跨页的译文"))
                    back(page)
                    mock_time:increase(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S") + 0.1)
                    UIManager:_checkTasks()
                    UIManager:forceRePaint()
                    -- the first page again, as before the selection, in page mode
                    assert.are.equal(1, #UIManager._window_stack)
                    assert.are.equal("page", ui.view.view_mode)
                    assert.are.equal(first, ui.view.state.page)
                    assert.are.same(xp, ui.rolling:getBookLocation())
                    assert.is_nil(ui.highlight.hold_pos)
                    -- saved without a preference; a temporary selection with ask, gone now
                    assert.are.equal(preference == "none" and 1 or 0, #ui.annotation.annotations)
                end)
                mock_time:uninstall()
                assert(ok, err)
            end)
        end

        it("should drop a translation answering as the page is left, changing and repainting nothing", function()
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            local dismissed = spy.new(function() end)
            local page, updates
            stubTranslator({ { { "太晚了", "x" } } }, function(trap)
                -- as Trapper does: closing the page calls the request's dismiss callback
                trap.dismiss_callback = dismissed
                page, updates = trap, spy.on(trap, "update")
                back(trap) -- and the answer comes in the same tick, as completed
            end)
            longPress(SAMPSON, unpack(PHRASE)) -- with ask: a temporary selection
            tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
            NetworkMgr.isOnline:revert()
            revertTranslator()
            assert.spy(dismissed).was_called(1)
            assert.is_false(UIManager:isWidgetShown(page))
            assert.are.same({ loading = true }, page.translation)
            assert.spy(updates).was_not_called()
            assert.are.equal(1, #UIManager._window_stack)
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.dictionary.dict_window)
        end)

        it("should stay offline when turning on Wi-Fi is declined, and leave nothing over the book", function()
            stubSdcv(ui.dictionary)
            local online = false -- Wi-Fi off
            stub(NetworkMgr, "isOnline").invokes(function() return online end)
            stub(NetworkMgr, "isConnected").invokes(function() return online end)
            local online_callback
            -- declined or cancelled: NetworkMgr never runs the callback (here: not before the page is gone)
            local wifi = stub(NetworkMgr, "runWhenOnline").invokes(function(_, callback) online_callback = callback end)
            local load = stubTranslator({ { { "不该出现", "x" } } })
            longPress(SAMPSON, unpack(PHRASE))
            tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
            local page = lookupPage()
            local refreshes = refreshesOf(function()
                tapWidget(button(cardOf(page, "Online translation"), "Turn on Wi-Fi"))
            end)
            assert.stub(wifi).was_called(1)
            assert.stub(load).was_not_called()
            local translation = cardOf(page, "Online translation")
            assert.is_true(hasText(translation, "Online translation needs Wi-Fi. Turn it on and try again."))
            assert.is_truthy(button(translation, "Turn on Wi-Fi"))
            assert.is_false(hasText(page, "Looking up…"))
            assertNoFull(refreshes)
            back(page)
            assert.are.equal(1, #UIManager._window_stack)
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.dictionary.dict_window)
            -- Wi-Fi coming on after the page has gone sends nothing
            online = true
            online_callback()
            UIManager:forceRePaint()
            NetworkMgr.isOnline:revert()
            NetworkMgr.isConnected:revert()
            NetworkMgr.runWhenOnline:revert()
            revertTranslator()
            assert.stub(load).was_not_called()
            assert.are.equal(1, #UIManager._window_stack)
        end)

        it("should offer the online translation of a phrase a dictionary has, sending it only on a tap", function()
            DICT["look up"] = { Demo = "v. to search for a word in a dictionary" }
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            local load = stubTranslator({ { { "查阅", "x" } } })
            ui:handleEvent(Event:new("LookupWord", "look up", false, nil, ui.highlight))
            UIManager:forceRePaint()
            DICT["look up"] = nil
            local page = lookupPage()
            assert.stub(load).was_not_called()
            local entry, row = button(page, "Demo"), button(page, "Online translation")
            assert.is_true(hasText(entry, "to search for a word in a dictionary"))
            assert.is_truthy(row)
            assert.is_true(hasText(row, "Needs a network connection"))
            assert.is_true(entry.dimen.y < row.dimen.y) -- under the dictionaries
            local region = page.body_rect
            local refreshes = refreshesOf(function() tapWidget(row) end)
            assert.stub(load).was_called(1)
            assert.stub(load).was_called_with(match.is_ref(Translator), "look up", match._, match._)
            -- the translation card in its place, the dictionary's card kept
            local translation = cardOf(page, "Online translation")
            assert.is_true(hasText(translation, "查阅"))
            assert.is_true(hasText(translation, "Needs a network connection"))
            assert.is_nil(button(page, "Online translation"))
            assert.is_true(hasText(button(page, "Demo"), "to search for a word in a dictionary"))
            for _, r in ipairs(refreshes) do assert.are.same({ mode = "ui", region = region }, r) end
            -- a word the dictionaries have gets no such row
            back(page)
            ui:handleEvent(Event:new("LookupWord", "sojourner", false, nil, ui.highlight))
            UIManager:forceRePaint()
            NetworkMgr.isOnline:revert()
            revertTranslator()
            assert.is_truthy(button(lookupPage(), "Demo"))
            assert.is_nil(button(lookupPage(), "Online translation"))
            assert.stub(load).was_called(1)
        end)

        it("should not send a selection of more than 1500 characters to the translator, saying it is too long", function()
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            local load = stubTranslator({ { { "过长", "x" } } })
            -- from the top of the page on past its foot: the page scrolls on by a third from its bottom right corner,
            -- each time the finger comes back into it
            local w, h = Screen:getWidth(), Screen:getHeight()
            local drag = { { x = 300, y = 400 }, { x = 500, y = 700 } }
            for _ = 1, 10 do
                table.insert(drag, { x = w - 5, y = h - 5 })
                table.insert(drag, { x = w - 150, y = h - 150 })
            end
            longPress({ x = 80, y = 30 }, unpack(drag))
            local selected = require("util").cleanupSelectedText(ui.highlight.selected_text.text)
            assert.is_true(#require("util").splitToChars(selected) > 1500, #selected)
            tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
            NetworkMgr.isOnline:revert()
            revertTranslator()
            local page = lookupPage()
            assert.stub(load).was_not_called()
            local translation = cardOf(page, "Online translation")
            assert.is_true(hasText(translation, "Selection too long to look up"))
            assert.is_nil(button(translation, "Retry"))
            assert.is_false(hasText(page, "Looking up…"))
            assert.is_false(hasText(page, "Translation failed."))
        end)

        it("should translate Latin text that Chinese punctuation sets off, as its popover says Translate", function()
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            local load = stubTranslator(function(text) return { { { "译：" .. text, "x" } } } end)
            -- a phrase, even past the 20 characters a Chinese selection is matched by
            for _, phrase in ipairs{ "「Xerox PARC」", "「the mouse and the graphical user interface」" } do
                assert.is_false(ui.highlight:isLookedUp(phrase))
                ui:handleEvent(Event:new("LookupWord", phrase, false, nil, ui.highlight))
                UIManager:forceRePaint()
                local page = lookupPage()
                assert.are.equal(phrase, load.calls[#load.calls].vals[2])
                assert.is_true(hasText(cardOf(page, "Online translation"), "译：" .. phrase))
                assert.is_false(hasText(page, "Selection too long to look up"))
                back(page)
            end
            -- a word: the dictionaries first, then online on demand
            ui:handleEvent(Event:new("LookupWord", "PARC，", false, nil, ui.highlight))
            UIManager:forceRePaint()
            assert.are.equal(2, #load.calls)
            tapWidget(button(lookupPage(), "Translate online"))
            NetworkMgr.isOnline:revert()
            revertTranslator()
            assert.are.equal("PARC，", load.calls[3].vals[2])
            assert.is_true(hasText(lookupPage(), "译：PARC，"))
        end)

        it("should not ask for Wi-Fi when connected without internet access, and load both online cards on retry", function()
            local Wikipedia = require("ui/wikipedia")
            stubSdcv(ui.dictionary)
            local online, connected = false, false
            stub(NetworkMgr, "isOnline").invokes(function() return online end)
            stub(NetworkMgr, "isConnected").invokes(function() return connected end)
            local wifi = stub(NetworkMgr, "runWhenOnline")
            local load = stubTranslator({ { { "联网之后", "x" } } })
            stub(Wikipedia, "searchAndGetIntros").returns({ [3] = { title = "Weapon", extract = "A weapon article.", index = 0 } })
            longPress(SAMPSON, unpack(PHRASE))
            tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
            local page = lookupPage()
            assert.is_truthy(button(cardOf(page, "Online translation"), "Turn on Wi-Fi"))
            -- Wi-Fi turned on from the system, the internet out of reach: 打开 Wi-Fi only checks again
            connected = true
            tapWidget(button(cardOf(page, "Online translation"), "Turn on Wi-Fi"))
            assert.stub(load).was_not_called()
            local translation = cardOf(page, "Online translation")
            assert.is_true(hasText(translation, "Needs a network connection")) -- still said
            assert.is_true(hasText(translation, "Network unreachable."))
            assert.is_true(hasText(translation, "Check the network connection and try again."))
            assert.is_nil(button(page, "Turn on Wi-Fi"))
            -- Wikipedia's card says the same, after its request showed it ran
            local region = page.body_rect
            local refreshes = refreshesOf(function() tapWidget(seek(page, "Encyclopedia definition")) end)
            assert.is_true(#refreshes > 0)
            for _, r in ipairs(refreshes) do assert.are.same({ mode = "ui", region = region }, r) end
            assert.is_true(hasText(cardOf(page, "Encyclopedia definition"), "Network unreachable."))
            assert.is_nil(button(page, "Turn on Wi-Fi"))
            -- a retry that fails again shows 查询中… first
            local shown = {}
            local update = page.update
            page.update = function(p, focus)
                update(p, focus)
                table.insert(shown, hasText(cardOf(p, "Online translation"), "Looking up…"))
            end
            tapWidget(button(cardOf(page, "Online translation"), "Retry"))
            page.update = update
            assert.are.same({ true, false }, shown)
            assert.is_true(hasText(cardOf(page, "Online translation"), "Network unreachable."))
            -- once the internet is back: the translation's Retry, then Wikipedia's
            online = true
            tapWidget(button(cardOf(page, "Online translation"), "Retry"))
            assert.is_true(hasText(cardOf(page, "Online translation"), "联网之后"))
            tapWidget(button(cardOf(page, "Encyclopedia definition"), "Retry"))
            NetworkMgr.isOnline:revert()
            NetworkMgr.isConnected:revert()
            NetworkMgr.runWhenOnline:revert()
            Wikipedia.searchAndGetIntros:revert()
            revertTranslator()
            assert.is_true(hasText(cardOf(page, "Encyclopedia definition"), "A weapon article."))
            assert.is_false(hasText(page, "Network unreachable."))
            assert.stub(wifi).was_not_called()
            assert.are.equal(2, #UIManager._window_stack)
        end)

        it("should show 查询中… while a slow lookup runs, then its results on the same page", function()
            local mock_time = require("mock_time")
            mock_time:install()
            UIManager:_checkTasks()
            local ok, err = pcall(function()
                stubSdcv(ui.dictionary, true)
                local raw = ui.dictionary.rawSdcv
                local seen
                ui.dictionary.rawSdcv = function(self, words, dict_names, fuzzy, trap)
                    -- nothing shows during the first half second; taps are caught all the same
                    assert.are.equal(trap, lookupPage() or trap)
                    assert.is_true(trap.invisible)
                    mock_time:increase(0.6)
                    local refreshes = refreshesOf(function() UIManager:_checkTasks() end)
                    seen = { page = lookupPage(), loading = hasText(lookupPage(), "Looking up…"), refreshes = refreshes }
                    return raw(self, words, dict_names, fuzzy, trap)
                end
                selectAndLookUp()
                ui.dictionary.rawSdcv = raw
                assert.is_truthy(seen.page)
                assert.is_true(seen.loading)
                assert.is_true(hasRefresh(seen.refreshes, "ui", seen.page.dimen))
                assert.are.equal(seen.page, lookupPage())
                assert.is_false(hasText(seen.page, "Looking up…"))
                assert.is_true(hasText(seen.page, "a demo sense"))
            end)
            mock_time:uninstall()
            assert(ok, err)
        end)

        it("should cancel a slow lookup with the back arrow of the waiting page", function()
            local mock_time = require("mock_time")
            mock_time:install()
            UIManager:_checkTasks()
            local ok, err = pcall(function()
                stubSdcv(ui.dictionary, true)
                ui.dictionary.rawSdcv:revert()
                local closed = spy.new(function() end)
                stub(ui.dictionary, "rawSdcv").invokes(function(_, _, _, _, trap)
                    -- as Trapper:dismissablePopen(): the trap's dismiss_callback cancels the command
                    local cancelled = false
                    trap.dismiss_callback = function() cancelled = true end
                    mock_time:increase(0.6)
                    UIManager:_checkTasks()
                    UIManager:forceRePaint()
                    back(lookupPage())
                    return cancelled, {}
                end)
                ui:handleEvent(Event:new("LookupWord", "sojourner", false, nil, ui.highlight, nil, closed))
                assert.are.equal(ui, topWidget())
                assert.is_nil(ui.dictionary.dict_window)
                assert.is_nil(ui.dictionary.lookup_page)
                assert.spy(closed).was_called(1)
            end)
            mock_time:uninstall()
            assert(ok, err)
        end)

        it("should go back to the book when a lookup is cancelled after a long wait, as right away", function()
            local mock_time = require("mock_time")
            mock_time:install()
            UIManager:_checkTasks()
            local ok, err = pcall(function()
                ui.highlight:onHold(nil, { pos = Geom:new{ x = 400, y = 110 } })
                ui.highlight:onHoldRelease()
                UIManager:forceRePaint()
                ui.highlight:closeBubble()
                local closed = spy.new(function() end)
                ui.dictionary.enabled_dict_names = { "Demo" }
                stub(ui.dictionary, "rawSdcv").invokes(function(_, _, _, _, trap)
                    local cancelled = false
                    trap.dismiss_callback = function() cancelled = true end
                    -- past upstream's 3 s, after which a cancelled lookup shows "interrupted" in its popup
                    mock_time:increase(3.5)
                    UIManager:_checkTasks()
                    UIManager:forceRePaint()
                    back(lookupPage())
                    return cancelled, {}
                end)
                ui:handleEvent(Event:new("LookupWord", "sojourner", false, nil, ui.highlight, nil, closed))
                UIManager:forceRePaint()
                -- nothing says "interrupted": the page is gone, as the back arrow asked
                assert.are.equal(ui, topWidget())
                assert.is_nil(ui.dictionary.dict_window)
                assert.are.equal(0, #DictQuickLookup.window_list)
                assert.spy(closed).was_called(1)
                -- the selection stays a moment, as when going back from results
                assert.is_truthy(ui.highlight.selected_text)
                mock_time:increase(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S") + 0.1)
                UIManager:_checkTasks()
                assert.is_nil(ui.highlight.selected_text)
            end)
            mock_time:uninstall()
            assert(ok, err)
        end)

        it("should say a word is not in the local dictionaries, and offer to translate it online", function()
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            local load = stubTranslator({ { { "朱丽叶", "x" } } })
            selectAndLookUp()
            local page = lookupPage()
            assert.is_true(hasText(page, ('No "%s" in local dictionaries'):format(page.word)))
            assert.is_true(hasText(page, "Try Wikipedia, or add more StarDict dictionaries in settings."))
            assert.is_truthy(button(page, "Add to vocabulary builder"))
            assert.is_truthy(button(page, "Encyclopedia definition"))
            assert.stub(load).was_not_called()
            tapWidget(button(page, "Translate online"))
            NetworkMgr.isOnline:revert()
            revertTranslator()
            assert.is_true(hasText(page, "朱丽叶"))
            assert.is_true(hasText(page, "Online translation"))
            assert.is_nil(button(page, "Translate online"))
        end)

        it("should say when no dictionary is installed", function()
            stubSdcv(ui.dictionary)
            ui.dictionary.rawSdcv:revert()
            stub(ui.dictionary, "rawSdcv").returns(false, nil)
            selectAndLookUp()
            local page = lookupPage()
            assert.is_true(hasText(page, "No dictionaries installed"))
            assert.is_true(hasText(page, 'To install dictionaries, search for "Dictionary support" in the KOReader wiki.'))
            assert.is_truthy(button(page, "Translate online"))
        end)

        it("should tell none installed from all disabled", function()
            stubSdcv(ui.dictionary)
            ui.dictionary.rawSdcv:revert()
            local sdcv = stub(ui.dictionary, "rawSdcv").returns(false, nil)
            ui.dictionary.enabled_dict_names = {} -- the test environment has no dictionaries: none is installed
            ui:handleEvent(Event:new("LookupWord", "sojourner"))
            UIManager:forceRePaint()
            assert.stub(sdcv).was_called(1)
            assert.is_true(hasText(lookupPage(), "No dictionaries installed"))
            back(lookupPage())
            -- some installed, all disabled: upstream's message
            stub(ui.dictionary, "getNumberOfDictionaries").returns(2, 0, 2)
            ui:handleEvent(Event:new("LookupWord", "sojourner"))
            UIManager:forceRePaint()
            ui.dictionary.getNumberOfDictionaries:revert()
            assert.stub(sdcv).was_called(1)
            assert.is_true(hasText(lookupPage(), "Not available"))
            assert.is_true(hasText(lookupPage(), "There are no enabled dictionaries.\nPlease check the 'Dictionary settings' menu."))
        end)

        it("should say no dictionary is installed above the translation of a phrase", function()
            stubSdcv(ui.dictionary)
            ui.dictionary.rawSdcv:revert()
            stub(ui.dictionary, "rawSdcv").returns(false, nil)
            stub(NetworkMgr, "isOnline").returns(true)
            stubTranslator({ { { "一个短语", "x" } } })
            ui:handleEvent(Event:new("LookupWord", "a demo phrase", false, nil, ui.highlight))
            UIManager:forceRePaint()
            NetworkMgr.isOnline:revert()
            revertTranslator()
            local page = lookupPage()
            assert.is_true(hasText(page, "No dictionaries installed"))
            assert.is_nil(button(page, "Translate online")) -- it is translated already
            assert.is_true(hasText(page, "一个短语"))
        end)

        it("should never send Chinese text to the translator", function()
            stubSdcv(ui.dictionary)
            local load = stubTranslator({})
            ui:handleEvent(Event:new("LookupWord", "我们读书吧", false, nil, ui.highlight))
            UIManager:forceRePaint()
            revertTranslator()
            local page = lookupPage()
            assert.stub(load).was_not_called()
            assert.is_true(hasText(page, 'No "我们读书吧" in local dictionaries'))
            assert.is_nil(button(page, "Translate online"))
            assert.is_false(hasText(page, "Online translation"))
        end)

        it("should look up the longest word in a long Chinese selection", function()
            stubSdcv(ui.dictionary)
            ui:handleEvent(Event:new("LookupWord", "我们读经典常谈"))
            UIManager:forceRePaint()
            local page = lookupPage()
            assert.are.equal("经典", page.headword)
            assert.is_true(hasText(page, "经典"))
            assert.is_true(hasText(page, "[jīng diǎn]"))
            assert.is_true(hasText(page, 'Selected "我们读经典常谈", found "经典" by longest match'))

            back(page)
            ui:handleEvent(Event:new("LookupWord", string.rep("读", 21)))
            UIManager:forceRePaint()
            assert.are.equal(1, #sdcv_words)
            assert.is_true(hasText(lookupPage(), "Selection too long to look up"))
        end)

        it("should look up the lemma of an English word", function()
            stubSdcv(ui.dictionary)
            ui:handleEvent(Event:new("LookupWord", "Stopped"))
            UIManager:forceRePaint()
            local page = lookupPage()
            assert.are.equal("stop", page.headword)
            assert.is_true(hasText(page, "stop"))
            assert.is_true(hasText(page, "/stɒp/"))
        end)

        it("should continue a long entry on the next pages under its dictionary's name, losing no sense", function()
            local senses = {}
            for i = 1, 30 do
                senses[i] = ("n. sense %d of a long entry, which takes a few lines on the card to say what it means"):format(i)
            end
            DICT.longword = { Demo = table.concat(senses, "\n") }
            stubSdcv(ui.dictionary)
            ui:handleEvent(Event:new("LookupWord", "longword"))
            UIManager:forceRePaint()
            DICT.longword = nil
            local page = lookupPage()
            assert.is_true(page.page_count > 1)
            local seen, pages_with_senses = {}, 0
            for p = 1, page.page_count do
                assert.are.equal(p, page.page)
                local senses_here = 0
                find(page, function(w)
                    local n = type(w.text) == "string" and w.text:match("^sense (%d+) of")
                    if n then
                        seen[tonumber(n)] = (seen[tonumber(n)] or 0) + 1
                        senses_here = senses_here + 1
                    end
                end)
                if senses_here > 0 then
                    -- every part of the entry is on a card named after its dictionary, above the bottom bar
                    pages_with_senses = pages_with_senses + 1
                    local card = button(page, "Demo")
                    assert.is_truthy(card, "page " .. p)
                    assert.is_true(card.dimen.y + card.dimen.h <= page.bar.dimen.y)
                end
                if p < page.page_count then
                    local region = page.body_rect
                    local refreshes = refreshesOf(function() nextPage(page) end)
                    assert.are.same({ { mode = "ui", region = region } }, refreshes)
                end
            end
            for i = 1, 30 do
                assert.are.equal(1, seen[i], "sense " .. i)
            end
            assert.is_true(pages_with_senses > 1)
        end)

        it("should save the exact EPUB context even when saving context is disabled, and confirm removal", function()
            stubSdcv(ui.dictionary, true)
            vocab_settings.with_context = false
            local Toast = require("ui/widget/toast")
            local vocab = ui.vocabbuilder
            -- as selectAndLookUp(), the word out of the vocabulary builder first
            ui.highlight:onHold(nil, { pos = Geom:new{ x = 400, y = 110 } })
            UIManager:forceRePaint()
            ui.highlight:onHoldRelease()
            UIManager:forceRePaint()
            local word = require("util").cleanupSelectedText(ui.highlight.selected_text.text)
            vocab:removeWord(word)
            tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
            local page = lookupPage()
            assert.are.equal(word, page.headword)
            tapWidget(button(page, "Add to vocabulary builder"))
            assert.is_true(vocab:hasWord(word))
            local item = package.loaded["db"]:hasWord(word)
            assert.are.equal("Montagues", word)
            assert.are.equal("Romeo and Juliet", item.book_title)
            assert.are.equal(epub_prev_context, item.prev_context)
            assert.are.equal(epub_next_context, item.next_context)
            assert.is_true(hasText(page, "In vocabulary builder"))
            assert.are.equal("Added to vocabulary builder", topWidget().text)
            UIManager:close(topWidget()) -- the toast
            assert.is_false(vocab_settings.with_context)
            -- The full entry's add action can encounter a word that was already saved by the card.
            tapWidget(button(page, "Demo"))
            local entry = topWidget()
            tapWidget(button(entry, "Add to vocabulary builder"))
            local duplicate = topWidget()
            assert.are.equal("Vocabulary exists: Montagues", duplicate.title)
            assert.are.equal("Romeo and Juliet", duplicate.book_title)
            assert.are.equal(epub_prev_context, duplicate.prev_context)
            assert.are.equal(epub_next_context, duplicate.next_context)
            duplicate:onClose()
            entry:onClose()
            UIManager:forceRePaint()
            assert.same(item, package.loaded["db"]:hasWord(word))
            -- a second tap asks first; cancelling keeps the word
            tapWidget(button(page, "In vocabulary builder"))
            local layer = topWidget()
            assert.is_true(hasText(layer, 'Remove "' .. word .. '" from the vocabulary builder?'))
            tapWidget(button(layer, "Cancel"))
            assert.are.equal(page, topWidget())
            assert.is_true(vocab:hasWord(word))
            tapWidget(button(page, "In vocabulary builder"))
            tapWidget(button(topWidget(), "Remove"))
            assert.is_false(vocab:hasWord(word))
            assert.is_true(hasText(page, "Add to vocabulary builder"))
            assert.are.equal(Toast, getmetatable(topWidget()))
            assert.are.equal("Removed from vocabulary builder", topWidget().text)
            UIManager:close(topWidget())
        end)

        it("should save an unknown word with its book and selected context for later review", function()
            stubSdcv(ui.dictionary)
            selectAndLookUp()
            local page = lookupPage()
            local word = page.word
            ui.vocabbuilder:removeWord(word)
            local add = seek(page, "Add to vocabulary builder")
            assert.is_truthy(add)
            tapWidget(add)
            UIManager:close(topWidget()) -- toast
            back(page)
            ui:handleEvent(Event:new("ShowVocabBuilder"))
            UIManager:forceRePaint()
            local vocab = topWidget()
            local item
            for _, entry in ipairs(vocab.item_table) do
                if entry.word == word then item = entry break end
            end
            assert.is_truthy(item)
            assert.are.equal("Montagues", word)
            assert.are.equal("Romeo and Juliet", item.book_title)
            assert.are.equal(epub_prev_context, item.prev_context)
            assert.are.equal(epub_next_context, item.next_context)
            UIManager:close(vocab)
            ui.vocabbuilder:removeWord(word)
        end)

        it("should hide the vocabulary card without the plugin or from within the vocabulary builder", function()
            stubSdcv(ui.dictionary)
            local vocab = ui.vocabbuilder
            vocab.widget = {}
            ui:handleEvent(Event:new("LookupWord", "sojourner"))
            UIManager:forceRePaint()
            assert.is_nil(seek(lookupPage(), "Add to vocabulary builder"))
            back(lookupPage())
            vocab.widget = nil
            ui.vocabbuilder = nil
            ui:handleEvent(Event:new("LookupWord", "sojourner"))
            UIManager:forceRePaint()
            ui.vocabbuilder = vocab
            assert.is_nil(seek(lookupPage(), "Add to vocabulary builder"))
        end)

        it("should request a Chinese headword in zh and remove blank paragraphs from its summary", function()
            local Wikipedia = require("ui/wikipedia")
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            ui.doc_props.language = "zh-CN"
            local requested_word, requested_language
            stub(Wikipedia, "searchAndGetIntros").invokes(function(_, word, lang)
                requested_word, requested_language = word, lang
                return { [1] = { title = "经典", extract = "经典可以指：\r\n\r\n \t\n典范著作\n\n权威作品\n\n" } }
            end)
            ui:handleEvent(Event:new("LookupWord", "经典"))
            UIManager:forceRePaint()
            local page = lookupPage()
            tapWidget(seek(page, "Encyclopedia definition"))
            Wikipedia.searchAndGetIntros:revert()
            NetworkMgr.isOnline:revert()
            assert.are.equal("经典", requested_word)
            assert.are.equal("zh", requested_language)
            assert.is_true(hasText(page, "经典可以指：\n典范著作\n权威作品"))
        end)

        for _, full in ipairs{ false, true } do
            it("should stay in the reader when lookup closes during Wikipedia loading (full=" .. tostring(full) .. ")", function()
                local Wikipedia = require("ui/wikipedia")
                stubSdcv(ui.dictionary, true)
                stub(NetworkMgr, "isOnline").returns(true)
                local page
                local function response()
                    if not full then page:onClose() end
                    return { [1] = { title = "Juliet", extract = "Summary." } }
                end
                stub(Wikipedia, "searchAndGetIntros").invokes(response)
                stub(Wikipedia, "getFullPage").invokes(function()
                    page:onClose()
                    return { [1] = { title = "Juliet", extract = "Full article." } }
                end)
                selectAndLookUp()
                page = lookupPage()
                tapWidget(seek(page, "Encyclopedia definition"))
                if full then tapWidget(button(page, "Encyclopedia definition")) end
                assert.stub(Wikipedia.getFullPage).was_called(full and 1 or 0)
                Wikipedia.searchAndGetIntros:revert()
                Wikipedia.getFullPage:revert()
                NetworkMgr.isOnline:revert()
                assert.is_true(page.closed)
                assert.is_nil(ui.dictionary.dict_window)
                assert.are.equal(ui, topWidget())
            end)
        end

        it("should go back to the card when the Wikipedia request is cancelled", function()
            local Wikipedia = require("ui/wikipedia")
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(true)
            stub(Wikipedia, "searchAndGetIntros").invokes(function() error(Wikipedia.dismissed_error_code) end)
            ui:handleEvent(Event:new("LookupWord", "sojourner"))
            UIManager:forceRePaint()
            local page = lookupPage()
            tapWidget(button(page, "Encyclopedia definition"))
            NetworkMgr.isOnline:revert()
            Wikipedia.searchAndGetIntros:revert()
            assert.is_nil(page.wiki)
            assert.is_truthy(button(page, "Encyclopedia definition"))
            assert.is_true(hasText(page, "旅居者；暂住者"))
            assert.is_false(hasText(page, "Failed searching Wikipedia."))
        end)

        it("should show the offline state of Wikipedia, repainting only the page's body", function()
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(false)
            stub(NetworkMgr, "isConnected").returns(false) -- Wi-Fi off
            ui:handleEvent(Event:new("LookupWord", "sojourner"))
            UIManager:forceRePaint()
            local page = lookupPage()
            local region = page.body_rect
            local refreshes = refreshesOf(function() tapWidget(button(page, "Encyclopedia definition")) end)
            NetworkMgr.isOnline:revert()
            NetworkMgr.isConnected:revert()
            assert.is_true(hasText(page, "Needs a network connection"))
            assert.is_true(hasText(page, "Wikipedia is an online lookup. Turn on Wi-Fi and try again."))
            assert.is_truthy(button(page, "Turn on Wi-Fi"))
            -- its request showing it ran, then the offline state
            assert.are.same({ { mode = "ui", region = region }, { mode = "ui", region = region } }, refreshes)
            assert.is_true(hasText(page, "旅居者；暂住者"))
        end)

        it("should open the complete Wikipedia article, page through it and return to the same lookup and book", function()
            local Wikipedia = require("ui/wikipedia")
            stubSdcv(ui.dictionary, true)
            stub(NetworkMgr, "isOnline").returns(true)
            stub(Wikipedia, "searchAndGetIntros").returns({ [7] = {
                title = "Juliet", extract = "The summary only.", index = 0,
            } })
            local full = "The full article.\n" .. string.rep("A paragraph beyond the summary.\n", 80) .. "Article ends here."
            local Blitbuffer = require("ffi/blitbuffer")
            local picture = { width = 40, height = 40, title = "Juliet illustration" }
            stub(Wikipedia, "getFullPage").invokes(function(_, title, lang)
                assert.are.equal("Juliet", title)
                assert.are.equal("en", lang)
                picture.bb = Blitbuffer.new(40, 40, Blitbuffer.TYPE_BB8)
                return { [7] = { title = title, extract = full, images = { picture } } }
            end)
            selectAndLookUp()
            local page = lookupPage()
            local anchor = ui.document:getXPointer()
            tapWidget(seek(page, "Encyclopedia definition"))
            assert.is_true(hasText(page, "The summary only."))
            local card_page = page.page
            ui.wikipedia.wiki_last_language = "fr" -- full article keeps the summary's language
            local refreshes = refreshesOf(function()
                for __ = 1, 2 do
                    tapWidget(button(page, "Encyclopedia definition"))
                    local article = topWidget()
                    assert.is_true(hasText(article, "Juliet"))
                    assert.is_true(hasText(article, full))
                    assert.is_truthy(find(article, function(w)
                        return w.line_num_to_image and w.line_num_to_image[1] == picture
                    end))
                    assert.is_true(article.page_count > 1)
                    while article.bar.capsule.next_enabled do nextPage(article) end
                    assert.are.equal(article.page_count, article.page)
                    back(article)
                    assert.are.equal(page, topWidget())
                    assert.is_nil(picture.bb)
                    assert.is_nil(picture.hi_bb)
                end
            end)
            ui.wikipedia.wiki_last_language = nil
            Wikipedia.getFullPage:revert()
            Wikipedia.searchAndGetIntros:revert()
            NetworkMgr.isOnline:revert()
            assertNoFull(refreshes)
            assert.are.equal(page, topWidget())
            assert.are.equal(card_page, page.page)
            assert.is_nil(picture.bb)
            assert.is_nil(picture.hi_bb)
            assert.is_true(hasText(page, "The summary only."))
            assert.is_truthy(ui.highlight.selected_text)
            back(page)
            assert.are.equal(ui, topWidget())
            assert.are.equal(anchor, ui.document:getXPointer())
        end)

        it("should discard pending article images on paging and closing, and load them on a later visit", function()
            local Wikipedia = require("ui/wikipedia")
            local Blitbuffer = require("ffi/blitbuffer")
            local mock_time = require("mock_time")
            mock_time:install()
            UIManager:_checkTasks()
            local picture = { width = 40, height = 40, title = "Juliet illustration" }
            local loads = 0
            picture.load_bb_func = function()
                loads = loads + 1
                picture.bb = Blitbuffer.new(40, 40, Blitbuffer.TYPE_BB8)
            end
            stubSdcv(ui.dictionary, true)
            stub(NetworkMgr, "isOnline").returns(true)
            stub(Wikipedia, "searchAndGetIntros").returns({ [1] = { title = "Juliet", extract = "Summary." } })
            stub(Wikipedia, "getFullPage").returns({ [1] = {
                title = "Juliet", extract = string.rep("Article paragraph.\n", 80), images = { picture },
            } })
            local ok, err = pcall(function()
                selectAndLookUp()
                local page = lookupPage()
                tapWidget(seek(page, "Encyclopedia definition"))
                tapWidget(button(page, "Encyclopedia definition"))
                nextPage(topWidget()) -- before the first image's timer runs
                mock_time:increase(1)
                UIManager:_checkTasks()
                assert.are.equal(0, loads)
                back(topWidget())
                tapWidget(button(page, "Encyclopedia definition"))
                back(topWidget()) -- close before the timer runs
                mock_time:increase(1)
                UIManager:_checkTasks()
                assert.are.equal(0, loads)
                assert.is_nil(picture.bb)
                tapWidget(button(page, "Encyclopedia definition"))
                mock_time:increase(1)
                UIManager:_checkTasks()
                assert.are.equal(1, loads)
                assert.is_truthy(picture.bb)
                back(topWidget())
                assert.is_nil(picture.bb)
                assert.are.equal(page, topWidget())
            end)
            Wikipedia.getFullPage:revert()
            Wikipedia.searchAndGetIntros:revert()
            NetworkMgr.isOnline:revert()
            mock_time:uninstall()
            assert(ok, err)
        end)

        for _, full in ipairs{ false, true } do
            it("should keep lookup context through Wikipedia offline, failure, no match, cancellation and retry (full=" .. tostring(full) .. ")", function()
                local Wikipedia = require("ui/wikipedia")
                stubSdcv(ui.dictionary, true)
                local online = false -- Wi-Fi off
                stub(NetworkMgr, "isOnline").invokes(function() return online end)
                stub(NetworkMgr, "isConnected").invokes(function() return online end)
                local state = "success"
                local function response()
                    if state == "failed" then error("network unavailable") end
                    if state == "missing" then return {} end
                    if state == "cancelled" then error(Wikipedia.dismissed_error_code) end
                    return { [7] = { title = "Juliet", extract = "Juliet article text.", index = 0 } }
                end
                stub(Wikipedia, "searchAndGetIntros").invokes(response)
                stub(Wikipedia, "getFullPage").invokes(response)
                stub(NetworkMgr, "runWhenOnline").invokes(function(_, callback) online = true callback() end)
                selectAndLookUp()
                local page = lookupPage()
                if full then
                    online = true
                    tapWidget(seek(page, "Encyclopedia definition"))
                    online = false
                end
                local anchor = ui.document:getXPointer()
                local refreshes = refreshesOf(function()
                    tapWidget(seek(page, "Encyclopedia definition"))
                    assert.is_truthy(seek(page, "Turn on Wi-Fi"))
                    state = "failed"
                    tapWidget(button(page, "Turn on Wi-Fi"))
                    assert.is_true(hasText(page, full and "Failed to retrieve Wikipedia article." or "Failed searching Wikipedia."))
                    state = "missing"
                    tapWidget(button(page, "Retry"))
                    assert.is_true(hasTextLike(page, full and "Wikipedia article not found" or "No Wikipedia article"))
                    state = "cancelled"
                    tapWidget(button(page, "Retry"))
                    assert.is_false(hasText(page, "Searching Wikipedia…"))
                    assert.is_false(hasText(page, "Retrieving Wikipedia article…"))
                    state = "success"
                    tapWidget(button(page, "Retry"))
                    if full then
                        assert.is_true(hasText(topWidget(), "Juliet article text."))
                        back(topWidget())
                    end
                end)
                NetworkMgr.runWhenOnline:revert()
                NetworkMgr.isOnline:revert()
                NetworkMgr.isConnected:revert()
                Wikipedia.searchAndGetIntros:revert()
                Wikipedia.getFullPage:revert()
                assertNoFull(refreshes)
                assert.are.equal(page, topWidget())
                assert.is_true(hasText(page, "Juliet article text."))
                assert.is_truthy(ui.highlight.selected_text)
                assert.are.equal(anchor, ui.document:getXPointer())
            end)
        end

        it("should search the selected text in the new search page and navigate a hit with the search bar", function()
            ui.dictionary.enabled_dict_names = { "Demo" }
            stub(ui.dictionary, "rawSdcv").returns(false, { { { dict = "Demo", word = "another lemma", definition = "n. sense" } } })
            stub(Trapper, "dismissableRunInSubprocess").invokes(function(_, task) return true, task() end)
            selectAndLookUp()
            local page = lookupPage()
            local selected = page.word
            local refreshes = refreshesOf(function() tapWidget(seek(page, "Search in this book")) end)
            Trapper.dismissableRunInSubprocess:revert()
            assertNoFull(refreshes)
            local search = topWidget()
            assert.are.equal(selected, search.input:getText())
            assert.is_true(#search.results > 0)
            assert.is_nil(ui.dictionary.dict_window)
            assert.is_nil(ui.highlight.selected_text)
            local hit = find(search, function(w) return w.hit_index and w.callback and w.dimen end)
            assert.is_truthy(hit)
            tapWidget(hit)
            assert.are.equal(ui, topWidget())
            assert.are.equal(selected, ui.search:barQuery())
            local bar = ui.search.bar:getRect()
            tap(bar.x + 20, bar.y + 10)
            UIManager:forceRePaint()
            assert.are.equal(selected, topWidget().input:getText())
            back(topWidget())
            tapWidget({ dimen = ui.search.bar:getCloseRect() })
            assert.is_nil(ui.search:barQuery())
        end)

        it("should open a dictionary's full entry in the upstream popup from its card, and come back to the cards", function()
            stubSdcv(ui.dictionary)
            local closed = spy.new(function() end)
            ui.highlight:onHold(nil, { pos = Geom:new{ x = 400, y = 110 } })
            ui.highlight:onHoldRelease()
            UIManager:forceRePaint()
            ui.highlight:closeBubble()
            ui:handleEvent(Event:new("LookupWord", "sojourner", false, nil, ui.highlight, nil, closed))
            UIManager:forceRePaint()
            local page = lookupPage()
            tapWidget(button(page, "Other"))
            local top = topWidget()
            assert.are.equal(DictQuickLookup.window_list[#DictQuickLookup.window_list], top)
            assert.are.equal(1, #top.results)
            assert.are.equal("Other", top.results[1].dict)
            -- over the page, without the selection: its search and highlight buttons are off (the page has them)
            assert.is_true(UIManager:isWidgetShown(page))
            assert.is_nil(top.highlight)
            assert.is_false(top:canSearch())
            assert.is_truthy(ui.highlight.selected_text)
            -- a lookup from inside the popup stays in the upstream popup
            ui:handleEvent(Event:new("LookupWord", "stop"))
            UIManager:forceRePaint()
            assert.are.equal(2, #DictQuickLookup.window_list)
            assert.are.equal(DictQuickLookup.window_list[2], topWidget())
            DictQuickLookup.window_list[2]:onClose()
            -- the vocabulary builder's own button in the popup adds the word: the card says so once back
            ui.vocabbuilder:removeWord("sojourner")
            assert.is_truthy(seek(page, "Add to vocabulary builder"))
            local add = button(top, "Add to vocabulary builder")
            assert.is_truthy(add)
            tapWidget(add)
            assert.is_true(ui.vocabbuilder:hasWord("sojourner"))
            top:onClose()
            UIManager:forceRePaint()
            assert.are.equal(page, lookupPage())
            assert.is_truthy(seek(page, "In vocabulary builder"))
            assert.is_nil(seek(page, "Add to vocabulary builder"))
            ui.vocabbuilder:removeWord("sojourner")
            assert.spy(closed).was_not_called()
            assert.is_truthy(ui.highlight.selected_text)
            back(page)
            assert.spy(closed).was_called(1)
        end)

        it("should continue a sense taller than a page from its next line, cutting nothing", function()
            local words = {}
            for i = 1, 700 do words[i] = "w" .. i end
            local long = table.concat(words, " ")
            DICT.longsense = { Demo = "n. " .. long .. "\nv. after it" }
            stubSdcv(ui.dictionary)
            ui:handleEvent(Event:new("LookupWord", "longsense"))
            UIManager:forceRePaint()
            DICT.longsense = nil
            local page = lookupPage()
            assert.is_true(page.page_count > 2)
            -- the slices of the sense, page after page, follow each other line by line, with no ellipsis
            local next_line, total, tags = 1, nil, 0
            for p = 1, page.page_count do
                find(page, function(w)
                    if w.text == long then
                        assert.are.equal(next_line, w.virtual_line_num)
                        assert.is_nil(w.line_with_ellipsis)
                        next_line = w.virtual_line_num + w.lines_per_page
                        total = #w.vertical_string_list
                    elseif w.text == "n." then
                        tags = tags + 1
                    end
                end)
                assert.is_truthy(button(page, "Demo"), "page " .. p)
                if p < page.page_count then nextPage(page) end
            end
            assert.are.equal(total + 1, next_line)
            assert.are.equal(1, tags) -- the part of speech only on its first line
            assert.is_nil(seek(page, "Tap the card for the rest of the entry."))
            assert.is_truthy(seek(page, "after it"))
        end)

        it("should measure the senses once, not on every change of a card", function()
            local senses = {}
            for i = 1, 100 do senses[i] = ("n. sense %d of a long entry"):format(i) end
            local entry = table.concat(senses, "\n")
            DICT.manysenses = { Demo = entry, Other = entry }
            stubSdcv(ui.dictionary)
            stub(NetworkMgr, "isOnline").returns(false)
            stub(NetworkMgr, "isConnected").returns(false) -- Wi-Fi off
            ui:handleEvent(Event:new("LookupWord", "manysenses"))
            UIManager:forceRePaint()
            DICT.manysenses = nil
            local page = lookupPage()
            local wiki = seek(page, "Encyclopedia definition")
            local TextBoxWidget = require("ui/widget/textboxwidget")
            local built = 0
            local new = TextBoxWidget.new
            TextBoxWidget.new = function(...)
                built = built + 1
                return new(...)
            end
            local ok, err = pcall(function()
                tapWidget(wiki) -- offline: the card changes, and so do the pages
            end)
            TextBoxWidget.new = new
            NetworkMgr.isOnline:revert()
            NetworkMgr.isConnected:revert()
            assert(ok, err)
            assert.is_true(hasText(page, "Wikipedia is an online lookup. Turn on Wi-Fi and try again."))
            assert.is_true(built < 40, built .. " text boxes built")
        end)

        it("should say an entry was cut after its 100th sense", function()
            local senses = {}
            for i = 1, 105 do senses[i] = ("n. sense %d"):format(i) end
            DICT.hugeword = { Demo = table.concat(senses, "\n") }
            stubSdcv(ui.dictionary)
            ui:handleEvent(Event:new("LookupWord", "hugeword"))
            UIManager:forceRePaint()
            DICT.hugeword = nil
            local page = lookupPage()
            local hint = seek(page, "Tap the card for the rest of the entry.")
            assert.is_truthy(hint)
            assert.is_true(hasText(page, "sense 100"))
            assert.is_false(hasText(page, "sense 101"))
        end)
    end)

    describe("with a PDF", function()
        it("should save exact PDF context with context disabled, return from Wikipedia and search the selection", function()
            local Wikipedia = require("ui/wikipedia")
            DocSettings:open(sample_pdf):purge()
            local ui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            UIManager:show(ui)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetScrollMode", false))
                ui.paging:onGotoPage(10)
                UIManager:forceRePaint()
                stubSdcv(ui.dictionary, true)
                stub(NetworkMgr, "isOnline").returns(true)
                stub(Wikipedia, "searchAndGetIntros").returns({ [1] = { title = "London", extract = "A city." } })
                stub(Wikipedia, "getFullPage").returns({ [1] = { title = "London", extract = "London full article." } })
                stub(Trapper, "dismissableRunInSubprocess").invokes(function(_, task) return true, task() end)
                ui.highlight:onHold(nil, { pos = Geom:new{ x = 430, y = 210 } })
                ui.highlight:onHoldRelease()
                UIManager:forceRePaint()
                tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
                local page = lookupPage()
                local selected = page.word
                vocab_settings.with_context = false
                ui.vocabbuilder:removeWord(selected)
                tapWidget(seek(page, "Add to vocabulary builder"))
                local item = package.loaded["db"]:hasWord(selected)
                assert.are.equal("to", selected)
                assert.are.equal("sample", item.book_title)
                assert.are.equal("into foreign countries, and accordingly they embarked for Hol land, after having left labourers sufficient", item.prev_context)
                assert.are.equal("take care of the London vineyard. Their labours were crowned with success in Amsterdam, but", item.next_context)
                assert.is_false(vocab_settings.with_context)
                UIManager:close(topWidget())
                ui.vocabbuilder:removeWord(selected)
                tapWidget(seek(page, "Encyclopedia definition"))
                tapWidget(button(page, "Encyclopedia definition"))
                assert.is_true(hasText(topWidget(), "London full article."))
                -- A physical Back returns to the lookup, without clearing the PDF selection.
                topWidget():onBack()
                UIManager:forceRePaint()
                assert.are.equal(page, topWidget())
                assert.is_truthy(ui.highlight.selected_text)
                assert.are.equal(10, ui.paging.current_page)
                tapWidget(seek(page, "Search in this book"))
                assert.are.equal(selected, topWidget().input:getText())
                assert.is_true(#topWidget().results > 0)
                back(topWidget())
                assert.are.equal(ui, topWidget())
                assert.are.equal(10, ui.paging.current_page)
            end)
            for _, method in ipairs{ "searchAndGetIntros", "getFullPage" } do
                if Wikipedia[method].revert then Wikipedia[method]:revert() end
            end
            vocab_settings.with_context = true
            if NetworkMgr.isOnline.revert then NetworkMgr.isOnline:revert() end
            if Trapper.dismissableRunInSubprocess.revert then Trapper.dismissableRunInSubprocess:revert() end
            if type(ui.dictionary.rawSdcv) == "table" then ui.dictionary.rawSdcv:revert() end
            ui:onClose()
            UIManager:quit()
            assert(ok, err)
        end)

        it("should translate a phrase selected on the page, and go back to that page", function()
            DocSettings:open(sample_pdf):purge()
            local ui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            UIManager:show(ui)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetScrollMode", false))
                ui.paging:onGotoPage(10)
                UIManager:forceRePaint()
                stubSdcv(ui.dictionary)
                stub(NetworkMgr, "isOnline").returns(true)
                local load = stubTranslator({ { { "照顾伦敦", "x" } } })
                ui.highlight:onHold(nil, { pos = Geom:new{ x = 430, y = 210 } })
                ui.highlight:onHoldPan(nil, { pos = Geom:new{ x = 60, y = 236 } })
                UIManager:forceRePaint()
                ui.highlight:onHoldRelease()
                UIManager:forceRePaint()
                local refreshes = refreshesOf(function()
                    tapWidget(button(ui.highlight.highlight_dialog, "Translate"))
                end)
                NetworkMgr.isOnline:revert()
                revertTranslator()
                assert.stub(load).was_called_with(match.is_ref(Translator), "to take care of the London", match._, match._)
                local page = lookupPage()
                assert.is_true(hasText(page, "to take care of the London"))
                assert.is_true(hasText(page, "照顾伦敦"))
                assertNoFull(refreshes)
                back(page)
                assert.are.equal(ui, topWidget())
                assert.are.equal(10, ui.paging.current_page)
            end)
            if type(ui.dictionary.rawSdcv) == "table" then ui.dictionary.rawSdcv:revert() end
            UIManager:close(ui.highlight.highlight_dialog)
            ui:onClose()
            UIManager:quit()
            assert(ok, err)
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
