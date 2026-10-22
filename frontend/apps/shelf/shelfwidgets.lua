--[[--
Small redesign widgets used by the shelf home (DESIGN.md, Components).

They take plain data so they can move to ui/widget once the other redesign
screens need them:

    Chip{ text, count, selected, callback }
    Pager{ page, pages, on_change } -- page is 1-based
    TabBar{ width, tabs = { { id, icon, text } }, current, on_change }
    BottomSheet{ title, header, rows = { { text, callback, checked } } } -- shown with BottomSheet:show()
]]

local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
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
local Palette = require("ui/palette")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local function dp(n) return Screen:scaleBySize(n) end

--- A region that calls `callback` on tap and `hold_callback` on long-press.
local Tappable = InputContainer:extend{
    callback = nil,
    hold_callback = nil,
}

function Tappable:init()
    local range = function() return self.dimen end
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = range } },
    }
    if self.hold_callback then
        self.ges_events.Hold = { GestureRange:new{ ges = "hold", range = range } }
    end
end

function Tappable:onTap()
    if self.callback then self.callback() end
    return true
end

function Tappable:onHold()
    self.hold_callback()
    return true
end

--- A pill (radius = half the height) of the given outer size, with `content` centered.
local function pill(content, w, h, bordersize, color, background)
    return FrameContainer:new{
        radius = math.floor(h / 2),
        bordersize = bordersize,
        color = color or Palette.ink,
        background = background or Palette.paper,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = w - 2 * bordersize, h = h - 2 * bordersize },
            content,
        },
    }
end

local Chip = Tappable:extend{
    text = nil,
    count = nil,
    selected = false,
}

function Chip:init()
    Tappable.init(self)
    local fg = self.selected and Palette.paper or Palette.ink
    local face = Font:getFace("ui_label")
    local label = HorizontalGroup:new{
        TextWidget:new{ text = self.text, face = face, fgcolor = fg },
    }
    if self.count then
        table.insert(label, HorizontalSpan:new{ width = dp(4) })
        -- the prototype's 75% opacity count, as the nearest gray on each ground
        table.insert(label, TextWidget:new{ text = tostring(self.count), face = face,
            fgcolor = self.selected and Palette.rule or Palette.ink_2 })
    end
    local h = dp(30)
    self[1] = pill(label, label:getSize().w + 2 * dp(13), h, Size.border.default, Palette.ink,
        self.selected and Palette.ink or Palette.paper)
end

local Pager = HorizontalGroup:extend{
    page = 1,
    pages = 1,
    on_change = nil,
}

function Pager:init()
    local function button(icon, enabled, to_page)
        return Tappable:new{
            callback = enabled and function() self.on_change(to_page) end or nil,
            pill(IconWidget:new{ icon = icon, width = dp(18), height = dp(18), dim = not enabled or nil },
                dp(44), dp(32), Size.border.default, enabled and Palette.ink or Palette.rule),
        }
    end
    local count = TextWidget:new{
        text = T("%1 / %2", self.page, self.pages),
        face = Font:getFace("ui_label"),
    }
    table.insert(self, button("chevron.left", self.page > 1, self.page - 1))
    table.insert(self, HorizontalSpan:new{ width = dp(14) })
    table.insert(self, CenterContainer:new{ dimen = Geom:new{ w = math.max(dp(54), count:getSize().w), h = dp(32) }, count })
    table.insert(self, HorizontalSpan:new{ width = dp(14) })
    table.insert(self, button("chevron.right", self.page < self.pages, self.page + 1))
end

local TabBar = VerticalGroup:extend{
    width = nil,
    tabs = nil,
    current = nil,
    on_change = nil,
}
TabBar.height = dp(56)

function TabBar:init()
    local tab_w = math.floor(self.width / #self.tabs)
    local row = HorizontalGroup:new{}
    for _, tab in ipairs(self.tabs) do
        local current = tab.id == self.current
        table.insert(row, Tappable:new{
            callback = function() self.on_change(tab.id) end,
            CenterContainer:new{
                dimen = Geom:new{ w = tab_w, h = TabBar.height - Size.border.default },
                VerticalGroup:new{
                    IconWidget:new{ icon = "eink/" .. tab.icon .. (current and ".bold" or ""),
                        width = dp(24), height = dp(24), dim = not current or nil },
                    VerticalSpan:new{ width = dp(2) },
                    TextWidget:new{ text = tab.text, face = Font:getFace("ui_micro"), bold = current,
                        fgcolor = current and Palette.ink or Palette.ink_2, padding = 0 },
                },
            },
        })
    end
    table.insert(self, LineWidget:new{ background = Palette.ink, dimen = Geom:new{ w = self.width, h = Size.border.default } })
    table.insert(self, row)
end

--- Sheet frame with 16dp top corners; it bleeds past the bottom and side edges of the screen.
local SheetFrame = FrameContainer:extend{
    radius = dp(16),
    bordersize = Size.border.default,
    background = Palette.paper,
    padding = 0,
}

function SheetFrame:paintTo(bb, x, y)
    local size = self:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    local r, b = self.radius, self.bordersize
    -- rounded box for the top corners only, then a plain paper body below it
    bb:paintRoundedRect(x, y, size.w, 2 * r + b, Palette.paper, r + b)
    bb:paintBorder(x, y, size.w, 2 * r + b, b, Palette.ink, r, G_reader_settings:nilOrTrue("anti_alias_ui"))
    bb:paintRect(x, y + r, size.w, size.h - r, Palette.paper)
    self[1]:paintTo(bb, x, y + b)
end

local BottomSheet = InputContainer:extend{
    title = nil,
    header = nil, -- optional widget under the title
    rows = nil,
    close_callback = nil,
}

function BottomSheet:init()
    local screen = Screen:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h }
    local gutter = dp(24)
    local inner_w = screen.w - 2 * gutter
    local close = Tappable:new{
        callback = function() self:onClose() end,
        CenterContainer:new{ dimen = Geom:new{ w = dp(44), h = dp(44) },
            IconWidget:new{ icon = "close", width = dp(24), height = dp(24) } },
    }
    local title = TextWidget:new{ text = self.title, face = Font:getFace("ui_title"), bold = true,
        max_width = inner_w - dp(44) }
    local body = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            LeftContainer:new{ dimen = Geom:new{ w = inner_w - dp(44), h = dp(54) }, title },
            close,
        },
    }
    if self.header then
        table.insert(body, self.header)
    end
    for _, row in ipairs(self.rows) do
        local label = HorizontalGroup:new{
            TextWidget:new{ text = row.text, face = Font:getFace("ui_body"), max_width = inner_w - dp(32) },
        }
        local mark = row.checked and TextWidget:new{ text = "✓", face = Font:getFace("ui_body") }
            or IconWidget:new{ icon = "chevron.right", width = dp(18), height = dp(18), dim = true }
        table.insert(body, Tappable:new{
            callback = function()
                self:onClose()
                row.callback()
            end,
            VerticalGroup:new{
                HorizontalGroup:new{
                    LeftContainer:new{ dimen = Geom:new{ w = inner_w - mark:getSize().w, h = dp(56) }, label },
                    CenterContainer:new{ dimen = Geom:new{ w = mark:getSize().w, h = dp(56) }, mark },
                },
                LineWidget:new{ background = Palette.rule, dimen = Geom:new{ w = inner_w, h = Size.border.default } },
            },
        })
    end
    table.insert(body, VerticalSpan:new{ width = dp(20) })
    self.sheet = SheetFrame:new{
        HorizontalGroup:new{ HorizontalSpan:new{ width = gutter }, body, HorizontalSpan:new{ width = gutter } },
    }
    self[1] = BottomContainer:new{ dimen = self.dimen:copy(), self.sheet }
    self.sheet_dimen = Geom:new{ x = 0, w = screen.w, h = self.sheet:getSize().h }
    self.sheet_dimen.y = screen.h - self.sheet_dimen.h
    -- the scrim is transparent: it only catches taps outside the sheet
    self.ges_events = {
        TapScrim = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function BottomSheet:onTapScrim(_, ges)
    if not ges.pos:intersectWith(self.sheet_dimen) then
        self:onClose()
    end
    return true
end

function BottomSheet:show()
    UIManager:show(self, "ui", self.sheet_dimen)
end

function BottomSheet:onClose()
    UIManager:close(self, "ui", self.sheet_dimen)
    if self.close_callback then self.close_callback() end
    return true
end

return {
    Tappable = Tappable,
    Chip = Chip,
    Pager = Pager,
    TabBar = TabBar,
    BottomSheet = BottomSheet,
    pill = pill,
}
