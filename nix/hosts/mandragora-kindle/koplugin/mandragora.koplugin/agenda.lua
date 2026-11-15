local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Screen = Device.screen

local CONFIG_PATH = "/mnt/us/mandragora/agenda.conf"
local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local MID = Blitbuffer.COLOR_LIGHT_GRAY
local SOFT = Blitbuffer.COLOR_GRAY

local DEFAULTS = { host = "192.168.0.27", port = 6616, timeout = 25 }

local Agenda = InputContainer:extend{
    days = nil,
    sync = nil,
    more = 0,
    loaded = false,
    error = nil,
    busy = false,
}

local function readConfig()
    local cfg = {}
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    local fh = io.open(CONFIG_PATH, "r")
    if not fh then return cfg end
    for line in fh:lines() do
        if not line:match("^%s*#") then
            local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if key == "host" and value ~= "" then cfg.host = value end
            if key == "port" then cfg.port = tonumber(value) or cfg.port end
            if key == "timeout" then cfg.timeout = tonumber(value) or cfg.timeout end
        end
    end
    fh:close()
    return cfg
end

local function split(line)
    local fields = {}
    for field in (line .. "\t"):gmatch("(.-)\t") do
        fields[#fields + 1] = field
    end
    return fields
end

local function blank(value)
    return value == nil or value == "" or value == "-"
end

function Agenda:fetch(force)
    local ok, socket = pcall(require, "socket")
    if not ok or not socket then return "no luasocket" end
    local sock = socket.tcp()
    if not sock then return "no socket" end
    sock:settimeout(self.cfg.timeout)
    local connected, cerr = sock:connect(self.cfg.host, self.cfg.port)
    if not connected then
        sock:close()
        return cerr or "connect failed"
    end
    sock:send((force and "REFRESH" or "NOW") .. "\n")

    local days, sync, more, failure, complete = {}, nil, 0, nil, false
    while true do
        local line, rerr = sock:receive("*l")
        if not line then
            failure = failure or rerr or "connection closed"
            break
        end
        if line == "END" then
            complete = true
            break
        end
        local fields = split(line)
        if fields[1] == "DAY" and fields[3] then
            days[#days + 1] = { date = fields[2], label = fields[3], events = {} }
        elseif fields[1] == "E" and fields[5] and #days > 0 then
            local events = days[#days].events
            events[#events + 1] = {
                start = fields[2], finish = fields[3], calendar = fields[4],
                title = fields[5], location = fields[6],
            }
        else
            local s = line:match("^SYNC%s+(%S+)$")
            local m = line:match("^MORE%s+(%d+)$")
            local err = line:match("^ERR%s+(.*)$")
            if s then
                sync = s
            elseif m then
                more = tonumber(m) or 0
            elseif err then
                failure = failure or err
            end
        end
    end
    sock:send("QUIT\n")
    sock:close()

    if complete then
        self.days, self.sync, self.more, self.loaded = days, sync, more, true
    end
    return failure
end

function Agenda:layout()
    local w, h = Screen:getWidth(), Screen:getHeight()
    return {
        w = w, h = h,
        m = math.floor(w * 0.030),
        top = math.floor(h * 0.030),
        gap = math.floor(h * 0.022),
    }
end

function Agenda:init()
    self.L = self:layout()
    self.cfg = readConfig()
    self.days = self.days or {}
    self.dimen = Geom:new{ x = 0, y = 0, w = self.L.w, h = self.L.h }
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
end

function Agenda:syncText()
    if self.busy then return "fetching" end
    if self.error and not self.loaded then return "unreachable" end
    if self.sync == nil then return "" end
    local seconds = tonumber(self.sync)
    if not seconds then return "never synced" end
    if seconds < 600 then return "in sync" end
    if seconds < 7200 then return string.format("synced %d min ago", math.floor(seconds / 60)) end
    if seconds < 172800 then return string.format("synced %d h ago", math.floor(seconds / 3600)) end
    return string.format("synced %d days ago", math.floor(seconds / 86400))
end

local function block(bb, x, y, str, face, fg, max_width)
    local widget = TextWidget:new{ text = str, face = face, fgcolor = fg, max_width = max_width }
    local size = widget:getSize()
    widget:paintTo(bb, x, y)
    widget:free()
    return size.h, size.w
end

local function measure(str, face)
    local widget = TextWidget:new{ text = str, face = face }
    local size = widget:getSize()
    widget:free()
    return size.h, size.w
end

local function timeText(event)
    if blank(event.start) then return "all day" end
    if blank(event.finish) then return event.start end
    return event.start .. " – " .. event.finish
end

local function titleText(event)
    if blank(event.location) then return event.title end
    return event.title .. "  ·  " .. event.location
end

function Agenda:paintTo(bb, x, y)
    local L = self.L
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, L.w, L.h, WHITE)

    local left = x + L.m
    local right = x + L.w - L.m
    local cursor = y + L.top

    local title = TextWidget:new{ text = "agenda", face = Font:getFace("tfont", 40) }
    local title_size = title:getSize()
    title:paintTo(bb, left, cursor)
    title:free()

    local age = TextWidget:new{
        text = self:syncText(), face = Font:getFace("infofont", 26), fgcolor = SOFT,
    }
    local age_size = age:getSize()
    age:paintTo(bb, right - age_size.w, cursor + title_size.h - age_size.h - 4)
    age:free()
    cursor = cursor + title_size.h + L.gap

    local foot_face = Font:getFace("infofont", 28)
    local foot_h = measure("Ag", foot_face)
    local foot_top = y + L.h - L.m - foot_h

    if not self.loaded then
        cursor = cursor + math.floor(L.h * 0.28)
        cursor = cursor + block(bb, left, cursor, "no agenda", Font:getFace("tfont", 58), BLACK)
        cursor = cursor + L.gap
        cursor = cursor + block(bb, left, cursor,
            self.cfg.host .. ":" .. self.cfg.port .. " did not answer",
            Font:getFace("infofont", 30), SOFT) + L.gap
        block(bb, left, cursor, "tap to try again", Font:getFace("infofont", 30), SOFT)
        if self.error then
            block(bb, left, foot_top, "· " .. tostring(self.error), foot_face, SOFT, L.w - L.m * 2)
        end
        return
    end

    if #self.days == 0 then
        cursor = cursor + math.floor(L.h * 0.28)
        cursor = cursor + block(bb, left, cursor, "nothing ahead", Font:getFace("tfont", 58), BLACK)
        cursor = cursor + L.gap
        block(bb, left, cursor, "the next two weeks are empty", Font:getFace("infofont", 30), SOFT)
        if self.error then
            block(bb, left, foot_top, "· " .. tostring(self.error), foot_face, SOFT, L.w - L.m * 2)
        end
        return
    end

    local day_face = Font:getFace("tfont", 36)
    local time_face = Font:getFace("infofont", 28)
    local event_face = Font:getFace("cfont", 30)
    local day_h = measure("Ag", day_face)
    local event_h = measure("Ag", event_face)
    local row_gap = math.floor(L.gap * 0.45)
    local _, time_w = measure("00:00 – 00:00", time_face)
    local title_x = left + time_w + math.floor(L.w * 0.03)
    local limit = foot_top - L.gap

    local hidden = self.more or 0
    local full = false
    for i, day in ipairs(self.days) do
        local need = day_h + row_gap + event_h + row_gap
        if not full and cursor + need > limit then full = true end
        if full then
            hidden = hidden + #day.events
        else
            if i > 1 then
                bb:paintRect(left, cursor, L.w - L.m * 2, 1, MID)
                cursor = cursor + row_gap
            end
            block(bb, left, cursor, day.label, day_face, BLACK)
            cursor = cursor + day_h + row_gap
            for _, event in ipairs(day.events) do
                if full or cursor + event_h > limit then
                    full = true
                    hidden = hidden + 1
                else
                    block(bb, left, cursor + math.floor((event_h - measure("Ag", time_face)) / 2),
                        timeText(event), time_face, SOFT)
                    block(bb, title_x, cursor, titleText(event), event_face, BLACK, right - title_x)
                    cursor = cursor + event_h + row_gap
                end
            end
            cursor = cursor + row_gap
        end
    end

    local foot = nil
    if self.error then
        foot = "· " .. tostring(self.error)
    elseif hidden > 0 then
        foot = string.format("+ %d more", hidden)
    end
    if foot then
        block(bb, left, foot_top, foot, foot_face, SOFT, L.w - L.m * 2)
    end
end

function Agenda:repaint(mode)
    UIManager:setDirty(self, function() return mode or "ui", self.dimen end)
end

function Agenda:load(force)
    self.busy = true
    self.error = nil
    self:repaint()
    UIManager:scheduleIn(0.05, function()
        local failure = self:fetch(force)
        self.busy = false
        if failure then
            self.error = failure
            logger.warn("mandragora: agenda:", tostring(failure))
        end
        self:repaint("full")
    end)
end

function Agenda:onTap()
    if self.busy then return true end
    self:load(true)
    return true
end

function Agenda:onDoubleTap()
    return self:onClose()
end

function Agenda:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    return true
end

function Agenda:onClose()
    UIManager:close(self)
    return true
end

function Agenda:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

function Agenda:onShow()
    self:repaint("full")
    return true
end

function Agenda.open()
    local view = Agenda:new{}
    UIManager:show(view)
    view:load(false)
    return view
end

return Agenda
