--[[--
The redesigned home: FileManager with a bottom tab bar (书架 / 文件 / 我的).

Requiring this module registers it in apps/replacements. It keeps the
original FileManager layout as the 文件 tab, so modules and plugins that rely
on file_chooser keep working, and the original menu stays reachable. Anything
that moves file_chooser to a folder (Show folder, search results, shortcuts,
plugins) brings the 文件 tab forward, and input meant for the file browser
(swipe, Back, Home) only reaches it while it is showing.

Each tab's `open(fm)` returns the widget for the content area, or nil when the
tab opens something on top instead. #10 and #11 replace the files and me tabs.
]]

local BD = require("ui/bidi")
local Device = require("device")
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
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local ShelfFileManager = FileManager:extend{
    current_tab = "shelf",
    file_chooser_class = require("apps/shelf/fileschooser"), -- the 文件 tab
}

ShelfFileManager.tabs = {
    { id = "shelf", icon = "shelf", text = _("Shelf"), open = function(fm)
        fm.shelf_view:reload()
        fm.shelf_view:update()
        return fm.shelf_view
    end },
    { id = "files", icon = "folder", text = _("Files"), open = function(fm) return fm.files_ui end },
    { id = "me", icon = "user", text = _("Me"), open = function(fm)
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
    local tabbar_h = ShelfWidgets.TabBar.height
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
    self.layout_group = VerticalGroup:new{ self.content, self:buildTabBar() }
    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Palette.paper,
        self.layout_group,
    }
    if Device:hasKeys() then
        self.key_events.Back = { { Device.input.group.Back } }
    end
end

function ShelfFileManager:buildTabBar()
    return ShelfWidgets.TabBar:new{
        width = self.dimen.w,
        tabs = self.tabs,
        current = self.current_tab,
        on_change = function(id) self:switchTab(id) end,
    }
end

function ShelfFileManager:switchTab(id)
    if id == self.current_tab then return end
    for _, tab in ipairs(self.tabs) do
        if tab.id == id then
            local widget = tab.open(self)
            if not widget then return end
            self.current_tab = id
            self.content[1] = widget
            self.layout_group[2]:free()
            self.layout_group[2] = self:buildTabBar()
            UIManager:setDirty(self, "ui", self.content_dimen)
            UIManager:setDirty(self, "ui", self.tabbar_dimen)
            return
        end
    end
end

-- file_chooser moved to a folder: show it (skipping the initial PathChanged sent by init)
function ShelfFileManager:onPathChanged(path)
    FileManager.onPathChanged(self, path)
    if self.initialized then
        self:switchTab("files")
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
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then
        self.shelf_view:turnPage(1)
    elseif direction == "east" then
        self.shelf_view:turnPage(-1)
    end
    return true
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
