--[[--
Small redesign widgets used by the shelf home (DESIGN.md, Components).

They take plain data so they can move to ui/widget once the other redesign
screens need them:

    Chip{ text, selected, callback }
    TabBar{ tabs = { { id, icon } }, current, height, on_change } -- the tab icons of the bottom band
    ActionBar{ items = { { icon, callback } }, enabled, height } -- actions in their place (selection mode)
    BottomSheet{ title, header, rows = { { text, callback, checked } } } -- shown with BottomSheet:show()

and the cover grids of 书架 and 书源:

    shelfGrid(width, grid_h) -- 书架: { cols, rows, cover_w, cover_h, gutter, col_gap, title_gap, cell_h, row_gap, peek }
    gridGeometry(width, grid_h) -- 书源: { cols, rows, cover_w, cover_h, col_gap }
    cover(book, w, h, image_bb, keep_image) -- the image cropped to fill (freed with the widget unless keep_image),
                                            -- or the typographic cover from book.title/authors
    finishedBadge() -- the 读完 tag at a finished book's top right corner
    SelectableCover{ selection } -- a cover with selection mode's ring, check and frame
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
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local Screen = Device.screen
local _ = require("gettext")
local C_ = _.pgettext

local function dp(n) return Screen:scaleBySize(n) end

local GUTTER = dp(24)
local TEXT_H = dp(60) -- title (2 lines) and status under each cover
local ROW_GAP = dp(18)
local COL_GAP = dp(20) -- minimum; columns are spread with space-between

-- Columns follow the physical panel width: 6" -> 3, 7" -> 4, 10.3" -> 5.
local function columnCount()
    local inches = Screen:getWidth() / Screen:getDPI()
    return inches < 3.9 and 3 or inches < 5.2 and 4 or 5
end

-- 书架, after the Leaf5 reference (DESIGN.md, Layout): 22dp gutters and gaps, covers about 123 × 178dp,
-- one bold title line whose glyphs start 12dp under the cover, and 24dp from them to the next row.
local SHELF_GUTTER = dp(22)
local SHELF_COL_GAP = dp(22)
local COVER_RATIO = 1.45
local TITLE_GAP = dp(9) -- to the title's line box, whose CJK glyphs start about 3dp lower
local SHELF_ROW_GAP = dp(20)
local MIN_PEEK = dp(40)

--- 书架's cover grid for a region `width` wide and `grid_h` tall. `rows` full rows fit; when at least
-- MIN_PEEK is left under them, `peek` is that height: the next page's first row shows there, cut off.
local function shelfGrid(width, grid_h)
    local cols = columnCount()
    local inner_w = width - 2 * SHELF_GUTTER
    local cover_w = math.floor((inner_w - SHELF_COL_GAP * (cols - 1)) / cols)
    local cover_h = math.floor(cover_w * COVER_RATIO + 0.5)
    local line_h = math.ceil(Font:getFace("ui_label").ftsize:getHeightAndAscender())
    local cell_h = cover_h + TITLE_GAP + line_h
    local pitch = cell_h + SHELF_ROW_GAP
    local rows = math.max(1, math.floor((grid_h + SHELF_ROW_GAP) / pitch))
    local left = grid_h - rows * pitch
    return {
        cols = cols,
        rows = rows,
        cover_w = cover_w,
        cover_h = cover_h,
        col_gap = cols > 1 and math.floor((inner_w - cols * cover_w) / (cols - 1)) or 0,
        gutter = SHELF_GUTTER,
        title_gap = TITLE_GAP,
        cell_h = cell_h,
        row_gap = SHELF_ROW_GAP,
        peek = left >= MIN_PEEK and left or nil,
    }
end

--- 书源's cover grid for a region `width` wide (24dp gutters) and `grid_h` tall.
local function gridGeometry(width, grid_h)
    local cols = columnCount()
    local inner_w = width - 2 * GUTTER
    local cover_w = math.floor((inner_w - COL_GAP * (cols - 1)) / cols)
    local rows = math.floor((grid_h + ROW_GAP) / (math.floor(cover_w * 4 / 3) + TEXT_H + ROW_GAP))
    -- Shrink covers a little to fit one more row rather than leave the bottom empty;
    -- below two rows, accept down to 3/4 of the column width (the prototype's rule).
    local shrunk = math.floor(((grid_h + ROW_GAP) / (rows + 1) - TEXT_H - ROW_GAP) * 3 / 4)
    if shrunk >= cover_w * (rows < 2 and 0.75 or 0.85) then
        rows, cover_w = rows + 1, shrunk
    end
    rows = math.max(rows, 1)
    return {
        cols = cols,
        rows = rows,
        cover_w = cover_w,
        cover_h = math.floor(cover_w * 4 / 3),
        col_gap = cols > 1 and math.floor((inner_w - cols * cover_w) / (cols - 1)) or 0,
    }
end

--- A `w` × `h` cover: `image_bb` cropped to fill, or the typographic "frame" cover (DESIGN.md, Typographic cover).
local function cover(book, w, h, image_bb, keep_image)
    local border = Size.border.default
    if image_bb then
        local bb = image_bb
        return FrameContainer:new{
            bordersize = border,
            color = Palette.rule,
            padding = 0,
            -- fill the 3:4 box and crop the overflow, centered
            ImageWidget:new{
                image = bb,
                width = w - 2 * border,
                height = h - 2 * border,
                scale_factor = math.max((w - 2 * border) / bb:getWidth(), (h - 2 * border) / bb:getHeight()),
                image_disposable = not keep_image,
            },
        }
    end
    local inset = math.floor(w * 0.07)
    local frame_w, frame_h = w - 2 * inset, h - 2 * inset
    local px_per_dp = dp(100) / 100
    local title_size = math.max(9, math.floor(w * 0.12 / px_per_dp))
    local author_size = math.max(8, math.floor(w * 0.065 / px_per_dp))
    local text_w = frame_w - 2 * dp(6)
    -- the cover's own lettering: the roles' font files, which the interface font size leaves alone
    local content = VerticalGroup:new{
        TextBoxWidget:new{
            text = book.title,
            face = Font:getFace(Font.fontmap.ui_headword, title_size),
            bold = true,
            alignment = "center",
            width = text_w,
            bgcolor = Palette.cover_stock,
            height = math.floor(frame_h * 0.6),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
    }
    if book.authors then
        table.insert(content, VerticalSpan:new{ width = math.floor(w * 0.08) })
        table.insert(content, TextWidget:new{
            text = book.authors,
            face = Font:getFace(Font.fontmap.ui_micro, author_size),
            max_width = text_w,
        })
    end
    return FrameContainer:new{
        bordersize = border,
        color = Palette.rule,
        background = Palette.cover_stock,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = w - 2 * border, h = h - 2 * border },
            FrameContainer:new{
                bordersize = Size.border.button,
                color = Palette.ink,
                padding = 0,
                CenterContainer:new{
                    dimen = Geom:new{ w = frame_w - 2 * border - 2 * Size.border.button, h = frame_h - 2 * border - 2 * Size.border.button },
                    content,
                },
            },
        },
    }
end

--- The 读完 tag of a finished book, set in the cover's top right corner: about 31 × 17dp of paper with a 1dp gray
-- frame and 12dp ink text (the reference's glyphs are smaller than DESIGN.md's 13dp).
local function finishedBadge()
    local face = Font:getFace("ui_caption")
    local text = C_("Status of single book", "Finished")
    local label
    local chars = util.splitToChars(text)
    if #chars == 2 and util.isCJKChar(chars[1]) and util.isCJKChar(chars[2]) then
        -- 读 完, spaced as in the reference
        label = HorizontalGroup:new{
            TextWidget:new{ text = chars[1], face = face, fgcolor = Palette.ink, padding = 0 },
            HorizontalSpan:new{ width = dp(2) },
            TextWidget:new{ text = chars[2], face = face, fgcolor = Palette.ink, padding = 0 },
        }
    else
        label = TextWidget:new{ text = text, face = face, fgcolor = Palette.ink, padding = 0 }
    end
    local border = Size.border.default
    local size = label:getSize()
    return FrameContainer:new{
        bordersize = border,
        color = Palette.rule,
        background = Palette.paper,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = math.max(dp(29), size.w + 2 * dp(2)), h = dp(15) },
            label,
        },
    }
end

-- Selection mode, after the Leaf5 reference (15-supplement/04-two-books-selected.png): a selected cover is framed in
-- ink just outside its edges, and every cover has a 25dp ring centered 16.5dp in from its lower right corner.
local SELECTED_FRAME = dp(4.3)
local RING = dp(25)
local RING_INSET = dp(16.5)
local rings = {}

--- `cover` in selection mode. `selection()` is read at each paint: nil outside selection mode (the cover alone),
-- false for a cover not selected (an empty ring), true for a selected one (a check in the ring, and the frame).
-- So a change of selection only needs a repaint of `getSelectionRect()`.
local SelectableCover = WidgetContainer:extend{
    selection = nil,
}

function SelectableCover:init()
    self.dimen = Geom:new{ w = self[1]:getSize().w, h = self[1]:getSize().h }
end

function SelectableCover:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self[1]:paintTo(bb, x, y)
    local selected = self.selection()
    if selected == nil then return end
    local w, h = self.dimen.w, self.dimen.h
    if selected then
        bb:paintBorder(x - SELECTED_FRAME, y - SELECTED_FRAME, w + 2 * SELECTED_FRAME, h + 2 * SELECTED_FRAME,
            SELECTED_FRAME, Palette.ink)
    end
    if not rings[selected] then
        rings[selected] = IconWidget:new{ icon = selected and "eink/ring.check" or "eink/ring",
            width = RING, height = RING, alpha = true }
    end
    local half = math.floor(RING / 2)
    rings[selected]:paintTo(bb, x + w - RING_INSET - half, y + h - RING_INSET - half)
end

--- The screen rect that a change of selection repaints: the cover and its frame, where it was last painted.
function SelectableCover:getSelectionRect()
    local d = self.dimen
    return Geom:new{ x = d.x - SELECTED_FRAME, y = d.y - SELECTED_FRAME, w = d.w + 2 * SELECTED_FRAME,
        h = d.h + 2 * SELECTED_FRAME }
end

--- A region that calls `callback` on tap and `hold_callback` on long-press. With `clip` (a screen rect),
-- it only takes the gestures inside it, as when it is painted partly under something else.
local Tappable = InputContainer:extend{
    callback = nil,
    hold_callback = nil,
    clip = nil,
}

function Tappable:init()
    local range = function()
        if self.clip and self.dimen then return self.dimen:intersect(self.clip) end
        return self.dimen
    end
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = range } },
    }
    if self.hold_callback then
        self.ges_events.Hold = { GestureRange:new{ ges = "hold", range = range } }
    end
end

-- An outer Tappable that matches hands its Tap/Hold down to its children first:
-- one nested inside (a row's ⋯) answers only when the finger is in its own range (which may be grown).
local function missed(self, ges, name)
    if not (ges and ges.pos) then return false end
    for _, range in ipairs(self.ges_events[name] or {}) do
        if range:match(ges) then return false end
    end
    return true
end

function Tappable:onTap(_, ges)
    if missed(self, ges, "Tap") then return end
    if self.callback then self.callback() end
    return true
end

function Tappable:onHold(_, ges)
    if missed(self, ges, "Hold") or not self.hold_callback then return end
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
    selected = false,
}

function Chip:init()
    Tappable.init(self)
    local label = TextWidget:new{ text = self.text, face = Font:getFace("ui_label"),
        fgcolor = self.selected and Palette.paper or Palette.ink }
    local h = dp(30)
    self[1] = pill(label, label:getSize().w + 2 * dp(13), h, Size.border.default, Palette.ink,
        self.selected and Palette.ink or Palette.paper)
end

--- The tab icons at the left of the bottom band (DESIGN.md, Tab bar): 28dp icons with no labels, 91dp apart
-- from a 32dp inset, each tappable over its 91dp cell and the band's height. The current tab's icon is the
-- filled "eink/<icon>.bold", the others "eink/<icon>".
local TabBar = HorizontalGroup:extend{
    tabs = nil,
    current = nil,
    height = nil,
    on_change = nil,
}
TabBar.cell_w = dp(91)

function TabBar:init()
    local size = dp(28)
    for _, tab in ipairs(self.tabs) do
        table.insert(self, Tappable:new{
            callback = function() self.on_change(tab.id) end,
            CenterContainer:new{
                dimen = Geom:new{ w = TabBar.cell_w, h = self.height },
                IconWidget:new{ icon = "eink/" .. tab.icon .. (tab.id == self.current and ".bold" or ""),
                    width = size, height = size, alpha = true },
            },
        })
    end
end

--- Actions in the tab icons' place, laid out as TabBar: selection mode's 移出书架 and 标记为. While not `enabled`
-- (nothing selected), they are gray as in the reference and take no taps. `enabled` is read when built: a change
-- needs a new ActionBar (ShelfFileManager keeps it in the band's state for that).
local ActionBar = HorizontalGroup:extend{
    items = nil, -- { { icon, callback } }
    enabled = true,
    height = nil,
}

function ActionBar:init()
    local size = dp(28)
    for _, item in ipairs(self.items) do
        table.insert(self, Tappable:new{
            callback = function()
                if self.enabled then item.callback() end
            end,
            CenterContainer:new{
                dimen = Geom:new{ w = TabBar.cell_w, h = self.height },
                IconWidget:new{ icon = item.icon, width = size, height = size, alpha = true,
                    dim = not self.enabled or nil },
            },
        })
    end
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
    TabBar = TabBar,
    ActionBar = ActionBar,
    BottomSheet = BottomSheet,
    SelectableCover = SelectableCover,
    pill = pill,
    shelfGrid = shelfGrid,
    gridGeometry = gridGeometry,
    cover = cover,
    finishedBadge = finishedBadge,
    TEXT_H = TEXT_H,
    ROW_GAP = ROW_GAP,
}
