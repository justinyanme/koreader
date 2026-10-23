--[[--
The panels the reader toolbar opens, by name: each entry builds the panel
(a ui/widget/panel) for a ReaderToolbar, which shows it with
ReaderToolbar:showPanel(). The panels live in their own modules:

- "progress": apps/reader/modules/readerprogresspanel
- "brightness": apps/reader/modules/readerbrightnesspanel
- "more": apps/reader/modules/readermorepanel
- "font": the typeset panel of ReaderTypesetPanel (ui.config), which shows itself

@usage
    local panel = require("apps/reader/modules/readertoolbarpanels").progress(toolbar)
]]

local Panels = {}

function Panels.progress(toolbar)
    return require("apps/reader/modules/readerprogresspanel"):new{ toolbar = toolbar }
end

function Panels.brightness(toolbar)
    return require("apps/reader/modules/readerbrightnesspanel"):new{ toolbar = toolbar }
end

function Panels.more(toolbar)
    return require("apps/reader/modules/readermorepanel"):new{ toolbar = toolbar }
end

-- Also previewed from the settings (apps/settings/einksettings).
Panels.TapZones = require("apps/reader/modules/readermorepanel").TapZones

return Panels
