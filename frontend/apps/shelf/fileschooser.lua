--[[--
The 文件 tab: FileManager's own FileChooser, drawn as the redesign's files page.

Only the rendering changes: a "Files" title with the plus-menu button, path
crumbs from the home folder, folder rows with their book counts, file rows
with a format tag, author and size, and status, a paged list and an
empty-folder hint. Item tables, sorting, selection, the file dialog and
navigation stay FileChooser's, so everything that drives file_chooser keeps
working. Long-pressing a book opens the shelf's book sheet, plus "More" for
the original file dialog.

Every change of folder or page repaints the chooser (the content area above
the tab bar) with one "ui" refresh (DESIGN.md, Refresh mapping).
]]

local BookList = require("ui/widget/booklist")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Palette = require("ui/palette")
local ShelfView = require("apps/shelf/shelfview")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("util")
local Screen = Device.screen
local T = ffiUtil.template
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext

local function dp(n) return Screen:scaleBySize(n) end

local GUTTER = dp(24)
local TITLE_H = dp(14) + dp(29) + dp(6) -- top padding + 22dp headline + bottom padding
local CRUMBS_H = dp(26)
-- both grow with the interface font size: see FilesChooser:_recalculateDimen()
local PAGER_H = dp(44)
local GAP = dp(14)

--- A list row that also takes D-pad focus (2dp ink outline).
local Row = ShelfWidgets.Tappable:extend{
    show_parent = nil,
}

function Row:paintTo(bb, x, y)
    ShelfWidgets.Tappable.paintTo(self, bb, x, y)
    if self.focused then
        bb:paintBorder(x, y, self.dimen.w, self.dimen.h, Size.border.thick, Palette.ink)
    end
end

-- rows focused before their first paint are drawn with the list
function Row:onFocus()
    self.focused = true
    if self.dimen then
        UIManager:setDirty(self.show_parent, "fast", self.dimen)
    end
    return true
end

function Row:onUnfocus()
    -- also sent to rows that never had focus
    if self.focused then
        self.focused = nil
        if self.dimen then
            UIManager:setDirty(self.show_parent, "fast", self.dimen)
        end
    end
    return true
end

local FilesChooser = FileChooser:extend{}

-- The crumbs replace the "⬆ ../" row.
function FilesChooser:genItemTable(dirs, files, path)
    local item_table = FileChooser.genItemTable(self, dirs, files, path)
    if item_table[1] and item_table[1].is_go_up then
        table.remove(item_table, 1)
    end
    return item_table
end

-- Without the "../" row a folder can list nothing: Menu would then look up item 0 for the focused path.
function FilesChooser:switchItemTable(new_title, new_item_table, itemnumber, itemmatch, new_subtitle)
    if new_item_table and #new_item_table == 0 then
        itemmatch = nil
    end
    return FileChooser.switchItemTable(self, new_title, new_item_table, itemnumber, itemmatch, new_subtitle)
end

-- Folders keep the counts upstream already lists for its mandatory text, instead of that text.
-- Files keep theirs: FileSearcher lists its results with our getListItem.
function FilesChooser:getMenuItemMandatory(item, collate)
    if collate then
        return FileChooser.getMenuItemMandatory(self, item, collate)
    end
    local sub_dirs, dir_files = self:getList(item.path)
    item.n_dirs, item.n_files = #sub_dirs, #dir_files
end

local function homeFolder()
    local home = filemanagerutil.getHomeFolder()
    return ffiUtil.realpath(home) or home
end

-- With the default setting Back goes up while there is a folder above (the crumbs replace "../"),
-- and only exits (or prompts) at home or "/".
function FilesChooser:onBack()
    if G_reader_settings:readSetting("back_in_filemanager", "default") == "default"
            and self.path ~= "/" and self.path ~= homeFolder() then
        self:onFolderUp()
        return true
    end
    return FileChooser.onBack(self)
end

function FilesChooser:_recalculateDimen()
    if not self.row_h then
        local probe = TextWidget:new{ text = "A", face = Font:getFace("ui_body") }:getSize().h
            + dp(2) + TextWidget:new{ text = "A", face = Font:getFace("ui_caption") }:getSize().h
        self.row_h = math.max(dp(56), probe + 2 * dp(8) + Size.border.default)
        -- the title (after its 10dp top span) and the crumbs (over their underline), at the interface font size
        local title_probe = TextWidget:new{ text = "A", face = Font:getFace("ui_headline") }:getSize().h
        local crumb_probe = TextWidget:new{ text = "A", face = Font:getFace("ui_caption") }:getSize().h
        self.title_h = math.max(TITLE_H, dp(14) - dp(4) + title_probe)
        self.crumbs_h = math.max(CRUMBS_H, crumb_probe + Size.border.default)
    end
    self.list_h = self.dimen.h - self.title_h - self.crumbs_h - PAGER_H
    self.perpage = math.max(1, math.floor(self.list_h / self.row_h))
    self.page_num = self:getPageNumber(#self.item_table)
    if self.page > self.page_num then
        self.page = self.page_num
    end
end

function FilesChooser:updateItems(select_number)
    self:_recalculateDimen()
    self.layout = {}
    local list = VerticalGroup:new{ align = "left" }
    local first = (self.page - 1) * self.perpage
    local focused -- the item Show folder asked for
    for i = first + 1, math.min(first + self.perpage, #self.item_table) do
        local item = self.item_table[i]
        item.idx = i
        if i == self.itemnumber then
            select_number, focused = i - first, true
        end
        local row = self:buildRow(item)
        table.insert(list, row)
        table.insert(self.layout, { row })
    end
    self.itemnumber = nil
    if #self.item_table == 0 then
        list = self:buildEmpty()
    end
    self.title_row = WidgetContainer:new{ dimen = Geom:new{ w = self.dimen.w, h = self.title_h }, self:buildTitle() }
    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Palette.paper,
        VerticalGroup:new{
            align = "left",
            self.title_row,
            self:buildCrumbs(),
            TopContainer:new{ dimen = Geom:new{ w = self.dimen.w, h = self.list_h }, list },
            self:buildPager(),
        },
    }
    if (focused or Device:hasDPad()) and #self.layout > 0 then
        local y = math.min(select_number or 1, #self.layout)
        self:moveFocusTo(1, y, FocusManager.FOCUS_ONLY_ON_NT)
        if focused then
            -- Show folder marks its book. Not with FORCED_FOCUS: that adds a "fast" refresh of the whole
            -- screen, while the mark is drawn with the list below.
            self.layout[y][1].focused = true
        end
    end
    self.path_items[self.path] = first + (select_number or 1)
    UIManager:setDirty(self.show_parent, "ui", self.dimen)
end

--- Redraws the title row only (the plus button turns into a check in select mode).
function FilesChooser:updateTitle()
    if not self.title_row then return end
    self.title_row[1] = self:buildTitle()
    UIManager:setDirty(self.show_parent, "ui", Geom:new{ x = self.dimen.x, y = self.dimen.y, w = self.dimen.w, h = self.title_h })
end

function FilesChooser:buildTitle()
    local plus = ShelfWidgets.Tappable:new{
        callback = function() self.ui:onShowPlusMenu() end,
        CenterContainer:new{ dimen = Geom:new{ w = dp(44), h = dp(44) },
            IconWidget:new{ icon = self.ui.selected_files and "eink/check" or "eink/more", width = dp(24), height = dp(24) } },
    }
    local title_w = self.dimen.w - 2 * GUTTER - dp(44) + dp(10) -- the icon's own padding sits in the gutter
    return HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = GUTTER },
        LeftContainer:new{
            dimen = Geom:new{ w = title_w, h = self.title_h },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = dp(14) - dp(4) },
                TextWidget:new{ text = _("Files"), face = Font:getFace("ui_headline"), max_width = title_w },
            },
        },
        plus,
    }
end

--- Returns the crumbs of `path`: { text, path } from the home folder, or from "/" outside it.
function FilesChooser:getCrumbs(path)
    local home = homeFolder()
    local base, rest
    if path == home or util.stringStartsWith(path, home == "/" and "/" or home .. "/") then
        base, rest = home, path:sub(#home + 1)
    else
        base, rest = "/", path
    end
    local crumbs = { { text = base == "/" and "/" or ffiUtil.basename(base), path = base } }
    local acc = base ~= "/" and base or ""
    for name in rest:gmatch("[^/]+") do
        acc = acc .. "/" .. name
        table.insert(crumbs, { text = name, path = acc })
    end
    return crumbs
end

function FilesChooser:buildCrumbs()
    local face = Font:getFace("ui_caption")
    local avail = self.dimen.w - 2 * GUTTER
    local crumbs = self:getCrumbs(self.path)
    local function widgets(from)
        local group = HorizontalGroup:new{ align = "center" }
        if from > 1 then
            table.insert(group, TextWidget:new{ text = "… / ", face = face, fgcolor = Palette.ink_2 })
        end
        for i = from, #crumbs do
            local crumb = crumbs[i]
            local text = TextWidget:new{ text = crumb.text, face = face, fgcolor = Palette.ink_2, max_width = math.floor(avail / 2) }
            if i < #crumbs then
                local w = text:getSize().w
                table.insert(group, ShelfWidgets.Tappable:new{
                    callback = function() self:changeToPath(crumb.path) end,
                    CenterContainer:new{
                        dimen = Geom:new{ w = w, h = self.crumbs_h },
                        VerticalGroup:new{
                            text,
                            LineWidget:new{ background = Palette.ink_2, dimen = Geom:new{ w = w, h = Size.border.default } },
                        },
                    },
                })
                table.insert(group, TextWidget:new{ text = " / ", face = face, fgcolor = Palette.ink_2 })
            else
                table.insert(group, text)
            end
        end
        return group
    end
    -- too wide: drop leading crumbs, keeping at least the current folder
    local from = 1
    local group = widgets(from)
    while group:getSize().w > avail and from < #crumbs do
        from = from + 1
        group = widgets(from)
    end
    return LeftContainer:new{
        dimen = Geom:new{ w = self.dimen.w, h = self.crumbs_h },
        HorizontalGroup:new{ HorizontalSpan:new{ width = GUTTER }, group },
    }
end

local function folderSubtitle(item)
    local dirs, files = item.n_dirs or 0, item.n_files or 0
    local books = files > 0 and T(N_("1 book", "%1 books", files), files)
    local folders = dirs > 0 and T(N_("1 folder", "%1 folders", dirs), dirs)
    if books and folders then
        return T("%1 · %2", folders, books)
    end
    return books or folders or C_("Folder", "Empty")
end

--- The shelf book (as ShelfView draws it) for a file row: metadata from CoverBrowser's cache when loaded.
function FilesChooser:getBook(item)
    local bim = package.loaded["bookinfomanager"]
    local info = bim and bim:getBookInfo(item.path, false)
    local use_meta = info and not info.ignore_meta
    local book_info = BookList.getBookInfo(item.path)
    return {
        file = item.path,
        title = use_meta and info.title or util.splitFileNameSuffix(ffiUtil.basename(item.path)),
        authors = use_meta and info.authors and info.authors:gsub("\n", ", ") or nil,
        has_cover = info and info.has_cover and not info.ignore_cover and true or false,
        status = book_info.been_opened and book_info.status or "new",
        percent = book_info.percent_finished,
    }
end

function FilesChooser:buildRow(item)
    local inner_w = self.dimen.w - 2 * GUTTER
    local fg = item.dim and Palette.ink_3 or Palette.ink
    local lead, trail, sub
    if item.is_file then
        local suffix = util.getFileNameSuffix(item.text):upper()
        lead = FrameContainer:new{
            bordersize = Size.border.default,
            color = fg,
            radius = dp(4),
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = dp(44) - 2 * Size.border.default, h = dp(32) - 2 * Size.border.default },
                TextWidget:new{ text = suffix, face = Font:getFace("ui_micro", 10), bold = true, fgcolor = fg,
                    max_width = dp(40), padding = 0 },
            },
        }
        local size = util.getFriendlySize(item.attr and item.attr.size or 0)
        if DocumentRegistry:hasProvider(item.path) then
            local book = self:getBook(item)
            sub = book.authors and T("%1 · %2", book.authors, size) or size
            trail = TextWidget:new{ text = ShelfView.statusText(book), face = Font:getFace("ui_label"), fgcolor = Palette.ink_2 }
        else
            sub = size
        end
    else
        lead = IconWidget:new{ icon = "eink/folder", width = dp(24), height = dp(24) }
        sub = folderSubtitle(item)
        trail = IconWidget:new{ icon = "eink/chev", width = dp(18), height = dp(18), dim = true }
    end
    local main_w = inner_w - lead:getSize().w - GAP - (trail and trail:getSize().w + GAP or 0)
    local name = item.is_file and ffiUtil.basename(item.path) or item.text:gsub("/$", "")
    local line = HorizontalGroup:new{
        align = "center",
        lead,
        HorizontalSpan:new{ width = GAP },
        LeftContainer:new{
            dimen = Geom:new{ w = main_w, h = self.row_h - Size.border.default },
            VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = name, face = Font:getFace("ui_body"), fgcolor = fg, max_width = main_w },
                VerticalSpan:new{ width = dp(2) },
                TextWidget:new{ text = sub, face = Font:getFace("ui_caption"), fgcolor = Palette.ink_2, max_width = main_w },
            },
        },
    }
    if trail then
        table.insert(line, HorizontalSpan:new{ width = GAP })
        table.insert(line, trail)
    end
    return Row:new{
        show_parent = self.show_parent,
        callback = function() self:onMenuSelect(item) end,
        hold_callback = function() self:onRowHold(item) end,
        HorizontalGroup:new{
            HorizontalSpan:new{ width = GUTTER },
            VerticalGroup:new{
                align = "left",
                line,
                LineWidget:new{ background = Palette.rule, dimen = Geom:new{ w = inner_w, h = Size.border.default } },
            },
            HorizontalSpan:new{ width = GUTTER },
        },
    }
end

function FilesChooser:buildEmpty()
    local w = self.dimen.w - 2 * GUTTER - 2 * dp(8)
    return CenterContainer:new{
        dimen = Geom:new{ w = self.dimen.w, h = dp(40) + dp(100) },
        VerticalGroup:new{
            TextWidget:new{ text = _("This folder is empty"), face = Font:getFace("ui_body"), bold = true },
            VerticalSpan:new{ width = dp(4) },
            TextBoxWidget:new{
                text = _("Put books here over USB or with Calibre wireless connection."),
                face = Font:getFace("ui_label_large"),
                fgcolor = Palette.ink_2,
                alignment = "center",
                width = w,
            },
        },
    }
end

function FilesChooser:buildPager()
    local pager = self.page_num > 1 and ShelfWidgets.Pager:new{
        page = self.page,
        pages = self.page_num,
        on_change = function(page) self:onGotoPage(page) end,
    } or VerticalSpan:new{ width = 0 }
    return CenterContainer:new{ dimen = Geom:new{ w = self.dimen.w, h = PAGER_H }, pager }
end

function FilesChooser:onRowHold(item)
    if item.is_file and not self.ui.selected_files and self.ui.shelf_view and DocumentRegistry:hasProvider(item.path) then
        self:showBookSheet(item)
    else
        self:onMenuHold(item)
    end
end

--- The shelf's long-press sheet, refreshing this list instead of the shelf, plus "More" for the file dialog.
function FilesChooser:showBookSheet(item)
    local chooser = self
    local proxy = setmetatable({
        update = function() chooser:refreshPath() end,
        getBookActions = function(view, book)
            local rows = ShelfView.getBookActions(view, book)
            table.insert(rows, { text = _("More"), callback = function() chooser:showFileDialog(item) end })
            return rows
        end,
    }, { __index = self.ui.shelf_view })
    ShelfView.showBookSheet(proxy, self:getBook(item))
end

return FilesChooser
