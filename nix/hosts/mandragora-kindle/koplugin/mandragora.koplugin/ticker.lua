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

local DP = Screen:scaleBySize(10000) / 10000
local function face(name, size)
    local px = math.floor(size / DP + 0.5)
    if px < 1 then px = 1 end
    return Font:getFace(name, px)
end

local CONFIG_PATH = "/mnt/us/mandragora/ticker.conf"
local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local HAIR = Blitbuffer.COLOR_LIGHT_GRAY
local MID = Blitbuffer.COLOR_GRAY
local SOFT = Blitbuffer.COLOR_GRAY

local RANGES = { { "1W", 7 }, { "1M", 22 }, { "3M", 66 }, { "6M", 130 } }
local FULL_BARS = 130
local GRID_BARS = 30
local MIN_BODY = 5
local MAX_BODY = 26
local GHOST_EVERY = 8

local DEFAULTS = { host = "192.168.0.27", port = 6614, timeout = 30 }

local Ticker = InputContainer:extend{
    quotes = nil,
    bars = nil,
    full = nil,
    sel = 1,
    tf = 2,
    mode = "chart",
    age = nil,
    error = nil,
    busy = false,
    since_flash = 0,
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

local function talk(cfg, verb, consume)
    local ok, socket = pcall(require, "socket")
    if not ok or not socket then return "no luasocket" end
    local sock = socket.tcp()
    if not sock then return "no socket" end
    sock:settimeout(math.min(5, cfg.timeout))
    local connected, cerr = sock:connect(cfg.host, cfg.port)
    if not connected then
        sock:close()
        return cerr or "connect failed"
    end
    sock:settimeout(cfg.timeout)
    sock:send(verb .. "\n")
    local failure = nil
    while true do
        local line, rerr = sock:receive("*l")
        if not line then
            failure = failure or rerr or "connection closed"
            break
        end
        if line == "END" then break end
        local err = line:match("^ERR%s+(.*)$")
        if err then
            failure = failure or err
        else
            consume(line)
        end
    end
    sock:send("QUIT\n")
    sock:close()
    return failure
end

function Ticker:loadQuotes(force)
    local rows, age = {}, nil
    local failure = talk(self.cfg, force and "REFRESH" or "QUOTES", function(line)
        local a = line:match("^AGE%s+(%d+)$")
        if a then
            age = tonumber(a)
            return
        end
        local key, price, change, label = line:match("^Q%s+(%S+)%s+(%S+)%s+(%S+)%s+(.*)$")
        if key then
            rows[#rows + 1] = { key = key, price = price, change = change, label = label }
        end
    end)
    if #rows > 0 then
        self.quotes = rows
        self.age = age
    end
    return failure
end

function Ticker:loadCandles(target, count)
    local current, got = nil, {}
    local failure = talk(self.cfg, "CANDLES " .. target .. " " .. count, function(line)
        local key = line:match("^K%s+(%S+)%s+%d+$")
        if key then
            current = key
            got[key] = {}
            return
        end
        if not current then return end
        local t, o, h, l, c = line:match("^C%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
        if t then
            local bar = got[current]
            bar[#bar + 1] = { tonumber(o), tonumber(h), tonumber(l), tonumber(c) }
        end
    end)
    local full = count >= FULL_BARS
    for key, series in pairs(got) do
        if #series > 0 then
            local have = self.bars[key]
            if full or not have or #series >= #have then
                self.bars[key] = series
            end
            if full then self.full[key] = true end
        end
    end
    return failure
end

function Ticker:current()
    return self.quotes and self.quotes[self.sel] or nil
end

function Ticker:layout()
    local w, h = Screen:getWidth(), Screen:getHeight()
    local m = math.floor(w * 0.027)
    local head_h = math.floor(h * 0.10)
    local side_w = math.floor(w * 0.30)
    local gap = math.floor(w * 0.012)
    local side_bottom = math.floor(h * 0.93)
    local chart_x = m + side_w + gap
    local chart_y = head_h + 12
    local chart_h = side_bottom - chart_y
    return {
        w = w, h = h, m = m,
        head_key_y = 30, head_label_y = 116,
        price_y = 30, change_y = 116,
        side_x = m, side_w = side_w,
        side_top = head_h, side_bottom = side_bottom,
        chart_x = chart_x, chart_y = chart_y,
        chart_w = w - chart_x - m, chart_h = chart_h,
        tf_x = chart_x + 10, tf_y = chart_y + 10, tf_w = 88, tf_h = 50, tf_gap = 8,
        all_w = 88, all_h = 50,
        ohlc_y = chart_y + chart_h - 46,
        foot_y = h - math.floor(h * 0.032),
    }
end

function Ticker:init()
    self.L = self:layout()
    self.cfg = readConfig()
    self.bars = self.bars or {}
    self.full = self.full or {}
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

local function money(v)
    if not v then return "-" end
    local a = math.abs(v)
    if a >= 1000 then
        local whole = string.format("%d", math.floor(v + 0.5))
        local sign = ""
        if whole:sub(1, 1) == "-" then sign, whole = "-", whole:sub(2) end
        local out = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        out = out:gsub("^,", "")
        return sign .. out
    end
    if a >= 100 then return string.format("%.1f", v) end
    if a >= 1 then return string.format("%.2f", v) end
    return string.format("%.4f", v)
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
    return size.w
end

local function measure(str, face)
    local widget = TextWidget:new{ text = str, face = face }
    local size = widget:getSize()
    widget:free()
    return size.w, size.h
end

function Ticker:drawCandles(bb, x, y, w, h, series, opts)
    if not series or #series < 2 then
        text(bb, x, y + math.floor(h / 2), "no candles yet", face("infofont", 30), SOFT)
        return
    end
    local lo, hi = series[1][3], series[1][2]
    for i = 1, #series do
        if series[i][3] < lo then lo = series[i][3] end
        if series[i][2] > hi then hi = series[i][2] end
    end
    local pad = (hi - lo) * 0.08
    if pad <= 0 then pad = math.max(hi * 0.001, 0.0001) end
    local top, bottom = hi + pad, lo - pad
    local span = top - bottom
    if span <= 0 then return end

    if opts and opts.grid then
        for i = 0, 3 do
            local gy = y + math.floor(h / 3 * i)
            bb:paintRect(x, gy, w, 2, HAIR)
            if opts.axis then
                local widget = TextWidget:new{
                    text = money(top - span * (i / 3)),
                    face = face("infofont", 24),
                    fgcolor = SOFT,
                }
                local size = widget:getSize()
                bb:paintRect(x + w - size.w - 10, gy - size.h - 5, size.w + 10, size.h + 5, WHITE)
                widget:paintTo(bb, x + w - size.w - 5, gy - size.h - 3)
                widget:free()
            end
        end
    end

    local slot = w / #series
    local body = math.floor(slot * 0.62)
    if body < MIN_BODY then body = MIN_BODY end
    if body > MAX_BODY then body = MAX_BODY end
    local edge = math.floor(body * 0.22)
    if edge < 1 then edge = 1 end
    if edge > 3 then edge = 3 end
    if body - edge * 2 < 2 then edge = 1 end
    local wick = math.max(2, math.floor(body * 0.18))
    local function ypos(v) return y + h - math.floor((v - bottom) / span * h) end

    for i = 1, #series do
        local o, high, low, c = series[i][1], series[i][2], series[i][3], series[i][4]
        local cx = x + math.floor((i - 0.5) * slot)
        local hy, ly = ypos(high), ypos(low)
        bb:paintRect(cx - math.floor(wick / 2), hy, wick, math.max(2, ly - hy), BLACK)
        local oy, cy = ypos(o), ypos(c)
        local bt = math.min(oy, cy)
        local bh = math.abs(cy - oy)
        if bh < edge * 2 + 2 then
            bb:paintRect(cx - math.floor(body / 2), bt, body, math.max(3, edge), BLACK)
        elseif c >= o then
            bb:paintRect(cx - math.floor(body / 2), bt, body, bh, WHITE)
            bb:paintBorder(cx - math.floor(body / 2), bt, body, bh, edge, BLACK)
        else
            bb:paintRect(cx - math.floor(body / 2), bt, body, bh, BLACK)
        end
    end

    if opts and opts.lastLine then
        local ly = ypos(series[#series][4])
        local step = 18
        local px = x
        while px < x + w do
            bb:paintRect(px, ly, math.min(10, x + w - px), 2, BLACK)
            px = px + step
        end
    end
end

function Ticker:sliceFor(key)
    local series = self.bars[key]
    if not series then return nil end
    local want = RANGES[self.tf][2]
    if #series <= want then return series end
    local out = {}
    for i = #series - want + 1, #series do out[#out + 1] = series[i] end
    return out
end

function Ticker:ageText()
    if self.busy then return "fetching" end
    if self.error and not self.quotes then return "unreachable" end
    if self.age == nil then return "" end
    if self.age < 60 then return "just now" end
    return string.format("%d min old", math.floor(self.age / 60))
end

function Ticker:tfRects()
    local L = self.L
    local out = {}
    for i = 1, #RANGES do
        out[i] = { x = L.tf_x + (i - 1) * (L.tf_w + L.tf_gap), y = L.tf_y, w = L.tf_w, h = L.tf_h }
    end
    return out
end

function Ticker:allRect()
    local L = self.L
    return { x = L.chart_x + L.chart_w - L.all_w - 10, y = L.tf_y, w = L.all_w, h = L.all_h }
end

function Ticker:sideRects()
    local L = self.L
    local n = self.quotes and #self.quotes or 0
    if n == 0 then return {} end
    local rh = math.floor((L.side_bottom - L.side_top) / n)
    local out = {}
    for i = 1, n do
        out[i] = { x = L.side_x, y = L.side_top + (i - 1) * rh, w = L.side_w, h = rh }
    end
    return out
end

function Ticker:gridRects()
    local L = self.L
    local cols, gap, top = 4, 14, math.floor(L.h * 0.095)
    local tw = math.floor((L.w - L.m * 2 - gap * (cols - 1)) / cols)
    local th = math.floor((L.h - top - math.floor(L.h * 0.07) - gap * 3) / 4)
    local out = {}
    for i = 1, (self.quotes and #self.quotes or 0) do
        local cx, cy = (i - 1) % cols, math.floor((i - 1) / cols)
        out[i] = { x = L.m + cx * (tw + gap), y = top + cy * (th + gap), w = tw, h = th }
    end
    return out
end

function Ticker:paintEmpty(bb, x, y)
    local L = self.L
    text(bb, x + L.m, y + math.floor(L.h * 0.42), "no quotes", face("tfont", 62), BLACK)
    text(bb, x + L.m, y + math.floor(L.h * 0.42) + 92,
        self.cfg.host .. ":" .. self.cfg.port .. " did not answer", face("infofont", 32), SOFT)
    text(bb, x + L.m, y + math.floor(L.h * 0.42) + 146, "tap to try again",
        face("infofont", 32), SOFT)
end

function Ticker:paintChart(bb, x, y)
    local L = self.L
    local q = self:current()
    if not q then return self:paintEmpty(bb, x, y) end

    text(bb, x + L.m, y + L.head_key_y, q.key, face("tfont", 60), BLACK)
    text(bb, x + L.m, y + L.head_label_y, q.label, face("infofont", 26), SOFT)
    textRight(bb, x + L.w - L.m, y + L.price_y, q.price, face("tfont", 60), BLACK)
    local neg = q.change:sub(1, 1) == "-"
    textRight(bb, x + L.w - L.m, y + L.change_y,
        (q.change ~= "-" and q.change .. "%" or "—"),
        face("tfont", 34), neg and SOFT or BLACK)

    self:drawCandles(bb, x + L.chart_x, y + L.chart_y, L.chart_w, L.chart_h,
        self:sliceFor(q.key), { grid = true, axis = true, lastLine = true })

    for i, r in ipairs(self:tfRects()) do
        local on = (i == self.tf)
        bb:paintRect(x + r.x, y + r.y, r.w, r.h, on and BLACK or WHITE)
        bb:paintBorder(x + r.x, y + r.y, r.w, r.h, 2, BLACK)
        local widget = TextWidget:new{
            text = RANGES[i][1],
            face = face("tfont", 24),
            fgcolor = on and WHITE or BLACK,
        }
        local size = widget:getSize()
        widget:paintTo(bb, x + r.x + math.floor((r.w - size.w) / 2),
                           y + r.y + math.floor((r.h - size.h) / 2))
        widget:free()
    end

    local ar = self:allRect()
    bb:paintRect(x + ar.x, y + ar.y, ar.w, ar.h, WHITE)
    bb:paintBorder(x + ar.x, y + ar.y, ar.w, ar.h, 2, BLACK)
    local aw = TextWidget:new{ text = "all", face = face("tfont", 24), fgcolor = BLACK }
    local asz = aw:getSize()
    aw:paintTo(bb, x + ar.x + math.floor((ar.w - asz.w) / 2), y + ar.y + math.floor((ar.h - asz.h) / 2))
    aw:free()

    local series = self.bars[q.key]
    if series and #series > 0 then
        local bar = series[#series]
        local items = { { "O", bar[1] }, { "H", bar[2] }, { "L", bar[3] }, { "C", bar[4] } }
        local total = 0
        for i = 1, 4 do
            total = total + measure(items[i][1], face("infofont", 22))
                + 8 + measure(money(items[i][2]), face("tfont", 24)) + 22
        end
        local ox = x + L.chart_x + 8
        local oy = y + L.ohlc_y - 6
        bb:paintRect(ox - 6, oy, total + 12, 40, WHITE)
        local cursor = 0
        for i = 1, 4 do
            local nw = measure(items[i][1], face("infofont", 22))
            text(bb, ox + cursor, oy + 8, items[i][1], face("infofont", 22), SOFT)
            cursor = cursor + nw + 8
            text(bb, ox + cursor, oy + 6, money(items[i][2]), face("tfont", 24), BLACK)
            cursor = cursor + measure(money(items[i][2]), face("tfont", 24)) + 22
        end
    end

    for i, r in ipairs(self:sideRects()) do
        local qq = self.quotes[i]
        local on = (i == self.sel)
        if on then bb:paintRect(x + r.x, y + r.y, r.w, r.h, BLACK) end
        bb:paintBorder(x + r.x, y + r.y, r.w, r.h, 2, on and BLACK or MID)
        local qneg = qq.change:sub(1, 1) == "-"
        local chg = (qq.change ~= "-" and qq.change .. "%" or "—")
        text(bb, x + r.x + 14, y + r.y + 30, qq.key, face("tfont", 26), on and WHITE or BLACK)
        textRight(bb, x + r.x + r.w - 14, y + r.y + 32, chg,
            face("infofont", 22), on and WHITE or (qneg and SOFT or BLACK))
    end

    text(bb, x + L.m, y + L.foot_y,
        self.error and ("· " .. tostring(self.error))
            or "tap a symbol · swipe to page · tap chart to refresh",
        face("infofont", 24), SOFT)
    textRight(bb, x + L.w - L.m, y + L.foot_y, self:ageText(), face("infofont", 24), SOFT)
end

function Ticker:paintGrid(bb, x, y)
    local L = self.L
    if not self.quotes then return self:paintEmpty(bb, x, y) end

    text(bb, x + L.m, y + 28, "all sixteen", face("tfont", 54), BLACK)
    textRight(bb, x + L.w - L.m, y + 46, self:ageText(), face("infofont", 28), SOFT)

    for i, r in ipairs(self:gridRects()) do
        local q = self.quotes[i]
        bb:paintBorder(x + r.x, y + r.y, r.w, r.h, 2, i == self.sel and BLACK or MID)
        text(bb, x + r.x + 16, y + r.y + 12, q.key, face("tfont", 32), BLACK)
        self:drawCandles(bb, x + r.x + 14, y + r.y + 70, r.w - 28, math.floor(r.h * 0.46),
            self.bars[q.key] and self:gridSlice(q.key) or nil, nil)
        local neg = q.change:sub(1, 1) == "-"
        text(bb, x + r.x + 16, y + r.y + r.h - 48,
            (q.change ~= "-" and q.change .. "%" or "—"),
            face("infofont", 26), neg and SOFT or BLACK)
    end

    text(bb, x + L.m, y + L.foot_y, "tap a chart to open it · double-tap to close",
        face("infofont", 28), SOFT)
end

function Ticker:gridSlice(key)
    local series = self.bars[key]
    if not series then return nil end
    if #series <= GRID_BARS then return series end
    local out = {}
    for i = #series - GRID_BARS + 1, #series do out[#out + 1] = series[i] end
    return out
end

function Ticker:paintTo(bb, x, y)
    local L = self.L
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, L.w, L.h, WHITE)
    if self.mode == "grid" then
        self:paintGrid(bb, x, y)
    else
        self:paintChart(bb, x, y)
    end
end

function Ticker:repaint(mode)
    mode = mode or "ui"
    if mode == "partial" then
        self.since_flash = self.since_flash + 1
        if self.since_flash >= GHOST_EVERY then mode = "full" end
    end
    if mode == "full" then self.since_flash = 0 end
    UIManager:setDirty(self, function() return mode, self.dimen end)
end

function Ticker:withBusy(work)
    self.busy = true
    self.error = nil
    self:repaint()
    UIManager:scheduleIn(0.05, function()
        local failure = work()
        self.busy = false
        if failure then
            self.error = failure
            logger.warn("mandragora: ticker:", tostring(failure))
        end
        self:repaint("partial")
    end)
end

function Ticker:refresh(force)
    self:withBusy(function()
        local failure = self:loadQuotes(force)
        if force and not failure then self.bars, self.full = {}, {} end
        local q = self:current()
        if q and not self.full[q.key] then
            failure = self:loadCandles(q.key, FULL_BARS) or failure
        end
        return failure
    end)
end

function Ticker:select(index)
    if not self.quotes or index < 1 or index > #self.quotes then return end
    self.sel = index
    local key = self.quotes[index].key
    if self.full[key] then
        self:repaint("partial")
        return
    end
    self:withBusy(function() return self:loadCandles(key, FULL_BARS) end)
end

function Ticker:openGrid()
    self.mode = "grid"
    local missing = false
    for _, q in ipairs(self.quotes or {}) do
        if not self.bars[q.key] then missing = true break end
    end
    if not missing then
        self:repaint("full")
        return
    end
    self:withBusy(function() return self:loadCandles("ALL", GRID_BARS) end)
end

local function inside(r, px, py)
    return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

function Ticker:onTap(_, ges)
    if self.busy then return true end
    local px, py = ges.pos.x, ges.pos.y

    if self.mode == "grid" then
        for i, r in ipairs(self:gridRects()) do
            if inside(r, px, py) then
                self.mode = "chart"
                self:select(i)
                return true
            end
        end
        return true
    end

    local L = self.L
    local ar = self:allRect()
    if inside(ar, px, py) then
        self:openGrid()
        return true
    end
    for i, r in ipairs(self:tfRects()) do
        if inside(r, px, py) then
            self.tf = i
            self:repaint("partial")
            return true
        end
    end
    for i, r in ipairs(self:sideRects()) do
        if inside(r, px, py) then
            self:select(i)
            return true
        end
    end

    if inside({ x = L.chart_x, y = L.chart_y, w = L.chart_w, h = L.chart_h }, px, py) then
        self:refresh(true)
    end
    return true
end

function Ticker:onDoubleTap()
    return self:onClose()
end

function Ticker:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    if self.mode == "grid" or self.busy then return true end
    if not self.quotes then return true end
    local step = ges.direction == "west" and 1 or -1
    local n = #self.quotes
    self:select(((self.sel - 1 + step) % n) + 1)
    return true
end

function Ticker:onClose()
    if self.mode == "grid" then
        self.mode = "chart"
        self:repaint("full")
        return true
    end
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
    view:refresh(false)
    return view
end

return Ticker
