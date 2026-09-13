local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetInfo = require("ffi/netinfo")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local util = require("ffi/util")
local logger = require("logger")

local Screen = Device.screen

local ROOT = "/mnt/us/mandragora"
local TS_BIN = ROOT .. "/bin/tailscale"
local TS_SOCK = ROOT .. "/state/tailscaled.sock"
local DROPBEAR_BIN = ROOT .. "/bin/dropbear"
local TAILSCALED_BIN = ROOT .. "/bin/tailscaled"
local VERSION_FILE = "/etc/version.txt"
local STORAGE_PATH = "/mnt/us"
local POWER_SUPPLY_DIR = "/sys/class/power_supply"
local WLAN_IFACE = "wlan0"

local REFRESH_SECONDS = 20
local FULL_REFRESH_EVERY = 6

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GREY = Blitbuffer.COLOR_GRAY

local M = 40
local FRAMEWORK_CLOCK_H = 40
local RULE = 3
local ROW_GAP = 30
local DIVIDER_GAP = 26
local BAR_H = 16

local SZ_TITLE = 40
local SZ_SUBTITLE = 11
local SZ_DATE = 13
local SZ_CLOCK = 30
local SZ_LABEL = 16
local SZ_VALUE = 36
local SZ_SUB = 15
local SZ_SVC = 18
local SZ_FOOTER = 12

local function face(size, bold)
    return Font:getFace(bold and "smallinfofontbold" or "infont", size)
end

local function measure(text, size, bold)
    local w = TextWidget:new{ text = tostring(text), face = face(size, bold), bold = bold or false }
    local sz = w:getSize()
    w:free()
    return sz.w, sz.h
end

local function drawText(bb, x, y, text, size, bold, fg)
    local w = TextWidget:new{
        text = tostring(text),
        face = face(size, bold),
        bold = bold or false,
        fgcolor = fg or BLACK,
    }
    w:paintTo(bb, x, y)
    local sz = w:getSize()
    w:free()
    return sz.w, sz.h
end

local function drawRightText(bb, right_x, y, text, size, bold, fg)
    local w, h = measure(text, size, bold)
    drawText(bb, right_x - w, y, text, size, bold, fg)
    return w, h
end

local function fitSize(text, size, max_w, bold)
    local s = size
    while s > 8 do
        local w = measure(text, s, bold)
        if w <= max_w then return s end
        s = s - 1
    end
    return 8
end

local function drawDot(bb, cx, cy, r, filled)
    bb:paintCircle(cx, cy, r, BLACK)
    if not filled then bb:paintCircle(cx, cy, r - 2, WHITE) end
end

local function drawBar(bb, x, y, w, h, frac)
    bb:paintRect(x, y, w, h, WHITE)
    bb:paintBorder(x, y, w, h, 2, BLACK)
    if frac and frac > 0 then
        local fill = math.floor((w - 4) * math.min(frac, 1))
        if fill > 0 then bb:paintRect(x + 2, y + 2, fill, h - 4, BLACK) end
    end
end

local function humanBytes(v)
    local units = { "B", "K", "M", "G", "T", "P" }
    local n = tonumber(v) or 0
    local i = 1
    while n >= 1024 and i < #units do
        n = n / 1024
        i = i + 1
    end
    if n >= 100 or n == math.floor(n) then
        return string.format("%d%s", n, units[i])
    end
    return string.format("%.1f%s", n, units[i])
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function firstLine(text)
    if not text then return nil end
    return text:match("([^\r\n]*)")
end

local function firmwareVersion()
    local line = firstLine(readFile(VERSION_FILE))
    if not line then return nil end
    return line:match("Version:%s*(.-)%s*$") or line
end

local function batteryInfo()
    local ok, iter, dir_obj = pcall(lfs.dir, POWER_SUPPLY_DIR)
    if not ok then return nil end
    for name in iter, dir_obj do
        if name ~= "." and name ~= ".." then
            local base = POWER_SUPPLY_DIR .. "/" .. name
            local kind = firstLine(readFile(base .. "/type"))
            if kind == "Battery" then
                local pct = tonumber(firstLine(readFile(base .. "/capacity")))
                local status = firstLine(readFile(base .. "/status"))
                return pct, status
            end
        end
    end
    return nil
end

local function wlanInfo()
    local ok, ni = pcall(NetInfo.new, NetInfo)
    if not ok or not ni then return nil end
    local ok2, ifaces = pcall(ni.retrieve, ni)
    ni:free()
    if not ok2 or not ifaces then return nil end
    for _, iface in ipairs(ifaces) do
        if iface.name == WLAN_IFACE then
            return iface.ipv4, iface.ssid
        end
    end
    return nil
end

local function processRunning(match)
    local ok, iter, dir_obj = pcall(lfs.dir, "/proc")
    if not ok then return false end
    for name in iter, dir_obj do
        if name:match("^%d+$") then
            local cmd = readFile("/proc/" .. name .. "/cmdline")
            if cmd and cmd:find(match, 1, true) then
                return true
            end
        end
    end
    return false
end

local function tailscaleInfo()
    local cmd = TS_BIN .. " --socket=" .. TS_SOCK .. " status --json 2>/dev/null"
    local pipe = io.popen(cmd)
    if not pipe then return nil end
    local body = pipe:read("*a")
    pipe:close()
    if not body or body == "" then return nil end
    local ok, decoded = pcall(json.decode, body)
    if not ok or type(decoded) ~= "table" then return nil end
    local ip = decoded.TailscaleIPs and decoded.TailscaleIPs[1]
    local online = decoded.Self and decoded.Self.Online
    local backend = decoded.BackendState
    return ip, online, backend
end

local Status = InputContainer:extend{
    info = nil,
    fetched_at = nil,
    error = nil,
    paints = 0,
}

function Status:gather()
    local info = {}
    info.fw = firmwareVersion()
    info.wlan_ip, info.wlan_ssid = wlanInfo()
    info.ts_ip, info.ts_online, info.ts_backend = tailscaleInfo()
    info.batt_pct, info.batt_status = batteryInfo()
    local ok, total, free = pcall(util.df, STORAGE_PATH)
    if ok then
        info.storage_total = total
        info.storage_free = free
    end
    info.dropbear_up = processRunning(DROPBEAR_BIN)
    info.tailscaled_up = processRunning(TAILSCALED_BIN)
    return info
end

function Status:buildRows()
    local info = self.info or {}

    local ts_value = info.ts_ip or "not joined"
    local ts_sub
    if info.ts_ip then
        if info.ts_online == false then
            ts_sub = "offline"
        elseif info.ts_backend and info.ts_backend ~= "Running" then
            ts_sub = info.ts_backend:lower()
        else
            ts_sub = "online"
        end
    elseif info.ts_backend then
        ts_sub = info.ts_backend:lower()
    end

    local batt_value = info.batt_pct and (info.batt_pct .. "%") or "--"
    local batt_frac = info.batt_pct and (info.batt_pct / 100) or nil
    local batt_sub = info.batt_status and info.batt_status:lower() or nil

    local storage_value = info.storage_free and (humanBytes(info.storage_free) .. " free") or "--"
    local storage_frac, storage_sub
    if info.storage_total and info.storage_free and info.storage_total > 0 then
        storage_frac = 1 - (info.storage_free / info.storage_total)
        storage_sub = "of " .. humanBytes(info.storage_total)
    end

    return {
        { label = "Firmware", value = info.fw or "unknown" },
        { label = "WLAN", value = info.wlan_ip or "disconnected",
          sub = info.wlan_ssid and ("ssid " .. info.wlan_ssid) or nil },
        { label = "Tailnet", value = ts_value, sub = ts_sub },
        { label = "Battery", value = batt_value, frac = batt_frac, sub = batt_sub },
        { label = "Storage free", value = storage_value, frac = storage_frac, sub = storage_sub },
        { label = "Services", services = {
            { label = "dropbear", up = info.dropbear_up },
            { label = "tailscaled", up = info.tailscaled_up },
        } },
    }
end

local function drawRow(bb, x, y, w, row)
    local cursor = y
    local _, lh = drawText(bb, x, cursor, row.label:upper(), SZ_LABEL, false, GREY)
    cursor = cursor + lh + 10

    if row.services then
        local _, sh = measure("X", SZ_SVC, false)
        local dot_r = 9
        local sx = x
        for _, svc in ipairs(row.services) do
            drawDot(bb, sx + dot_r, cursor + math.floor(sh / 2), dot_r, svc.up)
            local wlabel = select(1, drawText(bb, sx + dot_r * 2 + 12, cursor, svc.label, SZ_SVC, false))
            sx = sx + dot_r * 2 + 12 + wlabel + 40
        end
        cursor = cursor + sh
        return cursor
    end

    local vsize = fitSize(row.value, SZ_VALUE, w, true)
    local _, vh = drawText(bb, x, cursor, row.value, vsize, true)
    cursor = cursor + vh + 8

    if row.frac then
        drawBar(bb, x, cursor, math.min(w, 420), BAR_H, row.frac)
        cursor = cursor + BAR_H + 10
    end

    if row.sub then
        local _, subh = drawText(bb, x, cursor, row.sub, SZ_SUB, false, GREY)
        cursor = cursor + subh
    end

    return cursor
end

function Status:refresh(force_full)
    local ok, info = pcall(Status.gather, self)
    if ok then
        self.info = info
        self.fetched_at = os.time()
        self.error = nil
    else
        self.error = tostring(info)
    end
    self.paints = self.paints + 1
    local full = force_full or (self.paints % FULL_REFRESH_EVERY == 0)
    UIManager:setDirty(self, function()
        return full and "full" or "partial", self.dimen
    end)
end

function Status:scheduleRefresh()
    UIManager:unschedule(self.tick)
    self.tick = function()
        if self.closed then return end
        self:refresh(false)
        UIManager:scheduleIn(REFRESH_SECONDS, self.tick)
    end
    UIManager:scheduleIn(REFRESH_SECONDS, self.tick)
end

function Status:init()
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

    local canvas = Widget:extend{}
    function canvas:paintTo(bb, x, y) Status.paint(self.owner, bb, x, y) end
    canvas.owner = self
    canvas.dimen = self.dimen
    self[1] = canvas

    local ok, info = pcall(Status.gather, self)
    if ok then
        self.info = info
    else
        self.error = tostring(info)
    end
    self.fetched_at = os.time()
end

function Status:paint(bb, ox, oy)
    local W, H = Screen:getWidth(), Screen:getHeight()
    bb:paintRect(ox, oy, W, H, WHITE)

    local right = W - M
    local date_str = os.date("%d %b %Y"):upper()
    local time_str = os.date("%H:%M")

    local top_y = M + FRAMEWORK_CLOCK_H
    local tsize = fitSize("MANDRAGORA", SZ_TITLE, W * 0.52, true)
    local _, th = drawText(bb, M, top_y, "MANDRAGORA", tsize, true)
    local _, sh = drawText(bb, M + 2, top_y + th + 4, "DEVICE STATUS", SZ_SUBTITLE, false, GREY)

    local _, dh = drawRightText(bb, right, top_y, date_str, SZ_DATE, false)
    local _, clh = drawRightText(bb, right, top_y + dh + 4, time_str, SZ_CLOCK, true)

    local head_bottom = math.max(top_y + th + 4 + sh, top_y + dh + 4 + clh)
    local rule_y = head_bottom + 18
    bb:paintRect(M, rule_y, W - M * 2, RULE, BLACK)

    local _, fh = measure("X", SZ_FOOTER, false)
    local footer_y = H - M - fh - 14

    local rows = self:buildRows()
    local y = rule_y + RULE + 34
    local row_w = W - M * 2
    for i, row in ipairs(rows) do
        y = drawRow(bb, M, y, row_w, row)
        if i < #rows then
            y = y + DIVIDER_GAP
            bb:paintRect(M, y, row_w, 1, GREY)
            y = y + ROW_GAP - DIVIDER_GAP
        end
    end

    bb:paintRect(M, footer_y, W - M * 2, 2, BLACK)
    drawText(bb, M, footer_y + 12, "MANDRAGORA > DEVICE STATUS", SZ_FOOTER, false, GREY)
    local stamp
    if self.error then
        stamp = "stale - " .. self.error
    else
        stamp = "updated " .. os.date("%H:%M:%S", self.fetched_at)
    end
    drawRightText(bb, right, footer_y + 12, stamp, SZ_FOOTER, false)
end

function Status:onTap()
    self:refresh(true)
    return true
end

function Status:onDoubleTap()
    return self:onClose()
end

function Status:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    return true
end

function Status:onClose()
    self.closed = true
    UIManager:unschedule(self.tick)
    UIManager:close(self)
    return true
end

function Status:onCloseWidget()
    self.closed = true
    UIManager:unschedule(self.tick)
    UIManager:setDirty(nil, "full")
end

function Status:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    self:scheduleRefresh()
    return true
end

function Status.open()
    local viewer = Status:new{}
    if viewer.error then logger.warn("mandragora: status: " .. viewer.error) end
    UIManager:show(viewer)
    return viewer
end

return Status
