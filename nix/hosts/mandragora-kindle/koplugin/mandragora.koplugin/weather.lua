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

local CONFIG_PATH = "/mnt/us/mandragora/weather.conf"
local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local MID = Blitbuffer.COLOR_LIGHT_GRAY
local SOFT = Blitbuffer.COLOR_GRAY

local DEFAULTS = { host = "192.168.0.27", port = 6615, timeout = 25 }

local Weather = InputContainer:extend{
    now = nil,
    days = nil,
    age = nil,
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

function Weather:fetch(force)
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

    local now, days, age, failure = nil, {}, nil, nil
    while true do
        local line, rerr = sock:receive("*l")
        if not line then
            failure = failure or rerr or "connection closed"
            break
        end
        if line == "END" then break end
        local a = line:match("^AGE%s+(%d+)$")
        local err = line:match("^ERR%s+(.*)$")
        if a then
            age = tonumber(a)
        elseif err then
            failure = failure or err
        else
            local temp, feels, desc = line:match("^CUR%s+(%S+)%s+(%S+)%s+(.*)$")
            if temp then
                now = now or {}
                now.temp, now.feels, now.desc = temp, feels, desc
            else
                local hum, wind, place = line:match("^EXTRA%s+(%S+)%s+(%S+)%s+(.*)$")
                if hum then
                    now = now or {}
                    now.humidity, now.wind, now.place = hum, wind, place
                else
                    local label, lo, hi, dd = line:match("^D%s+(%S+)%s+(%S+)%s+(%S+)%s+(.*)$")
                    if label then
                        days[#days + 1] = { label = label, lo = lo, hi = hi, desc = dd }
                    end
                end
            end
        end
    end
    sock:send("QUIT\n")
    sock:close()

    if now or #days > 0 then
        self.now, self.days, self.age = now, days, age
        return failure
    end
    return failure or "no data"
end

function Weather:layout()
    local w, h = Screen:getWidth(), Screen:getHeight()
    return {
        w = w, h = h,
        m = math.floor(w * 0.030),
        top = math.floor(h * 0.030),
        gap = math.floor(h * 0.013),
    }
end

function Weather:init()
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

local function text(bb, x, y, str, face, fg)
    local widget = TextWidget:new{ text = str, face = face, fgcolor = fg }
    widget:paintTo(bb, x, y)
    local size = widget:getSize()
    widget:free()
    return size.w, size.h
end

local function textRight(bb, right, y, str, face, fg)
    local widget = TextWidget:new{ text = str, face = face, fgcolor = fg }
    local size = widget:getSize()
    widget:paintTo(bb, right - size.w, y)
    widget:free()
end

function Weather:ageText()
    if self.busy then return "fetching" end
    if self.error and not self.now then return "unreachable" end
    if self.age == nil then return "" end
    if self.age < 120 then return "just now" end
    return string.format("%d min old", math.floor(self.age / 60))
end

local function block(bb, x, y, str, face, fg)
    local widget = TextWidget:new{ text = str, face = face, fgcolor = fg }
    local size = widget:getSize()
    widget:paintTo(bb, x, y)
    widget:free()
    return size.h, size.w
end

function Weather:paintTo(bb, x, y)
    local L = self.L
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, L.w, L.h, WHITE)

    local left = x + L.m
    local right = x + L.w - L.m
    local cursor = y + L.top

    local title = TextWidget:new{ text = "weather", face = Font:getFace("tfont", 40) }
    local title_size = title:getSize()
    title:paintTo(bb, left, cursor)
    title:free()

    local age = TextWidget:new{
        text = self:ageText(), face = Font:getFace("infofont", 26), fgcolor = SOFT,
    }
    local age_size = age:getSize()
    age:paintTo(bb, right - age_size.w, cursor + title_size.h - age_size.h - 4)
    age:free()
    cursor = cursor + title_size.h + L.gap

    local foot = TextWidget:new{
        text = self.error and ("· " .. tostring(self.error))
            or "tap to refresh · double-tap to close",
        face = Font:getFace("infofont", 28), fgcolor = SOFT,
    }
    local foot_size = foot:getSize()
    local foot_top = y + L.h - L.m - foot_size.h
    foot:paintTo(bb, left, foot_top)
    foot:free()

    if not self.now then
        cursor = cursor + math.floor(L.h * 0.28)
        cursor = cursor + block(bb, left, cursor, "no forecast", Font:getFace("tfont", 58), BLACK)
        cursor = cursor + L.gap
        block(bb, left, cursor, self.cfg.host .. ":" .. self.cfg.port .. " did not answer",
            Font:getFace("infofont", 30), SOFT)
        return
    end

    cursor = cursor + block(bb, left, cursor, self.now.place or "",
        Font:getFace("infofont", 30), SOFT) + math.floor(L.gap * 0.5)
    cursor = cursor + block(bb, left, cursor, (self.now.temp or "-") .. "°",
        Font:getFace("tfont", 150), BLACK)
    cursor = cursor + block(bb, left, cursor, self.now.desc or "",
        Font:getFace("tfont", 44), BLACK) + math.floor(L.gap * 0.4)
    cursor = cursor + block(bb, left, cursor,
        string.format("feels %s°   humidity %s%%   wind %s m/s",
            self.now.feels or "-", self.now.humidity or "-", self.now.wind or "-"),
        Font:getFace("infofont", 30), SOFT) + L.gap

    bb:paintRect(left, cursor, L.w - L.m * 2, 2, MID)
    cursor = cursor + L.gap

    local count = #self.days
    if count == 0 then return end
    local room = foot_top - cursor - L.gap
    local row_h = math.floor(room / count)

    local day_face = Font:getFace("tfont", 40)
    local desc_face = Font:getFace("infofont", 28)
    local desc_x = left + math.floor(L.w * 0.16)
    for i, day in ipairs(self.days) do
        local top = cursor + (i - 1) * row_h
        if i > 1 then
            bb:paintRect(left, top - math.floor(L.gap * 0.5), L.w - L.m * 2, 1, MID)
        end
        local dw = TextWidget:new{ text = day.label, face = day_face }
        local ds = dw:getSize()
        local mid_y = top + math.floor((row_h - ds.h) / 2)
        dw:paintTo(bb, left, mid_y)
        dw:free()

        local cw = TextWidget:new{ text = day.desc or "", face = desc_face, fgcolor = SOFT }
        local cs = cw:getSize()
        cw:paintTo(bb, desc_x, top + math.floor((row_h - cs.h) / 2))
        cw:free()

        local rw = TextWidget:new{
            text = (day.lo or "-") .. "° / " .. (day.hi or "-") .. "°", face = day_face,
        }
        local rs = rw:getSize()
        rw:paintTo(bb, right - rs.w, mid_y)
        rw:free()
    end
end

function Weather:repaint(mode)
    UIManager:setDirty(self, function() return mode or "ui", self.dimen end)
end

function Weather:load(force)
    self.busy = true
    self.error = nil
    self:repaint()
    UIManager:scheduleIn(0.05, function()
        local failure = self:fetch(force)
        self.busy = false
        if failure then
            self.error = failure
            logger.warn("mandragora: weather:", tostring(failure))
        end
        self:repaint("full")
    end)
end

function Weather:onTap()
    if self.busy then return true end
    self:load(true)
    return true
end

function Weather:onDoubleTap()
    return self:onClose()
end

function Weather:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    return true
end

function Weather:onClose()
    UIManager:close(self)
    return true
end

function Weather:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

function Weather:onShow()
    self:repaint("full")
    return true
end

function Weather.open()
    local view = Weather:new{}
    UIManager:show(view)
    view:load(false)
    return view
end

return Weather
