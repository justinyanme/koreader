-- Artifact renderer for B4, not a spec runner. Run from an isolated emulator
-- staging directory with KO_HOME pointing at a fresh writable capture folder:
-- ./luajit /path/to/tools/ios/render-b4.lua W H OUTPUT [points|emulator]
-- Each invocation must be a fresh process: UI modules cache scaled constants.
require("setupkoenv")
local real_date = os.date
os.date = function(format, stamp) return real_date(format, stamp or 1792929600) end
local w, h, output, ruler = tonumber(arg[1]), tonumber(arg[2]), arg[3], arg[4]
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open(DataStorage:getDataDir() .. "/defaults.lua")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings:saveSetting("document_metadata_folder", "dir")
G_reader_settings:saveSetting("language", "zh_CN")
require("gettext").changeLang("zh_CN")
require("dbg"):turnOff()
require("logger"):setLevel(require("logger").levels.warn)
-- Use the same dummy framebuffer boundary as offscreen capture, without loading
-- commonrequire or any spec (Q46). No SDL window or simulator GUI is opened.
einkfb = require("ffi/framebuffer") -- luacheck: ignore
einkfb.dummy = true -- luacheck: ignore
local Device = require("device")
local Screen = Device.screen
local BB = require("ffi/blitbuffer")
Screen.bb:free()
Screen.bb = BB.new(w, h, BB.TYPE_BBRGB32)
Screen.screen_size = { w = w, h = h }
if ruler == "points" then
    Screen.scaleBySize = function(_, n) return math.ceil(n) end
    Screen.scaleByDPI = Screen.scaleBySize
    Device.minimum_touch_size = 44
end
require("document/canvascontext"):init(Device)
local plugins = require("pluginloader")
plugins.enabled_plugins, plugins.disabled_plugins, plugins.loaded_plugins = {}, {}, {}
local Replacements = require("apps/replacements")
require("apps/shelf/shelffilemanager")
Replacements.reader_menu = require("apps/reader/modules/readertoolbar")
Replacements.reader_config = require("apps/reader/modules/readertypesetpanel")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local function capture(name)
    UIManager:forceRePaint()
    Screen.bb:writePNG(output .. "/" .. name .. ".png")
end
local function tap(x, y)
    UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
end
local home = DataStorage:getDataDir() .. "/books"
G_reader_settings:saveSetting("home_dir", home)
local FM = require("apps/filemanager/filemanager")
FM:showFiles(home)
capture("shelf")
local fm = FM.instance
fm:switchTab("me")
capture("me")
fm:switchTab("shelf")
UIManager:forceRePaint()
-- Reach import through its painted action; use the same absolute KO_HOME in
-- baseline/final runs so its displayed home-folder path is identical.
local import = fm.shelf_view.import_button.dimen
tap(import.x + import.w / 2, import.y + import.h / 2)
capture("import")
local import_page = UIManager._window_stack[#UIManager._window_stack].widget
import_page:close()

-- A deterministic feed at the transport seam; real source entry/build/paging.
local BookSource = require("apps/opds/booksource")
local source = { title = "样本书源", url = "https://books.example/opds" }
local books = {}
for i = 1, 40 do
    books[i] = { key = tostring(i), title = i == 1 and "追忆似水年华 第一卷 在斯万家那边" or "样本书籍 " .. i,
        author = "作者", formats = { { ext = "epub", href = source.url .. "/" .. i } } }
end
local real_load = BookSource.load
BookSource.load = function()
    return { state = "ok", title = "最近添加", url = source.url,
        search_url = source.url .. "/search?q=%s", books = books, navs = {} }
end
local NetworkMgr = require("ui/network/manager")
local real_online, real_run = NetworkMgr.isOnline, NetworkMgr.runWhenOnline
NetworkMgr.isOnline = function() return true end
NetworkMgr.runWhenOnline = function(_, action) action() end
local Sources = require("apps/opds/booksourceview")
local view = Sources.show{ servers = { source }, ui = fm }
UIManager:_checkTasks()
capture("sources")
view:close()
BookSource.load = real_load
NetworkMgr.isOnline, NetworkMgr.runWhenOnline = real_online, real_run
view = Sources.show{ servers = {}, ui = fm }
capture("sources-empty")
view:close()
fm:onClose()
local ReaderUI = require("apps/reader/readerui")
local ui = ReaderUI:new{ dimen = Screen:getSize(),
    document = require("document/documentregistry"):openDocument(home .. "/juliet.epub") }
UIManager:show(ui)
ui:handleEvent(Event:new("GotoPage", 10))
capture("reader")
ui.menu:showToolbar()
capture("toolbar")
ui:handleEvent(Event:new("ShowConfigMenu"))
capture("typeset")
ui.menu:hideToolbar()
ui.menu:showToolbar()
ui.menu:onShowToolbarPanel("progress")
capture("progress")
ui.menu:hideToolbar()
ui:handleEvent(Event:new("ShowToc"))
capture("toc")
-- The process ends here; all settings, metadata and caches belong to KO_HOME.

ui:handleEvent(Event:new("ShowNotes"))
capture("notes")
