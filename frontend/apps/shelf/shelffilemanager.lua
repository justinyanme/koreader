--[[--
The redesigned home: FileManager with the bottom band of WeChat Read's shelf: the
tab icons 书源 / 书架 / 我 at the left and the page capsule at the right, which
turns the shelf's pages (it is gray on the other tabs, which page themselves).

Requiring this module registers it in apps/replacements. It keeps the
original FileManager layout as 文件, so modules and plugins that rely on
file_chooser keep working, and the original menu stays reachable. 文件 has no
tab: 导入 and 我 open it (openFiles), and so does anything that moves
file_chooser to a folder (Show folder, search results, shortcuts, plugins).
While it shows, the band's back arrow (and Back at the home folder) returns to
where it was opened from; input meant for the file browser (swipe, Back, Home,
page keys) only reaches it then.

Each tab's `open(fm)` returns the widget for the content area, or nil when the
tab opens something on top instead (书源, a full-screen page over the shelf).
]]

local BD = require("ui/bidi")
local Device = require("device")
local EinkControls = require("ui/widget/einkcontrols")
local Event = require("ui/event")
local FileChooser = require("ui/widget/filechooser")
local FileManager = require("apps/filemanager/filemanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local MeView = require("apps/shelf/meview")
local Palette = require("ui/palette")
local Replacements = require("apps/replacements")
local ShelfView = require("apps/shelf/shelfview")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")

local ShelfFileManager = FileManager:extend{
    current_tab = "shelf", -- a tab's id, or "files" while 文件 shows
    file_chooser_class = require("apps/shelf/fileschooser"), -- 文件
}

ShelfFileManager.tabs = {
    -- only with the OPDS plugin, which holds the sources
    { id = "sources", icon = "compass", available = function(fm) return fm.opds ~= nil end, open = function(fm)
        fm.opds:onShowOPDSCatalog()
    end },
    { id = "shelf", icon = "shelf", open = function(fm)
        fm.shelf_view:reload()
        fm.shelf_view:update()
        return fm.shelf_view
    end },
    { id = "me", icon = "user", open = function(fm)
        fm.me_view:reset()
        return fm.me_view
    end },
}

function ShelfFileManager:init()
    -- Land on 文件 when asked to show a folder (a folder target, or "Show folder" from the reader,
    -- which sets the one-shot FileManager.open_on_files); otherwise on 书架.
    if FileManager.open_on_files
            or (self.focused_file and lfs.attributes(self.focused_file, "mode") == "directory") then
        self.current_tab = "files"
    end
    FileManager.open_on_files = nil
    FileManager.init(self)
    self.initialized = true
end

function ShelfFileManager:setupLayout()
    local tabbar_h = EinkControls.BottomBar.height
    self.content_dimen = Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h - tabbar_h }
    self.tabbar_dimen = Geom:new{ x = 0, y = self.content_dimen.h, w = self.dimen.w, h = tabbar_h }
    self.file_chooser_height = self.content_dimen.h
    FileManager.setupLayout(self)
    self.files_ui = self[1]

    if self.shelf_view then
        self.shelf_view:stop()
        self.shelf_view:free()
    end
    self.shelf_view = ShelfView:new{ ui = self, width = self.content_dimen.w, height = self.content_dimen.h }
    -- a rebuild (rotation) keeps the 我的 subpage and its list page
    local me_state = self.me_view and self.me_view:getState()
    if self.me_view then self.me_view:free() end
    self.me_view = MeView:new{ ui = self, width = self.content_dimen.w, height = self.content_dimen.h }
    if self.current_tab == "me" then self.me_view:reset(me_state) end
    local current = { files = self.files_ui, me = self.me_view }
    self.content = WidgetContainer:new{
        dimen = self.content_dimen:copy(),
        current[self.current_tab] or self.shelf_view,
    }
    self.layout_group = VerticalGroup:new{ self.content, self:buildBottomBar() }
    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Palette.paper,
        self.layout_group,
    }
    if Device:hasKeys() then
        self.key_events.Back = { { Device.input.group.Back } }
        self.key_events.ShelfNextPage = { { Device.input.group.PgFwd } }
        self.key_events.ShelfPrevPage = { { Device.input.group.PgBack } }
    end
end

-- What the bottom band shows: the current tab (or 文件), and the page of 书架 or 文件 (one page, gray, on 我).
function ShelfFileManager:bottomBarState()
    local page, pages = 1, 1
    if self.current_tab == "shelf" then
        page, pages = self.shelf_view.page, self.shelf_view.pages
    elseif self.current_tab == "files" then
        page, pages = self.file_chooser.page, self.file_chooser.page_num or 1
    end
    return table.concat({ self.current_tab, page, pages }, "/"), page, pages
end

--- The bottom band: the tab icons (the back arrow on 文件), and the capsule turning the pages of 书架 or 文件.
-- Its paper ground covers the cut-off row of covers above it.
function ShelfFileManager:buildBottomBar()
    local state, page, pages = self:bottomBarState()
    self.bottom_bar_state = state
    local tab_bar
    if self.current_tab ~= "files" then
        local tabs = {}
        for _, tab in ipairs(self.tabs) do
            if not tab.available or tab.available(self) then
                table.insert(tabs, tab)
            end
        end
        tab_bar = ShelfWidgets.TabBar:new{
            tabs = tabs,
            current = self.current_tab,
            height = EinkControls.BottomBar.height - Size.border.default,
            on_change = function(id) self:switchTab(id) end,
        }
    end
    return FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Palette.paper,
        EinkControls.BottomBar:new{
            width = self.dimen.w,
            page = page,
            pages = pages,
            on_change = function(p) -- only enabled on 书架 and 文件
                if self.current_tab == "files" then
                    self.file_chooser:onGotoPage(p)
                else
                    self.shelf_view:setPage(p)
                end
            end,
            left = tab_bar,
            on_back = function() self:closeFiles() end,
        },
    }
end

--- Rebuilds the bottom band if the current tab or its page changed, and says so; the caller repaints it.
function ShelfFileManager:updateBottomBar()
    -- 文件 lists its first folder while FileManager lays itself out, before there is a band
    if not self.layout_group or self:bottomBarState() == self.bottom_bar_state then return false end
    self.layout_group[2]:free()
    self.layout_group[2] = self:buildBottomBar()
    return true
end

-- Puts `widget` in the content area as `id` ("files" or a tab's), repainting the content and the band.
function ShelfFileManager:showContent(id, widget)
    self.current_tab = id
    self.content[1] = widget
    self:updateBottomBar()
    UIManager:setDirty(self, "ui", self.content_dimen)
    UIManager:setDirty(self, "ui", self.tabbar_dimen)
end

function ShelfFileManager:switchTab(id)
    if id == self.current_tab then return end
    for _, tab in ipairs(self.tabs) do
        if tab.id == id then
            local widget = tab.open(self)
            if widget then
                self:showContent(id, widget)
            end
            return
        end
    end
end

--- Shows 文件, from 导入, 我 or a folder change. Leaving it returns to the tab it was opened from (书架 when the
-- home opened on it). With `on_back` (导入, which opens over 书架) it calls that instead to show its page again:
-- 书架 goes back as it was, not rebuilt under the page, which brings it up to date when it closes.
function ShelfFileManager:openFiles(on_back)
    if self.current_tab == "files" then return end
    self.files_from, self.files_on_back = self.current_tab, on_back
    self:showContent("files", self.files_ui)
end

--- The back arrow on 文件, and Back at its home folder.
function ShelfFileManager:closeFiles()
    if self.current_tab ~= "files" then return end
    local from, on_back = self.files_from, self.files_on_back
    self.files_from, self.files_on_back = nil, nil
    if on_back then
        self:showContent("shelf", self.shelf_view)
        on_back()
    else
        self:switchTab(from or "shelf")
    end
end

-- file_chooser moved to a folder: show it (skipping the initial PathChanged sent by init)
function ShelfFileManager:onPathChanged(path)
    FileManager.onPathChanged(self, path)
    if self.initialized then
        self:openFiles()
    end
end

-- the 文件 title's plus button turns into a check while selecting
function ShelfFileManager:onToggleSelectMode(...)
    FileManager.onToggleSelectMode(self, ...)
    self.file_chooser:updateTitle()
    return true
end

function ShelfFileManager:onSwipeFM(ges)
    if self.current_tab == "files" then
        return FileManager.onSwipeFM(self, ges)
    elseif self.current_tab == "me" then
        return self.me_view:swipe(ges)
    end
    -- as on full-screen pages: west or north to the next page, east or south to the previous one;
    -- diagonal swipes go on (a long one takes a screenshot)
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" or direction == "north" then
        self.shelf_view:turnPage(1)
    elseif direction == "east" or direction == "south" then
        self.shelf_view:turnPage(-1)
    else
        return false
    end
    return true
end

-- Page keys turn the shelf's pages; on 文件 the file browser takes them first, as before.
function ShelfFileManager:onShelfNextPage()
    if self.current_tab ~= "shelf" then return false end
    self.shelf_view:turnPage(1)
    return true
end

function ShelfFileManager:onShelfPrevPage()
    if self.current_tab ~= "shelf" then return false end
    self.shelf_view:turnPage(-1)
    return true
end

--- 设置 → 书架 changed the order (ShelfView.sortMenuItem); the settings page is still on top.
function ShelfFileManager:onShelfSortChanged(sort)
    self.shelf_view:setSort(sort)
end

-- Only reached on 书架 (file_chooser handles Back itself while 文件 shows it).
-- "Parent folder" means nothing here, so Back exits or prompts as by default.
function ShelfFileManager:onBack()
    if G_reader_settings:readSetting("back_in_filemanager", "default") == "default" then
        return FileChooser.onBack(self.file_chooser) -- not 文件's own Back, which goes up a folder
    end
    return true
end

function ShelfFileManager:onHome()
    if self.current_tab == "files" then
        return FileManager.onHome(self)
    end
    return true
end

function ShelfFileManager:onRefresh()
    FileManager.onRefresh(self)
    self.shelf_view:reload(true)
    self.shelf_view:update(self.current_tab == "shelf" and "header" or nil)
    self.me_view:invalidate()
    if self.current_tab == "me" then
        self.me_view:reset(self.me_view:getState())
        UIManager:setDirty(self, "ui", self.content_dimen)
    end
    return true
end

ShelfFileManager.onRefreshContent = ShelfFileManager.onRefresh
ShelfFileManager.onBookMetadataChanged = ShelfFileManager.onRefresh

--- The reorganized settings (apps/settings/einksettings), on an optional group or row id; 我的 → 设置 opens it.
function ShelfFileManager:onShowEinkSettings(target)
    require("apps/settings/einksettings").show(self, self.menu, target)
    return true
end

--- The interface font size changed (apps/settings/uifontsize): rebuilt with the new faces, as on rotation.
function ShelfFileManager:onUIFontScaleChanged()
    self:reinit()
end

function ShelfFileManager:onCloseWidget()
    self.shelf_view:stop()
    -- the file browser is out of the widget tree while 书架 shows: it needs its CloseWidget too
    -- (CoverBrowser stops its jobs and timers there)
    if self.content[1] ~= self.files_ui then
        self.files_ui:handleEvent(Event:new("CloseWidget"))
    end
    FileManager.onCloseWidget(self)
end

Replacements.filemanager = ShelfFileManager
require("apps/opds/booksourceview") -- registers the 书源 page for the OPDS plugin

return ShelfFileManager
