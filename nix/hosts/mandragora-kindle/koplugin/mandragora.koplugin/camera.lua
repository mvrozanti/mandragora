local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
local logger = require("logger")

local Screen = Device.screen

local ENDPOINT = "http://100.115.80.79:6686/frame.jpg"
local PROXY = "http://localhost:1056"
local CURL = "/usr/bin/curl"
local SLOTS = { "/tmp/mandragora-cam-a.jpg", "/tmp/mandragora-cam-b.jpg" }
local TIMEOUT = 6
local FULL_EVERY = 8

local MODES = {
    { label = "live", interval = 0.6 },
    { label = "2s", interval = 2 },
    { label = "10s", interval = 10 },
    { label = "hold", interval = nil },
}

local CameraViewer = InputContainer:extend{
    mode = 1,
    slot = 1,
    ticks = 0,
    shown = 0,
    path = nil,
    status = "connecting",
}

function CameraViewer:fetch()
    local target = SLOTS[self.slot]
    local cmd = string.format(
        "http_proxy=%s %s -s --max-time %d -o %s -w '%%{http_code}' %s 2>/dev/null",
        PROXY, CURL, TIMEOUT, target, ENDPOINT)
    local pipe = io.popen(cmd)
    if not pipe then return nil, "no pipe" end
    local out = pipe:read("*a")
    pipe:close()
    local code = tostring(out or ""):match("(%d%d%d)")
    if code ~= "200" then
        return nil, code and ("http " .. code) or "unreachable"
    end
    local fh = io.open(target, "rb")
    if not fh then return nil, "no file" end
    local size = fh:seek("end")
    fh:close()
    if not size or size < 1024 then return nil, "short frame" end
    self.slot = self.slot == 1 and 2 or 1
    return target, size
end

function CameraViewer:footer()
    local text = string.format("camera · %s · %s · tap to cycle, swipe to close",
        MODES[self.mode].label, self.status)
    return BottomContainer:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() },
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = Screen:scaleBySize(6),
            TextWidget:new{
                text = text,
                face = Font:getFace("smallinfofont"),
            },
        },
    }
end

function CameraViewer:build()
    if self.image then
        self.image:free()
        self.image = nil
    end
    local children = {
        dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
    }
    if self.path then
        self.image = ImageWidget:new{
            file = self.path,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            scale_factor = 0,
            alpha = false,
            file_do_cache = false,
        }
        children[#children + 1] = self.image
    else
        children[#children + 1] = TextWidget:new{
            text = "waiting for " .. ENDPOINT,
            face = Font:getFace("infofont"),
        }
    end
    children[#children + 1] = self:footer()
    self[1] = OverlapGroup:new(children)
end

function CameraViewer:refresh()
    local path, info = self:fetch()
    if path then
        self.path = path
        self.status = string.format("%.0f kB", info / 1024)
    else
        self.status = "stale - " .. tostring(info)
    end
    self:build()
    self.shown = self.shown + 1
    local full = self.shown % FULL_EVERY == 0
    UIManager:setDirty(self, function()
        return full and "full" or "partial", self.dimen
    end)
end

function CameraViewer:schedule()
    UIManager:unschedule(self.tick)
    local interval = MODES[self.mode].interval
    if not interval then return end
    UIManager:scheduleIn(interval, self.tick)
end

function CameraViewer:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true

    self.tick = function()
        if not self.alive then return end
        self:refresh()
        self:schedule()
    end
    self.alive = true

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

function CameraViewer:onTap()
    self.mode = self.mode % #MODES + 1
    if MODES[self.mode].interval then
        self:refresh()
        self:schedule()
    else
        UIManager:unschedule(self.tick)
        self:build()
        UIManager:setDirty(self, function() return "partial", self.dimen end)
    end
    return true
end

function CameraViewer:onDoubleTap()
    return self:onClose()
end

function CameraViewer:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    return true
end

function CameraViewer:onClose()
    UIManager:close(self)
    return true
end

function CameraViewer:onCloseWidget()
    self.alive = false
    UIManager:unschedule(self.tick)
    if self.image then
        self.image:free()
        self.image = nil
    end
    UIManager:setDirty(nil, "full")
end

function CameraViewer:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    UIManager:nextTick(function()
        if not self.alive then return end
        self:refresh()
        self:schedule()
    end)
    return true
end

function CameraViewer.open()
    local viewer = CameraViewer:new{}
    logger.info("mandragora: camera opening", ENDPOINT)
    UIManager:show(viewer)
    return viewer
end

return CameraViewer
