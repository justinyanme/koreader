--[[--
Dictionary sheet of the e-ink redesign (see DESIGN.md, Bottom sheet, and the
prototype's dictSheet()).

Replaces ReaderDictionary in the reader on touch devices (apps/replacements
reader_dictionary slot); the file manager keeps the upstream popup.
- Lookups are exact over a list of candidates: a Chinese selection that is not
  a word is matched by the longest word it contains (up to 20 characters), and
  an English word also tries simple lemmas (plural, past tense, -ing). The
  fuzzy search setting is not used here, so a miss shows the empty state.
- The sheet shows the headword with its phonetic, the senses by part of speech
  (paginated), 词典 / 维基百科 source chips, add to vocabulary builder, search the
  book, and a "Full entry" link to the upstream popup with the same results.

Refreshes: showing and closing refresh the sheet's rect ("ui"). Switching the
source, the page or the vocabulary state refreshes the sheet ("ui"); the sheet
keeps its height across these unless the new content is taller.
]]

local BottomSheet = require("ui/widget/bottomsheet")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local OverlapGroup = require("ui/widget/overlapgroup")
local Palette = require("ui/palette")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
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
local MAX_SENSES = 40 -- longer entries are cut; "Full entry" has the rest

-- Part-of-speech abbreviations that start a sense line ("n. 旅居者").
local POS = {}
for _, p in ipairs{ "n", "v", "vt", "vi", "adj", "a", "adv", "ad", "prep", "pron", "conj", "int",
                    "interj", "num", "art", "aux", "abbr", "pl" } do
    POS[p] = true
end

local function dp(n) return Screen:scaleBySize(n) end

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
    if util.hasCJKChar(word) then
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

-- Exact lookups of all candidates in one sdcv run; the first candidate with results wins.
function ReaderDictSheet:startSdcv(word, dict_names)
    local extra
    if self.ui.languagesupport and self.ui.languagesupport:hasActiveLanguagePlugins() then
        extra = self.ui.languagesupport:extraDictionaryFormCandidates(word)
    end
    local words = self.candidates(word, extra)
    local cancelled, results = self:rawSdcv(words, dict_names, false, self.lookup_progress_msg or false)
    if results == nil then
        return { {
            dict = "",
            word = word,
            definition = _([[No dictionaries installed. Please search for "Dictionary support" in the KOReader Wiki to get more information about installing new dictionaries.]]),
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

-- No input dialog offering fuzzy search: the sheet shows its empty state.
function ReaderDictSheet:showNoResultsDialog()
    return false
end

local DictSheet

function ReaderDictSheet:showDict(word, results, boxes, link, dict_close_callback)
    if #DictQuickLookup.window_list > 0 or DictQuickLookup.temp_large_window_request then
        -- a lookup from inside the upstream popup (links, its search, enlarging) stays there
        return ReaderDictionary.showDict(self, word, results, boxes, link, dict_close_callback)
    end
    self:dismissLookupInfo()
    if not (results and results[1]) then return end
    self.dict_window = DictSheet:new{
        dictionary = self,
        highlight = self.highlight,
        word = word,
        results = results,
        boxes = boxes,
        link = link,
        dict_close_callback = dict_close_callback,
    }
    UIManager:show(self.dict_window, "ui", self.dict_window:getRefreshRegion())
    if not results.lookup_cancelled and self._lookup_start_time
            and (time.now() - self._lookup_start_time) > self.quick_dismiss_before_delay then
        -- as upstream: taps made while waiting must not close the late result
        Device.input:inhibitInputUntil(true)
    end
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

--- A tappable row: its callback runs on tap.
local Tappable = InputContainer:extend{
    callback = nil,
}

function Tappable:init()
    self.dimen = Geom:new{ w = self[1]:getSize().w, h = self[1]:getSize().h }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function Tappable:onTapSelect()
    self.callback()
    return true
end

DictSheet = BottomSheet:extend{
    dictionary = nil, -- ReaderDictSheet
    highlight = nil, -- ReaderHighlight that made the selection, if any
    word = nil, -- the looked up text
    results = nil, -- sdcv results
    boxes = nil,
    link = nil,
    dict_close_callback = nil,
    source = "dict", -- or "wiki"
    page = 1,
}

function DictSheet:init()
    self.title = C_("Dictionary sheet", "Look up")
    self.ui = self.dictionary.ui
    self.not_found = self.results[1].no_result
    self.headword = self.not_found and self.word or self.results[1].word
    if not self.not_found then
        self.phonetic, self.senses = ReaderDictSheet.parseEntry(self.results)
        for i = #self.senses, MAX_SENSES + 1, -1 do
            self.senses[i] = nil
        end
    end
    self.content = self:buildContent()
    BottomSheet.init(self)
end

--- Height left for the content when the sheet is as tall as it may get (84% of the screen).
function DictSheet:maxContentHeight()
    return math.floor(Screen:getHeight() * 0.84) - Size.border.default - dp(54) - dp(20)
end

local function rule(w)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = Size.border.default }, background = Palette.rule }
end

local function emptyState(w, title, body)
    local group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = dp(40) },
        TextBoxWidget:new{ text = title, face = Font:getFace("ui_title"), fgcolor = Palette.ink, width = w, alignment = "center" },
    }
    if body and body ~= "" then
        table.insert(group, VerticalSpan:new{ width = dp(4) })
        table.insert(group, TextBoxWidget:new{
            text = body, face = Font:getFace("ui_label_large"), fgcolor = Palette.ink_2, width = w, alignment = "center",
        })
    end
    table.insert(group, VerticalSpan:new{ width = dp(40) })
    return group
end

function DictSheet:senseRow(sense, w, max_h)
    local gap = dp(10)
    local text_w = w
    local row = HorizontalGroup:new{ align = "top" }
    if sense.pos then
        local tag = FrameContainer:new{
            bordersize = Size.border.default,
            color = Palette.ink,
            radius = dp(4),
            padding = 0,
            padding_left = dp(5),
            padding_right = dp(5),
            margin = 0,
            TextWidget:new{ text = sense.pos, face = Font:getFace("ui_micro"), fgcolor = Palette.ink },
        }
        text_w = w - tag:getSize().w - gap
        table.insert(row, VerticalGroup:new{ VerticalSpan:new{ width = dp(2) }, tag })
        table.insert(row, HorizontalSpan:new{ width = gap })
    end
    local text_args = { text = sense.text, face = Font:getFace("ui_body"), fgcolor = Palette.ink, width = text_w }
    local text = TextBoxWidget:new(text_args)
    max_h = max_h and max_h - 2 * gap - Size.border.default
    if max_h and text:getSize().h > max_h then -- a sense taller than a whole page is clamped
        text:free()
        text_args.height = max_h
        text_args.height_overflow_show_ellipsis = true
        text = TextBoxWidget:new(text_args)
    end
    table.insert(row, text)
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = gap },
        row,
        VerticalSpan:new{ width = gap },
        rule(w),
    }
end

--- Splits the senses into pages that fit `avail`; returns { {first, last}, ... }.
function DictSheet:paginate(w, avail)
    local heights, total = {}, 0
    for i, sense in ipairs(self.senses) do
        local row = self:senseRow(sense, w)
        heights[i] = row:getSize().h
        total = total + heights[i]
        row:free()
    end
    if total <= avail then
        return { { 1, #self.senses } }
    end
    avail = avail - dp(44) -- room for the pager
    local pages, first, used = {}, 1, 0
    for i, h in ipairs(heights) do
        if used + h > avail and i > first then
            table.insert(pages, { first, i - 1 })
            first, used = i, 0
        end
        used = used + h
    end
    table.insert(pages, { first, #heights })
    return pages
end

function DictSheet:vocabulary()
    -- not from within the vocabulary builder, as upstream
    local vocab = self.ui.vocabbuilder
    return not self.not_found and vocab and not vocab.widget
end

function DictSheet:onVocabulary()
    local vocab = self.ui.vocabbuilder
    local word = self.headword
    if vocab:hasWord(word) then
        -- removing loses the review history: confirm, as upstream
        UIManager:show(ConfirmBox:new{
            text = T(_("Remove word \"%1\" from vocabulary builder?"), word),
            ok_text = _("Remove"),
            ok_callback = function()
                vocab:removeWord(word)
                if self.closed then return end
                self:update()
                UIManager:show(Notification:new{ text = _("Removed from vocabulary builder") })
            end,
        })
        return
    end
    local title = self.ui.doc_props and self.ui.doc_props.display_title or _("Dictionary lookup")
    -- the plugin saves the words around the selection, which is still there
    self.ui:handleEvent(Event:new("WordLookedUp", word, title, true))
    if vocab:hasWord(word) then
        self:update()
        UIManager:show(Notification:new{ text = _("Added to vocabulary builder") })
    end
end

function DictSheet:onSearchBook()
    if self.highlight then self.highlight:clear() end
    self:onClose(true)
    self.ui.search:searchCallback(nil, self.headword)
end

--- Hands the same results to the upstream popup, for rich HTML entries and plugin buttons.
function DictSheet:onFullEntry()
    local close_callback = self.dict_close_callback
    self.dict_close_callback = nil -- the popup calls it
    self:onClose(true)
    self.dictionary._lookup_start_time = nil -- no input block: this is not a slow lookup
    if self.source == "wiki" then
        local wikipedia = self.ui.wikipedia
        local highlight = wikipedia.highlight
        wikipedia.highlight = self.highlight
        wikipedia:showDict(self.headword, self.wiki.results, self.boxes, nil, close_callback)
        wikipedia.highlight = highlight
    else
        ReaderDictionary.showDict(self.dictionary, self.word, self.results, self.boxes, self.link, close_callback)
    end
end

function DictSheet:setSource(source)
    if source == self.source then return end
    self.source = source
    if source == "wiki" and (not self.wiki or self.wiki.offline) then
        self:loadWiki()
    else
        self:update()
    end
end

function DictSheet:loadWiki()
    if not NetworkMgr:isOnline() then
        self.wiki = { offline = true }
        return self:update()
    end
    local previous = { source = self.source == "wiki" and self.wiki and "wiki" or "dict", wiki = self.wiki }
    self.wiki = { loading = true }
    self:update()
    UIManager:forceRePaint()
    Trapper:wrap(function()
        local wikipedia = self.ui.wikipedia
        wikipedia:initLanguages(self.headword)
        local lang = wikipedia.wiki_last_language or wikipedia.wiki_languages[1]
        -- invisible: a tap cancels the request, the sheet shows the progress
        local trap = TrapWidget:new{ resend_event = true }
        UIManager:show(trap)
        Wikipedia:setTrapWidget(trap)
        local ok, pages = pcall(Wikipedia.searchAndGetIntros, Wikipedia, self.headword, lang)
        Wikipedia:resetTrapWidget()
        UIManager:close(trap)
        local results = {}
        if ok and pages then
            for __, page in pairs(pages) do
                if page.extract then
                    table.insert(results, {
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
            table.sort(results, function(a, b) return a.index < b.index end)
        end
        if self.closed then return end
        if not ok and tostring(pages):find(Wikipedia.dismissed_error_code, 1, true) then
            -- cancelled by a tap: back to where we were
            self.source, self.wiki = previous.source, previous.wiki
        elseif #results > 0 then
            self.wiki = { results = results }
        else
            self.wiki = { failed = not ok }
        end
        self:update()
    end)
end

--- Rebuilds the content and refreshes the sheet.
function DictSheet:update()
    self:setContent(self:buildContent())
end

function DictSheet:buildContent()
    local w = BottomSheet.getContentWidth()
    local top = VerticalGroup:new{ align = "left" }
    -- headword and phonetic
    local headword = TextWidget:new{
        text = self.headword, face = Font:getFace("ui_headword"), fgcolor = Palette.ink,
        max_width = self.phonetic and math.floor(w * 0.7) or w,
    }
    local head = HorizontalGroup:new{ align = "bottom", headword }
    if self.phonetic then
        table.insert(head, HorizontalSpan:new{ width = dp(10) })
        table.insert(head, VerticalGroup:new{
            TextWidget:new{
                text = self.phonetic, face = Font:getFace("ui_label"), fgcolor = Palette.ink_2,
                max_width = w - headword:getSize().w - dp(10),
            },
            VerticalSpan:new{ width = dp(4) },
        })
    end
    table.insert(top, head)
    if not self.not_found and self.headword ~= self.word and util.hasCJKChar(self.word) then
        local chars = util.splitToChars(self.word)
        local selected = #chars > 12 and table.concat(chars, "", 1, 12) .. "…" or self.word
        table.insert(top, VerticalSpan:new{ width = dp(4) })
        table.insert(top, TextBoxWidget:new{
            text = T(_("Selected \"%1\", found \"%2\" by longest match"), selected, self.headword),
            face = Font:getFace("ui_caption"), fgcolor = Palette.ink_2, width = w,
        })
    end
    -- source chips
    local chips = HorizontalGroup:new{}
    for i, source in ipairs{ { "dict", _("Dictionary") }, { "wiki", _("Wikipedia") } } do
        if i > 1 then table.insert(chips, HorizontalSpan:new{ width = dp(8) }) end
        table.insert(chips, EinkControls.PillButton:new{
            text = source[2],
            face = Font:getFace("ui_label"),
            height = dp(30),
            bordersize = Size.border.default,
            solid = self.source == source[1],
            callback = function() self:setSource(source[1]) end,
        })
    end
    table.insert(top, VerticalSpan:new{ width = dp(12) })
    table.insert(top, chips)
    table.insert(top, VerticalSpan:new{ width = dp(4) })

    -- foot: buttons and the link row
    local bottom = VerticalGroup:new{ align = "left" }
    local link_note
    if self.source == "dict" then
        local gap = dp(10)
        local buttons = {}
        if self:vocabulary() then
            local has = self.ui.vocabbuilder:hasWord(self.headword)
            table.insert(buttons, {
                text = has and _("In vocabulary builder") or C_("Dictionary sheet", "Add to vocabulary builder"),
                solid = has,
                callback = function() self:onVocabulary() end,
            })
        end
        if self.highlight then -- as upstream: no search from a lookup not started in the book
            table.insert(buttons, { text = C_("Dictionary sheet", "Search book"), callback = function() self:onSearchBook() end })
        end
        if #buttons > 0 then
            local button_w = math.floor((w - (#buttons - 1) * gap) / #buttons)
            local row = HorizontalGroup:new{}
            for i, b in ipairs(buttons) do
                if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
                b.width = button_w
                table.insert(row, EinkControls.PillButton:new(b))
            end
            table.insert(bottom, VerticalSpan:new{ width = dp(14) })
            table.insert(bottom, row)
        end
        if not self.not_found then
            link_note = self.results[1].dict
        end
    elseif self.wiki.results then
        link_note = self.wiki.results[1].dict
    end
    if link_note then
        table.insert(bottom, VerticalSpan:new{ width = dp(10) })
        table.insert(bottom, rule(w))
        local chev = dp(16)
        local note = TextWidget:new{
            text = link_note, face = Font:getFace("ui_micro"), fgcolor = Palette.ink_3, max_width = math.floor(w / 2),
        }
        table.insert(bottom, Tappable:new{
            callback = function() self:onFullEntry() end,
            OverlapGroup:new{
                dimen = Geom:new{ w = w, h = dp(44) },
                LeftContainer:new{
                    dimen = Geom:new{ w = w, h = dp(44) },
                    TextWidget:new{ text = C_("Dictionary sheet", "Full entry"), face = Font:getFace("ui_label"), fgcolor = Palette.ink },
                },
                RightContainer:new{
                    dimen = Geom:new{ w = w, h = dp(44) },
                    HorizontalGroup:new{
                        note,
                        HorizontalSpan:new{ width = dp(6) },
                        IconWidget:new{ icon = "eink/chev", width = chev, height = chev, alpha = true, dim = true },
                    },
                },
            },
        })
    end

    -- body
    local avail = self:maxContentHeight() - top:getSize().h - bottom:getSize().h
    local body = VerticalGroup:new{ align = "left" }
    if self.source == "dict" then
        if self.not_found then
            local too_long = util.hasCJKChar(self.word) and #util.splitToChars(self.word) > MAX_MATCH_CHARS
            if too_long then
                table.insert(body, emptyState(w, _("Selection too long to look up"), _("Try searching the book instead.")))
            else
                local hint = self.results[1].definition
                table.insert(body, emptyState(w, T(_("No \"%1\" in local dictionaries"), self.headword),
                    hint ~= "" and hint or _("Try Wikipedia, or add more StarDict dictionaries in settings.")))
            end
        else
            self.pages = self.pages or self:paginate(w, avail)
            local first, last = unpack(self.pages[self.page])
            local page_avail = #self.pages > 1 and avail - dp(44) or avail
            for i = first, last do
                table.insert(body, self:senseRow(self.senses[i], w, page_avail))
            end
            if #self.pages > 1 then
                self.pager_row = EinkControls.Pager:new{
                    page = self.page,
                    pages = #self.pages,
                    width = w,
                    on_change = function(page)
                        self.page = page
                        self:update()
                    end,
                }
            end
        end
    elseif self.wiki.offline then
        table.insert(body, emptyState(w, _("Needs a network connection"), _("Wikipedia is an online lookup. Turn on Wi-Fi and try again.")))
        table.insert(body, EinkControls.PillButton:new{
            text = C_("Dictionary sheet", "Turn on Wi-Fi"),
            solid = true,
            width = w,
            callback = function()
                NetworkMgr:runWhenOnline(function()
                    if not self.closed and self.source == "wiki" then self:loadWiki() end
                end)
            end,
        })
    elseif self.wiki.loading then
        table.insert(body, emptyState(w, _("Searching Wikipedia…")))
    elseif self.wiki.results then
        local args = { text = self.wiki.results[1].definition, face = Font:getFace("ui_body"), fgcolor = Palette.ink, width = w }
        local intro = TextBoxWidget:new(args)
        if intro:getSize().h > avail - dp(10) then
            intro:free()
            args.height = avail - dp(10)
            args.height_overflow_show_ellipsis = true
            intro = TextBoxWidget:new(args)
        end
        table.insert(body, VerticalSpan:new{ width = dp(10) })
        table.insert(body, intro)
    else
        table.insert(body, emptyState(w,
            self.wiki.failed and _("Failed searching Wikipedia.") or T(_("No Wikipedia article for \"%1\""), self.headword)))
    end

    local content = VerticalGroup:new{ align = "left", top, body }
    if self.source == "dict" and self.pages and #self.pages > 1 then
        table.insert(content, self.pager_row)
    end
    -- keep the sheet's height across sources and pages
    local h = content:getSize().h + bottom:getSize().h
    content:resetLayout()
    if self.min_h and h < self.min_h then
        table.insert(content, VerticalSpan:new{ width = self.min_h - h })
    end
    self.min_h = math.max(self.min_h or 0, h)
    table.insert(content, bottom)
    return content
end

--- no_clear: keep the selection, for a lookup or search taking over.
function DictSheet:onClose(no_clear)
    self.closed = true
    BottomSheet.onClose(self)
    self.dictionary.dict_window = nil
    if self.highlight and not no_clear then
        -- as upstream: the selection stays a moment, to see where the lookup was
        local clear_id = self.highlight:getClearId()
        UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), function()
            self.highlight:clear(clear_id)
        end)
    end
    if self.dict_close_callback then
        self.dict_close_callback()
    end
    return true
end

ReaderDictSheet.DictSheet = DictSheet

return ReaderDictSheet
