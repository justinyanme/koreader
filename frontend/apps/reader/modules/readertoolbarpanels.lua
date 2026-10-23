--[[--
The panels the reader toolbar opens, by name: each entry builds the panel
(a ui/widget/panel) for a ReaderToolbar, which shows it with
ReaderToolbar:showPanel(). The panels live in their own modules:

- "progress": apps/reader/modules/readerprogresspanel
- "brightness": apps/reader/modules/readerbrightnesspanel
- "more": apps/reader/modules/readermorepanel
The typeset panel ("font") is ReaderTypesetPanel's (ui.config): it shows itself
on "ShowConfigMenu", see ReaderToolbar:openPanel().

@usage
    local panel = require("apps/reader/modules/readertoolbarpanels").progress(toolbar)
]]

local ReaderBrightnessPanel = require("apps/reader/modules/readerbrightnesspanel")
local ReaderMorePanel = require("apps/reader/modules/readermorepanel")
local ReaderProgressPanel = require("apps/reader/modules/readerprogresspanel")

local Panels = {}

function Panels.progress(toolbar)
    return ReaderProgressPanel:new{ toolbar = toolbar }
end

function Panels.brightness(toolbar)
    return ReaderBrightnessPanel:new{ toolbar = toolbar }
end

function Panels.more(toolbar)
    return ReaderMorePanel:new{ toolbar = toolbar }
end

-- Also previewed from the settings (apps/settings/einksettings).
Panels.TapZones = ReaderMorePanel.TapZones

return Panels
