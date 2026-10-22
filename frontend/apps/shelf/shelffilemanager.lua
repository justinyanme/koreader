--[[--
The redesigned home: FileManager with a bottom tab bar (书架 / 文件 / 我的).

Requiring this module registers it in apps/replacements. It keeps the
original FileManager layout as the 文件 tab, so modules and plugins that rely
on file_chooser keep working, and the original menu stays reachable.

Each tab's `open(fm)` returns the widget for the content area, or nil when the
tab opens something on top instead. #10 and #11 replace the files and me tabs.
]]

local Device = require("device")
local FileManager = require("apps/filemanager/filemanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Palette = require("ui/palette")
local Replacements = require("apps/replacements")
local ShelfView = require("apps/shelf/shelfview")
local ShelfWidgets = require("apps/shelf/shelfwidgets")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ShelfFileManager = FileManager:extend{
    current_tab = "shelf",
}

ShelfFileManager.tabs = {
    { id = "shelf", icon = "shelf", text = _("Shelf"), open = function(fm)
        fm.shelf_view:reload()
        fm.shelf_view:update()
        return fm.shelf_view
    end },
    { id = "files", icon = "folder", text = _("Files"), open = function(fm) return fm.files_ui end },
    -- until #11: the original menu on top of the current tab
    { id = "me", icon = "user", text = _("Me"), open = function(fm) fm.menu:onShowMenu() end },
}

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
    self.content = WidgetContainer:new{
        dimen = self.content_dimen:copy(),
        self.current_tab == "files" and self.files_ui or self.shelf_view,
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

-- file_chooser handles Back itself while the 文件 tab shows it
function ShelfFileManager:onBack()
    return self.file_chooser:onBack()
end

function ShelfFileManager:onRefresh()
    FileManager.onRefresh(self)
    self.shelf_view:reload()
    self.shelf_view:update(self.current_tab == "shelf" and "header" or nil)
    return true
end

ShelfFileManager.onRefreshContent = ShelfFileManager.onRefresh
ShelfFileManager.onBookMetadataChanged = ShelfFileManager.onRefresh

function ShelfFileManager:onCloseWidget()
    self.shelf_view:stop()
    FileManager.onCloseWidget(self)
end

Replacements.filemanager = ShelfFileManager

return ShelfFileManager
