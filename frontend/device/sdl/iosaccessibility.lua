--[[--
VoiceOver regions of the iOS device (C3, Q21). Widgets on screen declare themselves with an `a11y` field:

    a11y = {
        label = string or function, -- what VoiceOver reads
        value = string or function, -- read after the label (a page number)
        activate = function, -- a double tap; defaults to the widget's callback
        adjust = function(delta), -- swipe up (+1) or down (-1): the element is adjustable
    }

Before each input wait, publish() collects them from the windows on screen (the topmost one covering
the screen and those above it, bottom to top, each depth-first) and hands them to the native overlay
(Device.bridge.accessibilitySet) when they changed. After each wait, dispatch() takes the activations
the overlay queued (Device.bridge.accessibilityPoll; the overlay wakes the wait with an SDL user event)
and runs them on the next tick. Nothing calls back from native code (ADR-0009). Only the iOS device
creates this: on other devices nothing reads the `a11y` fields.
]]

local A11y = {}
A11y.__index = A11y

function A11y.new(device, uimgr)
    return setmetatable({
        device = device,
        uimgr = uimgr,
        generation = 0, -- of the published set: activations of an older one are dropped
        published = nil, -- its serialization
        entries = {}, -- its elements, in order
        bottom = nil, -- the window covering the screen when it was published
    }, A11y)
end

local function text(v)
    if type(v) == "function" then v = v() end
    return v ~= nil and tostring(v) or ""
end

local function walk(widget, out, depth)
    if type(widget) ~= "table" or depth > 64 then return end
    if widget.a11y and widget.dimen then table.insert(out, widget) end
    for _, child in ipairs(widget) do
        walk(child, out, depth + 1)
    end
end

--- The declared elements on screen, in order, and the window covering the screen.
function A11y:collect()
    local stack = self.uimgr._window_stack
    local first = 1
    for i = #stack, 1, -1 do
        if stack[i].widget.covers_fullscreen then
            first = i
            break
        end
    end
    local widgets = {}
    for i = first, #stack do
        walk(stack[i].widget, widgets, 0)
    end
    local screen = self.device.screen
    local offset = screen.viewport or { x = 0, y = 0 }
    local elements = {}
    for _, widget in ipairs(widgets) do
        local rect = widget.dimen
        if widget.clip then rect = rect:intersect(widget.clip) end
        if rect.w > 0 and rect.h > 0 then
            local a11y = widget.a11y
            table.insert(elements, {
                widget = widget,
                x = rect.x + offset.x, y = rect.y + offset.y, w = rect.w, h = rect.h,
                label = text(a11y.label),
                value = text(a11y.value),
                adjustable = a11y.adjust ~= nil,
            })
        end
    end
    return elements, stack[first] and stack[first].widget
end

local function serialize(elements)
    local lines = {}
    for i, e in ipairs(elements) do
        lines[i] = table.concat({ e.x, e.y, e.w, e.h, tostring(e.adjustable), e.label, e.value }, "\t")
    end
    return table.concat(lines, "\n")
end

--- Hands the elements on screen to the overlay if they changed. Returns false once the bridge has no overlay.
function A11y:publish()
    if self.unsupported then return false end
    local elements, bottom = self:collect()
    self.entries = elements -- same order when unchanged, but maybe rebuilt widgets
    local key = serialize(elements)
    if key == self.published then return true end
    self.generation = self.generation + 1
    local ok = self.device.bridge.accessibilitySet{
        generation = self.generation,
        pixel_width = self.device.screen:getRawSize().w,
        screen_changed = bottom ~= self.bottom,
        elements = elements,
    }
    if not ok then
        self.unsupported = true
        return false
    end
    self.published, self.bottom = key, bottom
    return true
end

--- Schedules the activations the overlay queued. Returns true if there were any.
function A11y:dispatch()
    if self.unsupported then return false end
    local actions = self.device.bridge.accessibilityPoll()
    if not actions or #actions == 0 then return false end
    for _, action in ipairs(actions) do
        local entry = action.generation == self.generation and self.entries[action.index]
        if entry then
            self.uimgr:nextTick(function() self:run(entry.widget, action.action) end)
        end
    end
    return true
end

function A11y:run(widget, action)
    local a11y = widget.a11y
    if action == "activate" then
        local activate = a11y.activate or widget.callback
        if activate then activate() end
    elseif a11y.adjust and (action == "increment" or action == "decrement") then
        a11y.adjust(action == "increment" and 1 or -1)
    end
end

return A11y
