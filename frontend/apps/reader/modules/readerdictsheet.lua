--[[--
Lookup cards of the e-ink redesign (查询, see DESIGN.md, Other pages: Lookup), after WeChat Read's
07-selection-and-lookup/02-translation-result.png, 18-chinese-lookup-result.png and
22-english-translation-result.png.

Replaces ReaderDictionary in the reader on touch devices (apps/replacements reader_dictionary slot); the file
manager keeps the upstream popup. A lookup opens a full-screen page (ui/widget/fullscreenpage) with a stack of
cards, from the top:
- the headword with its phonetic, or the selection; 查询中… under it while the lookup runs;
- one card per dictionary that has the word, named on the card, with its senses by part of speech. A card that
  does not fit continues on the next page under its name, and so does a sense taller than a page, from its next
  line. A tap opens that dictionary's full entry in the upstream popup (rich HTML entries, plugin buttons), over
  the page: closing it comes back to the cards, updated (a word added to the vocabulary builder there);
- when no dictionary has it: a card saying why (not in the local dictionaries, none installed or enabled, the
  selection too long), with 在线翻译 for a word that is not CJK;
- the online translation (Translator), named as needing the network: for a selection of several words that is
  not CJK and that no dictionary has, or after 在线翻译. It has its own loading, offline (打开 Wi-Fi), network
  unreachable (connected without internet access: 重试) and failure (重试) states, and shows 查询中… before
  checking the network, as the 百科 card does;
- 百科释义, loaded on a tap, then its intro, which a tap opens as a paginated full-text article;
- 加入生词本 (vocabulary builder), removing a word after the confirm layer, and 在本书中搜索.
Lookups are exact over a list of candidates: a Chinese selection that is not a word is matched by the longest
word it contains (up to 20 characters), and an English word also tries simple lemmas (plural, past tense, -ing).
The fuzzy search setting is not used here. Chinese text is never sent to the translator; CJK punctuation alone
does not make text Chinese (as for the popover's 查询/翻译).

The back arrow (or the Back key) returns to the page of the selection, which stays a moment, as upstream.

Refreshes: the page opens and closes whole, and turning a page or a card changing state repaints the content and
the bar (all "ui"), as does the full Wikipedia article. A local lookup slower than upstream's delay shows the
page with 查询中… (a tap cancels it, as upstream); a faster one opens the page with its results. Nothing here asks
for "full" (the upstream popup flashes as it closes, as it always has).
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmLayer = require("ui/widget/confirmlayer")
local Device = require("device")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local FullscreenPage = require("ui/widget/fullscreenpage")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local NetworkMgr = require("ui/network/manager")
local OverlapGroup = require("ui/widget/overlapgroup")
local Palette = require("ui/palette")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local RightContainer = require("ui/widget/container/rightcontainer")
local Tappable = require("apps/shelf/shelfwidgets").Tappable
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Toast = require("ui/widget/toast")
local Translator = require("ui/translator")
local TrapWidget = require("ui/widget/trapwidget")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Wikipedia = require("ui/wikipedia")
local time = require("ui/time")
local util = require("util")
local ffiUtil = require("ffi/util")
local Screen = Device.screen
local T = ffiUtil.template
local _ = require("gettext")
local C_ = _.pgettext

local MAX_MATCH_CHARS = 20 -- longer selections are only looked up as a whole
local MAX_SENSES = 100 -- longer entries are cut, saying so; the upstream popup has the rest

-- Part-of-speech abbreviations that start a sense line ("n. 旅居者").
local POS = {}
for _, p in ipairs{ "n", "v", "vt", "vi", "adj", "a", "adv", "ad", "prep", "pron", "conj", "int",
                    "interj", "num", "art", "aux", "abbr", "pl" } do
    POS[p] = true
end

local function dp(n) return Screen:scaleBySize(n) end

-- Card page geometry, after the Leaf5 reference (DESIGN.md, Layout and Cards).
local COLUMN_W = dp(416) -- the centered column of cards
local GUTTER = dp(22)
local TOP = dp(62) -- above the first card
local BOTTOM = dp(13) -- between the last card and the bottom bar
local CARD_GAP = dp(13)
local CARD_PAD = dp(20)
local CARD_RADIUS = dp(14)
-- the reference's outline is 2px on the Leaf5, where 1dp (Size.border.default) rounds up to 3px
local CARD_BORDER = dp(0.94)
local HEADING_GAP = dp(12) -- between a card's heading and its body
local UNIT_GAP = dp(8) -- between senses
local POS_GAP = dp(8) -- between a part of speech and its sense
local LEADING = 0.9 -- extra line spacing of card text (of its size): loose, as in the reference
local HEADWORD_LEADING = 0.3 -- but not of the headword, whose card is as tall as one line in the reference
local INTRO_LINES = 4 -- the Wikipedia intro is clamped, as the reference's encyclopedia card
local HEADWORD_LINES = 3 -- a long selection is clamped on the headword card
local CHEV = dp(16)

--- Stem forms to try for a suffix-stripped English stem, most likely first.
local function stemForms(s)
    local undoubled = s:match("^(.-(%a))%2$")
    if undoubled and not s:find("[slfz]$") then
        return { undoubled, s } -- stopp(ed) -> stop
    end
    if s:find("[^aeiou][aeiou][^aeiouwxy]$") or s:find("^[aeiou][^aeiouwxy]$") then
        return { s .. "e", s } -- mak(ing) -> make, us(ed) -> use
    end
    return { s, s .. "e", undoubled }
end

--- Simple English lemmas: plural, past tense and progressive forms.
local function lemmas(w)
    local out = {}
    local function add(forms)
        for _, f in ipairs(forms) do table.insert(out, f) end
    end
    local s = w:match("^(%a%a+)ies$") or w:match("^(%a%a+)ied$")
    if s then add{ s .. "y" } end
    s = w:match("^(%a%a+)es$")
    if s then add{ s } end
    s = w:match("^(%a%a+[^s])s$")
    if s then add{ s } end
    s = w:match("^(%a%a+)ed$")
    if s then add(stemForms(s)) end
    s = w:match("^(%a%a+)ing$")
    if s then add(stemForms(s)) end
    return out
end

--- Whether a selection has CJK words, and is looked up (查询) rather than translated (翻译): CJK punctuation alone
-- (「Xerox PARC」 in a Chinese book) does not count, as for the selection popover's action.
local function hasCJKWords(text)
    for c in text:gmatch(util.UTF8_CHAR_PATTERN) do
        if util.isCJKWordChar(c) then return true end
    end
    return false
end

--- Whether a selection is several words of text that is not CJK (such as an English phrase or sentence):
-- the translator takes it when no dictionary has it.
local function isPhrase(word)
    return not hasCJKWords(word) and word:find("%S%s+%S") ~= nil
end

--- Whether an online card can send its request now: "online"; "offline", not connected (Wi-Fi off, or not
-- joined yet), which turning on Wi-Fi helps; or "unreachable", connected but without internet access, which
-- turning on Wi-Fi does not (it is on: NetworkMgr would only ask to turn it on again), only a retry.
local function networkState()
    if NetworkMgr:isOnline() then return "online" end
    return NetworkMgr:isConnected() and "unreachable" or "offline"
end

local ReaderDictSheet = ReaderDictionary:extend{}

--- Registers the sheet in its replacement slot. Touch devices only: it has no key navigation.
function ReaderDictSheet.register()
    if Device:isTouchDevice() then
        require("apps/replacements").reader_dictionary = ReaderDictSheet
    end
end

--- Words to look up for a selection, in order of preference.
-- extra: candidates from the language support plugins, tried right after the selection
function ReaderDictSheet.candidates(word, extra)
    local list, seen = {}, {}
    local function add(w)
        if w and not seen[w] then
            seen[w] = true
            table.insert(list, w)
        end
    end
    add(word)
    for _, w in ipairs(extra or {}) do add(w) end
    if hasCJKWords(word) then
        local chars = util.splitToChars(word)
        local n = #chars
        if n > MAX_MATCH_CHARS then return list end
        local cjk = {}
        for i, c in ipairs(chars) do cjk[i] = util.isCJKWordChar(c) end
        -- longest first, then leftmost; only runs of CJK characters
        for len = n - 1, 2, -1 do
            for i = 1, n - len + 1 do
                local ok = true
                for j = i, i + len - 1 do
                    if not cjk[j] then ok = false break end
                end
                if ok then add(table.concat(chars, "", i, i + len - 1)) end
            end
        end
    else
        local lower = Utf8Proc.lowercase(word, false)
        add(lower)
        if lower:match("^%a[%a'-]*$") then
            for _, w in ipairs(lemmas(lower)) do add(w) end
        end
    end
    return list
end

--- Whether a lookup happens from inside the upstream popup (its links, its search, enlarging): it stays there.
function ReaderDictSheet:inUpstreamPopup()
    return #DictQuickLookup.window_list > 0 or DictQuickLookup.temp_large_window_request ~= nil
end

-- Exact lookups of all candidates in one sdcv run; the first candidate with results wins.
function ReaderDictSheet:startSdcv(word, dict_names)
    local extra
    if self.ui.languagesupport and self.ui.languagesupport:hasActiveLanguagePlugins() then
        extra = self.ui.languagesupport:extraDictionaryFormCandidates(word)
    end
    local words = self.candidates(word, extra)
    -- the waiting page is the lookup's trap widget: a tap on it cancels the lookup
    local trap = self.lookup_page or self.lookup_progress_msg or false
    local cancelled, results = self:rawSdcv(words, dict_names, false, trap)
    if results == nil then
        return { {
            dict = _("No dictionaries installed"),
            word = word,
            definition = _([[To install dictionaries, search for "Dictionary support" in the KOReader wiki.]]),
            no_result = true,
        } }
    end
    for _, term_results in ipairs(results) do
        if #term_results > 0 then
            term_results.lookup_cancelled = cancelled or nil
            return term_results
        end
    end
    return {
        { dict = "", word = word, definition = cancelled and _("Dictionary lookup interrupted.") or "", no_result = true },
        lookup_cancelled = cancelled or nil,
    }
end

-- No input dialog offering fuzzy search: the page shows why nothing was found.
function ReaderDictSheet:showNoResultsDialog()
    return false
end

local LookupPage

--- A slow lookup shows the page with 查询中… after the delay. The page is shown at once, invisible, so that it
-- catches taps from the start, as upstream's lookup message does: a tap cancels the lookup.
function ReaderDictSheet:showLookupInfo(word, show_delay)
    if self:inUpstreamPopup() then
        return ReaderDictionary.showLookupInfo(self, word, show_delay)
    end
    self.lookup_page = LookupPage:new{ dictionary = self, highlight = self.highlight, word = word }
    self.lookup_page:showAfter(show_delay)
end

function ReaderDictSheet:stardictLookup(word, dict_names, ...)
    if dict_names and #dict_names == 0 and self:getNumberOfDictionaries() == 0 then
        -- none enabled because none is installed: upstream would say they are all disabled, sdcv says none is there
        dict_names = nil
    end
    ReaderDictionary.stardictLookup(self, word, dict_names, ...)
    -- a lookup cancelled right away ends without results (upstream has cleared the selection): drop its page
    if self.lookup_page then
        self.lookup_page:dispose()
        self.lookup_page = nil
    end
end

function ReaderDictSheet:showDict(word, results, boxes, link, dict_close_callback)
    if self:inUpstreamPopup() then
        return ReaderDictionary.showDict(self, word, results, boxes, link, dict_close_callback)
    end
    self:dismissLookupInfo()
    local page = self.lookup_page
    self.lookup_page = nil
    if not (results and results[1]) or results.lookup_cancelled then
        -- cancelled by a tap on the waiting page (its back arrow): back to the book, as from the page
        if page then page:dispose() end
        if results and results.lookup_cancelled then
            LookupPage.leave(self.highlight, false, dict_close_callback)
        end
        return
    end
    local args = { word = word, results = results, boxes = boxes, link = link, dict_close_callback = dict_close_callback }
    if page and not page.closed then
        page:setResults(args)
    else
        args.dictionary, args.highlight = self, self.highlight
        page = LookupPage:new(args)
        page:build() -- LookupPage:init() doesn't: the waiting page has nothing to show before its delay
        UIManager:show(page, "ui", page.dimen)
    end
    self.dict_window = page
    if self._lookup_start_time and (time.now() - self._lookup_start_time) > self.quick_dismiss_before_delay then
        -- as upstream: taps made while waiting must not close the late result
        Device.input:inhibitInputUntil(true)
    end
    page:requestTranslation()
end

--- Phonetic and senses of sdcv results. A leading /…/ or […] is the phonetic
-- (IPA, or pinyin in CEDICT style); every other line is a sense, tagged when it
-- starts with a part of speech.
function ReaderDictSheet.parseEntry(results)
    local phonetic, senses = nil, {}
    for _, r in ipairs(results) do
        local def = r.definition or ""
        if r.is_html then
            def = def:gsub("<[sS][tT][yY][lL][eE].-</[sS][tT][yY][lL][eE]%s*>", "")
                     :gsub("<[sS][cC][rR][iI][pP][tT].-</[sS][cC][rR][iI][pP][tT]%s*>", "")
            -- block ends become line breaks before the tags go
            for _, tag in ipairs{ "div", "li", "p", "dd", "dt", "tr", "h%d" } do
                def = def:gsub("</%s*" .. tag .. "%s*>", "\n")
            end
            def = util.htmlToPlainText(def)
        end
        for line in def:gmatch("[^\n]+") do
            line = util.trim(line)
            if not phonetic and #senses == 0 then
                local p, rest = line:match("^%*?(%b[])%s*(.*)$")
                if not p then p, rest = line:match("^(/[^/]+/)%s*(.*)$") end
                if p then
                    phonetic, line = p, rest
                end
            end
            if line ~= "" then
                local tag, text = line:match("^(%a+)%.%s*(.+)$")
                if tag and POS[tag:lower()] then
                    table.insert(senses, { pos = tag .. ".", text = text, dict = r.dict })
                else
                    table.insert(senses, { text = line, dict = r.dict })
                end
            end
        end
    end
    return phonetic, senses
end

--- The results of each dictionary, in their order, with their phonetic and senses.
local function byDictionary(results)
    local groups = {}
    for _, r in ipairs(results) do
        local last = groups[#groups]
        if last and last.dict == r.dict then
            table.insert(last.results, r)
        else
            table.insert(groups, { dict = r.dict, results = { r } })
        end
    end
    for _, g in ipairs(groups) do
        g.phonetic, g.senses = ReaderDictSheet.parseEntry(g.results)
        g.cut = #g.senses > MAX_SENSES
        for i = #g.senses, MAX_SENSES + 1, -1 do
            g.senses[i] = nil
        end
    end
    return groups
end

--- The main translation in a translate server response, or nil.
local function translationOf(result)
    if type(result) ~= "table" or type(result[1]) ~= "table" then return end
    local parts = {}
    for _, r in ipairs(result[1]) do
        if type(r) == "table" and type(r[1]) == "string" then
            table.insert(parts, r[1])
        end
    end
    local text = util.trim(table.concat(parts))
    return text ~= "" and text or nil
end

--- Text of a card, clamped to max_lines with an ellipsis if given.
local function textBox(text, face, width, max_lines, leading)
    local args = { text = text, face = face, fgcolor = Palette.ink, width = width, line_height = leading or LEADING }
    local box = TextBoxWidget:new(args)
    if max_lines and #box.vertical_string_list > max_lines then
        args.height = max_lines * box:getLineHeight()
        box:free()
        args.height_overflow_show_ellipsis = true
        box = TextBoxWidget:new(args)
    end
    return box
end

local function chevron()
    return IconWidget:new{ icon = "eink/chev", width = CHEV, height = CHEV, alpha = true }
end

local function headingFace() return Font:getFace("ui_headline", 18) end
local function bodyFace() return Font:getFace("ui_body", 16) end

local WikiTextBox = TextBoxWidget:extend{}

function WikiTextBox:free(full)
    TextBoxWidget.free(self, full)
    if full ~= false then
        -- TextBoxWidget's queued image wrapper outlives free(); invalidate it and any delayed repaint.
        self.image_update_action = function() end
        self.virtual_line_num = 0
    end
end

-- The full article uses Wikipedia's plain-text extract and the same page navigation as the lookup.
local WikiArticlePage = FullscreenPage:extend{}

function WikiArticlePage:init()
    FullscreenPage.init(self)
    self:build()
end

function WikiArticlePage:buildContent(rect)
    local width = rect.w - 2 * dp(46)
    local box = WikiTextBox:new{
        text = self.text, face = bodyFace(), fgcolor = Palette.ink,
        width = width, height = rect.h - 2 * GUTTER, line_height = LEADING,
        virtual_line_num = (self.page - 1) * (self.lines_per_page or 1) + 1,
        images = self.images, lang = self.lang, auto_para_direction = true, dialog = self,
    }
    self.lines_per_page = box.lines_per_page
    local lines = self.lines_per_page
    local pages = math.max(1, math.ceil(#box.vertical_string_list / lines))
    self.page = math.min(self.page, pages)
    return VerticalGroup:new{
        VerticalSpan:new{ width = GUTTER },
        HorizontalGroup:new{ HorizontalSpan:new{ width = dp(46) }, box },
    }, pages
end

function WikiArticlePage:onCloseWidget()
    for _, picture in ipairs(self.images or {}) do
        if picture.bb then picture.bb:free() end
        if picture.hi_bb then picture.hi_bb:free() end
        picture.bb, picture.hi_bb = nil, nil
    end
end

LookupPage = FullscreenPage:extend{
    dictionary = nil, -- ReaderDictSheet
    highlight = nil, -- ReaderHighlight that made the selection, if any
    word = nil, -- the looked up text
    results = nil, -- sdcv results; nil while the lookup runs
    boxes = nil,
    link = nil,
    dict_close_callback = nil,
    translation = nil, -- { loading | offline | unreachable | failed | text }, once asked for
    wiki = nil, -- { loading | offline | unreachable | failed | missing | results }, once asked for
}

function LookupPage:init()
    FullscreenPage.init(self)
    self.ui = self.dictionary.ui
    self.column_w = math.min(COLUMN_W, self.dimen.w - 2 * GUTTER)
    self.inner_w = self.column_w - 2 * (CARD_PAD + CARD_BORDER)
    if self.results then
        self:readResults()
    end
end

function LookupPage:readResults()
    self.not_found = self.results[1].no_result
    if self.not_found then
        self.headword = self.word
        self.groups = {}
        if isPhrase(self.word) then -- no dictionary has the phrase: the translator takes it
            self.translation = { loading = true }
        end
    else
        self.headword = self.results[1].word
        self.groups = byDictionary(self.results)
    end
    -- beside the headword: the first phonetic any dictionary has
    self.phonetic = nil
    for _, g in ipairs(self.groups) do
        if g.phonetic then
            self.phonetic = g.phonetic
            break
        end
    end
    -- the units of each dictionary's card, kept with their heights once measured
    for __, g in ipairs(self.groups) do -- not _, which is gettext
        g.units = {}
        if g.phonetic and g.phonetic ~= self.phonetic then -- another one than beside the headword
            table.insert(g.units, { text = g.phonetic })
        end
        for __, sense in ipairs(g.senses) do table.insert(g.units, sense) end
        if g.cut then
            table.insert(g.units, { text = _("Tap the card for the rest of the entry.") })
        end
    end
    self.pages = nil
end

--- Shows the waiting page, invisible until `delay` has passed.
function LookupPage:showAfter(delay)
    self.invisible = true
    self.covers_fullscreen = false
    UIManager:show(self) -- no refresh while invisible
    self._reveal = function() self:reveal() end
    UIManager:scheduleIn(delay, self._reveal)
end

--- Shows the waiting page after its delay, or sooner with the results: as opening the page.
function LookupPage:reveal()
    UIManager:unschedule(self._reveal)
    self._reveal = nil
    self.invisible = false
    self.covers_fullscreen = true
    self:build()
    UIManager:setDirty(self, "ui", self.dimen)
end

--- The lookup is done: shows its results on the waiting page.
function LookupPage:setResults(args)
    for k, v in pairs(args) do self[k] = v end
    self.dismiss_callback = nil -- the trap of the finished lookup
    self:readResults()
    if self.invisible then -- the lookup was quicker than the delay
        self:reveal()
    else
        self:update()
    end
end

function LookupPage:paintTo(bb, x, y)
    if self.invisible then return end
    FullscreenPage.paintTo(self, bb, x, y)
end

function LookupPage:showsVocabulary()
    -- not from within the vocabulary builder, as upstream
    local vocab = self.ui.vocabbuilder
    return self.results and vocab and not vocab.widget
        and (not self.not_found or (not isPhrase(self.word) and #util.splitToChars(self.word) <= MAX_MATCH_CHARS))
end

--- The cards, in order. A card has a `kind`; one with `units` (senses, paragraphs) can continue on the next page.
function LookupPage:cards()
    local cards = { { kind = "headword" } }
    if not self.results then return cards end
    local phrase = isPhrase(self.word)
    for __, g in ipairs(self.groups) do
        table.insert(cards, { kind = "dict", group = g, title = g.dict, units = g.units })
    end
    -- the translation takes a phrase that no dictionary has, unless none is there
    if self.not_found and (not phrase or self.results[1].dict ~= "") then
        table.insert(cards, { kind = "empty" })
    end
    if self.translation then
        table.insert(cards, { kind = "translation", title = _("Online translation"), units = self.translation.units })
    end
    table.insert(cards, { kind = "wiki" })
    if self:showsVocabulary() then
        table.insert(cards, { kind = "vocab" })
    end
    if self.highlight then -- as upstream: no search from a lookup not started in the book
        table.insert(cards, { kind = "search" })
    end
    return cards
end

--- A card: paper, 1dp ink outline, 14dp radius, 20dp padding.
function LookupPage:cardFrame(content, callback)
    local card = FrameContainer:new{
        bordersize = CARD_BORDER,
        color = Palette.ink,
        background = Palette.paper,
        radius = CARD_RADIUS,
        padding = CARD_PAD,
        margin = 0,
        -- as wide as the column, whatever the content
        LeftContainer:new{ dimen = Geom:new{ w = self.inner_w, h = content:getSize().h }, content },
    }
    if callback then
        return Tappable:new{ callback = callback, card }
    end
    return card
end

--- A card's heading: its name at the left, then an optional caption and a chevron at the right.
function LookupPage:heading(title, caption, chev)
    local right = HorizontalGroup:new{ align = "center" }
    if caption then
        table.insert(right, TextWidget:new{
            text = caption, face = Font:getFace("ui_label"), fgcolor = Palette.ink,
            max_width = math.floor(self.inner_w / 2),
        })
    end
    if chev then
        if caption then table.insert(right, HorizontalSpan:new{ width = dp(8) }) end
        table.insert(right, chevron())
    end
    local right_w = right:getSize().w
    local label = TextWidget:new{
        text = title, face = headingFace(), fgcolor = Palette.ink,
        max_width = self.inner_w - right_w - (right_w > 0 and dp(12) or 0),
    }
    local h = label:getSize().h
    return OverlapGroup:new{
        dimen = Geom:new{ w = self.inner_w, h = h },
        LeftContainer:new{ dimen = Geom:new{ w = self.inner_w, h = h }, label },
        RightContainer:new{ dimen = Geom:new{ w = self.inner_w, h = h }, right },
    }
end

--- A sense or a paragraph, after its part of speech if any; returns the widget and its text box.
-- from, count: only these lines of the text (measured), for a unit taller than a page that continues on the next.
function LookupPage:unitWidget(unit, from, count)
    local tag = unit.pos and TextWidget:new{ text = unit.pos, face = Font:getFace("ui_title", 16), fgcolor = Palette.ink }
    local indent = tag and tag:getSize().w + POS_GAP or 0
    local args = { text = unit.text, face = bodyFace(), fgcolor = Palette.ink, width = self.inner_w - indent, line_height = LEADING }
    if from then
        args.virtual_line_num = from
        args.height = count * unit.line_h
    end
    local box = TextBoxWidget:new(args)
    if not tag then
        return box, box
    end
    if from and from > 1 then -- the rest of a sense: under its text, without the part of speech again
        tag:free()
        return HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = indent }, box }, box
    end
    -- the tag sits on the first line of the text
    local lift = math.max(0, math.floor((box:getLineHeight() - tag:getSize().h) / 2))
    return HorizontalGroup:new{
        align = "top",
        VerticalGroup:new{ VerticalSpan:new{ width = lift }, tag },
        HorizontalSpan:new{ width = POS_GAP },
        box,
    }, box
end

--- Measures a unit once: its height, its number of lines and their height.
function LookupPage:measure(unit)
    if unit.h then return end
    local widget, box = self:unitWidget(unit)
    unit.h, unit.lines, unit.line_h = widget:getSize().h, #box.vertical_string_list, box:getLineHeight()
    widget:free()
end

--- A state line, its reason and at most one pill, inside a card (DESIGN.md, Loading, empty and error states).
function LookupPage:stateBlock(title, reason, pill)
    local group = VerticalGroup:new{ align = "left" }
    if title then
        table.insert(group, TextBoxWidget:new{
            text = title, face = Font:getFace("ui_title"), fgcolor = Palette.ink, width = self.inner_w,
        })
    end
    if reason and reason ~= "" then
        if #group > 0 then table.insert(group, VerticalSpan:new{ width = dp(4) }) end
        table.insert(group, TextBoxWidget:new{
            text = reason, face = Font:getFace("ui_label"), fgcolor = Palette.ink, width = self.inner_w,
        })
    end
    if pill then
        table.insert(group, VerticalSpan:new{ width = dp(12) })
        table.insert(group, EinkControls.PillButton:new{ text = pill[1], callback = pill[2] })
    end
    return group
end

function LookupPage:loadingLine()
    return TextWidget:new{ text = _("Looking up…"), face = bodyFace(), fgcolor = Palette.ink, max_width = self.inner_w }
end

function LookupPage:headwordCard()
    local group = VerticalGroup:new{ align = "left" }
    local phonetic = self.results and self.phonetic
    local face = Font:getFace("ui_title", 20)
    if phonetic then
        local head = TextWidget:new{ text = self.headword, face = face, fgcolor = Palette.ink, max_width = math.floor(self.inner_w * 0.7) }
        table.insert(group, HorizontalGroup:new{
            align = "center",
            head,
            HorizontalSpan:new{ width = dp(12) },
            TextWidget:new{
                text = phonetic, face = Font:getFace("ui_label_large"), fgcolor = Palette.ink,
                max_width = self.inner_w - head:getSize().w - dp(12),
            },
        })
    else
        table.insert(group, textBox(self.headword or self.word, face, self.inner_w, HEADWORD_LINES, HEADWORD_LEADING))
    end
    if not self.results then
        table.insert(group, VerticalSpan:new{ width = dp(8) })
        table.insert(group, self:loadingLine())
    elseif not self.not_found and self.headword ~= self.word and hasCJKWords(self.word) then
        local chars = util.splitToChars(self.word)
        local selected = #chars > 12 and table.concat(chars, "", 1, 12) .. "…" or self.word
        table.insert(group, VerticalSpan:new{ width = dp(8) })
        table.insert(group, TextBoxWidget:new{
            text = T(_("Selected \"%1\", found \"%2\" by longest match"), selected, self.headword),
            face = Font:getFace("ui_caption"), fgcolor = Palette.ink, width = self.inner_w,
        })
    end
    return self:cardFrame(group)
end

--- Why nothing was found, with what may help.
function LookupPage:emptyCard()
    local r = self.results[1]
    local title, reason
    if hasCJKWords(self.word) and #util.splitToChars(self.word) > MAX_MATCH_CHARS then
        title, reason = _("Selection too long to look up"), _("Try searching the book instead.")
    elseif r.dict ~= "" then -- none installed, or none enabled
        title, reason = r.dict, r.definition
    else
        title = T(_("No \"%1\" in local dictionaries"), self.word)
        reason = r.definition ~= "" and r.definition or _("Try Wikipedia, or add more StarDict dictionaries in settings.")
    end
    local pill
    if not hasCJKWords(self.word) and not self.translation then
        pill = { _("Translate online"), function() self:translate() end }
    end
    return self:cardFrame(self:stateBlock(title, reason, pill))
end

--- A card with units: its heading, then the blocks of its units on this page (see paginate()).
function LookupPage:unitsCard(card, blocks)
    local group = VerticalGroup:new{ align = "left" }
    -- the translation says it is online, unless its offline state says so already
    local caption = card.kind == "translation" and not self.translation.offline and _("Needs a network connection") or nil
    table.insert(group, self:heading(card.title, caption, card.kind == "dict"))
    if card.units then
        for i, block in ipairs(blocks) do
            table.insert(group, VerticalSpan:new{ width = i == 1 and HEADING_GAP or UNIT_GAP })
            table.insert(group, (self:unitWidget(block.unit, block.from, block.count)))
        end
    else
        table.insert(group, VerticalSpan:new{ width = HEADING_GAP })
        table.insert(group, self:translationState())
    end
    local callback
    if card.kind == "dict" then
        callback = function() self:onFullEntry(card.group) end
    end
    return self:cardFrame(group, callback)
end

--- The offline state of an online card: its reason, and 打开 Wi-Fi, which runs `retry` once online.
function LookupPage:offlineState(reason, retry)
    return self:stateBlock(_("Needs a network connection"), reason, { C_("Dictionary sheet", "Turn on Wi-Fi"), function()
        if NetworkMgr:isConnected() then
            -- Wi-Fi came on meanwhile (from the system): the retry says how things stand, as NetworkMgr would
            -- only ask to turn it on again without internet access
            return retry()
        end
        NetworkMgr:runWhenOnline(function()
            if not self.closed then retry() end
        end)
    end })
end

--- The state of an online card connected without internet access: retrying is what helps.
function LookupPage:unreachableState(retry)
    return self:stateBlock(_("Network unreachable."), _("Check the network connection and try again."),
        { _("Retry"), retry })
end

function LookupPage:translationState()
    local tr = self.translation
    if tr.loading then
        return self:loadingLine()
    elseif tr.offline then
        return self:offlineState(_("Online translation needs Wi-Fi. Turn it on and try again."), function() self:translate() end)
    elseif tr.unreachable then
        return self:unreachableState(function() self:translate() end)
    end
    return self:stateBlock(_("Translation failed."), _("Check the network connection and try again."),
        { _("Retry"), function() self:translate() end })
end

function LookupPage:wikiCard()
    local wiki = self.wiki
    local group = VerticalGroup:new{ align = "left" }
    local title = _("Encyclopedia definition")
    table.insert(group, self:heading(title, nil, not wiki or wiki.results))
    local callback
    if wiki and wiki.results then
        table.insert(group, VerticalSpan:new{ width = HEADING_GAP })
        local summary = util.trim(wiki.results[1].definition:gsub("%s*\n%s*", "\n"))
        table.insert(group, textBox(summary, bodyFace(), self.inner_w, INTRO_LINES))
    end
    if not wiki or (wiki.results and not (wiki.loading or wiki.offline or wiki.unreachable or wiki.failed or wiki.missing)) then
        callback = function() self:loadWiki(wiki and wiki.results ~= nil) end
    else
        table.insert(group, VerticalSpan:new{ width = HEADING_GAP })
        if wiki.loading then
            table.insert(group, textBox(wiki.full and _("Retrieving Wikipedia article…") or _("Searching Wikipedia…"),
                bodyFace(), self.inner_w))
        elseif wiki.offline then
            table.insert(group, self:offlineState(_("Wikipedia is an online lookup. Turn on Wi-Fi and try again."),
                function() self:loadWiki(wiki.full) end))
        elseif wiki.unreachable then
            table.insert(group, self:unreachableState(function() self:loadWiki(wiki.full) end))
        else
            local message = wiki.failed and (wiki.full and _("Failed to retrieve Wikipedia article.") or _("Failed searching Wikipedia."))
                or (wiki.full and _("Wikipedia article not found.") or T(_("No Wikipedia article for \"%1\""), self.headword))
            table.insert(group, self:stateBlock(message, nil, { _("Retry"), function() self:loadWiki(wiki.full) end }))
        end
    end
    return self:cardFrame(group, callback)
end

--- A card with a centered label, for an action (加入生词本).
function LookupPage:vocabCard()
    local has = self.ui.vocabbuilder:hasWord(self.headword)
    local text = has and _("In vocabulary builder") or C_("Dictionary sheet", "Add to vocabulary builder")
    local icon_size = dp(22)
    local row = HorizontalGroup:new{
        align = "center",
        IconWidget:new{ icon = has and "eink/check" or "eink/plus", width = icon_size, height = icon_size, alpha = true },
        HorizontalSpan:new{ width = dp(12) },
        TextWidget:new{ text = text, face = headingFace(), fgcolor = Palette.ink, max_width = self.inner_w - icon_size - dp(12) },
    }
    return self:cardFrame(CenterContainer:new{ dimen = Geom:new{ w = self.inner_w, h = row:getSize().h }, row },
        function() self:onVocabulary() end)
end

function LookupPage:searchCard()
    return self:cardFrame(self:heading(_("Search in this book"), nil, true),
        function() self:onSearchBook() end)
end

--- A card of a page (see paginate()): part.card, with part.blocks of its units.
function LookupPage:buildCard(part)
    local card = part.card
    if card.kind == "headword" then return self:headwordCard()
    elseif card.kind == "dict" or card.kind == "translation" then return self:unitsCard(card, part.blocks)
    elseif card.kind == "empty" then return self:emptyCard()
    elseif card.kind == "wiki" then return self:wikiCard()
    elseif card.kind == "vocab" then return self:vocabCard()
    elseif card.kind == "search" then return self:searchCard()
    end
end

local function heightOf(widget)
    local h = widget:getSize().h
    widget:free()
    return h
end

--- Splits the cards into pages of `avail` height: { { { card =, blocks = } ... } ... }, where a block is a unit
-- (whole, or `count` lines `from` one). A card with units continues on the next page, under its heading again. A
-- unit that fits a page moves there whole; one taller than a page fills the rest of this one and goes on, line by
-- line, on the next ones. Nothing is cut.
function LookupPage:paginate(avail)
    local pages, page, used = {}, {}, 0
    local function push()
        table.insert(pages, page)
        page, used = {}, 0
    end
    local function place(part, h)
        used = used + (#page > 0 and CARD_GAP or 0) + h
        table.insert(page, part)
    end
    for __, card in ipairs(self:cards()) do
        if not (card.units and #card.units > 0) then
            local part = { card = card, blocks = {} }
            local h = heightOf(self:buildCard(part))
            if #page > 0 and used + CARD_GAP + h > avail then push() end
            place(part, h)
        else
            local frame_h = heightOf(self:buildCard{ card = card, blocks = {} })
            local capacity = avail - frame_h - HEADING_GAP -- for units, on a page of their own
            local units, i, from = card.units, 1, 1 -- the next line to place: line `from` of unit i
            while i <= #units do
                local room = avail - used - (#page > 0 and CARD_GAP or 0) - frame_h
                local blocks, h = {}, 0
                while i <= #units do
                    local unit = units[i]
                    self:measure(unit)
                    local gap = #blocks > 0 and UNIT_GAP or HEADING_GAP
                    local lines = unit.lines - from + 1
                    local rest_h = from == 1 and unit.h or lines * unit.line_h
                    if h + gap + rest_h <= room then
                        table.insert(blocks, { unit = unit, from = from > 1 and from or nil, count = from > 1 and lines or nil })
                        h, i, from = h + gap + rest_h, i + 1, 1
                    else
                        local fit = math.floor((room - h - gap) / unit.line_h)
                        if fit < 1 and #blocks == 0 and #page == 0 then
                            fit = 1 -- a line taller than a page still shows
                        end
                        if rest_h > capacity and fit >= 1 then -- too tall for any page: as much as fits here
                            table.insert(blocks, { unit = unit, from = from, count = fit })
                            h, from = h + gap + fit * unit.line_h, from + fit
                        end
                        break
                    end
                end
                if #blocks > 0 then
                    place({ card = card, blocks = blocks }, frame_h + h)
                end
                if i <= #units then push() end
            end
        end
    end
    if #page > 0 or #pages == 0 then push() end
    return pages
end

function LookupPage:buildContent(rect)
    self.pages = self.pages or self:paginate(rect.h - TOP - BOTTOM)
    self.page = math.max(1, math.min(self.page, #self.pages))
    local column = VerticalGroup:new{ align = "left" }
    for i, part in ipairs(self.pages[self.page]) do
        if i > 1 then table.insert(column, VerticalSpan:new{ width = CARD_GAP }) end
        table.insert(column, self:buildCard(part))
    end
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = TOP },
        HorizontalGroup:new{ HorizontalSpan:new{ width = math.floor((rect.w - self.column_w) / 2) }, column },
    }, #self.pages
end

--- Rebuilds the cards and repaints the content and the bar. focus: the kind of a card to show, on whichever page.
function LookupPage:update(focus)
    if self.closed then return end
    self.pages = nil
    if focus then
        self.pages = self:paginate(self.content_rect.h - TOP - BOTTOM)
        local found
        for p, parts in ipairs(self.pages) do
            for _, part in ipairs(parts) do
                if part.card.kind == focus then found = p break end
            end
            if found then break end
        end
        self.page = found or self.page
    end
    self:build()
    if not self.invisible then
        UIManager:setDirty(self, "ui", self.body_rect)
    end
end

--- Online translation of the selection (after 在线翻译, 打开 Wi-Fi or 重试).
function LookupPage:translate()
    if self.translation and self.translation.loading then return end -- one request at a time
    self.translation = { loading = true }
    self:update("translation")
    self:requestTranslation()
end

--- Sends the selection to the translator for the translation card, if it waits for it, or says why it cannot.
function LookupPage:requestTranslation()
    if not (self.translation and self.translation.loading) then return end
    -- 查询中… first: checking the network may take a while, and a retry that fails again shows it ran
    UIManager:forceRePaint()
    local state = networkState()
    if state ~= "online" then
        self.translation = { offline = state == "offline", unreachable = state == "unreachable" }
        return self:update("translation")
    end
    local text = self.word
    Trapper:wrap(function()
        -- in a subprocess, as upstream: closing the page (our dismiss_callback) abandons it
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local ok, res = pcall(Translator.loadPage, Translator, text,
                Translator:getTargetLanguage(), Translator:getSourceLanguage())
            return ok and res or nil
        end, self)
        self.dismiss_callback = nil
        if self.closed or not completed then return end
        local translated = translationOf(result)
        if translated then
            self.translation = { text = translated, units = {} }
            for para in translated:gmatch("[^\n]+") do
                table.insert(self.translation.units, { text = para })
            end
        else
            self.translation = { failed = true }
        end
        self:update("translation")
    end)
end

function LookupPage:loadWiki(full)
    if self.wiki and self.wiki.loading then return end -- one request at a time
    local previous = self.wiki
    local results = full and previous.results or nil
    self.wiki = { loading = true, full = full, results = results }
    self:update("wiki")
    UIManager:forceRePaint() -- the request waits, before the network is checked: see requestTranslation()
    local state = networkState()
    if state ~= "online" then
        self.wiki = { offline = state == "offline", unreachable = state == "unreachable", full = full, results = results }
        return self:update("wiki")
    end
    Trapper:wrap(function()
        local wikipedia = self.ui.wikipedia
        wikipedia:initLanguages(self.headword)
        local lang = full and results[1].lang or wikipedia.wiki_last_language or wikipedia.wiki_languages[1]
        -- invisible: a tap cancels the request (and goes no further), the card shows the progress
        local trap = TrapWidget:new{ resend_event = false }
        UIManager:show(trap)
        Wikipedia:setTrapWidget(trap)
        local ok, pages = pcall(full and Wikipedia.getFullPage or Wikipedia.searchAndGetIntros, Wikipedia,
            full and results[1].word or self.headword, lang)
        Wikipedia:resetTrapWidget()
        UIManager:close(trap)
        local found = {}
        if ok and pages then
            for __, page in pairs(pages) do
                if page.extract and page.extract ~= "" then
                    table.insert(found, {
                        dict = T(_("Wikipedia %1"), lang:upper()),
                        word = page.title,
                        definition = page.extract,
                        lang = lang,
                        rtl_lang = Wikipedia:isWikipediaLanguageRTL(lang),
                        images = page.images,
                        index = page.index or 0,
                    })
                end
            end
            table.sort(found, function(a, b) return a.index < b.index end)
        end
        if self.closed then return end
        if not ok and tostring(pages):find(Wikipedia.dismissed_error_code, 1, true) then
            self.wiki = previous -- cancelled by a tap: back to where we were
        elseif #found > 0 then
            if full then
                self.wiki = { results = results }
                self:update("wiki")
                local article = WikiArticlePage:new{
                    title = found[1].word, text = found[1].definition, images = found[1].images, lang = lang,
                }
                UIManager:show(article, "ui", article.dimen)
                return
            end
            self.wiki = { results = found }
        else
            self.wiki = { failed = not ok, missing = ok, full = full, results = results }
        end
        self:update("wiki")
    end)
end

function LookupPage:onVocabulary()
    local vocab = self.ui.vocabbuilder
    local word = self.headword
    if vocab:hasWord(word) then
        -- removing loses the review history: confirm, as upstream
        local layer = ConfirmLayer:new{
            text = T(_("Remove \"%1\" from the vocabulary builder?"), word),
            actions = { { text = _("Remove"), callback = function()
                vocab:removeWord(word)
                if self.closed then return end
                self:update()
                UIManager:show(Toast:new{ text = _("Removed from vocabulary builder") })
            end } },
        }
        UIManager:show(layer, "ui", layer:getRefreshRegion())
        return
    end
    local title = self.ui.doc_props and self.ui.doc_props.display_title or _("Dictionary lookup")
    -- The card always keeps the source, even when automatic context saving is disabled.
    self.ui:handleEvent(Event:new("WordLookedUp", word, title, true, true))
    if vocab:hasWord(word) then
        self:update()
        UIManager:show(Toast:new{ text = _("Added to vocabulary builder") })
    end
end

function LookupPage:onSearchBook()
    if self.highlight then self.highlight:clear() end
    self:onClose(true)
    if not self.ui:handleEvent(Event:new("ShowSearchPage", self.word)) then
        self.ui.search:searchCallback(nil, self.word)
    end
end

--- Rich dictionary entries keep the original popup and its plugin buttons.
function LookupPage:onFullEntry(group)
    self.dictionary._lookup_start_time = nil
    local highlight = self.dictionary.highlight
    self.dictionary.highlight = nil
    ReaderDictionary.showDict(self.dictionary, self.word, group.results, self.boxes, self.link, function()
        if not self.closed then self:update() end
    end)
    self.dictionary.highlight = highlight
    self.dictionary.dict_window = self
end

--- Back to the book: the selection stays a moment, to see where the lookup was (as upstream), then the close
-- callback runs.
function LookupPage.leave(highlight, no_clear, dict_close_callback)
    if highlight and not no_clear then
        local clear_id = highlight:getClearId()
        UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), function()
            highlight:clear(clear_id)
        end)
    end
    if dict_close_callback then
        dict_close_callback()
    end
end

--- Takes the page away without leaving the lookup (whose end does that).
function LookupPage:dispose()
    if self.closed then return end
    self.closed = true
    if self._reveal then
        UIManager:unschedule(self._reveal)
        self._reveal = nil
    end
    if self.invisible then
        UIManager:close(self)
    else
        UIManager:close(self, "ui", self.dimen)
    end
end

--- no_clear: keep the selection, for a lookup or search taking over.
function LookupPage:onClose(no_clear)
    if self.closed then return true end
    local waiting = not self.results
    self:dispose()
    if self.dictionary.dict_window == self then
        self.dictionary.dict_window = nil
    end
    local dismiss = self.dismiss_callback
    self.dismiss_callback = nil
    if not waiting then
        LookupPage.leave(self.highlight, no_clear, self.dict_close_callback)
    end
    if dismiss then
        -- cancels the lookup or the translation; a cancelled lookup leaves by itself (showDict)
        dismiss()
    end
    return true
end

function LookupPage:goBack()
    self:onClose()
end

-- While waiting, even invisible, a tap anywhere cancels the lookup.
function LookupPage:onTapBlock()
    if not self.results then
        self:onClose()
    end
    return true
end


return ReaderDictSheet
