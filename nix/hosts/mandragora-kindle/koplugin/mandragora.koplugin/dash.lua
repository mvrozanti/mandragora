local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Screen = Device.screen

local DashViewer = InputContainer:extend{
    image = "/mnt/us/mandragora/dash/latest.png",
    refresh_script = "/mnt/us/mandragora/scriptlets/mandragora-dash-render.sh",
}

function DashViewer:age()
    local attr = lfs.attributes(self.image)
    if not attr then return nil end
    return os.time() - attr.modification
end

function DashViewer:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true

    if Device:isTouchDevice() then
        self.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
            DoubleTap = { GestureRange:new{ ges = "double_tap", range = self.dimen } },
            Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        }
    end
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end

    self:build()
end

function DashViewer:build()
    if lfs.attributes(self.image) then
        self[1] = ImageWidget:new{
            file = self.image,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            scale_factor = nil,
            alpha = false,
        }
    else
        self[1] = TextBoxWidget:new{
            text = "no dashboard yet\n\nrun kindle-dash from the desktop",
            face = Font:getFace("infofont"),
            width = math.floor(Screen:getWidth() * 0.8),
            alignment = "center",
        }
    end
end

function DashViewer:onTap()
    self:build()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function DashViewer:onDoubleTap()
    return self:onClose()
end

function DashViewer:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    return true
end

function DashViewer:onClose()
    UIManager:close(self)
    return true
end

function DashViewer:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

function DashViewer:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function DashViewer.open()
    local viewer = DashViewer:new{}
    local age = viewer:age()
    if not age then
        logger.warn("mandragora: dash: no image at " .. viewer.image)
    else
        logger.info("mandragora: dash: image age " .. age .. "s")
    end
    UIManager:show(viewer)
    return viewer
end

return DashViewer
