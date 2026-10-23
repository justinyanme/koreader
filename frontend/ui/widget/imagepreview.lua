--[[--
Image preview of the e-ink redesign (see DESIGN.md, Image preview): an image of the text
shown over the whole screen, centered on an ink ground, with no title or buttons, as WeChat
Read shows a tapped illustration (09-images/02-image-preview.png).

- a double tap zooms in to twice the fitting size around the point tapped, and the next one
  fits it again (09-images/03-image-preview-zoom.png); ImageViewer's pinches, spreads, drags,
  swipes and keys keep working;
- a tap closes it, back to the same place in the text, and so do Back and ImageViewer's
  closing swipes; the side thirds still step through the frames of an animated image;
- the image lies on paper, so that its transparent parts read as they do on the page.

ReaderHighlightBubble opens it for a tap on an image. A long-press still opens ImageViewer
itself, with its buttons (original size, rotation) and, without multitouch, the bottom-left
corner that saves the view (a two-finger tap does here).

Refreshes: showing and closing it repaint the screen with "ui" (dithered when showing), as a
full-screen page does, never with a flash; zooming and panning are ImageViewer's "ui" too.
A hold without moving still asks for ImageViewer's full refresh, which the reader requests.

@usage
    UIManager:show(ImagePreview:new{ image = image })
]]

local Device = require("device")
local GestureRange = require("ui/gesturerange")
local ImageViewer = require("ui/widget/imageviewer")
local Palette = require("ui/palette")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

--- Paints paper under the part of its ImageWidget that is shown, then the image.
local Paper = WidgetContainer:extend{}

function Paper:paintTo(bb, x, y)
    local image = self[1]
    local box = image:getSize() -- renders it
    -- where ImageWidget:paintTo() blits the image in its box, centered or panned by its offsets
    local x0, y0 = math.max(0, -image._offset_x), math.max(0, -image._offset_y)
    local x1 = math.min(box.w, image:getCurrentWidth() - image._offset_x)
    local y1 = math.min(box.h, image:getCurrentHeight() - image._offset_y)
    if x1 > x0 and y1 > y0 then
        bb:paintRect(x + x0, y + y0, x1 - x0, y1 - y0, Palette.paper)
    end
    image:paintTo(bb, x, y)
end

local ImagePreview = ImageViewer:extend{
    fullscreen = true,
    with_title_bar = false,
    disable_double_tap = false, -- for the zoom, while the preview is on top
    close_refresh_type = "ui",
    double_tap_zoom = 2, -- times the fitting size
}

function ImagePreview:init()
    ImageViewer.init(self)
    self.main_frame.background = Palette.ink
    if Device:isTouchDevice() then
        self.ges_events.DoubleTap = { GestureRange:new{ ges = "double_tap", range = self.region } }
    end
end

function ImagePreview:_new_image_wg()
    ImageViewer._new_image_wg(self)
    self.image_container[1] = Paper:new{ self._image_wg }
end

function ImagePreview:onShow()
    self.dithered = true
    UIManager:setDirty(self, function()
        return "ui", self.main_frame.dimen, true
    end)
    return true
end

function ImagePreview:onTap(_, ges)
    local x = ges.pos.x / Screen:getWidth()
    if self._images_list and (x < 1/3 or x > 2/3) then
        return ImageViewer.onTap(self, _, ges) -- the previous or next frame
    end
    return self:onClose()
end

function ImagePreview:onDoubleTap(_, ges)
    if self.scale_factor == 0 then -- fitting
        self:_refreshScaleFactor()
        -- centered on the point tapped, as a spread is
        self._center_x_ratio, self._center_y_ratio = self._image_wg:getPanByCenterRatio(
            ges.pos.x - Screen:getWidth() / 2, ges.pos.y - Screen:getHeight() / 2)
        self:_applyNewScaleFactor(self.scale_factor * self.double_tap_zoom)
    else
        self.scale_factor = 0
        self._center_x_ratio, self._center_y_ratio = 0.5, 0.5
        self:update()
    end
    return true
end

return ImagePreview
