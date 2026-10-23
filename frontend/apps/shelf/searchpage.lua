-- Home search (A09): local titles/authors, persistent history, and paged cover rows.
-- Layout follows 15-supplement/07–09; the reference's recommendations and bookstore are omitted.
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmLayer = require("ui/widget/confirmlayer")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local FullscreenPage = require("ui/widget/fullscreenpage")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputText = require("ui/widget/inputtext")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local RightContainer = require("ui/widget/container/rightcontainer")
local Shelf = require("apps/shelf/shelf")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext

local function dp(n) return Screen:scaleBySize(n) end
local GUTTER, FIELD_H, CLEAR_W = dp(22), dp(50), dp(44)
local HEADER_H = dp(130)
local HISTORY_KEY = "shelf_search_history"
local HISTORY_MAX = 20
local Tappable = ShelfWidgets.Tappable

local function text(str, role, width, bold)
    return TextWidget:new{ text = str, face = Font:getFace(role), max_width = width, bold = bold, fgcolor = Palette.ink }
end

local function icon(name, size)
    return IconWidget:new{ icon = name, width = size, height = size, alpha = true }
end

local function rule(width, color)
    return LineWidget:new{ dimen = Geom:new{ w = width, h = Size.border.default }, background = color }
end

local SearchInput = InputText:extend{}
function SearchInput:onTapTextBox(arg, ges)
    if not self.parent.typing then
        self.parent:startTyping()
        return true
    end
    return InputText.onTapTextBox(self, arg, ges)
end

-- The input survives page rebuilds; the page frees it on close.
local FieldSlot = WidgetContainer:extend{}
function FieldSlot:free() end
function FieldSlot:paintTo(bb, x, y)
    self[1]:paintTo(bb, x, y)
    if self[1]:getText() == "" then
        self.placeholder:paintTo(bb, x + dp(3), y)
    end
end

local SearchPage = FullscreenPage:extend{
    shelf = nil,
    typing = false,
    is_always_active = true,
}

function SearchPage:init()
    FullscreenPage.init(self)
    self.inner_w = self.dimen.w - 2 * GUTTER
    self.history = util.tableDeepCopy(G_reader_settings:readSetting(HISTORY_KEY) or {})
    local face = Font:getAdjustedFace(Font:getFace("ui_body"), true)
    self.placeholder = text(_("Search books"), "ui_body")
    self.placeholder.fgcolor = Palette.ink_2
    self.input = SearchInput:new{
        text = "", face = face, focused = false, parent = self,
        width = self.inner_w - dp(50) - CLEAR_W - 2 * Size.border.default,
        height = math.floor(1.3 * face.size + 0.5),
        padding = 0, margin = 0, bordersize = 0,
        enter_callback = function() self:submit() end,
        edit_callback = function() self:onQueryEdited() end,
    }
    self:build()
end

function SearchPage:buildField()
    local bw = Size.border.default
    local clear = CenterContainer:new{ dimen = Geom:new{ w = CLEAR_W, h = FIELD_H - 2 * bw },
        HorizontalSpan:new{ width = 0 },
    }
    if self.input:getText() ~= "" then
        clear[1] = FrameContainer:new{
            padding = dp(3), bordersize = 0, radius = dp(9), background = Palette.ink,
            IconWidget:new{ icon = "eink/close", width = dp(10), height = dp(10), invert = true },
        }
    end
    self.clear_button = Tappable:new{ callback = function() self:clearQuery() end, clear }
    self.search_field = Tappable:new{
        callback = function() self:startTyping() end,
        FrameContainer:new{
            padding = 0, bordersize = bw, radius = math.floor(FIELD_H / 2), background = Palette.paper,
            LeftContainer:new{
                dimen = Geom:new{ w = self.inner_w - 2 * bw, h = FIELD_H - 2 * bw },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = dp(11) }, icon("eink/search", dp(24)),
                    HorizontalSpan:new{ width = dp(7) },
                    FieldSlot:new{ placeholder = self.placeholder, self.input },
                    HorizontalSpan:new{ width = dp(8) }, self.clear_button,
                },
            },
        },
    }
    return self.search_field
end

function SearchPage:buildContent(rect)
    local heading = text(self.results and T(_("Search in shelf: %1"), self.query) or _("Search history"),
        "ui_title", self.inner_w - (self.results and 0 or dp(90)), true)
    local heading_row = HorizontalGroup:new{
        LeftContainer:new{ dimen = Geom:new{ w = self.results and self.inner_w or self.inner_w - dp(90), h = dp(44) }, heading },
    }
    if not self.results and #self.history > 0 then
        local clear_label = text(C_("Search history", "Clear"), "ui_body", dp(90), true)
        self.clear_history = Tappable:new{
            callback = function() self:confirmClearHistory() end,
            RightContainer:new{ dimen = Geom:new{ w = dp(90), h = dp(44) },
                VerticalGroup:new{ clear_label,
                    LineWidget:new{ dimen = Geom:new{ w = clear_label:getSize().w, h = Size.border.default }, background = Palette.ink },
                },
            },
        }
        table.insert(heading_row, self.clear_history)
    end
    local list = VerticalGroup:new{
        align = "left", VerticalSpan:new{ width = dp(12) }, self:buildField(),
        VerticalSpan:new{ width = dp(24) }, heading_row,
    }
    if self.results then table.insert(list, rule(self.inner_w, Palette.rule)) end
    local items = self.results or self.history
    local row_h = self.results and math.max(dp(104), 2 * self.input:getSize().h + dp(20))
        or math.max(dp(57), self.input:getSize().h + dp(16))
    local top_gap = self.results and dp(20) or 0
    self.per_page = math.max(1, math.floor((rect.h - HEADER_H - top_gap) / row_h))
    local pages = math.max(1, math.ceil(#items / self.per_page))
    self.page = math.min(self.page, pages)
    self.shown_rows = {}
    table.insert(list, VerticalSpan:new{ width = top_gap })
    if #items == 0 then
        table.insert(list, CenterContainer:new{
            dimen = Geom:new{ w = self.inner_w, h = math.max(dp(60), (rect.h - HEADER_H) / 2) },
            text(self.results and _("No matching content found") or _("No search history"), "ui_body", self.inner_w),
        })
    end
    for i = (self.page - 1) * self.per_page + 1, math.min(self.page * self.per_page, #items) do
        local item = items[i]
        local row
        if self.results then
            local cover_w, cover_h, gap = dp(58), dp(84), dp(12)
            -- Leaf5 reference glyphs: about 26px for titles and 22px for authors at the default UI size.
            local labels = VerticalGroup:new{ align = "left",
                text(item.title, "ui_label", self.inner_w - cover_w - gap, true),
            }
            if item.authors then
                table.insert(labels, VerticalSpan:new{ width = dp(4) })
                table.insert(labels, text(item.authors, "ui_micro", self.inner_w - cover_w - gap))
            end
            row = Tappable:new{
                callback = function()
                    self:goBack()
                    self.shelf:openBook(item)
                end,
                LeftContainer:new{ dimen = Geom:new{ w = self.inner_w, h = row_h },
                    HorizontalGroup:new{ self.shelf:coverWidget(item, cover_w, cover_h),
                        HorizontalSpan:new{ width = gap }, labels },
                },
            }
        else
            row = Tappable:new{
                callback = function()
                    self.input:setText(item)
                    self:submit()
                end,
                VerticalGroup:new{ align = "left",
                    LeftContainer:new{ dimen = Geom:new{ w = self.inner_w, h = row_h - Size.border.default },
                        HorizontalGroup:new{ HorizontalSpan:new{ width = dp(6) }, icon("eink/search", dp(20)),
                            HorizontalSpan:new{ width = dp(10) }, text(item, "ui_body", self.inner_w - dp(36), true) },
                    }, rule(self.inner_w, Palette.mark),
                },
            }
        end
        table.insert(list, row)
        table.insert(self.shown_rows, row)
    end
    return HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, list }, pages
end

function SearchPage:refresh()
    self:build()
    UIManager:setDirty(self, "ui", self.dimen)
end

function SearchPage:startTyping()
    if self.typing or self.closed then return end
    self.typing = true
    self.input:focus()
    if not ((Device:hasKeyboard() or Device:hasScreenKB()) and G_reader_settings:nilOrFalse("virtual_keyboard_enabled")) then
        self.input:onShowKeyboard()
    end
    self:onKeyboardHeightChanged()
end

-- Keep the back arrow and pager above the keyboard, as in 08-home-search-query.
function SearchPage:onKeyboardHeightChanged()
    local kb_h = self.input:isKeyboardVisible() and self.input:getKeyboardDimen().h or 0
    self.content_rect.h = self.dimen.h - EinkControls.BottomBar.height - kb_h
    self:refresh()
end

function SearchPage:stopTyping()
    if not self.typing then return end
    self.typing = false
    self.input:onCloseKeyboard()
    self.input:unfocus()
    self:onKeyboardHeightChanged()
end

function SearchPage:onKeyboardClosed()
    self:stopTyping()
end

function SearchPage:onQueryEdited()
    if not self.input then return end
    local empty = self.input:getText() == ""
    local edited_results = self.results and self.input:getText() ~= self.query
    if edited_results then self.results, self.page = nil, 1 end
    if empty ~= self.query_empty or edited_results then
        self.query_empty = empty
        self:refresh()
    end
end

function SearchPage:clearQuery()
    self.input:setText("")
    self.results, self.query, self.page = nil, nil, 1
    self:refresh()
    self:startTyping()
end

function SearchPage:submit()
    if self.closed then return end
    local query = util.trim(self.input:getText())
    if query == "" then return end
    self.input:setText(query)
    self:stopTyping()
    self.query, self.page = query, 1
    local books = Shelf.load(self.shelf.scanned, self.shelf.bim, self.shelf.cover_specs)
    self.results = Shelf.view(books, "all", self.shelf.sort, query)
    for i = #self.history, 1, -1 do
        if self.history[i] == query then table.remove(self.history, i) end
    end
    table.insert(self.history, 1, query)
    for i = #self.history, HISTORY_MAX + 1, -1 do self.history[i] = nil end
    G_reader_settings:saveSetting(HISTORY_KEY, util.tableDeepCopy(self.history))
    G_reader_settings:flush()
    self:refresh()
end

function SearchPage:confirmClearHistory()
    self:stopTyping()
    local layer = ConfirmLayer:new{
        text = _("Clear shelf search history?"),
        actions = {{ text = C_("Search history", "Clear"), callback = function()
            self.history, self.page = {}, 1
            G_reader_settings:delSetting(HISTORY_KEY)
            G_reader_settings:flush()
            self:refresh()
        end }},
    }
    UIManager:show(layer, "ui", layer:getRefreshRegion())
end

function SearchPage:goBack()
    if self.closed then return end
    self:stopTyping()
    FullscreenPage.goBack(self)
end

function SearchPage:onCloseDialog()
    self:goBack()
    return true
end

function SearchPage:onTapBlock()
    self:stopTyping()
    return true
end

function SearchPage:getFocusableWidgetXY() end

function SearchPage:onCloseWidget()
    self.closed = true
    self.placeholder:free()
end

return SearchPage
