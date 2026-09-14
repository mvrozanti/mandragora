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

local CONFIG_PATH = "/mnt/us/mandragora/ticker.conf"
local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local RULE = Blitbuffer.COLOR_LIGHT_GRAY

local DEFAULTS = {
    host = "192.168.0.27",
    port = 6614,
    timeout = 25,
}

local Ticker = InputContainer:extend{
    rows = nil,
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

local function query(cfg, verb)
    local ok, socket = pcall(require, "socket")
    if not ok or not socket then return nil, "no luasocket" end
    local sock = socket.tcp()
    if not sock then return nil, "no socket" end
    sock:settimeout(cfg.timeout)
    local connected, cerr = sock:connect(cfg.host, cfg.port)
    if not connected then
        sock:close()
        return nil, cerr or "connect failed"
    end
    sock:send(verb .. "\n")

    local rows, age = {}, nil
    local failure = nil
    while true do
        local line, rerr = sock:receive("*l")
        if not line then
            failure = rerr or "connection closed"
            break
        end
        if line == "END" then break end
        local a = line:match("^AGE%s+(%d+)$")
        if a then
            age = tonumber(a)
        elseif line:match("^ERR%s") then
            failure = failure or line:sub(5)
        else
            local key, price, change, label = line:match("^Q%s+(%S+)%s+(%S+)%s+(%S+)%s+(.*)$")
            if key then
                rows[#rows + 1] = { key = key, price = price, change = change, label = label }
            end
        end
    end
    sock:send("QUIT\n")
    sock:close()
    if #rows == 0 then return nil, failure or "no quotes" end
    return rows, nil, age, failure
end

function Ticker:layout()
    local w, h = Screen:getWidth(), Screen:getHeight()
    local margin = math.floor(w * 0.026)
    local head_h = math.floor(h * 0.082)
    local foot_h = math.floor(h * 0.052)
    local body = h - head_h - foot_h
    return {
        w = w, h = h,
        margin = margin,
        head_h = head_h,
        foot_h = foot_h,
        body_y = head_h,
        row_h = math.floor(body / 16),
    }
end

function Ticker:init()
    self.L = self:layout()
    self.cfg = readConfig()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.L.w, h = self.L.h }
    self.covers_fullscreen = true
    self.rows = self.rows or {}

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

function Ticker:fetch(force)
    self.busy = true
    self.error = nil
    self:repaint()
    UIManager:scheduleIn(0.05, function()
        local rows, err, age, partial = query(self.cfg, force and "REFRESH" or "QUOTES")
        self.busy = false
        if rows then
            self.rows = rows
            self.age = age
            self.error = partial
        else
            self.error = err
            logger.warn("mandragora: ticker:", tostring(err))
        end
        self:repaint("full")
    end)
end

function Ticker:headline()
    if self.busy then return "markets · fetching" end
    if self.error and #self.rows == 0 then return "markets · unreachable" end
    if self.age == nil then return "markets" end
    if self.age < 60 then return "markets · just now" end
    return string.format("markets · %d min old", math.floor(self.age / 60))
end

function Ticker:paintTo(bb, x, y)
    local L = self.L
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, L.w, L.h, WHITE)

    local head = TextWidget:new{
        text = self:headline(),
        face = Font:getFace("tfont", math.floor(L.head_h * 0.38)),
    }
    head:paintTo(bb, x + L.margin, y + math.floor(L.head_h * 0.22))
    head:free()

    local sym_face = Font:getFace("tfont", math.floor(L.row_h * 0.40))
    local label_face = Font:getFace("infofont", math.floor(L.row_h * 0.23))
    local num_face = Font:getFace("tfont", math.floor(L.row_h * 0.36))
    local chg_face = Font:getFace("infofont", math.floor(L.row_h * 0.29))

    for i, row in ipairs(self.rows) do
        local top = y + L.body_y + (i - 1) * L.row_h
        if i > 1 then
            bb:paintRect(x + L.margin, top, L.w - L.margin * 2, 1, RULE)
        end

        local sym = TextWidget:new{ text = row.key, face = sym_face }
        sym:paintTo(bb, x + L.margin, top + math.floor(L.row_h * 0.16))
        local sym_w = sym:getSize().w
        sym:free()

        local label = TextWidget:new{ text = row.label or "", face = label_face }
        label:paintTo(bb, x + L.margin + sym_w + math.floor(L.margin * 0.7),
                          top + math.floor(L.row_h * 0.34))
        label:free()

        local chg = TextWidget:new{
            text = (row.change ~= "-" and row.change .. "%" or "—"),
            face = chg_face,
        }
        local chg_w = chg:getSize().w
        chg:paintTo(bb, x + L.w - L.margin - chg_w, top + math.floor(L.row_h * 0.26))
        chg:free()

        local price = TextWidget:new{ text = row.price, face = num_face }
        local price_w = price:getSize().w
        price:paintTo(bb, x + L.w - L.margin - math.floor(L.w * 0.16) - price_w,
                          top + math.floor(L.row_h * 0.18))
        price:free()
    end

    local foot_text = self.error and ("· " .. tostring(self.error))
        or "tap to refresh · double-tap to close"
    local foot = TextWidget:new{
        text = foot_text,
        face = Font:getFace("infofont", math.floor(L.foot_h * 0.40)),
    }
    foot:paintTo(bb, x + L.margin, y + L.h - L.foot_h + math.floor(L.foot_h * 0.18))
    foot:free()
end

function Ticker:repaint(mode)
    UIManager:setDirty(self, function() return mode or "ui", self.dimen end)
end

function Ticker:onTap()
    if self.busy then return true end
    self:fetch(true)
    return true
end

function Ticker:onDoubleTap()
    return self:onClose()
end

function Ticker:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    return true
end

function Ticker:onClose()
    UIManager:close(self)
    return true
end

function Ticker:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

function Ticker:onShow()
    self:repaint("full")
    return true
end

function Ticker.open()
    local view = Ticker:new{}
    UIManager:show(view)
    view:fetch(false)
    return view
end

return Ticker
