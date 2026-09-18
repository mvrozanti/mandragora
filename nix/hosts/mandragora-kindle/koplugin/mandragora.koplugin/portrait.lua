local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Screen = Device.screen

local PortraitViewer = InputContainer:extend{
    dir = "/mnt/us/mandragora/art",
    state_file = "/mnt/us/mandragora/state/portrait.last",
    files = nil,
    index = nil,
}

local function isImage(name)
    local lower = name:lower()
    return lower:match("%.png$") or lower:match("%.jpe?g$")
end

local function lockToImage(path)
    G_reader_settings:saveSetting("screensaver_type", "document_cover")
    G_reader_settings:saveSetting("screensaver_document_cover", path)
end

local function hideStatusBar()
    os.execute("/usr/bin/lipc-set-prop com.lab126.pillow disableEnablePillow disable >/dev/null 2>&1 &")
end

function PortraitViewer:scan()
    local files = {}
    local ok, iter, dir_obj = pcall(lfs.dir, self.dir)
    if not ok then return files end
    for name in iter, dir_obj do
        if isImage(name) then files[#files + 1] = self.dir .. "/" .. name end
    end
    table.sort(files)
    return files
end

function PortraitViewer:remember(path)
    local fh = io.open(self.state_file, "w")
    if not fh then return end
    fh:write(path)
    fh:close()
end

function PortraitViewer:restoreScreensaver()
    if self.prev_screensaver_type then
        G_reader_settings:saveSetting("screensaver_type", self.prev_screensaver_type)
    else
        G_reader_settings:delSetting("screensaver_type")
    end
    if self.prev_document_cover then
        G_reader_settings:saveSetting("screensaver_document_cover", self.prev_document_cover)
    else
        G_reader_settings:delSetting("screensaver_document_cover")
    end
end

function PortraitViewer:pickRandom()
    if not self.files or #self.files == 0 then return nil end
    if #self.files == 1 then return 1 end
    local choice = self.index
    for _ = 1, 8 do
        choice = math.random(#self.files)
        if choice ~= self.index then break end
    end
    return choice
end

function PortraitViewer:init()
    self.files = self:scan()
    math.randomseed(os.time())
    self.index = self:pickRandom() or 1

    self.prev_screensaver_type = G_reader_settings:readSetting("screensaver_type")
    self.prev_document_cover = G_reader_settings:readSetting("screensaver_document_cover")

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

function PortraitViewer:build()
    local path = self.files and self.files[self.index]
    if path then
        self[1] = ImageWidget:new{
            file = path,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            scale_factor = nil,
            alpha = false,
        }
        self:remember(path)
        lockToImage(path)
    else
        local TextWidget = require("ui/widget/textwidget")
        local Font = require("ui/font")
        self[1] = TextWidget:new{
            text = "no art in " .. self.dir,
            face = Font:getFace("infofont"),
        }
    end
end

function PortraitViewer:shuffle()
    if not self.files or #self.files < 2 then return end
    self.index = self:pickRandom()
    self:build()
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

function PortraitViewer:onTap()
    self:shuffle()
    return true
end

function PortraitViewer:onDoubleTap()
    return self:onClose()
end

function PortraitViewer:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    return true
end

function PortraitViewer:onClose()
    UIManager:close(self)
    return true
end

function PortraitViewer:onCloseWidget()
    UIManager:unschedule(self.rehideStatusBar, self)
    self:restoreScreensaver()
    UIManager:setDirty(nil, "full")
end

function PortraitViewer:rehideStatusBar()
    hideStatusBar()
    UIManager:scheduleIn(60, self.rehideStatusBar, self)
end

function PortraitViewer:onShow()
    self:rehideStatusBar()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function PortraitViewer.open()
    local viewer = PortraitViewer:new{}
    if not viewer.files or #viewer.files == 0 then
        logger.warn("mandragora: portrait: no images in " .. viewer.dir)
    end
    Screen:clear()
    Screen:refreshFull(0, 0, Screen:getWidth(), Screen:getHeight())
    UIManager:show(viewer)
    return viewer
end

return PortraitViewer
