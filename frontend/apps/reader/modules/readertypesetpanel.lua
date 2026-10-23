--[[--
排版面板 of the e-ink redesign (see DESIGN.md, Panels): tracks for the font
size, weight, line spacing and margins of reflowable books, then the font, in
one panel between the page and the reader toolbar's bottom bar, opened from the
toolbar's "Font" ("ShowConfigMenu"). The bottom bar keeps showing; the top bar
hides, as in WeChat Read. The pill at the right of its title row opens the
layout options page (render mode, embedded fonts and styles, and links into the
existing hyphenation and style tweak menus), nested in the toolbar: the bottom
bar then holds only a back arrow, back to the panel.

Replaces ReaderConfig (apps/replacements reader_config slot) for reflowable
books on touch devices. Fixed-layout books and devices without touch keep the
original bottom bar, which stays reachable for every book through the
"ShowOriginalConfigMenu" event. Also registers the chapter page header.

Showing and closing the panel refresh ("ui") only its rect and the toolbar's
bars it shows or hides, with the page under what they no longer cover; updating
it refreshes only its rect. A type
change re-lays the page out, which the reader refreshes as it does for a page
turn ("partial", promoted to "full" by the user's full refresh setting).
]]

local CanvasContext = require("document/canvascontext")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local FontList = require("fontlist")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local Panel = require("ui/widget/panel")
local ReaderChapterHeader = require("apps/reader/modules/readerchapterheader")
local ReaderConfig = require("apps/reader/modules/readerconfig")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext

-- Stops of the panel's tracks; DESIGN.md (Tracks) records them. Font weight uses the engine's own steps (creoptions).
local FONT_SIZES = { 15, 16, 17, 18, 19, 20, 22, 24, 26, 28 }
-- % of the font's line height; the first round's 105 / 125 / 145 measure about 1.55 / 1.8 / 2.1 em with CJK faces.
local LINE_SPACINGS = { 85, 95, 105, 115, 125, 135, 145, 155, 165 }
local MARGINS = { 10, 14, 18, 23, 28, 36, 44, 56, 70 } -- dp, left and right; with the first round's 18 / 28 / 44
local MAX_LINE_CHARS = 38 -- CJK characters per line
-- 思源宋体, not bundled. Only the first face of a .ttc collection is listed by crengine (as in ReaderFont).
local SERIF_FACES = { "Source Han Serif SC", "Noto Serif CJK SC", "Noto Serif SC", "Source Han Serif CN", "Source Han Serif" }
local CJK_SANS = "Noto Sans CJK SC" -- 思源黑体, bundled
local LATIN_FACES = { serif = "Noto Serif", sans = "Noto Sans" }

local LABEL_W = Screen:scaleBySize(64)

local function text(str, face, color, max_width)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width }
end

local function hasFace(name)
    for _, info in pairs(FontList.fontinfo) do
        if info[1] and info[1].name == name then return true end
    end
    return false
end

local function serifFace()
    for _, face in ipairs(SERIF_FACES) do
        if hasFace(face) then return face end
    end
end

-- Where users put their own fonts on this device.
local function fontsDir()
    local dirs = CanvasContext:hasSystemFonts() and require("ui/elements/font_settings"):getPath()
              or os.getenv("EXT_FONT_DIR")
    return dirs and dirs:match("[^;]+") or require("ffi/util").realpath(FontList.fontdir) or FontList.fontdir
end

-- Gray label column, then the control ("srow").
local function controlRow(label, control)
    return HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = LABEL_W, h = Screen:scaleBySize(52) },
            text(label, "ui_label", Palette.ink_2, LABEL_W),
        },
        control,
    }
end

local function ruleAbove(widget)
    return VerticalGroup:new{
        LineWidget:new{ dimen = Geom:new{ w = Panel.getContentWidth(), h = Screen:scaleBySize(1) }, background = Palette.rule },
        widget,
    }
end

local function linkRow(label, callback)
    local chev = Screen:scaleBySize(18)
    return ruleAbove(Panel.Row:new{
        height = Screen:scaleBySize(48),
        label = text(label, "ui_label_large", Palette.ink, Panel.getContentWidth() - chev),
        right = IconWidget:new{ icon = "eink/chev", width = chev, height = chev, alpha = true },
        callback = callback,
    })
end

-- Outline pill naming a page of the panel, with a chevron: the entry at the right of the title row.
-- The whole 44dp row height is its touch target.
local EntryPill = InputContainer:extend{
    text = nil,
    callback = nil,
}

function EntryPill:init()
    local h = Screen:scaleBySize(29)
    local bw = Size.border.default
    local chev = Screen:scaleBySize(14)
    local pad = Screen:scaleBySize(12)
    local label = HorizontalGroup:new{
        align = "center",
        -- no vertical padding: the largest interface font size fills the pill
        TextWidget:new{ text = self.text, face = Font:getFace("ui_label"), fgcolor = Palette.ink, padding = 0 },
        HorizontalSpan:new{ width = Screen:scaleBySize(4) },
        IconWidget:new{ icon = "eink/chev", width = chev, height = chev, alpha = true },
    }
    local w = label:getSize().w + 2 * (pad + bw)
    self.dimen = Geom:new{ w = w, h = Screen:scaleBySize(44) }
    self[1] = CenterContainer:new{
        dimen = self.dimen:copy(),
        FrameContainer:new{
            bordersize = bw, padding = 0, radius = math.floor(h / 2),
            color = Palette.ink, background = Palette.paper,
            CenterContainer:new{ dimen = Geom:new{ w = w - 2 * bw, h = h - 2 * bw }, label },
        },
    }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function EntryPill:onTapSelect()
    self.callback()
    return true
end

-- Font tile: a sample in the face over its name; 2dp ink border when selected, 1dp rule gray otherwise.
local FontCard = InputContainer:extend{
    width = nil,
    sample = nil, -- widget
    name = nil, -- string
    selected = false,
    enabled = true,
    callback = nil,
}

function FontCard:init()
    local h = Screen:scaleBySize(66)
    local bw = self.selected and Screen:scaleBySize(2) or Screen:scaleBySize(1)
    self.dimen = Geom:new{ w = self.width, h = h }
    self[1] = FrameContainer:new{
        bordersize = bw, padding = 0, radius = Screen:scaleBySize(10),
        color = self.selected and Palette.ink or Palette.rule, background = Palette.paper,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width - 2 * bw, h = h - 2 * bw },
            VerticalGroup:new{
                self.sample,
                VerticalSpan:new{ width = Screen:scaleBySize(2) },
                text(self.name, "ui_micro", self.enabled and Palette.ink_2 or Palette.ink_3, self.width - 2 * bw),
            },
        },
    }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function FontCard:onTapSelect()
    self.callback()
    return true
end

local ReaderTypesetPanel = ReaderConfig:extend{
    panel = nil, -- ui/widget/panel while shown by the toolbar
    page = nil, -- "main" or "more"
}

--- Registers the panel in its replacement slot.
function ReaderTypesetPanel.register()
    require("apps/replacements").reader_config = ReaderTypesetPanel
end

-- Design defaults, each with the defaults.lua key a user customizes for the same option.
-- The 44dp top margin leaves room for the chapter header.
local DESIGN_DEFAULTS = {
    { "copt_font_size", 19, "DCREREADER_CONFIG_DEFAULT_FONT_SIZE" },
    { "copt_line_spacing", 125, "DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM" },
    { "copt_h_page_margins", { 28, 28 }, "DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM" },
    { "copt_t_page_margin", 44, "DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE" },
}

--- Design defaults for books without their own settings; never overrides a default the user has set.
function ReaderTypesetPanel.applyTypesetDefaults()
    for __, default in ipairs(DESIGN_DEFAULTS) do
        if not G_reader_settings:has(default[1]) and not G_defaults:hasBeenCustomized(default[3]) then
            G_reader_settings:saveSetting(default[1], default[2])
        end
    end
end

function ReaderTypesetPanel:init()
    self.applyTypesetDefaults() -- before ReaderConfig.init() loads them
    ReaderConfig.init(self)
    if self.document.koptinterface == nil then -- reflowable
        self.view:registerViewModule("chapter_header", ReaderChapterHeader:new{})
    end
end

--- Reflowable books on touch devices, with the reader toolbar to host the panel.
function ReaderTypesetPanel:usesPanel()
    return self.ui.rolling ~= nil and Device:isTouchDevice() and self.ui.menu.showPanel ~= nil
end

function ReaderTypesetPanel:onShowConfigMenu()
    if not self:usesPanel() then
        return ReaderConfig.onShowConfigMenu(self)
    end
    if not self.panel then
        self:showPage("main")
    end
    self.ui:handleEvent(Event:new("HandledAsSwipe")) -- cancel any pan scroll made
    return true
end

--- The original bottom bar, for reflowable books too.
function ReaderTypesetPanel:onShowOriginalConfigMenu()
    self:closeWithToolbar()
    return ReaderConfig.onShowConfigMenu(self)
end

function ReaderTypesetPanel:onCloseConfigMenu()
    self:closePanel()
    self:closeMenu()
    ReaderConfig.onCloseConfigMenu(self)
end

function ReaderTypesetPanel:onSetDimensions(dimen)
    self:closeWithToolbar(true)
    self:closeMenu()
    ReaderConfig.onSetDimensions(self, dimen)
    if self.ui.rolling and self.ui.postReaderReadyCallback == nil then
        -- On rotation or resize, ReaderRolling re-renders after us: batch so that its re-render is the only one.
        self.ui:handleEvent(Event:new("BatchedUpdate"))
        self:applyMargin()
        self.ui:handleEvent(Event:new("BatchedUpdateDone"))
    end
end

function ReaderTypesetPanel:onCloseWidget()
    self:closeWithToolbar(true)
    self:closeMenu()
end

--- Closes the panel, if it shows; the toolbar stays.
function ReaderTypesetPanel:closePanel()
    if self.panel then
        self.ui.menu:closePanel() -- calls the panel's on_close
    end
end

--- Closes the panel, if it shows, and the toolbar with it.
function ReaderTypesetPanel:closeWithToolbar(no_refresh)
    if self.panel then
        self.ui.menu:hideToolbar(no_refresh) -- calls the panel's on_close
    end
end

--- Shows a page of the panel in the toolbar: "main", or "more" (the layout options, nested with a way back).
function ReaderTypesetPanel:showPage(page)
    self.page = page
    local panel = Panel:new{
        content = self:pageContent(),
        on_back = page == "more" and function() self:showPage("main") end or nil,
        hide_top_bar = true,
    }
    panel.on_close = function()
        if self.panel == panel then
            self.panel = nil
        end
    end
    self.panel = panel
    self.ui.menu:showPanel("font", panel)
end

function ReaderTypesetPanel:pageContent()
    return self.page == "more" and self:moreContent() or self:mainContent()
end

--- Re-renders the shown page with the current values ("ui" on the panel's rect).
function ReaderTypesetPanel:refreshPanel()
    if self.panel then
        self.panel:setContent(self:pageContent())
    end
end

-- Same path as ConfigDialog: record the option, then apply it.
function ReaderTypesetPanel:apply(name, value, event, arg)
    self.ui:handleEvent(Event:new("ConfigChange", name, value))
    if arg == nil then arg = value end
    self.ui:handleEvent(Event:new(event, arg))
end

------------------------------------------------------------------------
-- Font size and margins

local MARGIN_KEY = "typeset_margin" -- doc setting: the margin (dp) chosen in the panel
-- The first round saved the step of its three margins instead.
local FIRST_ROUND_MARGIN_STEP_KEY = "typeset_margin_step"
local FIRST_ROUND_MARGINS = { 18, 28, 44 }

--- Left and right margin (dp) for a margin chosen in the panel: the margin, widened so that a line holds at
-- most MAX_LINE_CHARS characters at the current font size. KOReader's dp grows with the screen, so this only
-- widens margins in landscape or with a DPI override.
function ReaderTypesetPanel:marginsFor(margin)
    if self.configurable.visible_pages == 2 then
        return margin -- ponytail: no cap in two-column mode, use the column width if it matters
    end
    local width = Screen:getWidth() * 1000 / Screen:scaleBySize(1000)
    return margin + math.max(0, math.ceil((width - 2 * margin - MAX_LINE_CHARS * self.configurable.font_size) / 2))
end

--- The margin of this book on the track: the one chosen in the panel, else the track's margin the margins
-- match, if any.
function ReaderTypesetPanel:trackMargin()
    local margin = self.ui.doc_settings:readSetting(MARGIN_KEY)
    if margin then return margin end
    local current = self.configurable.h_page_margins or {}
    if current[1] ~= current[2] then return end
    for __, m in ipairs(MARGINS) do
        if current[1] == m or current[1] == self:marginsFor(m) then return m end
    end
end

--- Sets the margins of the chosen margin for the current screen and font size.
function ReaderTypesetPanel:applyMargin()
    local chosen = self.ui.doc_settings:readSetting(MARGIN_KEY)
    if not chosen then return end
    local margin = self:marginsFor(chosen)
    local current = self.configurable.h_page_margins or {}
    if current[1] ~= margin or current[2] ~= margin then
        self.setting_margins = true
        self:apply("h_page_margins", { margin, margin }, "SetPageHorizMargins")
        self.setting_margins = nil
    end
end

function ReaderTypesetPanel:setMargin(margin)
    self.ui.doc_settings:saveSetting(MARGIN_KEY, margin)
    self:applyMargin()
end

-- Margins set elsewhere (the original bottom bar, gestures) are the user's own: forget the chosen one.
function ReaderTypesetPanel:onSetPageHorizMargins()
    if not self.setting_margins then
        self.ui.doc_settings:delSetting(MARGIN_KEY)
    end
end

function ReaderTypesetPanel:setFontSize(size)
    local margin = self:trackMargin() -- before the size changes
    self.ui:handleEvent(Event:new("BatchedUpdate")) -- a single re-render for size and margins
    self:apply("font_size", size, "SetFontSize")
    if margin then
        self:setMargin(margin)
    end
    self.ui:handleEvent(Event:new("BatchedUpdateDone"))
end

local function indexOf(values, value)
    for i, v in ipairs(values) do
        if v == value then return i end
    end
end

--- The position of `value` on a track of `values`: its stop, or between the two around it. Past an end it goes on
-- at the pace of the last interval, so that it is never taken for the end stop.
local function trackPosition(values, value)
    local i = 2
    while i < #values and value > values[i] do
        i = i + 1
    end
    return i - 1 + (value - values[i - 1]) / (values[i] - values[i - 1])
end

--- The first of `values` strictly below (direction -1) or above (+1) `value`, if any.
local function nextValue(values, value, direction)
    for i = direction > 0 and 1 or #values, direction > 0 and #values or 1, direction do
        if (values[i] - value) * direction > 0 then return values[i] end
    end
end

------------------------------------------------------------------------
-- Fonts

--- Whether the book is CJK: by its typography language, or by the UI language when that language is only
-- a fallback (no language chosen by the user, none usable in the book: txt, "und", missing).
function ReaderTypesetPanel:isCJK()
    local typography = self.ui.typography
    local tag = typography and typography.text_lang_tag
    local book_tag = typography and typography.book_lang_tag
    if typography and typography.allow_doc_lang_tag_override and (not book_tag or book_tag:lower() == "und") then
        tag = _.current_lang
    end
    tag = (tag or ""):lower()
    return tag:match("^zh") or tag:match("^ja") or tag:match("^ko")
end

--- The face behind a font card ("serif" or "sans") for this book's language,
-- or nil for the CJK serif when it is not installed.
function ReaderTypesetPanel:cardFace(kind)
    if not self:isCJK() then
        return LATIN_FACES[kind]
    end
    return kind == "sans" and CJK_SANS or serifFace()
end

function ReaderTypesetPanel:showSerifMissing()
    UIManager:show(InfoMessage:new{
        text = T(_("Source Han Serif is not installed. Put its font files in %1 and restart KOReader. Source Han Sans is used for now."),
                 fontsDir()),
    })
end

function ReaderTypesetPanel:setCardFont(kind)
    local face = self:cardFace(kind)
    if not face then
        face = CJK_SANS
        self:showSerifMissing()
    end
    self.ui.font:onSetFont(face)
end

function ReaderTypesetPanel:fontCards(width)
    local gap = Screen:scaleBySize(10)
    local card_w = math.floor((width - 2 * gap) / 3)
    local cre = require("document/credocument"):engineInit()
    local function sample(face, color)
        local file, index = cre.getFontFaceFilenameAndFaceIndex(face)
        return TextWidget:new{
            text = "永 Aa",
            face = file and Font:getFace(file, 20, index) or Font:getFace("cfont", 20),
            fgcolor = color,
            max_width = card_w,
        }
    end
    local row = HorizontalGroup:new{}
    for __, card in ipairs{ { "serif", _("Source Han Serif") }, { "sans", _("Source Han Sans") } } do
        local face = self:cardFace(card[1])
        local name = card[2]
        if not face then
            name = T(_("%1 · not installed"), name)
        end
        table.insert(row, FontCard:new{
            width = card_w,
            sample = sample(face or CJK_SANS, face and Palette.ink or Palette.ink_3),
            name = name,
            enabled = face ~= nil,
            selected = face ~= nil and self.ui.font.font_face == face,
            callback = function()
                self:setCardFont(card[1])
                self:refreshPanel()
            end,
        })
        table.insert(row, HorizontalSpan:new{ width = gap })
    end
    local icon_size = Screen:scaleBySize(20)
    table.insert(row, FontCard:new{
        width = width - 2 * (card_w + gap),
        sample = IconWidget:new{ icon = "eink/plus", width = icon_size, height = icon_size, alpha = true },
        name = _("More fonts"),
        callback = function() self:showFontMenu() end,
    })
    return row
end

------------------------------------------------------------------------
-- Existing menus, opened on their own

--- Shows a menu item table (the original menu's format) as a single-tab menu, after closing the panel and the toolbar.
function ReaderTypesetPanel:showMenu(item_table)
    self:closeWithToolbar()
    self:closeMenu()
    local TouchMenu = require("ui/widget/touchmenu")
    local tab = { icon = "appbar.typeset", max_per_page = item_table.max_per_page }
    for i, item in ipairs(item_table) do
        tab[i] = item
    end
    local container = CenterContainer:new{ covers_header = true, ignore = "height", dimen = Screen:getSize() }
    local menu = TouchMenu:new{ width = Screen:getWidth(), tab_item_table = { tab }, show_parent = container }
    menu.close_callback = function() self:closeMenu() end
    container[1] = menu
    self.menu_container = container
    UIManager:show(container)
end

function ReaderTypesetPanel:closeMenu()
    if self.menu_container then
        UIManager:close(self.menu_container)
        self.menu_container = nil
    end
end

function ReaderTypesetPanel:showFontMenu()
    local font = self.ui.font
    if font.face_table.needs_refresh and font.face_table.refresh_func then
        font.face_table.refresh_func()
    end
    self:showMenu(font.face_table)
end

--- The style tweaks submenu holding the tweak `tweak_id`, or all style tweaks.
function ReaderTypesetPanel:styleTweaks(tweak_id)
    local tweaks = self.ui.styletweak.tweaks_table
    local function find(items)
        for __, item in ipairs(items) do
            if item.tweak_id == tweak_id then return items end
            local found = item.sub_item_table and find(item.sub_item_table)
            if found then return found end
        end
    end
    return tweak_id and find(tweaks) or tweaks
end

------------------------------------------------------------------------
-- Pages

--- A track (DESIGN.md, Tracks) over `t.values` at `t.value`, showing `t.label` in its knob and `t.low` and `t.high` at
-- its ends; `t.set` applies one of the values. − and + go to the next value below or above, from a value between two
-- of them too.
function ReaderTypesetPanel:track(t)
    local function set(v)
        t.set(v)
        self:refreshPanel()
    end
    return EinkControls.Track:new{
        width = Panel.getContentWidth(),
        count = #t.values,
        position = trackPosition(t.values, t.value),
        label = t.label,
        low = t.low,
        high = t.high,
        on_change = function(i) set(t.values[i]) end,
        on_step = function(direction)
            local target = nextValue(t.values, t.value, direction)
            if target then set(target) end
        end,
    }
end

function ReaderTypesetPanel:mainContent()
    local w = Panel.getContentWidth()
    local size = self.configurable.font_size
    local weights = self:option("font_base_weight").values
    local weight = self.configurable.font_base_weight
    -- The weight's knob shows its step on the engine's scale (3 is regular), or the row's name between two steps.
    local weight_step = indexOf(weights, weight)
    local margins = self.configurable.h_page_margins
    local small, large = C_("Typeset track", "Small"), C_("Typeset track", "Large")
    local entry = EntryPill:new{ text = _("More layout options"), callback = function() self:showPage("more") end }
    return VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            LeftContainer:new{
                dimen = Geom:new{ w = w - entry:getSize().w, h = entry:getSize().h },
                text(_("Font settings"), "ui_title_large", Palette.ink, w - entry:getSize().w),
            },
            entry,
        },
        self:track{
            values = FONT_SIZES, value = size, label = string.format("%g", size),
            low = small, high = large,
            set = function(v) self:setFontSize(v) end,
        },
        self:track{
            values = weights, value = weight, label = weight_step and tostring(weight_step) or _("Font Weight"),
            low = C_("Typeset track", "Light"), high = C_("Typeset track", "Bold"),
            set = function(v) self:apply("font_base_weight", v, "SetFontBaseWeight") end,
        },
        self:track{
            values = LINE_SPACINGS, value = self.configurable.line_spacing, label = C_("Typeset panel", "Line spacing"),
            low = C_("Typeset track", "Tight"), high = C_("Typeset track", "Loose"),
            set = function(v) self:apply("line_spacing", v, "SetLineSpace") end,
        },
        -- margins set elsewhere, even uneven ones, read back at their own place
        self:track{
            values = MARGINS, value = self:trackMargin() or (margins[1] + margins[2]) / 2, label = _("Margins"),
            low = small, high = large,
            set = function(v) self:setMargin(v) end,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
        controlRow(_("Font"), self:fontCards(w - LABEL_W)),
    }
end

function ReaderTypesetPanel:option(name)
    for _, tab in ipairs(self.options) do
        for _, option in ipairs(tab.options) do
            if option.name == name then return option end
        end
    end
end

function ReaderTypesetPanel:toggleRow(label, name, event)
    local toggle = EinkControls.Toggle:new{ checked = self.configurable[name] == 1 }
    toggle.callback = function(on)
        UIManager:setDirty(self.panel.show_parent, "fast", toggle.dimen)
        self:apply(name, on and 1 or 0, event, on)
    end
    return ruleAbove(Panel.Row:new{
        height = Screen:scaleBySize(52) - Screen:scaleBySize(1),
        label = text(label, "ui_label_large", Palette.ink, Panel.getContentWidth() - toggle:getSize().w),
        right = toggle,
    })
end

function ReaderTypesetPanel:moreContent()
    local control_w = Panel.getContentWidth() - LABEL_W
    local render = self:option("block_rendering_mode")
    return VerticalGroup:new{
        align = "left",
        controlRow(_("Render Mode"),
            EinkControls.Segmented:new{
                labels = render.toggle, width = control_w,
                value = indexOf(render.values, self.configurable.block_rendering_mode),
                on_change = function(i)
                    self:apply("block_rendering_mode", render.values[i], "SetBlockRenderingMode", render.args[i])
                    self:refreshPanel()
                end,
            }),
        self:toggleRow(_("Embedded Fonts"), "embedded_fonts", "ToggleEmbeddedFonts"),
        self:toggleRow(_("Embedded Style"), "embedded_css", "ToggleEmbeddedStyleSheet"),
        linkRow(_("Hyphenation"), function() self:showMenu(self.ui.typography.menu_table) end),
        linkRow(_("Paragraph indent"), function() self:showMenu(self:styleTweaks("paragraph_indent")) end),
        linkRow(_("Paragraph spacing"), function() self:showMenu(self:styleTweaks("paragraph_whitespace")) end),
        linkRow(_("Style tweaks"), function() self:showMenu(self:styleTweaks()) end),
        linkRow(_("All layout options (original)"), function() self:onShowOriginalConfigMenu() end),
    }
end

------------------------------------------------------------------------
-- Default reading font

-- A book opened for the first time, with no font chosen by the user, reads in the CJK serif when its
-- language is CJK (Source Han Sans while the serif is missing). Applied before the first render.
function ReaderTypesetPanel:onReadSettings(config)
    ReaderConfig.onReadSettings(self, config)
    local first_round_step = config:readSetting(FIRST_ROUND_MARGIN_STEP_KEY)
    if first_round_step then
        config:delSetting(FIRST_ROUND_MARGIN_STEP_KEY)
        config:saveSetting(MARGIN_KEY, FIRST_ROUND_MARGINS[first_round_step])
    end
    -- The margins of the chosen margin for this screen, before ReaderTypeset applies them and the first render.
    local chosen = config:readSetting(MARGIN_KEY)
    if chosen and self.document.koptinterface == nil then
        local margin = self:marginsFor(chosen)
        self.configurable.h_page_margins = { margin, margin }
    end
    self.pick_default_font = self.document.koptinterface == nil
        and not config:has("font_face") and not G_reader_settings:has("cre_font")
end

-- Sent by ReaderTypography once it knows the book's language (and again if the book's metadata overrides it).
function ReaderTypesetPanel:onTypographyLanguageChanged()
    if not self.pick_default_font then return end
    local face
    if self:isCJK() then
        face = serifFace()
        self.serif_missing = face == nil
        face = face or CJK_SANS
    else
        self.serif_missing = nil
        face = self.document.default_font
    end
    self.ui.font:onSetFont(face)
end

function ReaderTypesetPanel:onReaderReady()
    if self.pick_default_font and self.serif_missing and not G_reader_settings:isTrue("typeset_serif_missing_shown") then
        G_reader_settings:makeTrue("typeset_serif_missing_shown")
        self:showSerifMissing()
    end
    self.pick_default_font = nil
end

return ReaderTypesetPanel
