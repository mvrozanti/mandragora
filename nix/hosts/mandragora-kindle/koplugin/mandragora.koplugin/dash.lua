local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local json = require("json")
local logger = require("logger")

local Screen = Device.screen

local VM_URL = "http://100.115.80.79:8428/api/v1/query"
local PROXY = "http://localhost:1056"
local QUERY = '{__name__=~"up|node_load1|node_memory_MemAvailable_bytes|'
    .. 'node_memory_MemTotal_bytes|node_filesystem_avail_bytes|node_filesystem_size_bytes|'
    .. 'nvidia_smi_utilization_gpu_ratio|nvidia_smi_temperature_gpu|kindle_battery_percent|'
    .. 'kindle_charging|kindle_storage_used_percent|kindle_uptime_seconds|kindle_art_images|'
    .. 'kindle_service_up",mountpoint=~"/|"}'

local REFRESH_SECONDS = 30
local FULL_REFRESH_EVERY = 8

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GREY = Blitbuffer.COLOR_GRAY

local M = 40
local FRAMEWORK_CLOCK_H = 40
local RULE = 3
local PANEL_GAP = 18
local PANEL_BORDER = 2
local BAR_H = 14

local SZ_TITLE = 40
local SZ_SUBTITLE = 11
local SZ_DATE = 13
local SZ_CLOCK = 30
local SZ_HOST = 24
local SZ_DETAIL = 12
local SZ_TAG = 11
local SZ_LABEL = 12
local SZ_VALUE = 28
local SZ_SUB = 11
local SZ_SVC = 12
local SZ_FOOTER = 12

local function face(size, bold)
    return Font:getFace(bold and "smallinfofontbold" or "infont", size)
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

local function fmtUptime(v)
    local s = math.floor(tonumber(v) or 0)
    local d = math.floor(s / 86400); s = s % 86400
    local h = math.floor(s / 3600); s = s % 3600
    local m = math.floor(s / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh%02dm", h, m) end
    return string.format("%dm", m)
end

local Dash = InputContainer:extend{
    metrics = nil,
    fetched_at = nil,
    error = nil,
    paints = 0,
}

function Dash:fetch()
    local cmd = string.format(
        "http_proxy=%s /usr/bin/curl -s --max-time 8 -G %q --data-urlencode 'query=%s' 2>/dev/null",
        PROXY, VM_URL, QUERY)
    local pipe = io.popen(cmd)
    if not pipe then return nil, "popen failed" end
    local body = pipe:read("*a")
    pipe:close()
    if not body or body == "" then return nil, "no response from victoriametrics" end
    local ok, decoded = pcall(json.decode, body)
    if not ok or type(decoded) ~= "table" or not decoded.data then
        return nil, "bad json from victoriametrics"
    end
    local out = {}
    for _, series in ipairs(decoded.data.result or {}) do
        local name = series.metric.__name__
        local inst = series.metric.instance or "-"
        local sub = series.metric.service or series.metric.mountpoint
        local value = tonumber(series.value and series.value[2])
        out[name] = out[name] or {}
        out[name][inst] = out[name][inst] or {}
        if sub then
            out[name][inst][sub] = value
        else
            out[name][inst].value = value
        end
    end
    return out
end

function Dash:get(name, inst, sub)
    local m = self.metrics
    if not m or not m[name] or not m[name][inst] then return nil end
    return m[name][inst][sub or "value"]
end

function Dash:refresh(force_full)
    local metrics, err = self:fetch()
    if metrics then
        self.metrics = metrics
        self.fetched_at = os.time()
        self.error = nil
    else
        self.error = err
    end
    self.paints = self.paints + 1
    local full = force_full or (self.paints % FULL_REFRESH_EVERY == 0)
    UIManager:setDirty(self, function()
        return full and "full" or "partial", self.dimen
    end)
end

function Dash:scheduleRefresh()
    UIManager:unschedule(self.tick)
    self.tick = function()
        if self.closed then return end
        self:refresh(false)
        UIManager:scheduleIn(REFRESH_SECONDS, self.tick)
    end
    UIManager:scheduleIn(REFRESH_SECONDS, self.tick)
end

function Dash:init()
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
    function canvas:paintTo(bb, x, y) Dash.paint(self.owner, bb, x, y) end
    canvas.owner = self
    canvas.dimen = self.dimen
    self[1] = canvas

    self.metrics = self:fetch()
    self.fetched_at = os.time()
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

local function drawTag(bb, right_x, y, text)
    local pad_x, pad_y = 10, 5
    local tw, th = measure(text, SZ_TAG, true)
    local w, h = tw + pad_x * 2, th + pad_y * 2
    local x = right_x - w
    bb:paintRect(x, y, w, h, BLACK)
    drawText(bb, x + pad_x, y + pad_y, text, SZ_TAG, true, WHITE)
    return w, h
end

local function drawBar(bb, x, y, w, h, frac)
    bb:paintRect(x, y, w, h, WHITE)
    bb:paintBorder(x, y, w, h, 2, BLACK)
    if frac and frac > 0 then
        local fill = math.floor((w - 4) * math.min(frac, 1))
        if fill > 0 then bb:paintRect(x + 2, y + 2, fill, h - 4, BLACK) end
    end
end

local function metricHeight()
    local _, lh = measure("X", SZ_LABEL, false)
    local _, vh = measure("0", SZ_VALUE, true)
    local _, sh = measure("x", SZ_SUB, false)
    return lh + 6 + vh + 8 + BAR_H + 6 + sh
end

local function drawMetric(bb, x, y, col_w, m)
    local avail = col_w - 16
    local _, lh = drawText(bb, x, y, m.label:upper(), SZ_LABEL, false, GREY)
    local cursor = y + lh + 6
    local vsize = fitSize(m.value, SZ_VALUE, avail, true)
    local _, vh = drawText(bb, x, cursor, m.value, vsize, true)
    cursor = cursor + vh + 8
    if m.frac then
        drawBar(bb, x, cursor, math.min(avail, 180), BAR_H, m.frac)
    end
    cursor = cursor + BAR_H + 6
    if m.sub then
        drawText(bb, x, cursor, m.sub, SZ_SUB, false, GREY)
    end
end

function Dash:hostPanel(bb, x0, y0, x1, y1, host)
    bb:paintBorder(x0, y0, x1 - x0, y1 - y0, PANEL_BORDER, BLACK)

    local pad = 22
    local _, nh = measure(host.label:upper(), SZ_HOST, true)
    local dot_r = 8
    drawDot(bb, x0 + pad + dot_r, y0 + pad + math.floor(nh / 2), dot_r, host.up)
    drawText(bb, x0 + pad + dot_r * 2 + 12, y0 + pad, host.label:upper(), SZ_HOST, true)
    local _, dh = drawText(bb, x0 + pad + dot_r * 2 + 14, y0 + pad + nh + 2,
        host.detail, SZ_DETAIL, false, GREY)
    drawTag(bb, x1 - pad, y0 + pad, host.up and "ONLINE" or "OFFLINE")

    local n = #host.metrics
    if n == 0 then return end
    local avail = (x1 - x0) - pad * 2
    local col_w = math.floor(avail / n)
    local my = y0 + pad + nh + 2 + dh + 18
    for i, m in ipairs(host.metrics) do
        drawMetric(bb, x0 + pad + (i - 1) * col_w, my, col_w, m)
    end

    if host.services then
        local _, sh = measure("x", SZ_SVC, false)
        local sy = y1 - pad - sh
        local sx = x0 + pad
        for _, svc in ipairs(host.services) do
            drawDot(bb, sx + 6, sy + math.floor(sh / 2), 6, svc.up)
            local w = select(1, drawText(bb, sx + 18, sy, svc.label, SZ_SVC, false))
            sx = sx + 18 + w + 26
        end
    end
end

function Dash:buildHosts()
    local function up(inst, job) return (self:get("up", inst) or 0) >= 1 end

    local d_avail = self:get("node_memory_MemAvailable_bytes", "mandragora-desktop")
    local d_total = self:get("node_memory_MemTotal_bytes", "mandragora-desktop")
    local d_davail = self:get("node_filesystem_avail_bytes", "mandragora-desktop", "/")
    local d_dtotal = self:get("node_filesystem_size_bytes", "mandragora-desktop", "/")
    local d_gpu = self:get("nvidia_smi_utilization_gpu_ratio", "mandragora-desktop")
    local d_temp = self:get("nvidia_smi_temperature_gpu", "mandragora-desktop")
    local d_load = self:get("node_load1", "mandragora-desktop")

    local v_avail = self:get("node_memory_MemAvailable_bytes", "mandragora-vps")
    local v_total = self:get("node_memory_MemTotal_bytes", "mandragora-vps")
    local v_davail = self:get("node_filesystem_avail_bytes", "mandragora-vps", "/")
    local v_dtotal = self:get("node_filesystem_size_bytes", "mandragora-vps", "/")
    local v_load = self:get("node_load1", "mandragora-vps")

    local k_batt = self:get("kindle_battery_percent", "mandragora-kindle")
    local k_chg = self:get("kindle_charging", "mandragora-kindle")
    local k_store = self:get("kindle_storage_used_percent", "mandragora-kindle")
    local k_uptime = self:get("kindle_uptime_seconds", "mandragora-kindle")
    local k_art = self:get("kindle_art_images", "mandragora-kindle")

    local function pct(avail, total)
        if not avail or not total or total == 0 then return nil end
        return 1 - avail / total
    end

    local dm = pct(d_avail, d_total)
    local dd = pct(d_davail, d_dtotal)
    local vm = pct(v_avail, v_total)
    local vd = pct(v_davail, v_dtotal)

    return {
        {
            label = "Desktop",
            detail = "ryzen 9 7900x - rtx 5070 ti",
            up = up("mandragora-desktop"),
            metrics = {
                { label = "Load 1m", value = d_load and string.format("%.1f", d_load) or "--" },
                { label = "Memory used", value = dm and string.format("%d%%", dm * 100) or "--",
                  frac = dm, sub = d_avail and (humanBytes(d_avail) .. " free") or nil },
                { label = "Disk free /", value = d_davail and humanBytes(d_davail) or "--",
                  frac = dd, sub = d_dtotal and ("of " .. humanBytes(d_dtotal)) or nil },
                { label = "GPU", value = d_gpu and string.format("%d%%", d_gpu * 100) or "--",
                  sub = d_temp and string.format("%d C", d_temp) or nil },
            },
        },
        {
            label = "VPS",
            detail = "oracle cloud - mandragora-vps",
            up = up("mandragora-vps"),
            metrics = {
                { label = "Load 1m", value = v_load and string.format("%.1f", v_load) or "--" },
                { label = "Memory used", value = vm and string.format("%d%%", vm * 100) or "--",
                  frac = vm, sub = v_avail and (humanBytes(v_avail) .. " free") or nil },
                { label = "Disk free /", value = v_davail and humanBytes(v_davail) or "--",
                  frac = vd, sub = v_dtotal and ("of " .. humanBytes(v_dtotal)) or nil },
            },
        },
        {
            label = "Kindle",
            detail = "paperwhite 12 - tailnet",
            up = up("mandragora-kindle"),
            metrics = {
                { label = "Battery", value = k_batt and string.format("%d%%", k_batt) or "--",
                  frac = k_batt and k_batt / 100 or nil,
                  sub = (k_chg or 0) >= 1 and "charging" or "on battery" },
                { label = "Storage used", value = k_store and string.format("%d%%", k_store) or "--",
                  frac = k_store and k_store / 100 or nil },
                { label = "Uptime", value = k_uptime and fmtUptime(k_uptime) or "--" },
                { label = "Art images", value = k_art and string.format("%d", k_art) or "--" },
            },
            services = {
                { label = "dropbear", up = (self:get("kindle_service_up", "mandragora-kindle", "dropbear") or 0) >= 1 },
                { label = "koreader", up = (self:get("kindle_service_up", "mandragora-kindle", "koreader") or 0) >= 1 },
                { label = "tailscaled", up = (self:get("kindle_service_up", "mandragora-kindle", "tailscaled") or 0) >= 1 },
            },
        },
    }
end

function Dash:paint(bb, ox, oy)
    local W, H = Screen:getWidth(), Screen:getHeight()
    bb:paintRect(ox, oy, W, H, WHITE)

    local right = W - M
    local date_str = os.date("%d %b %Y"):upper()
    local time_str = os.date("%H:%M")

    local top_y = M + FRAMEWORK_CLOCK_H
    local tsize = fitSize("MANDRAGORA", SZ_TITLE, W * 0.52, true)
    local _, th = drawText(bb, M, top_y, "MANDRAGORA", tsize, true)
    local _, sh = drawText(bb, M + 2, top_y + th + 4, "E-INK DASHBOARD", SZ_SUBTITLE, false, GREY)

    local _, dh = drawRightText(bb, right, top_y, date_str, SZ_DATE, false)
    local _, clh = drawRightText(bb, right, top_y + dh + 4, time_str, SZ_CLOCK, true)

    local head_bottom = math.max(top_y + th + 4 + sh, top_y + dh + 4 + clh)
    local rule_y = head_bottom + 18
    bb:paintRect(M, rule_y, W - M * 2, RULE, BLACK)

    local _, fh = measure("X", SZ_FOOTER, false)
    local footer_y = H - M - fh - 14

    local top = rule_y + RULE + 22
    local usable = footer_y - top - 22
    local panel_h = math.floor((usable - PANEL_GAP * 2) / 3)

    local hosts = self:buildHosts()
    for i, host in ipairs(hosts) do
        local y0 = top + (i - 1) * (panel_h + PANEL_GAP)
        self:hostPanel(bb, M, y0, W - M, y0 + panel_h, host)
    end

    bb:paintRect(M, footer_y, W - M * 2, 2, BLACK)
    drawText(bb, M, footer_y + 12, "MANDRAGORA > TAILNET STATUS", SZ_FOOTER, false, GREY)
    local stamp
    if self.error then
        stamp = "stale - " .. self.error
    else
        stamp = "updated " .. os.date("%H:%M:%S", self.fetched_at)
    end
    drawRightText(bb, right, footer_y + 12, stamp, SZ_FOOTER, false)
end

function Dash:onTap()
    self:refresh(true)
    return true
end

function Dash:onDoubleTap()
    return self:onClose()
end

function Dash:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    return true
end

function Dash:onClose()
    self.closed = true
    UIManager:unschedule(self.tick)
    UIManager:close(self)
    return true
end

function Dash:onCloseWidget()
    self.closed = true
    UIManager:unschedule(self.tick)
    UIManager:setDirty(nil, "full")
end

function Dash:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    self:scheduleRefresh()
    return true
end

function Dash.open()
    local viewer = Dash:new{}
    if viewer.error then logger.warn("mandragora: dash: " .. viewer.error) end
    UIManager:show(viewer)
    return viewer
end

return Dash
