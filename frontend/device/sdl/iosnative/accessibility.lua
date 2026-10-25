-- The VoiceOver overlay's FFI adapter (C3): platform/ios/JustReader/Sources/Accessibility.swift.
local ffi = require("ffi")

ffi.cdef[[
void ko_ios_a11y_set(const char *elements, int generation, double pixel_width, bool screen_changed);
const char *ko_ios_a11y_poll(void);
]]

local C = ffi.C

local function clean(s)
    return (s:gsub("[\t\n]", " "))
end

local Accessibility = {}

-- One line per element: x, y, w, h (screen pixels), "true" if adjustable, label, value.
function Accessibility.accessibilitySet(update)
    local lines = {}
    for i, e in ipairs(update.elements) do
        lines[i] = table.concat({ e.x, e.y, e.w, e.h, tostring(e.adjustable), clean(e.label), clean(e.value) }, "\t")
    end
    C.ko_ios_a11y_set(table.concat(lines, "\n"), update.generation, update.pixel_width, update.screen_changed == true)
    return true
end

-- One line per action: generation, element index (from 1), "activate", "increment" or "decrement".
function Accessibility.accessibilityPoll()
    local actions = {}
    for line in ffi.string(C.ko_ios_a11y_poll()):gmatch("[^\n]+") do
        local generation, index, action = line:match("^(%d+)\t(%d+)\t(%a+)$")
        if generation then
            table.insert(actions, { generation = tonumber(generation), index = tonumber(index), action = action })
        end
    end
    return actions
end

return Accessibility
