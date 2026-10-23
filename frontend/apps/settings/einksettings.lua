--[[--
Settings of the e-ink redesign (see the prototype's settings subpage): groups
laid out in ui/elements/eink_settings_order.lua, ending with the original menu.

A full-screen page (ui/widget/fullscreenpage), opened by the "ShowEinkSettings"
event in the reader (ReaderToolbar) and the file manager (ShelfFileManager): the
centered title on top, the back arrow and the page capsule at the bottom. Rows are
backed by the original menu's items: a group row opens its items, and their entries
open as pages of uniform rows (name, current value, then a chevron, a toggle or a
check mark). A row may instead open a page of the new settings' own (the interface font
size). The back arrow goes back up a level, and closes the page from the top.
The page keeps TouchMenu's state names (item_table, item_table_stack, page) and
methods (updateItems, closeMenu, backToUpperMenu), so the items' callbacks work
unchanged.

Opening and closing the page and going into and back from a page of entries refresh
it whole with "ui"; turning a list page refreshes the list and the bottom bar ("ui").
Toggling refreshes the toggle ("fast"), and other rows only when they changed ("ui").
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local Font = require("ui/font")
local FullscreenPage = require("ui/widget/fullscreenpage")
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
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TocDrawer = require("apps/reader/modules/readertocdrawer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local function dp(n) return Screen:scaleBySize(n) end

local GUTTER = dp(24)
local ROW_H = dp(56)
local HEADER_H = dp(36)

local function text(str, face, color, max_width, bold)
    return TextWidget:new{ text = str, face = Font:getFace(face), fgcolor = color or Palette.ink, max_width = max_width, bold = bold }
end

local function rule(w, color)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = Size.border.default }, background = color }
end

local function itemText(item)
    if item.text_func then return item.text_func() end
    return item.text or ""
end

--- "Name: value" (or "Name：value") as name and value; other texts as the name alone.
local function splitText(str)
    -- at the first separator of either kind ("：" is three bytes, so no character class)
    local a, b = str:find(":", 1, true), str:find("：", 1, true)
    local at = a and b and math.min(a, b) or a or b
    if at and at > 1 then
        local name = str:sub(1, at - 1):match("^(.-)%s*$")
        local value = str:sub(at + (at == b and 3 or 1)):match("^%s*(.-)$")
        if name ~= "" and value ~= "" then
            return name, value
        end
    end
    return str
end

local function isEnabled(item)
    if item.enabled_func then return item.enabled_func() ~= false end
    return item.enabled ~= false
end

local function isChecked(item)
    if item.checked_func then return item.checked_func() and true or false end
    return item.checked and true or false
end

-- Whether a row stands only for items of the reader's menu, which the file browser's lacks.
local function needsBook(row)
    if not row.items then return false end
    local fm_order = require("ui/elements/filemanager_menu_order")
    for _, id in ipairs(row.items) do
        for _, ids in pairs(fm_order) do
            for _, fm_id in ipairs(ids) do
                if fm_id == id then return false end
            end
        end
    end
    return true
end

-- Entries of `items` that are single-choice: radio ones, and in a `choice` list those up to the first separator.
local function choiceSet(items, choice)
    local set = {}
    local open = choice
    for _, item in ipairs(items) do
        if type(item) == "table" and (item.radio or open) then set[item] = true end
        if item.separator then open = false end
    end
    return set
end

--- The current value of a menu item: its "Name: value" text, or its checked single-choice entry.
local function valueOf(item, choice)
    local _name, value = splitText(itemText(item))
    if value or type(item.sub_item_table) ~= "table" then return value end
    local choices = choiceSet(item.sub_item_table, choice)
    for _, entry in ipairs(item.sub_item_table) do
        if choices[entry] and isChecked(entry) then
            return (splitText(itemText(entry)))
        end
    end
end

--- Original menu items by id, from a menu's sorted tab_item_table.
local function indexMenu(tab_item_table)
    local by_id = {}
    local function walk(items)
        for _, item in ipairs(items) do
            if type(item) == "table" then
                if item.id and by_id[item.id] == nil then by_id[item.id] = item end
                if type(item.sub_item_table) == "table" then walk(item.sub_item_table) end
            end
        end
    end
    for _, tab in ipairs(tab_item_table) do
        walk(tab)
    end
    return by_id
end

local Row = InputContainer:extend{
    width = nil,
    height = nil,
    on_tap = nil,
    on_hold = nil,
}

function Row:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    -- not TapSelect, which would reach a child toggle's own handler first
    self.ges_events = {
        TapRow = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldRow = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end

function Row:onTapRow()
    if self.on_tap then self.on_tap() end
    return true
end

function Row:onHoldRow()
    if self.on_hold then self.on_hold() end
    return true
end

local EinkSettings = FullscreenPage:extend{
    ui = nil, -- ReaderUI or FileManager: gets "ShowOriginalMenu"
    menu = nil, -- its ReaderMenu or FileManagerMenu, whose items back the rows
    target = nil, -- group or row id to open on
    groups = nil, -- defaults to ui/elements/eink_settings_order
    -- TouchMenu's state, used by menu item callbacks
    item_table = nil,
    item_table_stack = nil,
    page = 1,
}

--- Shows the settings over `ui`, on `target` (a group or row id); without touch, the original menu.
function EinkSettings.show(ui, menu, target)
    if not Device:isTouchDevice() then
        return ui:handleEvent(Event:new("ShowOriginalMenu"))
    end
    local page = EinkSettings:new{ ui = ui, menu = menu, target = target }
    UIManager:show(page, "ui", page.dimen)
    return page
end

function EinkSettings:init()
    self.title = _("Settings")
    FullscreenPage.init(self)
    self.content_w = self.dimen.w - 2 * GUTTER
    if self.menu.tab_item_table == nil then
        self.menu:setUpdateItemTable()
    end
    self.by_id = indexMenu(self.menu.tab_item_table)
    self.groups = self.groups or require("ui/elements/eink_settings_order")
    self.home = self:buildHome()
    self.item_table, self.item_table_stack = self.home, {}
    self.title_stack, self.page_stack = {}, {}
    self.choice_tables = setmetatable({}, { __mode = "k" })
    self:build()
    if self.target then
        self:openTarget(self.target)
    end
end

--- The backing items of a config row that exist in this menu.
function EinkSettings:rowItems(row)
    local items = {}
    if row.file then
        table.insert(items, dofile(row.file))
    end
    if row.build then
        table.insert(items, row.build())
    end
    for _, id in ipairs(row.items or {}) do
        local item = self.by_id[id]
        local event = item and row.events and row.events[id]
        if event then
            -- an entry of its own: it sends an event instead of running the original callback
            item = { text = event.text or itemText(item), callback = function() self.ui:handleEvent(Event:new(event.event)) end }
        end
        if item then
            table.insert(items, item)
        end
    end
    return items
end

-- Home entries: group headers, then one menu-item-like entry per row.
function EinkSettings:buildHome()
    local home = {}
    for _, group in ipairs(self.groups) do
        table.insert(home, { header = true, text = group.text, group_id = group.id })
        for _, row in ipairs(group.rows) do
            table.insert(home, self:homeEntry(row, group.id))
        end
    end
    return home
end

function EinkSettings:homeEntry(row, group_id)
    local entry = { text = row.text, row_id = row.id, group_id = group_id, choice = row.choice }
    if row.original then
        entry.callback = function() self:openOriginal() end
        return entry
    end
    if row.open then
        entry.callback, entry.value_func = row.open, row.value
        return entry
    end
    local items = self:rowItems(row)
    local item = items[1]
    if not item then
        -- a book brings reader-only items; nothing brings what this device lacks (e-ink refresh control on a
        -- screen KOReader doesn't take for e-ink, sleep screens on Android) or a plugin that is off
        local reason = not self.ui.document and needsBook(row) and _("Open a book first") or _("Not available")
        entry.enabled = false
        entry.value_func = function() return reason end
    elseif row.toggle then
        entry.checked_func, entry.callback = item.checked_func, item.callback
    else
        local own = #items == 1 and (item.sub_item_table or item.sub_item_table_func)
        entry.id = own and item.id or nil -- the row stands for this item
        entry.value_func = function()
            if row.value then return row.value(item) end
            return #items == 1 and valueOf(item, row.choice) or nil
        end
        entry.hold_callback, entry.help_text = item.hold_callback, item.help_text
        entry.sub_item_table_func = function()
            local entries = items
            if own then
                entries = item.sub_item_table_func and item.sub_item_table_func() or item.sub_item_table
            end
            if row.preview == "tap_zones" and self:canPreviewTapZones() then
                local with_preview = { { text = _("Preview tap zones"), callback = function() self:previewTapZones() end } }
                for _, e in ipairs(entries) do table.insert(with_preview, e) end
                return with_preview
            end
            return entries
        end
    end
    return entry
end

function EinkSettings:canPreviewTapZones()
    return self.ui.document ~= nil and self.ui.menu.getTapLayout ~= nil
end

function EinkSettings:previewTapZones()
    self:closeMenu(true)
    local zones = require("apps/reader/modules/readertoolbarpanels").TapZones:new{ layout = self.ui.menu:getTapLayout() }
    UIManager:show(zones, "ui", zones.dimen)
end

function EinkSettings:openOriginal()
    -- stays underneath: closing the original menu comes back here
    self.ui:handleEvent(Event:new("ShowOriginalMenu"))
end

function EinkSettings:openTarget(target)
    for i, entry in ipairs(self.home) do
        if entry.row_id == target and entry.sub_item_table_func and isEnabled(entry) then
            self:goToHomeEntry(i)
            self:push(entry.sub_item_table_func(), entry)
            return self:build()
        elseif entry.header and entry.group_id == target or entry.row_id == target then
            return self:goToHomeEntry(i)
        end
    end
end

function EinkSettings:goToHomeEntry(index)
    for p, indexes in ipairs(self.pages) do
        for _, i in ipairs(indexes) do
            if i == index then
                self.page = p
                self:build()
                return
            end
        end
    end
end

--- Row specs of the shown table: { item, name, value, kind = "header"|"toggle"|"check"|"chevron"|"none", enabled, checked }.
function EinkSettings:rowSpecs()
    local specs = {}
    local is_home = self.item_table == self.home
    local choices = choiceSet(self.item_table, self.choice_tables[self.item_table])
    for _, item in ipairs(self.item_table) do
        if type(item) == "table" then
            local spec = { item = item, enabled = isEnabled(item), checked = isChecked(item) }
            if item.header then
                spec.kind, spec.name = "header", item.text
            else
                if is_home then
                    spec.name = item.text
                    spec.value = item.value_func and item.value_func()
                else
                    spec.name, spec.value = splitText(itemText(item))
                    if not spec.value and item.sub_item_table then
                        spec.value = valueOf(item)
                    end
                end
                if item.sub_item_table or item.sub_item_table_func then
                    spec.kind = "chevron"
                elseif choices[item] then
                    spec.kind = "check"
                elseif item.checked_func then
                    spec.kind = "toggle"
                elseif item.callback or item.callback_func or item.tap_input or item.tap_input_func then
                    spec.kind = "chevron"
                else
                    spec.kind = "none"
                end
            end
            spec.h = spec.kind == "header" and HEADER_H or ROW_H
            spec.is_header = spec.kind == "header"
            spec.sig = table.concat({ spec.kind, spec.name or "", spec.value or "", tostring(spec.enabled), tostring(spec.checked) }, "\0")
            table.insert(specs, spec)
        end
    end
    return specs
end

function EinkSettings:buildRow(spec)
    local w = self.content_w
    if spec.kind == "header" then
        local label = text(spec.name, "ui_caption", Palette.ink_2, w)
        return VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = HEADER_H - dp(6) - Size.border.default - label:getSize().h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, label },
            VerticalSpan:new{ width = dp(6) },
            HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, rule(w, Palette.ink) },
        }
    end
    local fg = spec.enabled and Palette.ink or Palette.ink_3
    local right = HorizontalGroup:new{ align = "center" }
    local gap = dp(8)
    if spec.value and spec.value ~= "" then
        table.insert(right, text(spec.value, "ui_label", spec.enabled and Palette.ink_2 or Palette.ink_3, math.floor(w * 0.45)))
    end
    local function add(widget)
        if #right > 0 then table.insert(right, HorizontalSpan:new{ width = gap }) end
        table.insert(right, widget)
    end
    if spec.kind == "toggle" then
        local toggle = EinkControls.Toggle:new{ checked = spec.checked, enabled = spec.enabled }
        toggle.ges_events = {} -- the whole row toggles
        spec.toggle = toggle
        add(toggle)
    elseif spec.kind == "check" then
        local size = dp(20)
        if spec.checked then
            add(IconWidget:new{ icon = "eink/check", width = size, height = size, alpha = true, dim = not spec.enabled or nil })
        end
    elseif spec.kind == "chevron" then
        add(IconWidget:new{ icon = "eink/chev", width = dp(18), height = dp(18), alpha = true, dim = true })
    end
    local right_w = right:getSize().w
    local name_w = w - right_w - (right_w > 0 and dp(12) or 0)
    local name = text(spec.name, "ui_body", fg, name_w)
    spec.truncated = name:isTruncated()
    local inner_h = ROW_H - Size.border.default
    return Row:new{
        width = self.dimen.w, height = ROW_H,
        on_tap = spec.enabled and function() self:select(spec.item) end or nil,
        on_hold = function() self:hold(spec) end,
        VerticalGroup:new{
            HorizontalGroup:new{
                HorizontalSpan:new{ width = GUTTER },
                LeftContainer:new{ dimen = Geom:new{ w = w - right_w, h = inner_h }, name },
                CenterContainer:new{ dimen = Geom:new{ w = right_w, h = inner_h }, right },
            },
            HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, rule(w, Palette.rule) },
        },
    }
end

--- The shown list page, without widgets: its row specs, each with its screen rect, the page and the page count.
function EinkSettings:layout()
    local specs = self:rowSpecs()
    local rect = self.content_rect
    self.pages = TocDrawer.paginate(specs, rect.h)
    self.page = math.max(1, math.min(self.page, #self.pages))
    local shown = { title = self.title, page = self.page, page_count = #self.pages }
    local y = rect.y
    for _, i in ipairs(self.pages[self.page] or {}) do
        local spec = specs[i]
        spec.rect = Geom:new{ x = 0, y = y, w = self.dimen.w, h = spec.h }
        y = y + spec.h
        table.insert(shown, spec)
    end
    return shown
end

--- The rows of the shown list page and the number of pages; `self.shown` gets their specs.
function EinkSettings:buildContent()
    local shown = self:layout()
    local list = VerticalGroup:new{ align = "left" }
    for _, spec in ipairs(shown) do
        table.insert(list, self:buildRow(spec))
        if spec.toggle then
            local size = spec.toggle:getSize()
            spec.toggle_rect = Geom:new{ x = GUTTER + self.content_w - size.w,
                y = spec.rect.y + math.floor((ROW_H - Size.border.default - size.h) / 2), w = size.w, h = size.h }
        end
    end
    self.shown = shown
    return list, shown.page_count
end

--- After a change, rebuilds and refreshes what changed: the toggle of `toggled` ("fast"), other changed rows ("ui"),
-- or the whole list when its rows moved. When nothing shown changed, it keeps the page as painted: rebuilt widgets
-- only take their place (and their gesture ranges) when repainted, and a repaint always refreshes the screen.
function EinkSettings:refreshChanged(toggled)
    if self.closed then return end
    local old, new = self.shown, self:layout()
    if #old ~= #new or old.title ~= new.title or old.page ~= new.page or old.page_count ~= new.page_count then
        self:build()
        UIManager:setDirty(self, "ui", old.title ~= new.title and self.dimen or self.body_rect)
        return
    end
    local changed = {}
    for i, spec in ipairs(new) do
        if spec.sig ~= old[i].sig then
            table.insert(changed, i)
        end
    end
    if #changed == 0 then return end
    self:build()
    for _, i in ipairs(changed) do
        local spec = self.shown[i]
        if spec.item == toggled and spec.toggle_rect then
            UIManager:setDirty(self, "fast", spec.toggle_rect)
        else
            UIManager:setDirty(self, "ui", spec.rect)
        end
    end
end

--- Goes into the entries `sub_item_table` of `item` (not rebuilt yet).
function EinkSettings:push(sub_item_table, item)
    table.insert(self.item_table_stack, self.item_table)
    table.insert(self.title_stack, self.title)
    table.insert(self.page_stack, self.page)
    if item.choice then
        self.choice_tables[sub_item_table] = true
    end
    self.item_table, self.page = sub_item_table, 1
    self.title = item.row_id and item.text or (splitText(itemText(item)))
end

function EinkSettings:select(item)
    if item.tap_input or item.tap_input_func then
        self:onInput(item.tap_input or item.tap_input_func())
        return
    end
    local sub_item_table = item.sub_item_table_func and item.sub_item_table_func() or item.sub_item_table
    if sub_item_table then
        if #sub_item_table > 0 then
            self:push(sub_item_table, item)
            self:build()
            UIManager:setDirty(self, "ui", self.dimen)
        end
        return
    end
    local callback = item.callback_func and item.callback_func() or item.callback
    if callback then
        self.in_callback = true
        callback(self)
        self.in_callback = nil
        self:refreshChanged(item)
    end
end

function EinkSettings:hold(spec)
    local item = spec.item
    local hold_callback = item.hold_callback_func and item.hold_callback_func() or item.hold_callback
    if hold_callback then
        return hold_callback(self, item)
    end
    local help_text = item.help_text_func and item.help_text_func(self) or item.help_text
    if help_text or spec.truncated then
        UIManager:show(InfoMessage:new{ text = help_text or itemText(item), show_icon = help_text ~= nil })
    end
end

--- The interface font size changed (apps/settings/uifontsize, on top): rebuilt with the new faces, repainted when uncovered.
function EinkSettings:onUIFontScaleChanged()
    if not self.closed then
        self:build()
    end
end

-- TouchMenu API for menu item callbacks

function EinkSettings:updateItems()
    if not self.in_callback then -- after a callback, select() refreshes
        self:refreshChanged()
    end
end

function EinkSettings:backToUpperMenu()
    if #self.item_table_stack == 0 then
        return self:closeMenu()
    end
    self.item_table = table.remove(self.item_table_stack)
    self.title = table.remove(self.title_stack) or _("Settings")
    self.page = table.remove(self.page_stack) or 1
    self:build()
    UIManager:setDirty(self, "ui", self.dimen)
end

function EinkSettings:closeMenu(no_refresh)
    if self.closed then return end
    self.closed = true
    if no_refresh then
        UIManager:close(self)
    else
        UIManager:close(self, "ui", self.dimen)
    end
end

EinkSettings.onClose = EinkSettings.closeMenu

EinkSettings.goBack = EinkSettings.backToUpperMenu

return EinkSettings
