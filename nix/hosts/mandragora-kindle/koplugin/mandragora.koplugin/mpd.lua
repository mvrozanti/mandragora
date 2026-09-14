local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local RenderImage = require("ui/renderimage")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local socket_ok, socket = pcall(require, "socket")

local Screen = Device.screen

local CONFIG_PATH = "/mnt/us/mandragora/mpd.conf"
local COVER_PATH = "/tmp/mandragora-mpd-cover.png"
local NC_BIN = "/usr/bin/nc"
local TIMEOUT_SECONDS = 3
local SEARCH_LIMIT = 40
local VIS_CONNECT_TIMEOUT = 1
local VIS_RETRY_SECONDS = 20
local REF_W = 1272

local DEFAULTS = {
    host = "192.168.0.27",
    port = 6600,
    vis_host = "",
    vis_port = 6612,
    vis_fps = 5,
    vis_gc16_frames = 50,
    poll_seconds = 3,
    volume_buttons = false,
}

local INK = Blitbuffer.COLOR_BLACK
local PAPER = Blitbuffer.COLOR_WHITE
local INK_DIM = Blitbuffer.Color8(0x60)
local INK_FAINT = Blitbuffer.Color8(0xAA)

local MONO = "DroidSansMono.ttf"
local DISPLAY = "NotoSans-Bold.ttf"
local BODY = "NotoSans-Regular.ttf"

local function fileExists(path)
    local fh = io.open(path, "r")
    if not fh then return false end
    fh:close()
    return true
end

local nc_ok = fileExists(NC_BIN)

local function parseConfigFile(path)
    local values = {}
    local fh = io.open(path, "r")
    if not fh then return values end
    for line in fh:lines() do
        local key, val = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
        if key and val then values[key] = val end
    end
    fh:close()
    return values
end

local function numberOr(values, key, fallback, low, high)
    local n = tonumber(values[key])
    if not n then return fallback end
    n = math.floor(n)
    if low and n < low then return low end
    if high and n > high then return high end
    return n
end

local TRUTHY = { ["1"] = true, ["true"] = true, ["yes"] = true, ["on"] = true }
local FALSY = { ["0"] = true, ["false"] = true, ["no"] = true, ["off"] = true }

local function boolOr(values, key, fallback)
    local raw = values[key]
    if type(raw) ~= "string" then return fallback end
    raw = raw:lower()
    if TRUTHY[raw] then return true end
    if FALSY[raw] then return false end
    return fallback
end

local function loadConfig()
    local values = parseConfigFile(CONFIG_PATH)
    local cfg = {}
    cfg.host = (values.host and values.host ~= "") and values.host or DEFAULTS.host
    cfg.port = numberOr(values, "port", DEFAULTS.port, 1, 65535)
    cfg.vis_host = (values.vis_host and values.vis_host ~= "") and values.vis_host or cfg.host
    cfg.vis_port = numberOr(values, "vis_port", DEFAULTS.vis_port, 1, 65535)
    cfg.vis_fps = numberOr(values, "vis_fps", DEFAULTS.vis_fps, 1, 12)
    cfg.vis_gc16_frames = numberOr(values, "vis_gc16_frames", DEFAULTS.vis_gc16_frames, 5, 600)
    cfg.poll_seconds = numberOr(values, "poll_seconds",
        numberOr(values, "refresh_seconds", DEFAULTS.poll_seconds, 1, 120), 1, 120)
    cfg.volume_buttons = boolOr(values, "volume_buttons", DEFAULTS.volume_buttons)
    return cfg
end

local function splitLines(text)
    local lines = {}
    local from = 1
    while true do
        local nl = text:find("\n", from, true)
        if not nl then
            if from <= #text then lines[#lines + 1] = text:sub(from) end
            break
        end
        lines[#lines + 1] = text:sub(from, nl - 1)
        from = nl + 1
    end
    return lines
end

local function socketExchange(host, port, payload)
    local sock = socket.tcp()
    sock:settimeout(TIMEOUT_SECONDS)
    local ok, cerr = sock:connect(host, port)
    if not ok then
        sock:close()
        return nil, cerr or "connection failed"
    end
    local banner, berr = sock:receive("*l")
    if not banner or not banner:find("^OK MPD") then
        sock:close()
        return nil, berr or "unexpected banner"
    end
    local sent, serr = sock:send(payload)
    if not sent then
        sock:close()
        return nil, serr or "send failed"
    end
    local lines = {}
    while true do
        local line, rerr = sock:receive("*l")
        if not line then
            sock:close()
            if rerr == "closed" then return lines end
            if #lines > 0 then return lines end
            return nil, rerr or "connection closed"
        end
        lines[#lines + 1] = line
    end
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function popenExchange(host, port, payload)
    if not nc_ok then return nil, "nc not found on device" end
    local cmd = string.format(
        "printf %%s %s | timeout %d %s -w %d %s %d 2>/dev/null",
        shellQuote(payload), TIMEOUT_SECONDS + 2, NC_BIN, TIMEOUT_SECONDS,
        shellQuote(host), port)
    local proc = io.popen(cmd, "r")
    if not proc then return nil, "failed to spawn nc" end
    local out = proc:read("*a")
    proc:close()
    if not out or out == "" then return nil, "no response from nc" end
    local lines = splitLines(out)
    if not lines[1] or not lines[1]:find("^OK MPD") then
        return nil, "unexpected banner"
    end
    table.remove(lines, 1)
    return lines
end

local function exchange(host, port, payload)
    if socket_ok then return socketExchange(host, port, payload) end
    return popenExchange(host, port, payload)
end

local function splitBlocks(lines, expected_count)
    local blocks = {}
    local current = {}
    for _, line in ipairs(lines) do
        if line == "OK" then
            blocks[#blocks + 1] = current
            current = {}
            if #blocks == expected_count then break end
        elseif line:find("^ACK ") then
            return nil, line
        else
            current[#current + 1] = line
        end
    end
    if #blocks < expected_count then
        return nil, "incomplete response from MPD"
    end
    return blocks
end

local function parseKV(lines)
    local dict = {}
    for _, line in ipairs(lines) do
        local key, val = line:match("^([%w_%-]+):%s*(.*)$")
        if key then dict[key] = val end
    end
    return dict
end

local function parseTracks(lines)
    local tracks = {}
    local current = nil
    for _, line in ipairs(lines) do
        local key, val = line:match("^([%w_%-]+):%s*(.*)$")
        if key == "file" then
            current = { file = val }
            tracks[#tracks + 1] = current
        elseif key and current then
            current[key] = val
        end
    end
    return tracks
end

local function queryNowPlaying(cfg)
    local lines, err = exchange(cfg.host, cfg.port, "currentsong\nstatus\nclose\n")
    if not lines then return nil, err end
    local blocks, berr = splitBlocks(lines, 2)
    if not blocks then return nil, berr end
    return { current = parseKV(blocks[1]), status = parseKV(blocks[2]) }
end

local function sendCommand(cfg, command)
    local lines, err = exchange(cfg.host, cfg.port, command .. "\nclose\n")
    if not lines then return false, err end
    local blocks, berr = splitBlocks(lines, 1)
    if not blocks then return false, berr end
    return true
end

local function mpdQuote(value)
    local s = tostring(value or "")
    s = s:gsub("[\r\n]", " ")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    return '"' .. s .. '"'
end

local function searchTracks(cfg, query)
    local payload = string.format("search any %s window 0:%d\nclose\n",
        mpdQuote(query), SEARCH_LIMIT + 1)
    local lines, err = exchange(cfg.host, cfg.port, payload)
    if not lines then return nil, err end
    local blocks, berr = splitBlocks(lines, 1)
    if not blocks then return nil, berr end
    local tracks = parseTracks(blocks[1])
    local truncated = #tracks > SEARCH_LIMIT
    while #tracks > SEARCH_LIMIT do table.remove(tracks) end
    return tracks, truncated
end

local function addAndPlay(cfg, uri)
    local lines, err = exchange(cfg.host, cfg.port, "addid " .. mpdQuote(uri) .. "\nclose\n")
    if not lines then return nil, err end
    local blocks, berr = splitBlocks(lines, 1)
    if not blocks then return nil, berr end
    local id = parseKV(blocks[1]).Id
    if not id then return nil, "MPD returned no song id" end
    local played, perr = sendCommand(cfg, "playid " .. id)
    if not played then return nil, perr end
    return id
end

local function formatTime(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 0 then seconds = 0 end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

local function trackTitle(track)
    local title = track.Title
    if title and title ~= "" then return title end
    local path = track.file or ""
    local base = path:match("([^/]+)$") or path
    base = base:gsub("%.%w+$", "")
    if base == "" then return "unknown" end
    return base
end

local function trackByline(track)
    local parts = {}
    local artist = track.Artist or track.AlbumArtist
    if artist and artist ~= "" then parts[#parts + 1] = artist end
    if track.Album and track.Album ~= "" then parts[#parts + 1] = track.Album end
    if #parts == 0 then return "" end
    return table.concat(parts, "  ·  ")
end

local SCALE = Screen:getWidth() / REF_W
local DP = Screen:scaleBySize(10000) / 10000

local function u(v)
    return math.floor(v * SCALE + 0.5)
end

local face_cache = {}

local function face(name, px)
    local key = name .. "/" .. px
    local cached = face_cache[key]
    if cached then return cached end
    local size = math.floor(px * SCALE / DP + 0.5)
    if size < 6 then size = 6 end
    local f = Font:getFace(name, size)
    face_cache[key] = f
    return f
end

local metric_cache = {}

local function metrics(f)
    local m = metric_cache[f.hash]
    if m then return m end
    local caps = RenderText:sizeUtf8Text(0, nil, f, "ABCXYZ0", true, false)
    local full = RenderText:sizeUtf8Text(0, nil, f, "AXgjpqy0", true, false)
    m = { cap = caps.y_top, top = full.y_top, bottom = full.y_bottom, line = full.y_top + full.y_bottom }
    metric_cache[f.hash] = m
    return m
end

local function textW(f, s, bold)
    if not s or s == "" then return 0 end
    return RenderText:sizeUtf8Text(0, nil, f, s, true, bold).x
end

local function text(bb, x, baseline, f, s, colour, bold)
    if not s or s == "" then return end
    RenderText:renderUtf8Text(bb, x, baseline, f, s, true, bold, colour or INK)
end

local function trackedW(f, s, tracking, bold)
    if not s or s == "" then return 0 end
    return textW(f, s, bold) + tracking * (#s - 1)
end

local function tracked(bb, x, baseline, f, s, colour, tracking, bold)
    if not s or s == "" then return end
    local pads = {}
    for i = 1, #s do pads[i] = tracking end
    RenderText:renderUtf8Text(bb, x, baseline, f, s, true, bold, colour or INK, nil, pads)
end

local function rect(bb, x, y, w, h, colour)
    if w <= 0 or h <= 0 then return end
    bb:paintRect(x, y, w, h, colour or INK)
end

local function outline(bb, x, y, w, h, thickness, colour)
    thickness = thickness or u(3)
    colour = colour or INK
    rect(bb, x, y, w, thickness, colour)
    rect(bb, x, y + h - thickness, w, thickness, colour)
    rect(bb, x, y + thickness, thickness, h - 2 * thickness, colour)
    rect(bb, x + w - thickness, y + thickness, thickness, h - 2 * thickness, colour)
end

local function triangle(bb, x, y, w, h, dir, colour)
    for row = 0, h - 1 do
        local d = math.abs((row / (h - 1)) * 2 - 1)
        local span = math.floor(w * (1 - d) + 0.5)
        if span > 0 then
            if dir == "left" then
                rect(bb, x + w - span, y + row, span, 1, colour)
            else
                rect(bb, x, y + row, span, 1, colour)
            end
        end
    end
end

local function triangleV(bb, x, y, w, h, dir, colour)
    for col = 0, w - 1 do
        local d = math.abs((col / (w - 1)) * 2 - 1)
        local span = math.floor(h * (1 - d) + 0.5)
        if span > 0 then
            if dir == "up" then
                rect(bb, x + col, y + h - span, 1, span, colour)
            else
                rect(bb, x + col, y, 1, span, colour)
            end
        end
    end
end

local function stroke(bb, x0, y0, x1, y1, thickness, colour)
    local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
    if steps < 1 then
        rect(bb, x0, y0, thickness, thickness, colour)
        return
    end
    for i = 0, steps do
        local px = x0 + math.floor((x1 - x0) * i / steps + 0.5)
        local py = y0 + math.floor((y1 - y0) * i / steps + 0.5)
        rect(bb, px, py, thickness, thickness, colour)
    end
end

local function ring(bb, cx, cy, radius, thickness, colour)
    local inner = radius - thickness
    for dy = -radius, radius do
        local outer_span = math.floor(math.sqrt(math.max(0, radius * radius - dy * dy)) + 0.5)
        local inner_span = 0
        if math.abs(dy) < inner then
            inner_span = math.floor(math.sqrt(math.max(0, inner * inner - dy * dy)) + 0.5)
        end
        if inner_span > 0 then
            rect(bb, cx - outer_span, cy + dy, outer_span - inner_span, 1, colour)
            rect(bb, cx + inner_span, cy + dy, outer_span - inner_span, 1, colour)
        else
            rect(bb, cx - outer_span, cy + dy, outer_span * 2, 1, colour)
        end
    end
end

local function elide(f, s, width, bold)
    if not s or s == "" then return "" end
    if textW(f, s, bold) <= width then return s end
    local ellipsis = "…"
    local ew = textW(f, ellipsis, bold)
    local out = s
    while #out > 1 and textW(f, out, bold) + ew > width do
        out = out:sub(1, #out - 1)
        while #out > 1 do
            local b = out:byte(#out)
            if b >= 0x80 and b < 0xC0 then out = out:sub(1, #out - 1) else break end
        end
    end
    return out .. ellipsis
end

local function wrap(f, s, width, bold, maxlines)
    local lines = {}
    local current = ""
    for word in s:gmatch("%S+") do
        local candidate = current == "" and word or (current .. " " .. word)
        if textW(f, candidate, bold) <= width or current == "" then
            current = candidate
        else
            lines[#lines + 1] = current
            current = word
            if #lines >= maxlines then break end
        end
    end
    if #lines < maxlines and current ~= "" then lines[#lines + 1] = current end
    if #lines == 0 then lines[1] = "" end
    lines[#lines] = elide(f, lines[#lines], width, bold)
    return lines
end

local function fitLines(name, s, width, maxlines, high, low)
    for px = high, low, -3 do
        local f = face(name, px)
        local probe = wrap(f, s, width, false, maxlines + 1)
        if #probe <= maxlines then return f, probe end
    end
    local f = face(name, low)
    return f, wrap(f, s, width, false, maxlines)
end

local function layout()
    local L = {}
    L.x0 = u(54)
    L.x1 = Screen:getWidth() - u(54)
    L.cw = L.x1 - L.x0
    L.hair = u(3)
    L.heavy = u(6)

    L.head_y = u(92)
    L.head_rule = u(184)
    L.flags = { y = u(138), w = u(36), h = u(28), gap = u(24) }

    L.cover = { x = L.x0, y = u(216), size = u(520) }
    L.meta = { x = L.x0 + u(560), w = L.x1 - (L.x0 + u(560)), y = u(216), bottom = u(736) }

    L.media_rule = u(754)
    L.scrub_label = u(794)
    L.tick = { y = u(812), h = u(538) }
    L.times = u(816)
    L.bar = { y = u(882), h = u(28) }
    L.mid_rule = u(942)
    L.spec_row = u(962)
    L.bars = { y = u(1011), h = u(335), baseline = u(1346) }
    L.axis = u(1358)
    L.search = { query = u(238), meta = u(330), rule = u(376), y = u(400), pitch = u(96), rows = 10 }
    L.foot_rule = u(1430)
    L.transport = { y = u(1450), h = u(140), gap = u(16) }
    L.tail_rule = u(1612)
    L.footer = u(1624)

    L.bands = 48
    local gap = u(4)
    L.bar_w = math.floor((L.cw - gap * (L.bands - 1)) / L.bands)
    L.bar_gap = gap
    L.bars.w = L.bar_w * L.bands + gap * (L.bands - 1)
    L.bars.x = L.x0 + math.floor((L.cw - L.bars.w) / 2)
    L.seg = u(10)
    L.seg_gap = u(3)
    L.segments = math.floor((L.bars.h + L.seg_gap) / (L.seg + L.seg_gap))
    L.bars.h = L.segments * (L.seg + L.seg_gap) - L.seg_gap
    L.bars.y = L.bars.baseline - L.bars.h
    return L
end

local MPDPlayer = InputContainer:extend{
    cfg = nil,
    data = nil,
    error = nil,
}

function MPDPlayer:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    self.cfg = loadConfig()
    self.L = layout()

    self.mode = "player"
    self.player_buttons = {
        { id = "prev", label = "PREV" },
        { id = "play", label = "PLAY" },
        { id = "next", label = "NEXT" },
        { id = "search", label = "SEARCH" },
    }
    if self.cfg.volume_buttons then
        self.player_buttons[#self.player_buttons + 1] = { id = "voldown", label = "VOL -" }
        self.player_buttons[#self.player_buttons + 1] = { id = "volup", label = "VOL +" }
    end
    self.search_buttons = {
        { id = "back", label = "BACK" },
        { id = "search", label = "SEARCH" },
        { id = "pageprev", label = "PREV" },
        { id = "pagenext", label = "NEXT" },
    }
    self.search_results = {}
    self.search_page = 1

    self.vis_enabled = true
    self.vis_bands = self.L.bands
    self.vis_bars = {}
    self.vis_peaks = {}
    for i = 1, self.vis_bands do
        self.vis_bars[i] = 0
        self.vis_peaks[i] = 0
    end
    self.vis_state = "X"
    self.vis_error = socket_ok and "not connected" or "no luasocket"
    self.vis_partial = ""
    self.frame_count = 0
    self.last_poll = 0
    self.poll_stamp = 0
    self.hits = {}
    self.paint_zone = "all"

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

    self:poll()
    self:maybeVisConnect()
    self:schedule()
end

function MPDPlayer:state()
    if not self.data then return "stop" end
    return (self.data.status and self.data.status.state) or "stop"
end

function MPDPlayer:playing()
    return self:state() == "play"
end

function MPDPlayer:visLive()
    return self.vis_sock ~= nil and self.vis_state == "L"
end

function MPDPlayer:animating()
    return self.vis_enabled and self:playing() and self.vis_sock ~= nil
end

function MPDPlayer:interval()
    if self.mode == "search" then return 4 end
    if self:animating() then return 1 / self.cfg.vis_fps end
    if self:playing() then return 1 end
    return 4
end

function MPDPlayer:schedule()
    if self._closed then return end
    UIManager:scheduleIn(self:interval(), function() self:tick() end)
end

function MPDPlayer:tick()
    if self._closed then return end
    if self.mode == "search" or self.dialog_open then
        self:schedule()
        return
    end
    local now = os.time()

    if now - self.last_poll >= self.cfg.poll_seconds then
        self:poll()
    end

    self:maybeVisConnect()

    if self:playing() then
        if self:animating() then
            for i = 1, self.vis_bands do self.vis_bars[i] = 0 end
            self:visDrain()
            self.frame_count = self.frame_count + 1
            local mode = "a2"
            if self.frame_count % self.cfg.vis_gc16_frames == 0 then mode = "full" end
            self:repaint("tick", mode)
        else
            self:repaint("tick", "ui")
        end
    end

    self:schedule()
end

function MPDPlayer:poll()
    self.last_poll = os.time()
    local ok, data, err = pcall(queryNowPlaying, self.cfg)
    local before = self:signature()
    if ok and data then
        self.data = data
        self.error = nil
    else
        self.data = nil
        self.error = (ok and err) or tostring(data)
        logger.warn("mandragora: mpd:", self.error)
    end
    self.poll_stamp = os.time()
    self.poll_elapsed = tonumber(self.data and self.data.status and self.data.status.elapsed) or 0

    local file = self.data and self.data.current and self.data.current.file
    if file ~= self.cover_file then
        self.cover_file = file
        self:releaseCover()
        if file then self:fetchCover(file) end
    end

    if self:signature() ~= before then
        if not self:playing() then self:visClose(nil) end
        self:repaint("all", "full")
    end
end

function MPDPlayer:maybeVisConnect()
    if self.vis_sock or not self.vis_enabled or not self:playing() then return end
    local now = os.time()
    if now - (self.vis_retry or 0) < VIS_RETRY_SECONDS then return end
    self.vis_retry = now
    self:visConnect()
end

function MPDPlayer:signature()
    if self.error then return "error:" .. tostring(self.error) end
    if not self.data then return "none" end
    local s = self.data.status or {}
    local c = self.data.current or {}
    return table.concat({
        s.state or "", s.songid or "",
        self.cfg.volume_buttons and (s.volume or "") or "",
        s["repeat"] or "", s.random or "", s.single or "", c.file or "",
    }, "|")
end

function MPDPlayer:elapsed()
    local base = self.poll_elapsed or 0
    if self:playing() then base = base + (os.time() - self.poll_stamp) end
    local duration = self:duration()
    if duration > 0 and base > duration then base = duration end
    return base
end

function MPDPlayer:duration()
    if not self.data then return 0 end
    local c = self.data.current or {}
    local s = self.data.status or {}
    return tonumber(c.duration) or tonumber(s.duration) or tonumber(c.Time) or 0
end

function MPDPlayer:visConnect()
    self:visClose(nil)
    if not socket_ok then
        self.vis_error = "no luasocket"
        return
    end
    local sock = socket.tcp()
    sock:settimeout(VIS_CONNECT_TIMEOUT)
    local ok, cerr = sock:connect(self.cfg.vis_host, self.cfg.vis_port)
    if not ok then
        sock:close()
        self.vis_error = cerr or "connect failed"
        return
    end
    sock:send("SUB\n")
    local header = sock:receive("*l")
    local bands = header and tonumber(header:match("^VIS %d+ (%d+)"))
    if not bands then
        sock:close()
        self.vis_error = "bad handshake"
        return
    end
    sock:settimeout(0)
    self.vis_sock = sock
    self.vis_bands = bands
    self.vis_partial = ""
    self.vis_error = nil
    self.vis_state = "S"
    for i = 1, bands do
        self.vis_bars[i] = 0
        self.vis_peaks[i] = 0
    end
    logger.info("mandragora: mpd: visualiser attached,", bands, "bands")
end

function MPDPlayer:visClose(reason)
    if self.vis_sock then
        pcall(function() self.vis_sock:close() end)
        self.vis_sock = nil
    end
    self.vis_partial = ""
    self.vis_state = "X"
    if reason then self.vis_error = reason end
end

function MPDPlayer:visApply(line)
    if line:sub(1, 1) ~= "F" then return end
    local n = self.vis_bands
    if #line < 2 + n * 2 then return end
    self.vis_state = line:sub(2, 2)
    local bars, peaks = self.vis_bars, self.vis_peaks
    for i = 1, n do
        local v = line:byte(2 + i) - 48
        if v < 0 then v = 0 elseif v > 63 then v = 63 end
        if v > bars[i] then bars[i] = v end
        local p = line:byte(2 + n + i) - 48
        if p < 0 then p = 0 elseif p > 63 then p = 63 end
        peaks[i] = p
    end
end

function MPDPlayer:visDrain()
    local sock = self.vis_sock
    if not sock then return end
    for _ = 1, 12 do
        local line, err, partial = sock:receive("*l")
        if line then
            if self.vis_partial ~= "" then
                line = self.vis_partial .. line
                self.vis_partial = ""
            end
            self:visApply(line)
        elseif err == "timeout" then
            self.vis_partial = self.vis_partial .. (partial or "")
            return
        else
            self:visClose(err or "stream closed")
            return
        end
    end
end

function MPDPlayer:releaseCover()
    if self.cover_bb then
        pcall(function() self.cover_bb:free() end)
        self.cover_bb = nil
    end
end

function MPDPlayer:fetchCover(uri)
    if not socket_ok then return end
    local now = os.time()
    if now - (self.cover_retry or 0) < VIS_RETRY_SECONDS then return end
    local size = self.L.cover.size
    local sock = socket.tcp()
    sock:settimeout(VIS_CONNECT_TIMEOUT)
    local ok = sock:connect(self.cfg.vis_host, self.cfg.vis_port)
    if not ok then
        sock:close()
        self.cover_retry = now
        return
    end
    self.cover_retry = 0
    sock:settimeout(4)
    sock:send("COVER " .. size .. " " .. (uri or "") .. "\n")
    local header = sock:receive("*l")
    local length = header and tonumber(header:match("^COVER (%d+)$"))
    if not length then
        sock:close()
        return
    end
    local data = sock:receive(length)
    sock:close()
    if not data or #data ~= length then return end
    local fh = io.open(COVER_PATH, "wb")
    if not fh then return end
    fh:write(data)
    fh:close()
    local rendered = nil
    pcall(function() rendered = RenderImage:renderImageFile(COVER_PATH, false, size, size) end)
    self.cover_bb = rendered
end

function MPDPlayer:zoneGeom(zone)
    local L = self.L
    if zone == "tick" then
        return Geom:new{ x = 0, y = L.tick.y, w = Screen:getWidth(), h = L.tick.h }
    end
    if zone == "transport" then
        return Geom:new{ x = 0, y = L.transport.y - u(20), w = Screen:getWidth(), h = L.transport.h + u(40) }
    end
    return self.dimen
end

function MPDPlayer:repaint(zone, mode)
    if self.paint_zone ~= "all" then self.paint_zone = zone end
    if self.paint_zone == "all" then mode = "full" end
    local region = self:zoneGeom(self.paint_zone)
    UIManager:setDirty(self, function() return mode, region end)
end

function MPDPlayer:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local zone = self.paint_zone or "all"
    self.paint_zone = nil
    if zone == "tick" then
        self:paintTick(bb, x, y)
    elseif zone == "transport" then
        self:paintTransport(bb, x, y)
    else
        self:paintAll(bb, x, y)
    end
end

function MPDPlayer:paintAll(bb, ox, oy)
    local L = self.L
    self.hits = {}
    rect(bb, ox, oy, Screen:getWidth(), Screen:getHeight(), PAPER)
    if self.mode == "search" then
        self:paintHeader(bb, ox, oy, "MANDRAGORA / SEARCH")
        self:paintSearch(bb, ox, oy)
    else
        self:paintHeader(bb, ox, oy, "MANDRAGORA / NOW PLAYING")
        if self.error then
            self:paintOffline(bb, ox, oy)
        else
            self:paintMedia(bb, ox, oy)
            self:paintScrubLabels(bb, ox, oy)
            self:paintTick(bb, ox, oy)
            self:paintAxis(bb, ox, oy)
        end
    end
    self:paintTransport(bb, ox, oy)
    self:paintFooter(bb, ox, oy)
    rect(bb, ox + L.x0, oy + L.head_rule, L.cw, L.heavy, INK)
end

function MPDPlayer:paintHeader(bb, ox, oy, subtitle)
    local L = self.L
    local mark = face(MONO, 84)
    local mm = metrics(mark)
    local baseline = oy + L.head_y + mm.cap
    text(bb, ox + L.x0, baseline, mark, "MPD", INK, true)

    local sub = face(MONO, 21)
    tracked(bb, ox + L.x0 + textW(mark, "MPD", true) + u(30), baseline, sub,
        subtitle, INK_DIM, u(5), false)

    local status = (self.data and self.data.status) or {}
    local label = "STOPPED"
    local filled = false
    if self.error then
        label = "OFFLINE"
    elseif status.state == "play" then
        label = "PLAYING"
        filled = true
    elseif status.state == "pause" then
        label = "PAUSED"
    end
    self:paintTag(bb, ox + L.x1, oy + L.head_y, label, filled, 28)
    self:paintFlags(bb, ox, oy, status)
end

function MPDPlayer:paintFlags(bb, ox, oy, status)
    local L = self.L
    local F = L.flags
    local modes = {
        { id = "repeat", on = status["repeat"] == "1" },
        { id = "random", on = status.random == "1" },
        { id = "single", on = status.single == "1" },
    }

    local width = #modes * F.w + (#modes - 1) * F.gap
    local vf, volume_label
    if self.cfg.volume_buttons then
        local volume = tonumber(status.volume)
        volume_label = "VOL " .. (volume and (volume .. "%") or "--")
        vf = face(MONO, 21)
        width = width + trackedW(vf, volume_label, u(3), true) + F.gap
    end

    local x = ox + L.x1 - width
    if volume_label then
        local vm = metrics(vf)
        local vw = trackedW(vf, volume_label, u(3), true)
        tracked(bb, x, oy + F.y + math.floor((F.h + vm.cap) / 2), vf, volume_label,
            INK_FAINT, u(3), true)
        x = x + vw + F.gap
    end
    for _, mode in ipairs(modes) do
        local ink = mode.on and INK or INK_FAINT
        self:paintModeIcon(bb, mode.id, x, oy + F.y, F.w, F.h, ink)
        if mode.on then
            rect(bb, x, oy + F.y + F.h + u(8), F.w, L.hair, INK)
        end
        x = x + F.w + F.gap
    end
end

function MPDPlayer:paintModeIcon(bb, id, x, y, w, h, ink)
    local t = u(3)
    local head_w, head_h = u(11), u(13)
    local top, bottom = y + u(5), y + h - u(5) - t
    local function head(hx, line_y, dir)
        triangle(bb, hx, line_y + math.floor(t / 2) - math.floor(head_h / 2),
            head_w, head_h, dir, ink)
    end
    if id == "repeat" then
        rect(bb, x + head_w, top, w - head_w, t, ink)
        head(x, top, "left")
        rect(bb, x, bottom, w - head_w, t, ink)
        head(x + w - head_w, bottom, "right")
    elseif id == "random" then
        local far = x + w - head_w - t
        stroke(bb, x, top, far, bottom, t, ink)
        stroke(bb, x, bottom, far, top, t, ink)
        head(x + w - head_w, top, "right")
        head(x + w - head_w, bottom, "right")
    elseif id == "single" then
        local wall = u(4)
        local mid = y + math.floor((h - t) / 2)
        local tip = x + w - head_w - wall - t
        rect(bb, x, mid, tip - x, t, ink)
        head(tip, mid, "right")
        rect(bb, x + w - t, y + wall, t, h - wall * 2, ink)
    end
end

function MPDPlayer:paintTag(bb, right_x, y, label, filled, px)
    local f = face(MONO, px or 26)
    local m = metrics(f)
    local tracking = u(4)
    local tw = trackedW(f, label, tracking, true)
    local padx, pady = u(20), u(11)
    local w = tw + padx * 2
    local h = m.cap + pady * 2
    local x = right_x - w
    if filled then
        rect(bb, x, y, w, h, INK)
        tracked(bb, x + padx, y + pady + m.cap, f, label, PAPER, tracking, true)
    else
        outline(bb, x, y, w, h, u(3), INK)
        tracked(bb, x + padx, y + pady + m.cap, f, label, INK, tracking, true)
    end
    return x, w, h
end

function MPDPlayer:paintChip(bb, x, y, label)
    local f = face(MONO, 21)
    local m = metrics(f)
    local tracking = u(3)
    local tw = trackedW(f, label, tracking, true)
    local padx, pady = u(14), u(9)
    local w = tw + padx * 2
    local h = m.cap + pady * 2
    outline(bb, x, y, w, h, u(3), INK)
    tracked(bb, x + padx, y + pady + m.cap, f, label, INK, tracking, true)
    return w, h
end

function MPDPlayer:paintMedia(bb, ox, oy)
    local L = self.L
    local c = (self.data and self.data.current) or {}
    local s = (self.data and self.data.status) or {}
    local cx, cy, size = ox + L.cover.x, oy + L.cover.y, L.cover.size

    if self.cover_bb then
        local ok = pcall(function()
            bb:blitFrom(self.cover_bb, cx, cy, 0, 0, size, size)
        end)
        if not ok then self.cover_bb = nil end
    end
    if not self.cover_bb then
        outline(bb, cx, cy, size, size, u(3), INK)
        local step = u(26)
        for i = 1, math.floor(size / step) - 1 do
            local d = i * step
            rect(bb, cx + u(3), cy + d, size - u(6), 1, INK_FAINT)
        end
        rect(bb, cx + u(3), cy + math.floor(size / 2) - u(34), size - u(6), u(68), PAPER)
        local f = face(MONO, 24)
        local m = metrics(f)
        local label = "NO COVER ART"
        local tw = trackedW(f, label, u(6), true)
        tracked(bb, cx + math.floor((size - tw) / 2), cy + math.floor(size / 2) + math.floor(m.cap / 2),
            f, label, INK_DIM, u(6), true)
    end
    outline(bb, cx, cy, size, size, u(3), INK)

    local mx, mw = ox + L.meta.x, L.meta.w
    local pos = tonumber(s.song)
    local total = tonumber(s.playlistlength)
    local badge = "TRACK --"
    if pos and total then
        badge = string.format("TRACK %d / %d", pos + 1, total)
    end
    local bf = face(MONO, 21)
    local bm = metrics(bf)
    tracked(bb, mx, oy + L.meta.y + bm.cap, bf, badge, INK_DIM, u(4), true)
    rect(bb, mx, oy + L.meta.y + bm.cap + u(14), mw, L.hair, INK)

    local title = c.Title or c.file or "Nothing playing"
    local tf, tlines = fitLines(DISPLAY, title, mw, 3, 66, 34)
    local tm = metrics(tf)
    local artist = c.Artist or c.AlbumArtist
    local af = face(MONO, 36)
    local am = metrics(af)
    local album = c.Album
    local alf = face(BODY, 27)
    local alm = metrics(alf)
    if album and album ~= "" then
        local year = c.Date and c.Date:sub(1, 4)
        if year and year ~= "" then album = album .. "  ·  " .. year end
    end

    local block = #tlines * (tm.cap + u(14)) - u(14)
    if artist and artist ~= "" then block = block + u(26) + am.cap end
    if album and album ~= "" then block = block + u(16) + alm.cap end

    local top = oy + L.meta.y + u(58)
    local bottom = oy + L.meta.bottom - u(64)
    local ty = top + math.max(0, math.floor((bottom - top - block) / 2))
    for _, line in ipairs(tlines) do
        ty = ty + tm.cap
        text(bb, mx, ty, tf, line, INK, false)
        ty = ty + u(14)
    end
    ty = ty - u(14)

    if artist and artist ~= "" then
        ty = ty + u(26) + am.cap
        text(bb, mx, ty, af, elide(af, artist, mw, true), INK, true)
    end
    if album and album ~= "" then
        ty = ty + u(16) + alm.cap
        text(bb, mx, ty, alf, elide(alf, album, mw, false), INK_DIM, false)
    end

    local chips = {}
    local ext = c.file and c.file:match("%.(%w+)$")
    if ext then chips[#chips + 1] = ext:upper() end
    local audio = s.audio or c.Format
    if audio then
        local rate, bits = audio:match("^(%d+):(%w+)")
        if rate then chips[#chips + 1] = string.format("%.1f kHz", tonumber(rate) / 1000) end
        if bits and bits ~= "f" then chips[#chips + 1] = bits .. " BIT" end
    end
    if s.bitrate and s.bitrate ~= "0" then chips[#chips + 1] = s.bitrate .. " KBPS" end

    local chip_y = oy + L.meta.bottom - u(46)
    local chip_x = mx
    for _, label in ipairs(chips) do
        local w = self:paintChip(bb, chip_x, chip_y, label)
        chip_x = chip_x + w + u(12)
    end
    rect(bb, ox + L.x0, oy + L.media_rule, L.cw, L.hair, INK)
end

function MPDPlayer:paintScrubLabels(bb, ox, oy)
    local L = self.L
    local f = face(MONO, 20)
    local m = metrics(f)
    local baseline = oy + L.scrub_label + m.cap
    tracked(bb, ox + L.x0, baseline, f, "ELAPSED", INK_DIM, u(5), true)
    local right = "REMAINING"
    tracked(bb, ox + L.x1 - trackedW(f, right, u(5), true), baseline, f, right, INK_DIM, u(5), true)
    local duration = self:duration()
    local middle = "TOTAL " .. (duration > 0 and formatTime(duration) or "--:--")
    local mwidth = trackedW(f, middle, u(5), true)
    tracked(bb, ox + L.x0 + math.floor((L.cw - mwidth) / 2), baseline, f, middle, INK_DIM, u(5), true)
end

function MPDPlayer:paintTick(bb, ox, oy)
    local L = self.L
    rect(bb, ox, oy + L.tick.y, Screen:getWidth(), L.tick.h, PAPER)
    self:paintScrubber(bb, ox, oy)
    rect(bb, ox + L.x0, oy + L.mid_rule, L.cw, L.hair, INK)
    self:paintSpectrum(bb, ox, oy)
end

function MPDPlayer:paintScrubber(bb, ox, oy)
    local L = self.L
    local elapsed = self:elapsed()
    local duration = self:duration()
    local remaining = duration > 0 and (duration - elapsed) or 0

    local f = face(MONO, 46)
    local m = metrics(f)
    local baseline = oy + L.times + m.cap
    text(bb, ox + L.x0, baseline, f, formatTime(elapsed), INK, true)
    local right = duration > 0 and ("-" .. formatTime(remaining)) or "--:--"
    text(bb, ox + L.x1 - textW(f, right, false), baseline, f, right, INK, false)

    local bx, by, bh = ox + L.x0, oy + L.bar.y, L.bar.h
    local fraction = 0
    if duration > 0 then fraction = math.max(0, math.min(1, elapsed / duration)) end
    bb:hatchRect(bx + u(3), by + u(3), L.cw - u(6), bh - u(6), u(3), INK, 1)
    local filled = math.floor((L.cw - u(6)) * fraction + 0.5)
    rect(bb, bx + u(3), by + u(3), filled, bh - u(6), INK)
    outline(bb, bx, by, L.cw, bh, u(3), INK)

    local head = bx + u(3) + filled - u(9)
    if head < bx then head = bx end
    if head > bx + L.cw - u(21) then head = bx + L.cw - u(21) end
    rect(bb, head, by - u(13), u(21), bh + u(26), PAPER)
    rect(bb, head + u(6), by - u(13), u(9), bh + u(26), INK)

    self.hits.scrub = { x = bx, y = by - u(22), w = L.cw, h = bh + u(44) }
end

function MPDPlayer:paintSpectrum(bb, ox, oy)
    local L = self.L
    local f = face(MONO, 21)
    local m = metrics(f)
    local baseline = oy + L.spec_row + m.cap
    tracked(bb, ox + L.x0, baseline, f, "SPECTRUM", INK, u(6), true)

    local label, filled = "NO FEED", false
    if not self.vis_enabled then
        label = "MUTED"
    elseif not self:playing() then
        label = "IDLE"
    elseif self.vis_sock and self.vis_state == "L" then
        label = "LIVE"
        filled = true
    elseif self.vis_sock then
        label = "SILENT"
    end
    self:paintTag(bb, ox + L.x1, oy + L.spec_row - u(10), label, filled, 21)

    local bars_x, base_y = ox + L.bars.x, oy + L.bars.baseline
    for _, level in ipairs({ 0.25, 0.5, 0.75, 1.0 }) do
        local gy = base_y - math.floor(L.bars.h * level + 0.5)
        local gx = ox + L.x0
        while gx < ox + L.x1 do
            rect(bb, gx, gy, u(3), u(3), INK)
            gx = gx + u(17)
        end
    end

    local live = self.vis_enabled and self.vis_sock ~= nil
    if live then
        for i = 1, L.bands do
            local x = bars_x + (i - 1) * (L.bar_w + L.bar_gap)
            local value = self.vis_bars[i] or 0
            local segments = math.max(1, math.floor(value / 63 * L.segments + 0.5))
            for s = 1, segments do
                local sy = base_y - s * (L.seg + L.seg_gap) + L.seg_gap
                rect(bb, x, sy, L.bar_w, L.seg, INK)
            end
            local peak = self.vis_peaks[i] or 0
            if peak > 1 then
                local py = base_y - math.floor(peak / 63 * L.bars.h + 0.5) - u(5)
                if py < oy + L.bars.y - u(5) then py = oy + L.bars.y - u(5) end
                rect(bb, x, py, L.bar_w, u(5), INK)
            end
        end
    else
        for i = 1, L.bands do
            local x = bars_x + (i - 1) * (L.bar_w + L.bar_gap)
            rect(bb, x, base_y - L.seg, L.bar_w, L.seg, INK)
        end
        local rf = face(MONO, 23)
        local rm = metrics(rf)
        local msg = "tap to enable"
        if self.vis_enabled then
            if self:playing() then
                msg = self.vis_error or "no feed"
            else
                msg = "playback " .. self:state() .. "ped"
                if self:state() == "pause" then msg = "playback paused" end
            end
        end
        msg = string.upper(msg)
        local tw = trackedW(rf, msg, u(5), true)
        local pad = u(30)
        local bw = math.min(L.cw, tw + pad * 2)
        local bh = rm.cap + u(28)
        local bxx = ox + L.x0 + math.floor((L.cw - bw) / 2)
        local byy = base_y - math.floor(L.bars.h / 2) - math.floor(bh / 2)
        rect(bb, bxx, byy, bw, bh, PAPER)
        outline(bb, bxx, byy, bw, bh, u(3), INK)
        tracked(bb, bxx + math.floor((bw - tw) / 2), byy + math.floor((bh - rm.cap) / 2) + rm.cap,
            rf, msg, INK, u(5), true)
    end
    rect(bb, ox + L.x0, base_y, L.cw, L.hair, INK)
    self.hits.spectrum = { x = ox + L.x0, y = oy + L.spec_row - u(14), w = L.cw, h = L.bars.baseline - L.spec_row + u(20) }
end

function MPDPlayer:paintAxis(bb, ox, oy)
    local L = self.L
    local f = face(MONO, 19)
    local m = metrics(f)
    local baseline = oy + L.axis + m.cap
    local ticks = { "35", "120", "400", "1.4k", "4.7k", "16k" }
    for i, label in ipairs(ticks) do
        local fraction = (i - 1) / (#ticks - 1)
        local w = trackedW(f, label, u(3), false)
        local x = ox + L.x0 + math.floor(L.cw * fraction - w * fraction + 0.5)
        rect(bb, ox + L.x0 + math.floor(L.cw * fraction + 0.5) - (i == #ticks and L.hair or 0),
            oy + L.axis - u(11), L.hair, u(9), INK_DIM)
        tracked(bb, x, baseline, f, label, INK_DIM, u(3), false)
    end
end

function MPDPlayer:searchPages()
    local n = #(self.search_results or {})
    if n == 0 then return 1 end
    return math.ceil(n / self.L.search.rows)
end

function MPDPlayer:paintNotice(bb, ox, oy, top, height, message)
    local L = self.L
    local f = face(MONO, 23)
    local m = metrics(f)
    local tw = trackedW(f, message, u(5), true)
    local pad = u(30)
    local bw = math.min(L.cw, tw + pad * 2)
    local bh = m.cap + u(28)
    local bx = ox + L.x0 + math.floor((L.cw - bw) / 2)
    local by = oy + top + math.floor((height - bh) / 2)
    rect(bb, bx, by, bw, bh, PAPER)
    outline(bb, bx, by, bw, bh, u(3), INK)
    tracked(bb, bx + math.floor((bw - tw) / 2), by + math.floor((bh - m.cap) / 2) + m.cap,
        f, message, INK, u(5), true)
end

function MPDPlayer:paintSearch(bb, ox, oy)
    local L = self.L
    local S = L.search
    local results = self.search_results or {}
    local pages = self:searchPages()
    local page = math.max(1, math.min(self.search_page or 1, pages))
    self.search_page = page

    local qf = face(DISPLAY, 54)
    local qm = metrics(qf)
    local query = self.search_query or ""
    if query == "" then query = "no query yet" end
    text(bb, ox + L.x0, oy + S.query + qm.cap, qf, elide(qf, query, L.cw, false), INK, false)

    local mf = face(MONO, 21)
    local mm = metrics(mf)
    local summary
    if self.search_error then
        summary = string.upper(tostring(self.search_error))
    else
        summary = string.format("%d MATCH%s", #results, #results == 1 and "" or "ES")
        if self.search_truncated then
            summary = summary .. "  ·  CAPPED AT " .. SEARCH_LIMIT
        end
        if pages > 1 then
            summary = summary .. string.format("  ·  PAGE %d / %d", page, pages)
        end
    end
    tracked(bb, ox + L.x0, oy + S.meta + mm.cap, mf, elide(mf, summary, L.cw, true),
        INK_DIM, u(5), true)
    rect(bb, ox + L.x0, oy + S.rule, L.cw, L.hair, INK)

    self.hits.results = {}
    if #results == 0 then
        self:paintNotice(bb, ox, oy, S.y, S.rows * S.pitch,
            self.search_error and "SEARCH FAILED" or "NO MATCHES FOR THAT TERM")
        return
    end

    local nf = face(MONO, 23)
    local tf = face(BODY, 32)
    local af = face(MONO, 24)
    local df = face(MONO, 22)
    local nm, tm, am, dm = metrics(nf), metrics(tf), metrics(af), metrics(df)
    local first = (page - 1) * S.rows

    for i = 1, S.rows do
        local track = results[first + i]
        if not track then break end
        local row_y = oy + S.y + (i - 1) * S.pitch

        tracked(bb, ox + L.x0, row_y + nm.cap, nf, string.format("%02d", first + i), INK_DIM, u(2), true)

        local duration = tonumber(track.duration) or tonumber(track.Time)
        local stamp = duration and formatTime(duration) or ""
        local sw = textW(df, stamp, false)
        if stamp ~= "" then
            text(bb, ox + L.x1 - sw, row_y + dm.cap, df, stamp, INK_DIM, false)
        end

        local tx = ox + L.x0 + u(66)
        local avail = (ox + L.x1 - sw - u(24)) - tx
        text(bb, tx, row_y + tm.cap, tf, elide(tf, trackTitle(track), avail, false), INK, false)

        local byline = trackByline(track)
        if byline ~= "" then
            text(bb, tx, row_y + tm.cap + u(30) + am.cap, af, elide(af, byline, avail, false),
                INK_DIM, false)
        end

        rect(bb, ox + L.x0, row_y + u(84), L.cw, L.hair, INK_FAINT)
        self.hits.results[#self.hits.results + 1] =
            { x = ox + L.x0, y = row_y - u(10), w = L.cw, h = S.pitch, track = track }
    end
end

function MPDPlayer:paintOffline(bb, ox, oy)
    local L = self.L
    local hf = face(MONO, 52)
    local hm = metrics(hf)
    local af = face(MONO, 26)
    local am = metrics(af)
    local ef = face(BODY, 25)
    local em = metrics(ef)
    local rf = face(MONO, 21)
    local rm = metrics(rf)

    local heading = "MPD UNREACHABLE"
    local address = string.format("%s:%d", self.cfg.host, self.cfg.port)
    local reason = tostring(self.error)
    local hint = "TAP ANYWHERE TO RETRY"

    local pad = u(64)
    local body = hm.cap + u(40) + am.cap + u(22) + em.cap + u(46) + rm.cap
    local height = body + pad * 2
    local top = oy + L.head_rule + math.floor(((L.foot_rule - L.head_rule) - height) / 2)

    rect(bb, ox + L.x0, top, L.cw, height, PAPER)
    outline(bb, ox + L.x0, top, L.cw, height, u(3), INK)

    local y = top + pad + hm.cap
    local hw = trackedW(hf, heading, u(9), true)
    tracked(bb, ox + L.x0 + math.floor((L.cw - hw) / 2), y, hf, heading, INK, u(9), true)

    rect(bb, ox + L.x0 + math.floor(L.cw / 2) - u(90), y + u(22), u(180), L.hair, INK)

    y = y + u(40) + am.cap
    local aw = textW(af, address, false)
    text(bb, ox + L.x0 + math.floor((L.cw - aw) / 2), y, af, address, INK, false)

    y = y + u(22) + em.cap
    local ew = textW(ef, reason, false)
    text(bb, ox + L.x0 + math.floor((L.cw - ew) / 2), y, ef, elide(ef, reason, L.cw - pad * 2, false), INK_DIM, false)

    y = y + u(46) + rm.cap
    local rw = trackedW(rf, hint, u(6), true)
    tracked(bb, ox + L.x0 + math.floor((L.cw - rw) / 2), y, rf, hint, INK_DIM, u(6), true)

    self.hits.retry = { x = 0, y = oy + L.head_rule, w = Screen:getWidth(), h = L.foot_rule - L.head_rule }
end

function MPDPlayer:buttons()
    if self.mode == "search" then return self.search_buttons end
    return self.player_buttons
end

function MPDPlayer:paintTransport(bb, ox, oy)
    local L = self.L
    rect(bb, ox, oy + L.transport.y - u(20), Screen:getWidth(), L.transport.h + u(40), PAPER)
    rect(bb, ox + L.x0, oy + L.foot_rule, L.cw, L.heavy, INK)

    local row = self:buttons()
    local count = #row
    local w = math.floor((L.cw - L.transport.gap * (count - 1)) / count)
    local h = L.transport.h
    local y = oy + L.transport.y
    local f = face(MONO, 19)
    local m = metrics(f)

    self.hits.transport = {}
    for i, button in ipairs(row) do
        local x = ox + L.x0 + (i - 1) * (w + L.transport.gap)
        local pressed = self.pressed == button.id
        local ink = pressed and PAPER or INK
        if pressed then
            rect(bb, x, y, w, h, INK)
        else
            outline(bb, x, y, w, h, u(3), INK)
        end

        local label = button.label
        if button.id == "play" then label = self:playing() and "PAUSE" or "PLAY" end
        local tw = trackedW(f, label, u(4), true)
        tracked(bb, x + math.floor((w - tw) / 2), y + h - u(20), f, label, pressed and PAPER or INK_DIM, u(4), true)

        local cx = x + math.floor(w / 2)
        local cy = y + math.floor(h / 2) - u(12)
        self:paintGlyph(bb, button.id, cx, cy, ink, u(46))

        self.hits.transport[i] = { x = x, y = y, w = w, h = h, id = button.id }
    end
end

function MPDPlayer:paintGlyph(bb, id, cx, cy, ink, size)
    size = size or u(34)
    local function g(v) return math.floor(v * size / 34 + 0.5) end
    local half = math.floor(size / 2)
    if id == "prev" or id == "next" or id == "back" then
        local bar = g(6)
        local tw = g(24)
        local top = cy - half
        if id == "back" then
            triangle(bb, cx - math.floor(tw / 2), top, tw, size, "left", ink)
        elseif id == "prev" then
            rect(bb, cx - tw - g(4), top, bar, size, ink)
            triangle(bb, cx - g(2), top, tw, size, "left", ink)
        else
            rect(bb, cx + tw - g(2), top, bar, size, ink)
            triangle(bb, cx - tw + g(2), top, tw, size, "right", ink)
        end
    elseif id == "play" then
        if self:playing() then
            rect(bb, cx - g(13), cy - half, g(10), size, ink)
            rect(bb, cx + g(3), cy - half, g(10), size, ink)
        else
            triangle(bb, cx - g(12), cy - half, g(26), size, "right", ink)
        end
    elseif id == "search" then
        local radius = g(13)
        local thick = g(5)
        ring(bb, cx - g(4), cy - g(4), radius, thick, ink)
        stroke(bb, cx + g(5), cy + g(5), cx + g(14), cy + g(14), thick, ink)
    elseif id == "pageprev" or id == "pagenext" then
        triangleV(bb, cx - half, cy - g(12), size, g(24),
            id == "pageprev" and "up" or "down", ink)
    elseif id == "voldown" or id == "volup" then
        local arm = g(30)
        local thick = g(7)
        rect(bb, cx - math.floor(arm / 2), cy - math.floor(thick / 2), arm, thick, ink)
        if id == "volup" then
            rect(bb, cx - math.floor(thick / 2), cy - math.floor(arm / 2), thick, arm, ink)
        end
    end
end

function MPDPlayer:paintFooter(bb, ox, oy)
    local L = self.L
    rect(bb, ox + L.x0, oy + L.tail_rule, L.cw, L.hair, INK)
    local f = face(MONO, 19)
    local m = metrics(f)
    local baseline = oy + L.footer + m.cap
    tracked(bb, ox + L.x0, baseline, f,
        string.format("MPD %s:%d", self.cfg.host, self.cfg.port), INK_DIM, u(3), false)

    local right
    if self.vis_sock then
        right = string.format("VIS %s:%d / %d BANDS / %d FPS",
            self.cfg.vis_host, self.cfg.vis_port, self.vis_bands, self.cfg.vis_fps)
    else
        right = string.format("VIS %s:%d / DOWN", self.cfg.vis_host, self.cfg.vis_port)
    end
    tracked(bb, ox + L.x1 - trackedW(f, right, u(3), false), baseline, f, right, INK_DIM, u(3), false)
end

local function inside(zone, x, y)
    return zone and x >= zone.x and x < zone.x + zone.w and y >= zone.y and y < zone.y + zone.h
end

function MPDPlayer:command(cmd)
    local ok, sent = pcall(sendCommand, self.cfg, cmd)
    if not ok or sent == false then
        logger.warn("mandragora: mpd: command failed:", cmd)
    end
    self.last_poll = 0
    self:poll()
end

function MPDPlayer:enterSearch()
    self.mode = "search"
    self:visClose(nil)
    self:repaint("all", "full")
end

function MPDPlayer:leaveSearch()
    self.mode = "player"
    self.vis_retry = 0
    self.last_poll = 0
    self:poll()
    self:repaint("all", "full")
end

function MPDPlayer:turnPage(delta)
    local pages = self:searchPages()
    local page = (self.search_page or 1) + delta
    if page < 1 then page = pages end
    if page > pages then page = 1 end
    self.search_page = page
    self:repaint("all", "full")
end

function MPDPlayer:runSearch(query)
    query = tostring(query or ""):gsub("^%s+", "")
    query = query:gsub("%s+$", "")
    if query == "" then
        self:repaint("all", "full")
        return
    end
    self.search_query = query
    self.search_page = 1
    self.search_error = nil
    self.search_truncated = false
    local ok, results, extra = pcall(searchTracks, self.cfg, query)
    if ok and results then
        self.search_results = results
        self.search_truncated = extra and true or false
    else
        self.search_results = {}
        self.search_error = ok and tostring(extra) or tostring(results)
        logger.warn("mandragora: mpd: search failed:", self.search_error)
    end
    self:enterSearch()
end

function MPDPlayer:openSearch()
    local dialog
    dialog = InputDialog:new{
        title = "Search MPD",
        input = self.search_query or "",
        input_hint = "artist, title or album",
        buttons = {{
            {
                text = "Cancel",
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                    self.dialog_open = false
                    self:repaint("all", "full")
                end,
            },
            {
                text = "Search",
                is_enter_default = true,
                callback = function()
                    local query = dialog:getInputText()
                    UIManager:close(dialog)
                    self.dialog_open = false
                    self:runSearch(query)
                end,
            },
        }},
    }
    self.dialog_open = true
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function MPDPlayer:playResult(track)
    if not track or not track.file then return end
    local ok, id, err = pcall(addAndPlay, self.cfg, track.file)
    if ok and id then
        self:leaveSearch()
        return
    end
    self.search_error = ok and tostring(err) or tostring(id)
    logger.warn("mandragora: mpd: play failed:", self.search_error)
    self:repaint("all", "full")
end

function MPDPlayer:press(id)
    self.pressed = id
    self:repaint("transport", "fast")
    UIManager:nextTick(function()
        if self._closed then return end
        local status = (self.data and self.data.status) or {}
        if id == "prev" then
            self:command("previous")
        elseif id == "next" then
            self:command("next")
        elseif id == "play" then
            if status.state == "play" then
                self:command("pause 1")
            elseif status.state == "pause" then
                self:command("pause 0")
            else
                self:command("play")
            end
        elseif id == "voldown" or id == "volup" then
            local volume = tonumber(status.volume) or 50
            local step = id == "volup" and 5 or -5
            volume = math.max(0, math.min(100, volume + step))
            self:command("setvol " .. volume)
        elseif id == "search" then
            self.pressed = nil
            self:repaint("transport", "ui")
            self:openSearch()
            return
        elseif id == "back" then
            self.pressed = nil
            self:leaveSearch()
            return
        elseif id == "pageprev" or id == "pagenext" then
            self.pressed = nil
            self:turnPage(id == "pagenext" and 1 or -1)
            return
        end
        self.pressed = nil
        if self.paint_zone ~= "all" then self:repaint("transport", "ui") end
    end)
end

function MPDPlayer:onTap(_, ges)
    if self.dialog_open then return true end
    local pos = ges and ges.pos
    if not pos then return true end
    local x, y = pos.x, pos.y

    for _, button in ipairs(self.hits.transport or {}) do
        if inside(button, x, y) then
            self:press(button.id)
            return true
        end
    end

    if self.mode == "search" then
        for _, row in ipairs(self.hits.results or {}) do
            if inside(row, x, y) then
                self:playResult(row.track)
                return true
            end
        end
        return true
    end

    if self.hits.retry and inside(self.hits.retry, x, y) then
        self.last_poll = 0
        self:poll()
        self:repaint("all", "full")
        return true
    end

    if inside(self.hits.scrub, x, y) then
        local duration = self:duration()
        if duration > 0 then
            local fraction = (x - self.hits.scrub.x) / self.hits.scrub.w
            fraction = math.max(0, math.min(1, fraction))
            self:command(string.format("seekcur %d", math.floor(duration * fraction)))
            self:repaint("all", "full")
        end
        return true
    end

    if inside(self.hits.spectrum, x, y) then
        self.vis_enabled = not self.vis_enabled
        if self.vis_enabled then
            self:visConnect()
        else
            self:visClose("visualiser off")
        end
        self:repaint("all", "full")
        return true
    end

    return true
end

function MPDPlayer:onDoubleTap()
    if self.dialog_open then return true end
    if self.mode == "search" then
        self:leaveSearch()
        return true
    end
    return self:onClose()
end

function MPDPlayer:onSwipe(_, ges)
    if self.dialog_open then return true end
    if ges.direction == "south" or ges.direction == "north" then
        if self.mode == "search" then
            self:leaveSearch()
            return true
        end
        return self:onClose()
    end
    return true
end

function MPDPlayer:onClose()
    self._closed = true
    self:visClose(nil)
    self:releaseCover()
    UIManager:close(self)
    return true
end

function MPDPlayer:onCloseWidget()
    self._closed = true
    self:visClose(nil)
    self:releaseCover()
    UIManager:setDirty(nil, "full")
end

function MPDPlayer:onShow()
    self.paint_zone = "all"
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function MPDPlayer.open()
    local player = MPDPlayer:new{}
    UIManager:show(player)
    return player
end

return MPDPlayer
