-- The notes page (笔记页), driven through the reader with taps: the toolbar's 笔记, the contents page's 书签,
-- the cards, 仅显示书签, the page capsule and the back arrow. Highlights, thoughts and bookmarks are made the
-- way a reader makes them: a long-press and the popover, the top bar's bookmark.
describe("ReaderNotesPage module", function()
    local DocumentRegistry, DocSettings, ReaderUI, ReaderToolbar, Replacements, UIManager, Event, Geom, Screen, time
    local _, C_, N_, T
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local sample_pdf = "spec/front/unit/data/sample.pdf"

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderToolbar = require("apps/reader/modules/readertoolbar")
        Replacements = require("apps/replacements")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        Screen = require("device").screen
        time = require("ui/time")
        _ = require("gettext")
        C_ = _.pgettext
        N_ = _.ngettext
        T = require("ffi/util").template
        Replacements.reader_menu = ReaderToolbar
        require("apps/reader/modules/readerhighlightbubble").register() -- the popover's Highlight and Write note
    end)

    teardown(function()
        Replacements.reader_menu = nil
        Replacements.reader_highlight = nil
        G_reader_settings:delSetting("highlight_drawing_style")
        DocSettings:open(sample_epub):purge()
        DocSettings:open(sample_pdf):purge()
    end)

    -- These fixtures save selections from the popover with the explicit legacy Ask action.
    before_each(function() G_reader_settings:saveSetting("default_highlight_action", "ask") end)
    after_each(function() G_reader_settings:delSetting("default_highlight_action") end)

    local function openReader(file, keep_settings)
        if not keep_settings then DocSettings:open(file):purge() end
        local ui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(file),
        }
        UIManager:show(ui)
        UIManager:forceRePaint()
        return ui
    end

    local function closeReader(ui)
        if ui.menu.drawer then
            ui.menu:closeDrawer()
        end
        ui:onClose()
    end

    local function topWidget()
        return UIManager._window_stack[#UIManager._window_stack].widget
    end

    local function tap(x, y)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
    end

    -- Taps the middle of `rect` and repaints.
    local function tapRect(rect)
        tap(rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2))
        UIManager:forceRePaint()
    end

    local function tapWidget(widget)
        tapRect(widget.dimen)
    end

    local function holdWidget(widget)
        local r = widget.dimen
        UIManager:sendEvent(Event:new("Gesture", { ges = "hold",
            pos = Geom:new{ x = r.x + math.floor(r.w / 2), y = r.y + math.floor(r.h / 2) } }))
        UIManager:forceRePaint()
    end

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

    local function hasText(widget, str)
        return find(widget, function(w) return w.text == str end) ~= nil
    end

    -- Whether some text of `widget` holds `str`.
    local function holdsText(widget, str)
        return find(widget, function(w) return type(w.text) == "string" and w.text:find(str, 1, true) end) ~= nil
    end

    -- The popover's action labelled `text`.
    local function cell(bubble, text)
        return find(bubble, function(w)
            return w.callback and w.dimen and find(w, function(c) return c.text == text end) ~= nil
        end)
    end

    -- Selects from pos0 to pos1 with a long-press and a drag, and highlights it from the popover.
    local function highlight(ui, pos0, pos1)
        ui.highlight:onHold(nil, { pos = pos0 })
        ui.highlight:onHoldPan(nil, { pos = pos1 })
        UIManager:forceRePaint()
        ui.highlight:onHoldRelease()
        UIManager:forceRePaint()
        tapWidget(cell(ui.highlight.highlight_dialog, "Highlight"))
        ui.highlight:closeBubble()
        UIManager:forceRePaint()
    end

    local function saveThought(thought)
        local sheet
        for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i].widget
            if w.input and w.getRefreshRegion then sheet = w break end
        end
        sheet.input:setText(thought)
        tapWidget(find(sheet, function(w) return w.text == "Save" and w.callback end))
    end

    -- Selects from pos0 to pos1 and writes `thought` on it from the popover.
    local function writeThought(ui, pos0, pos1, thought)
        ui.highlight:onHold(nil, { pos = pos0 })
        ui.highlight:onHoldPan(nil, { pos = pos1 })
        UIManager:forceRePaint()
        ui.highlight:onHoldRelease()
        UIManager:forceRePaint()
        tapWidget(cell(ui.highlight.highlight_dialog, "Write note"))
        saveThought(thought)
    end

    -- Shows the toolbar with a tap in the middle of the page.
    local function showToolbar(ui)
        tap(Screen:getWidth() / 2, Screen:getHeight() / 2)
        UIManager:forceRePaint()
        assert.is_truthy(ui.menu.bars)
        return ui.menu.bars
    end

    -- Bookmarks the page shown with the top bar's bookmark.
    local function bookmarkPage(ui)
        showToolbar(ui)
        tapWidget(ui.menu.bookmark_button)
        local toast = topWidget()
        assert.is_true(toast.toast)
        UIManager:close(toast)
        UIManager:forceRePaint()
    end

    local function iconCell(widget, icon)
        return find(widget, function(w)
            return w.callback and w.dimen and find(w, function(c) return c.icon == icon end) ~= nil
        end)
    end

    -- The toolbar's 笔记.
    local function openFromToolbar(ui)
        local bars = showToolbar(ui)
        tapWidget(iconCell(bars.bottom, "eink/notes"))
        local page = ui.menu.drawer
        assert.is_truthy(page)
        assert.are.equal(page, topWidget())
        return page
    end

    -- The contents page's 书签.
    local function openFromContents(ui)
        ui:handleEvent(Event:new("ShowToc"))
        UIManager:forceRePaint()
        local contents = ui.menu.drawer
        tapWidget(contents.bookmarks_button)
        assert.is_false(UIManager:isWidgetShown(contents))
        local page = ui.menu.drawer
        assert.are.equal(page, topWidget())
        return page
    end

    local function back(page)
        tapWidget(page.bar.back)
        assert.is_false(UIManager:isWidgetShown(page))
    end

    local function nextPage(page)
        tapRect(page.bar.capsule.next_rect)
    end

    local function toFirstPage(page)
        while page.bar.capsule.prev_enabled do
            tapRect(page.bar.capsule.prev_rect)
        end
    end

    -- The annotations of the cards of every page, in order, from the first page.
    local function allCards(page)
        toFirstPage(page)
        local items = {}
        while true do
            for _, card in ipairs(page.cards) do
                table.insert(items, card.item)
            end
            if not page.bar.capsule.next_enabled then break end
            nextPage(page)
        end
        return items
    end

    -- The overview card's line with the note count, for `n` notes.
    local function countLine(ui, n)
        local percent = math.floor(ui:getCurrentPage() / ui.document:getPageCount() * 100)
        return T(N_("Read to %1% · 1 note", "Read to %1% · %2 notes", n), percent, n)
    end

    -- Whether `action` is waiting in UIManager's task queue.
    local function scheduled(action)
        for _, task in ipairs(UIManager._task_queue) do
            if task.action == action then return true end
        end
        return false
    end

    -- How many texts of `widget` are exactly `str`.
    local function countText(widget, str)
        if type(widget) ~= "table" then return 0 end
        local n = widget.text == str and 1 or 0
        for _, child in ipairs(widget) do
            n = n + countText(child, str)
        end
        for _, key in ipairs{ "frame", "content" } do
            if rawget(widget, key) then n = n + countText(widget[key], str) end
        end
        return n
    end

    -- Jumps to the first card of the notes page, made of one highlight on page 12, from page 2.
    local function jumpToHighlight(ui)
        ui.rolling:onGotoPage(12)
        UIManager:forceRePaint()
        highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 })
        ui.rolling:onGotoPage(2)
        UIManager:forceRePaint()
        tapWidget(openFromToolbar(ui).cards[1])
        return ui.view.view_modules.notes_jump_focus
    end

    -- Lets `seconds` pass for the scheduled tasks.
    local function wait(seconds)
        UIManager:shiftScheduledTasksBy(-time.s(seconds))
        UIManager:_checkTasks()
    end

    describe("with an EPUB", function()
        local ui
        before_each(function()
            ui = openReader(sample_epub)
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()
        end)
        after_each(function()
            ui.statistics = nil
            closeReader(ui)
        end)

        it("should open full screen from the toolbar's Notes, with the overview card, chapters and typed cards", function()
            highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 })
            ui.rolling:onGotoPage(30)
            UIManager:forceRePaint()
            bookmarkPage(ui)
            writeThought(ui, Geom:new{ x = 260, y = 200 }, Geom:new{ x = 260, y = 230 }, "A thought of mine")
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()
            assert.are.equal(3, #ui.annotation.annotations)
            ui.statistics = { isEnabled = function() return true end, book_read_time = 1440, mem_read_time = 75 }

            local bars = showToolbar(ui)
            local refreshes = refreshesOf(function() tapWidget(iconCell(bars.bottom, "eink/notes")) end)
            local page = ui.menu.drawer
            assert.are.equal(page, topWidget())
            assert.is_true(page.covers_fullscreen)
            assert.is_nil(ui.menu.bars)
            assert.is_true(#refreshes > 0)
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
            end
            assert.is_true(refreshes[#refreshes].region:contains(page.dimen))

            -- 笔记, then the overview card: title, reading progress and count, time, cover
            assert.is_true(hasText(page, C_("Notes page", "Notes")))
            assert.is_true(hasText(page.overview, ui.doc_props.display_title))
            assert.is_true(hasText(page.overview, countLine(ui, 3)))
            assert.is_true(hasText(page.overview, T(N_("Read for 1 minute", "Read for %1 minutes", 25), 25)))
            assert.is_truthy(page.overview.cover)
            -- one card per note, in book order, each with its type
            assert.are.equal(3, #page.cards)
            local by_kind = {}
            for i, card in ipairs(page.cards) do
                assert.are.equal(ui.annotation.annotations[i], card.item)
                by_kind[card.kind] = card
            end
            assert.is_truthy(by_kind.highlight and by_kind.bookmark and by_kind.thought)
            assert.is_true(holdsText(by_kind.highlight, by_kind.highlight.item.text:sub(1, 12)))
            -- a thought shows the thought and the text it is on
            assert.is_true(holdsText(by_kind.thought, "A thought of mine"))
            assert.is_true(holdsText(by_kind.thought, by_kind.thought.item.text:sub(1, 12)))
            -- a bookmark shows the text its page starts with
            local xp = by_kind.bookmark.item.page
            local page_text = ui.document:getTextFromXPointers(xp, ui.document:getPageXPointer(ui.document:getPageFromXPointer(xp) + 1))
            assert.is_true(holdsText(by_kind.bookmark, page_text:match("%S+")))
            -- grouped under their chapters
            for _, card in ipairs(page.cards) do
                assert.is_true(hasText(page, card.item.chapter))
            end
            -- the cards share the overview card's centered column, as on the Leaf5 (416dp)
            local column = Screen:scaleBySize(416)
            assert.are.equal(column, page.overview.dimen.w)
            for _, card in ipairs(page.cards) do
                assert.are.equal(page.overview.dimen.x, card.dimen.x)
                assert.are.equal(column, card.dimen.w)
            end
            assert.are.equal(math.floor((Screen:getWidth() - column) / 2), page.overview.dimen.x)
            -- no filter without bookmarks only: here there is one, so 仅显示书签 shows, off
            assert.is_truthy(page.filter_button)
            assert.is_nil(page.filter)
            assert.is_false(page.bar.capsule.prev_enabled)
            assert.is_false(page.bar.capsule.next_enabled)

            refreshes = refreshesOf(function() back(page) end)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.menu.drawer)
        end)

        it("should open this same notes page by tapping the progress count, including all three kinds", function()
            highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 })
            ui.rolling:onGotoPage(30)
            UIManager:forceRePaint()
            bookmarkPage(ui)
            writeThought(ui, Geom:new{ x = 260, y = 200 }, Geom:new{ x = 260, y = 230 }, "Progress count thought")
            local position = ui:getCurrentPage()
            local bars = showToolbar(ui)
            tapWidget(iconCell(bars.bottom, "eink/progress"))
            local panel = ui.menu.panel
            assert.is_true(hasText(panel, "3"))
            local column = find(panel, function(w)
                return w.ges_events and hasText(w, C_("Notes page", "Notes"))
                    and w ~= panel
            end)
            tapWidget(column)
            local page = ui.menu.drawer
            assert.are.equal(3, page.count)
            assert.is_true(hasText(page.overview, countLine(ui, 3)))
            assert.is_nil(ui.menu.panel)
            assert.is_nil(ui.menu.bars)
            UIManager:sendEvent(Event:new("KeyPress", require("device/key"):new("Back", {})))
            assert.are.equal(position, ui:getCurrentPage())
            assert.is_nil(ui.menu.drawer)
        end)

        it("should leave out the reading time without statistics, and close on the Back key", function()
            local page = openFromToolbar(ui)
            assert.is_false(holdsText(page.overview, "minute"))
            assert.is_true(hasText(page.overview, countLine(ui, 0)))
            page:onBack()
            UIManager:forceRePaint()
            assert.is_false(UIManager:isWidgetShown(page))
            assert.is_nil(ui.menu.drawer)
        end)

        it("should say how to start when the book has no notes, keeping the overview, with nothing to page", function()
            ui.statistics = { isEnabled = function() return true end, book_read_time = 7 * 60, mem_read_time = 0 }
            local page = openFromToolbar(ui)
            assert.is_true(hasText(page.overview, countLine(ui, 0)))
            assert.is_true(hasText(page.overview, T(N_("Read for 1 minute", "Read for %1 minutes", 7), 7)))
            assert.are.same({}, page.cards)
            assert.is_truthy(page.empty_card)
            assert.is_true(hasText(page.empty_card, _("You can keep your thoughts, highlights and bookmarks on this book here.")))
            assert.are.equal(page.overview.dimen.x, page.empty_card.dimen.x)
            assert.is_nil(page.filter_button)
            assert.is_false(page.bar.capsule.prev_enabled)
            assert.is_false(page.bar.capsule.next_enabled)
            back(page)
        end)

        it("should show hours past an hour of reading", function()
            ui.statistics = { isEnabled = function() return true end, book_read_time = 2 * 3600 + 5 * 60, mem_read_time = 0 }
            local page = openFromToolbar(ui)
            assert.is_true(hasText(page.overview, T(_("Read for %1 h %2 min"), 2, 5)))
            back(page)
        end)

        it("should open the same page from the contents page's 书签, on the bookmarks, with the same count", function()
            highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 })
            ui.rolling:onGotoPage(20)
            UIManager:forceRePaint()
            bookmarkPage(ui)
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()

            local page
            local refreshes = refreshesOf(function() page = openFromContents(ui) end)
            for _, r in ipairs(refreshes) do
                assert.are.equal("ui", r.mode)
            end
            -- titled 笔记 all the same, the count of every note, but only the bookmark listed, its filter on
            assert.is_true(hasText(page, C_("Notes page", "Notes")))
            assert.is_true(hasText(page.overview, countLine(ui, 2)))
            assert.are.equal("bookmarks", page.filter)
            assert.is_true(hasText(page.filter_button, _("Bookmarks only")))
            assert.are.equal(1, #page.cards)
            assert.are.equal("bookmark", page.cards[1].kind)
            assert.is_truthy(find(page.filter_button, function(w) return w.icon == "eink/bookmark-on" end))

            -- 仅显示书签 again shows them all, title band included in the repaint
            refreshes = refreshesOf(function() tapWidget(page.filter_button) end)
            assert.is_nil(page.filter)
            assert.are.equal(2, #page.cards)
            assert.is_truthy(find(page.filter_button, function(w) return w.icon == "eink/bookmark" end))
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            back(page)

            -- and the toolbar's 笔记 says the same
            page = openFromToolbar(ui)
            assert.is_true(hasText(page.overview, countLine(ui, 2)))
            assert.is_nil(page.filter)
            assert.are.equal(2, #page.cards)
            back(page)
        end)

        it("should list everything from the contents page's 书签 when the book has no bookmarks", function()
            highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 })
            local page = openFromContents(ui)
            assert.is_nil(page.filter)
            assert.is_nil(page.filter_button)
            assert.are.equal(1, #page.cards)
            back(page)
        end)

        it("should page the notes without losing or repeating any, and come back to the page left", function()
            for p = 12, 60, 4 do
                ui.rolling:onGotoPage(p)
                UIManager:forceRePaint()
                bookmarkPage(ui)
            end
            ui.rolling:onGotoPage(64)
            UIManager:forceRePaint()
            highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 130 })
            local n = #ui.annotation.annotations
            assert.are.equal(14, n)

            local page = openFromToolbar(ui)
            assert.is_true(hasText(page.overview, countLine(ui, n)))
            assert.are.same(ui.annotation.annotations, allCards(page))
            -- on the last page, only back
            assert.is_true(page.bar.capsule.prev_enabled)
            assert.is_false(page.bar.capsule.next_enabled)
            -- the overview card is on the first page only; the cards of a page all fit above the bar
            for _, card in ipairs(page.cards) do
                assert.is_true(card.dimen.y + card.dimen.h <= page.bar.dimen.y)
            end
            toFirstPage(page)
            assert.is_truthy(UIManager:isWidgetShown(page))
            assert.is_true(page.overview.dimen ~= nil)
            -- turning a page repaints the content and the bar, and no page text is read again
            local reads = 0
            local orig = ui.document.getTextFromXPointers
            ui.document.getTextFromXPointers = function(...) reads = reads + 1 return orig(...) end
            local refreshes = refreshesOf(function() nextPage(page) nextPage(page) toFirstPage(page) nextPage(page) end)
            ui.document.getTextFromXPointers = orig
            assert.are.equal(0, reads)
            for _, r in ipairs(refreshes) do
                assert.are.same({ mode = "ui", region = page.body_rect }, r)
            end
            assert.are.equal(2, page.page)
            local shown = page.cards[1].item

            -- a jump from page 2, then the notes again: on page 2
            tapWidget(page.cards[1])
            assert.are.equal(ui, topWidget())
            page = openFromToolbar(ui)
            assert.are.equal(2, page.page)
            assert.are.equal(shown, page.cards[1].item)
            back(page)
        end)

        it("should jump to a highlight, mark it briefly in gray without saving anything, and remember the position", function()
            ui.rolling:onGotoPage(12)
            UIManager:forceRePaint()
            highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 })
            local item = ui.annotation.annotations[1]
            local note_page = ui.document:getPageFromXPointer(item.pos0)
            ui.rolling:onGotoPage(2)
            UIManager:forceRePaint()
            local stack_size = #(ui.link.location_stack or {})

            local page = openFromToolbar(ui)
            local refreshes = refreshesOf(function() tapWidget(page.cards[1]) end)
            assert.are.equal(ui, topWidget())
            assert.is_nil(ui.menu.drawer)
            assert.are.equal(note_page, ui:getCurrentPage())
            assert.are.equal(stack_size + 1, #ui.link.location_stack)
            -- the reader's partial covers the page left, and nothing flashes
            local covered = false
            for _, r in ipairs(refreshes) do
                assert.are.equal("partial", r.mode)
                covered = covered or r.region == nil or r.region:contains(page.dimen)
            end
            assert.is_true(covered)
            -- the highlight's lines are marked in gray, over the line under them
            local focus = ui.view.view_modules.notes_jump_focus
            local rects = focus:rects()
            assert.is_true(#rects > 0)
            local r = rects[1]
            local gray = Screen.bb:getPixel(r.x + 1, r.y + 1):getColor8().a
            assert.is_true(gray < 0xF0 and gray > 0x80, "marker gray, not " .. gray)
            -- no new note, nothing new saved
            assert.are.equal(1, #ui.annotation.annotations)
            assert.are.same(item, ui.annotation.annotations[1])

            -- soon gone, repainting just the marked lines
            local region = rects[1]
            for _, rect in ipairs(rects) do region = region:combine(rect) end
            refreshes = refreshesOf(function() wait(2) end)
            assert.are.same({ { mode = "ui", region = region } }, refreshes)
            assert.are.same({}, focus:rects())
            assert.are.equal(0xFF, Screen.bb:getPixel(r.x + 1, r.y + 1):getColor8().a)
            assert.are.equal(1, #ui.annotation.annotations)
        end)

        it("should cancel or delete just the held bookmark, updating the last-bookmark filter", function()
            highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 })
            bookmarkPage(ui) -- on the same page as the highlight
            local saved = require("util").tableDeepCopy(ui.annotation.annotations)
            local page = openFromContents(ui)
            local refreshes = refreshesOf(function() holdWidget(page.cards[1]) end)
            local confirm = topWidget()
            assert.is_true(hasText(confirm, _("Delete this note?")))
            assert.is_truthy(cell(confirm, _("Delete")))
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
            tapWidget(cell(confirm, _("Cancel")))
            assert.are.equal(page, topWidget())
            assert.are.same(saved, ui.annotation.annotations)
            assert.are.equal("bookmarks", page.filter)

            holdWidget(page.cards[1])
            refreshes = refreshesOf(function() tapWidget(cell(topWidget(), _("Delete"))) end)
            for _, r in ipairs(refreshes) do assert.are.equal("ui", r.mode) end
            assert.are.equal(page, topWidget())
            assert.is_nil(page.filter)
            assert.is_nil(page.filter_button)
            assert.are.equal(1, #page.cards)
            assert.are.equal("highlight", page.cards[1].kind)
            assert.is_true(hasText(page.overview, countLine(ui, 1)))
            assert.is_false(ui.view.dogear_visible)
            local kept = require("util").tableDeepCopy(ui.annotation.annotations)
            closeReader(ui)
            ui = openReader(sample_epub, true)
            assert.are.same(kept, ui.annotation.annotations)
            page = openFromToolbar(ui)
            assert.is_nil(page.filter_button)
            assert.are.equal("highlight", page.cards[1].kind)
            holdWidget(page.cards[1])
            tapWidget(cell(topWidget(), _("Delete")))
            assert.is_truthy(page.empty_card)
            assert.is_true(hasText(page.overview, countLine(ui, 0)))
            assert.is_false(page.bar.capsule.next_enabled)
            closeReader(ui)
            ui = openReader(sample_epub, true)
            assert.are.same({}, ui.annotation.annotations)
            page = openFromToolbar(ui)
            assert.is_truthy(page.empty_card)
        end)

        it("should jump to a bookmark's page without marking anything", function()
            ui.rolling:onGotoPage(20)
            UIManager:forceRePaint()
            bookmarkPage(ui)
            ui.rolling:onGotoPage(3)
            UIManager:forceRePaint()
            local page = openFromToolbar(ui)
            tapWidget(page.cards[1])
            assert.are.equal(20, ui:getCurrentPage())
            local focus = ui.view.view_modules.notes_jump_focus
            assert.is_true(focus == nil or #focus:rects() == 0)
        end)

        it("should open all notes from the toolbar except the first return after a bookmark jump", function()
            highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 })
            bookmarkPage(ui)
            local page = openFromContents(ui)
            back(page)
            page = openFromToolbar(ui)
            assert.is_nil(page.filter)
            assert.are.equal(2, #page.cards)
            tapWidget(page.filter_button)
            tapWidget(page.cards[1])
            page = openFromToolbar(ui)
            assert.are.equal("bookmarks", page.filter)
            assert.are.equal(1, #page.cards)
            back(page)
            page = openFromToolbar(ui)
            assert.is_nil(page.filter)
            assert.are.equal(2, #page.cards)
        end)

        it("should return to the filtered list even when the bookmark is on the current reading page", function()
            bookmarkPage(ui)
            local page = openFromToolbar(ui)
            tapWidget(page.cards[1])
            page = openFromToolbar(ui)
            assert.is_nil(page.filter)
            tapWidget(page.filter_button)
            tapWidget(page.cards[1])
            local bars = showToolbar(ui)
            local refreshes = refreshesOf(function()
                tapWidget(iconCell(bars.bottom, "eink/notes"))
                page = ui.menu.drawer
            end)
            assert.are.equal("bookmarks", page.filter)
            assert.are.equal(1, #page.cards)
            assert.are.same({ { mode = "ui", region = page.dimen } }, refreshes)
        end)

        it("should restore the filtered list page and jump to the bookmark after font reflow", function()
            for p = 12, 60, 4 do
                ui.rolling:onGotoPage(p)
                UIManager:forceRePaint()
                bookmarkPage(ui)
            end
            ui:handleEvent(Event:new("ChangeSize", 2))
            UIManager:forceRePaint()
            ui.rolling:onGotoPage(3)
            UIManager:forceRePaint()
            local before = ui.document:getXPointer()
            local page = openFromContents(ui)
            nextPage(page)
            local item = page.cards[1].item
            local destination = ui.document:getPageFromXPointer(item.page)
            tapWidget(page.cards[1])
            assert.are.equal(destination, ui:getCurrentPage())
            ui:handleEvent(Event:new("GoBackLink"))
            UIManager:forceRePaint()
            assert.are.equal(before, ui.document:getXPointer())
            page = openFromToolbar(ui)
            assert.are.equal("bookmarks", page.filter)
            assert.are.equal(2, page.page)
            assert.are.equal(item, page.cards[1].item)
        end)

        for _i, origin in ipairs{ "note", "highlight", "legacy" } do
            it("should delete a thought with " .. origin .. " origin safely and persist it", function()
                writeThought(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 }, "Keep the quote")
                -- Sidecar variants from J05, including old records with no origin.
                ui.annotation.annotations[1].origin = origin ~= "legacy" and origin or nil
                closeReader(ui)
                ui = openReader(sample_epub, true)
                local saved = require("util").tableDeepCopy(ui.annotation.annotations)
                local page = openFromToolbar(ui)
                assert.are.equal("thought", page.cards[1].kind)
                holdWidget(page.cards[1])
                tapWidget(cell(topWidget(), _("Cancel")))
                assert.are.same(saved, ui.annotation.annotations)
                holdWidget(page.cards[1])
                tapWidget(cell(topWidget(), _("Delete")))
                if origin == "note" then
                    assert.is_truthy(page.empty_card)
                else
                    assert.are.equal("highlight", page.cards[1].kind)
                    assert.are.equal(saved[1].text, page.cards[1].item.text)
                    assert.are.equal(saved[1].drawer, page.cards[1].item.drawer)
                    assert.is_nil(page.cards[1].item.note)
                end
                closeReader(ui)
                ui = openReader(sample_epub, true)
                page = openFromToolbar(ui)
                if origin == "note" then
                    assert.is_truthy(page.empty_card)
                    assert.is_true(hasText(page.overview, countLine(ui, 0)))
                else
                    assert.are.equal(1, #page.cards)
                    assert.are.equal("highlight", page.cards[1].kind)
                    assert.is_nil(page.cards[1].item.note)
                    assert.are.equal(saved[1].pos0, page.cards[1].item.pos0)
                    assert.are.equal(saved[1].pos1, page.cards[1].item.pos1)
                end
            end)
        end

        it("should keep the last list page after cancel and clamp it after deleting its last card", function()
            for p = 12, 60, 4 do
                ui.rolling:onGotoPage(p)
                UIManager:forceRePaint()
                bookmarkPage(ui)
            end
            -- These are distinct bookmarks even when their creation timestamps coincide.
            for _, item in ipairs(ui.annotation.annotations) do item.datetime = "2026-10-24 00:00:00" end
            local page = openFromContents(ui)
            while page.bar.capsule.next_enabled do nextPage(page) end
            local last_page, last_count = page.page, #page.cards
            holdWidget(page.cards[1])
            UIManager:sendEvent(Event:new("KeyPress", require("device/key"):new("Back", {})))
            UIManager:forceRePaint()
            assert.are.equal(page, topWidget())
            assert.are.equal(last_page, page.page)
            assert.are.equal(last_count, #page.cards)
            for _i = 1, last_count do
                holdWidget(page.cards[1])
                tapWidget(cell(topWidget(), _("Delete")))
            end
            assert.are.equal(last_page - 1, page.page)
            assert.is_true(#page.cards > 0)
            assert.is_false(page.bar.capsule.next_enabled)
        end)

        it("should not delete another note if the held bookmark disappears before confirmation", function()
            highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 })
            bookmarkPage(ui)
            local page = openFromContents(ui)
            holdWidget(page.cards[1])
            local confirm = topWidget()
            ui:handleEvent(Event:new("ToggleBookmark"))
            UIManager:forceRePaint()
            tapWidget(cell(confirm, _("Delete")))
            assert.are.equal(page, topWidget())
            assert.are.equal(1, #page.cards)
            assert.are.equal("highlight", page.cards[1].kind)
            assert.is_nil(page.filter_button)
        end)

        it("should drop the gray mark and its timer when the page turns before it goes", function()
            local focus = jumpToHighlight(ui)
            local clear = focus.clear
            assert.is_true(#focus:rects() > 0)
            assert.is_true(scheduled(clear))
            local shown = ui:getCurrentPage()
            -- a tap on the right of the page turns it
            tap(Screen:getWidth() - 10, math.floor(Screen:getHeight() / 2))
            UIManager:forceRePaint()
            assert.are.equal(shown + 1, ui:getCurrentPage())
            assert.is_nil(focus.item)
            assert.is_false(scheduled(clear))
            assert.are.same({}, refreshesOf(function() wait(2) end))
        end)

        it("should read a bookmark's page text once, however often the notes change", function()
            for _, p in ipairs{ 20, 22 } do
                ui.rolling:onGotoPage(p)
                UIManager:forceRePaint()
                bookmarkPage(ui)
            end
            local page = openFromToolbar(ui)
            assert.are.equal(2, #page.cards)
            local reads = 0
            local orig = ui.document.getTextFromXPointers
            ui.document.getTextFromXPointers = function(...) reads = reads + 1 return orig(...) end
            local ok, err = pcall(function()
                ui.rolling:onGotoPage(24)
                ui:handleEvent(Event:new("ToggleBookmark")) -- the page follows: all three cards again
                UIManager:forceRePaint()
            end)
            ui.document.getTextFromXPointers = orig
            assert(ok, err)
            assert.are.equal(3, #page.cards)
            assert.are.equal(1, reads) -- the new bookmark's page only
            back(page)
        end)

        it("should follow notes added and removed: the cards, the count and 仅显示书签", function()
            highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 100 })
            local page = openFromToolbar(ui)
            assert.is_nil(page.filter_button)
            assert.are.equal(1, #page.cards)

            -- a bookmark made while the page is open (as any module may): a card more, 仅显示书签, one repaint
            ui.rolling:onGotoPage(40)
            local refreshes = refreshesOf(function() ui:handleEvent(Event:new("ToggleBookmark")) end)
            assert.are.equal(2, #ui.annotation.annotations)
            assert.are.equal(2, #page.cards)
            assert.is_true(hasText(page.overview, countLine(ui, 2)))
            assert.is_truthy(page.filter_button)
            local repainted = false
            for _, r in ipairs(refreshes) do
                repainted = repainted or r.mode == "ui" and r.region:contains(page.dimen)
            end
            assert.is_true(repainted)

            -- on the bookmarks, the last bookmark goes: back to all of them, without 仅显示书签
            tapWidget(page.filter_button)
            assert.are.equal("bookmarks", page.filter)
            ui:handleEvent(Event:new("ToggleBookmark"))
            UIManager:forceRePaint()
            assert.is_nil(page.filter)
            assert.is_nil(page.filter_button)
            assert.are.equal(1, #page.cards)
            assert.is_true(hasText(page.overview, countLine(ui, 1)))
            back(page)

            -- a highlight deleted from its popover: gone from the page the next time
            ui.rolling:onGotoPage(10)
            UIManager:forceRePaint()
            local box = ui.view.highlight.visible_boxes[1].rect
            tap(box.x + math.floor(box.w / 2), box.y + math.floor(box.h / 2))
            UIManager:forceRePaint()
            tapWidget(cell(ui.highlight.highlight_dialog, "Delete highlight"))
            UIManager:forceRePaint()
            page = openFromToolbar(ui)
            assert.is_true(hasText(page.overview, countLine(ui, 0)))
            assert.is_truthy(page.empty_card)
            back(page)
        end)
    end)

    describe("when the reader closes", function()
        it("should close a pending deletion without changing the bookmark", function()
            local ui = openReader(sample_epub)
            ui.rolling:onGotoPage(10) -- past the cover, whose image would take the tap
            bookmarkPage(ui)
            holdWidget(openFromToolbar(ui).cards[1])
            local confirm = topWidget()
            closeReader(ui)
            assert.is_false(UIManager:isWidgetShown(confirm))
            ui = openReader(sample_epub, true)
            local page = openFromToolbar(ui)
            assert.are.equal(1, #page.cards)
            assert.are.equal("bookmark", page.cards[1].kind)
            closeReader(ui)
        end)
        it("should go with the reader while it is shown", function()
            local ui = openReader(sample_epub)
            ui.rolling:onGotoPage(10)
            local page = openFromToolbar(ui)
            ui:onClose() -- the document goes first, then the reader, whose toolbar closes the page
            assert.is_false(UIManager:isWidgetShown(page))
            assert.is_false(UIManager:isWidgetShown(ui))
            assert.is_nil(ui.menu.drawer)
        end)

        it("should take the gray mark's timer along", function()
            local ui = openReader(sample_epub)
            local clear = jumpToHighlight(ui).clear
            assert.is_true(scheduled(clear))
            closeReader(ui)
            assert.is_false(scheduled(clear))
        end)
    end)

    describe("with a PDF", function()
        it("should list a highlight and a bookmark and jump to them", function()
            local ui = openReader(sample_pdf)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetScrollMode", false))
                ui.paging:onGotoPage(10)
                UIManager:forceRePaint()
                highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                ui.paging:onGotoPage(5)
                UIManager:forceRePaint()
                bookmarkPage(ui)
                ui.paging:onGotoPage(1)
                UIManager:forceRePaint()

                local page = openFromToolbar(ui)
                assert.is_true(hasText(page.overview, countLine(ui, 2)))
                assert.are.equal(2, #page.cards)
                assert.are.equal("bookmark", page.cards[1].kind)
                assert.are.equal("highlight", page.cards[2].kind)
                tapWidget(page.cards[2])
                assert.are.equal(10, ui:getCurrentPage())
                assert.is_true(#ui.view.view_modules.notes_jump_focus:rects() > 0)
                wait(2)

                page = openFromContents(ui)
                assert.are.equal("bookmarks", page.filter)
                tapWidget(page.cards[1])
                assert.are.equal(5, ui:getCurrentPage())
                assert.are.equal(ui, topWidget())
                ui:handleEvent(Event:new("GoBackLink"))
                UIManager:forceRePaint()
                assert.are.equal(10, ui:getCurrentPage())
                page = openFromToolbar(ui)
                assert.are.equal("bookmarks", page.filter)
                holdWidget(page.cards[1])
                tapWidget(cell(topWidget(), _("Delete")))
                assert.is_nil(page.filter_button)
                assert.are.equal(1, #page.cards)
                assert.are.equal("highlight", page.cards[1].kind)
                closeReader(ui)
                ui = openReader(sample_pdf, true)
                assert.are.equal(1, #ui.annotation.annotations)
                assert.is_truthy(ui.annotation.annotations[1].drawer)
                page = openFromToolbar(ui)
                local pdf_write = spy.on(ui.highlight, "writePdfAnnotation")
                holdWidget(page.cards[1])
                tapWidget(cell(topWidget(), _("Delete")))
                local match = require("luassert.match")
                assert.spy(pdf_write).was.called_with(match._, "delete", match.is_table())
                pdf_write:revert()
                assert.is_truthy(page.empty_card)
                closeReader(ui)
                ui = openReader(sample_pdf, true)
                assert.are.same({}, ui.annotation.annotations)
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should clear an attached thought in the PDF and keep its highlight after reopening", function()
            local ui = openReader(sample_pdf)
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetScrollMode", false))
                ui.paging:onGotoPage(10)
                UIManager:forceRePaint()
                highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                tapRect(ui.view:pageToScreenTransform(10, ui.view.highlight.visible_boxes[1].rect))
                tapWidget(cell(ui.highlight.highlight_dialog, "Write note"))
                saveThought("PDF thought")
                local page = openFromToolbar(ui)
                assert.are.equal("thought", page.cards[1].kind)
                local pdf_write = spy.on(ui.highlight, "writePdfAnnotation")
                holdWidget(page.cards[1])
                tapWidget(cell(topWidget(), _("Delete")))
                local match = require("luassert.match")
                assert.spy(pdf_write).was.called_with(match._, "content", match.is_table(), "")
                pdf_write:revert()
                assert.are.equal("highlight", page.cards[1].kind)
                closeReader(ui)
                ui = openReader(sample_pdf, true)
                assert.are.equal(1, #ui.annotation.annotations)
                assert.is_truthy(ui.annotation.annotations[1].drawer)
                assert.is_nil(ui.annotation.annotations[1].note)
            end)
            closeReader(ui)
            assert(ok, err)
        end)

        it("should file the notes of a book without contents under its title", function()
            local ui = openReader(sample_pdf) -- no outline
            local ok, err = pcall(function()
                ui:handleEvent(Event:new("SetScrollMode", false))
                ui.paging:onGotoPage(10)
                UIManager:forceRePaint()
                highlight(ui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                assert.are.equal("", ui.annotation.annotations[1].chapter) -- as ReaderHighlight stores it without contents
                ui.paging:onGotoPage(5)
                UIManager:forceRePaint()
                bookmarkPage(ui)
                -- a bookmark of an old sidecar has "" too (ReaderAnnotation), here on a page without a text layer
                local bookmark = ui.annotation.annotations[1]
                assert.is_nil(bookmark.drawer)
                bookmark.chapter = ""
                ui.document.getPageTextBoxes = function() end

                local page = openFromToolbar(ui)
                local title = ui.doc_props.display_title
                assert.are.equal(2, #page.cards)
                -- no empty heading, no blank card: the title heads both, and stands in for the bookmark's text
                assert.is_nil(find(page, function(w) return w.text == "" end))
                assert.is_true(hasText(page.cards[1], title))
                assert.are.equal(3, countText(page, title)) -- the overview card, the heading, the bookmark card
            end)
            closeReader(ui)
            assert(ok, err)
        end)
    end)
end)
