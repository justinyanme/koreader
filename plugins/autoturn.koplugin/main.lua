local Event = require("ui/event")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")
local T = require("ffi/util").template

local AutoTurn = WidgetContainer:extend{
    name = "autoturn",
    is_doc_only = true,
    autoturn_sec = 0,
    autoturn_distance = 1,
    enabled = false,
    last_action_time = 0,
    task = nil,
}

function AutoTurn:_enabled()
    return self.enabled and self.autoturn_sec > 0
end

function AutoTurn:_schedule()
    if not self:_enabled() then
        logger.dbg("AutoTurn:_schedule is disabled")
        return
    end

    local delay = self.last_action_time + time.s(self.autoturn_sec) - UIManager:getElapsedTimeSinceBoot()

    if delay <= 0 then
        local top_wg = UIManager:getTopmostVisibleWidget() or {}
        if top_wg.name == "ReaderUI" then
            logger.dbg("AutoTurn: go to next page")
            self.ui:handleEvent(Event:new("GotoViewRel", self.autoturn_distance))
            self.last_action_time = UIManager:getElapsedTimeSinceBoot()
        end
        logger.dbg("AutoTurn: schedule in", self.autoturn_sec)
        UIManager:scheduleIn(self.autoturn_sec, self.task)
        self.scheduled = true
    else
        local delay_s = time.to_number(delay)
        logger.dbg("AutoTurn: schedule in", delay_s, "s")
        UIManager:scheduleIn(delay_s, self.task)
        self.scheduled = true
    end
end

function AutoTurn:_unschedule()
    PluginShare.pause_auto_suspend = false
    if self.scheduled then
        logger.dbg("AutoTurn: unschedule")
        UIManager:unschedule(self.task)
        self.scheduled = false
    end
end

function AutoTurn:_start(silent)
    self:_unschedule()
    if self:_enabled() and not self.suspended then
        local time_since_boot = UIManager:getElapsedTimeSinceBoot()
        logger.dbg("AutoTurn: start at", time.format_time(time_since_boot))
        PluginShare.pause_auto_suspend = true
        self.last_action_time = time_since_boot
        self:_schedule()

        if self.pill and not self.settings then
            UIManager:setDirty(self.ui.view.dialog, "ui", self.pill.dimen)
        end
        if silent then return end

        local text
        if self.autoturn_distance == 1 then
            local time_string = datetime.secondsToClockDuration("letters", self.autoturn_sec, false, true, true)
            text = T(_("Autoturn is now active and will automatically turn the page every %1."), time_string)
        else
            text = T(_("Autoturn is now active and will automatically scroll %1 % of the page every %2 seconds."),
                self.autoturn_distance * 100,
                self.autoturn_sec)
        end

        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = text,
            timeout = 3,
        })
    end
end

-- Both the original precise controls and the five quick speeds use the same timer and saved values.
function AutoTurn:setInterval(seconds, distance, silent)
    self.autoturn_sec = seconds
    if distance then self.autoturn_distance = distance end
    self.enabled = seconds > 0
    G_reader_settings:saveSetting("autoturn_timeout_seconds", seconds)
    G_reader_settings:saveSetting("autoturn_distance", self.autoturn_distance)
    G_reader_settings:saveSetting("autoturn_enabled", self.enabled)
    self:_start(silent)
end

function AutoTurn:start()
    self:setInterval(self.autoturn_sec > 0 and self.autoturn_sec or 60, 1, true)
end

function AutoTurn:stop()
    self.enabled = false
    G_reader_settings:makeFalse("autoturn_enabled")
    self:_unschedule()
    if self.pill then
        UIManager:setDirty(self.ui.view.dialog, "ui", self.pill.dimen)
    end
end

function AutoTurn:showSettings()
    if self.settings then return end
    self.settings = require("apps/reader/modules/readerautoturn").Settings:new{ autoturn = self }
    UIManager:show(self.settings, "ui", self.settings.panel:getRefreshRegion())
end

function AutoTurn:onReaderReady()
    if not (require("device"):isTouchDevice() and self.ui.menu.showPanel) then return end
    if self.pill then self.pill:free() end
    self.pill = require("apps/reader/modules/readerautoturn").Pill:new{ autoturn = self }
    self.ui.view:registerViewModule("autoturn", self.pill)
    self.ui:registerTouchZones({{
        id = "autoturn_settings", ges = "tap",
        screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
        overrides = { "readermenu_tap", "tap_forward", "tap_backward", "readerfooter_tap", "tap_link", "readerhighlight_tap" },
        handler = function(ges)
            if self:_enabled() and not self.suspended and self.pill.touch_dimen:contains(ges.pos) then
                self:showSettings()
                return true
            end
        end,
    }})
end

function AutoTurn:onSetDimensions()
    if self.settings then self.settings:close() end
    self:onReaderReady()
end

function AutoTurn:init()
    UIManager.event_hook:registerWidget("InputEvent", self)
    self.autoturn_sec = G_reader_settings:readSetting("autoturn_timeout_seconds", 0)
    self.autoturn_distance = G_reader_settings:readSetting("autoturn_distance", 1)
    self.enabled = G_reader_settings:isTrue("autoturn_enabled")
    self.ui.menu:registerToMainMenu(self)
    self.task = function()
        self:_schedule()
    end
    self:_start(self.ui.menu.showPanel ~= nil)
end

function AutoTurn:onCloseWidget()
    logger.dbg("AutoTurn: onCloseWidget")
    self:_unschedule()
    self.task = nil
end

function AutoTurn:onCloseDocument()
    logger.dbg("AutoTurn: onCloseDocument")
    self:_unschedule()
    if self.settings then self.settings:close() end
    if self.pill then
        self.ui.view.view_modules.autoturn = nil
        self.pill:free()
        self.pill = nil
    end
end

function AutoTurn:onInputEvent()
    logger.dbg("AutoTurn: onInputEvent")
    self.last_action_time = UIManager:getElapsedTimeSinceBoot()
end

-- We do not want autoturn to turn pages during the suspend process.
-- Unschedule it and restart after resume.
function AutoTurn:onSuspend()
    logger.dbg("AutoTurn: onSuspend")
    self.suspended = true
    self:_unschedule()
    if self.settings then self.settings:close() end
end

function AutoTurn:onResume()
    logger.dbg("AutoTurn: onResume")
    self.suspended = false
    self:_start(true)
end

function AutoTurn:addToMainMenu(menu_items)
    menu_items.autoturn = {
        sorting_hint = "navi",
        text_func = function()
            local time_string = datetime.secondsToClockDuration("letters", self.autoturn_sec, false, true, true)
            return self:_enabled() and T(_("Autoturn: %1"), time_string) or _("Autoturn")
        end,
        checked_func = function() return self:_enabled() end,
        check_callback_updates_menu = true,
        callback = function(menu)
            local DateTimeWidget = require("ui/widget/datetimewidget")
            local autoturn_seconds = G_reader_settings:readSetting("autoturn_timeout_seconds", 30)
            local autoturn_minutes = math.floor(autoturn_seconds * (1/60))
            autoturn_seconds = autoturn_seconds % 60
            local autoturn_spin = DateTimeWidget:new {
                title_text = _("Autoturn time"),
                info_text = _("Enter time in minutes and seconds."),
                min = autoturn_minutes,
                min_max = 60 * 24, -- maximum one day
                min_default = 0,
                sec = autoturn_seconds,
                sec_default = 30,
                keep_shown_on_apply = true,
                ok_text = _("Set timeout"),
                cancel_text = _("Disable"),
                cancel_callback = function()
                    self:stop()
                    menu:updateItems()
                end,
                ok_always_enabled = true,
                callback = function(t)
                    self:setInterval(t.min * 60 + t.sec)
                    menu:updateItems()
                end,
            }
            UIManager:show(autoturn_spin)
        end,
        hold_callback = function(menu)
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = G_reader_settings:readSetting("autoturn_distance") or 1
            local autoturn_spin = SpinWidget:new {
                value = curr_items,
                value_min = -20,
                value_max = 20,
                precision = "%.2f",
                value_step = .1,
                value_hold_step = .5,
                ok_text = _("Set distance"),
                title_text = _("Scrolling distance"),
                callback = function(autoturn_spin)
                    self.autoturn_distance = autoturn_spin.value
                    G_reader_settings:saveSetting("autoturn_distance", autoturn_spin.value)
                    if self.enabled then
                        self:_unschedule()
                        self:_start()
                    end
                    menu:updateItems()
                end,
            }
            UIManager:show(autoturn_spin)
        end,
    }
end

return AutoTurn
