local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local socket_ok, socket = pcall(require, "socket")

local Screen = Device.screen

local CONFIG_PATH = "/mnt/us/mandragora/mpd.conf"
local NC_BIN = "/usr/bin/nc"
local TIMEOUT_SECONDS = 3
local QUEUE_LOOKAHEAD = 3

local DEFAULT_CONFIG = {
    host = "192.168.0.27",
    port = 6600,
    refresh_seconds = 0,
}

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
        if key and val and val ~= "" then
            values[key] = val
        end
    end
    fh:close()
    return values
end

local function loadConfig()
    local cfg = {
        host = DEFAULT_CONFIG.host,
        port = DEFAULT_CONFIG.port,
        refresh_seconds = DEFAULT_CONFIG.refresh_seconds,
    }
    local values = parseConfigFile(CONFIG_PATH)
    if values.host and values.host ~= "" then
        cfg.host = values.host
    end
    local port = tonumber(values.port)
    if port and port > 0 and port < 65536 then
        cfg.port = math.floor(port)
    end
    local refresh = tonumber(values.refresh_seconds)
    if refresh and refresh > 0 then
        cfg.refresh_seconds = math.max(10, math.floor(refresh))
    else
        cfg.refresh_seconds = 0
    end
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
    if not nc_ok then
        return nil, "nc not found on device"
    end
    local cmd = string.format(
        "printf %%s %s | timeout %d %s -w %d %s %d 2>/dev/null",
        shellQuote(payload), TIMEOUT_SECONDS + 2, NC_BIN, TIMEOUT_SECONDS,
        shellQuote(host), port)
    local proc = io.popen(cmd, "r")
    if not proc then
        return nil, "failed to spawn nc"
    end
    local out = proc:read("*a")
    proc:close()
    if not out or out == "" then
        return nil, "no response from nc"
    end
    local lines = splitLines(out)
    if not lines[1] or not lines[1]:find("^OK MPD") then
        return nil, "unexpected banner"
    end
    table.remove(lines, 1)
    return lines
end

local function exchange(host, port, payload)
    if socket_ok then
        return socketExchange(host, port, payload)
    end
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

    local current = parseKV(blocks[1])
    local status = parseKV(blocks[2])
    local queue = {}

    local song_pos = tonumber(status.song)
    if song_pos then
        local from = song_pos + 1
        local to = from + QUEUE_LOOKAHEAD
        local qlines = exchange(cfg.host, cfg.port,
            string.format("playlistinfo %d:%d\nclose\n", from, to))
        if qlines then
            local qblocks = splitBlocks(qlines, 1)
            if qblocks then queue = parseTracks(qblocks[1]) end
        end
    end

    return { current = current, status = status, queue = queue }
end

local function sendCommand(cfg, command)
    local lines, err = exchange(cfg.host, cfg.port, command .. "\nclose\n")
    if not lines then return false, err end
    local blocks, berr = splitBlocks(lines, 1)
    if not blocks then return false, berr end
    return true
end

local function playPauseCommand(state)
    if state == "play" then return "pause 1" end
    if state == "pause" then return "pause 0" end
    return "play"
end

local function formatTime(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 0 then seconds = 0 end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
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

    if Device:isTouchDevice() then
        self.ges_events = {
            Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        }
    end
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end

    self:fetchAndBuild()

    if self.cfg.refresh_seconds >= 10 then
        self:scheduleAutoRefresh()
    end
end

function MPDPlayer:scheduleAutoRefresh()
    UIManager:scheduleIn(self.cfg.refresh_seconds, function()
        if self._closed then return end
        self:refresh()
        self:scheduleAutoRefresh()
    end)
end

function MPDPlayer:fetchAndBuild()
    local ok, data, err = pcall(queryNowPlaying, self.cfg)
    if ok and data then
        self.data = data
        self.error = nil
    else
        self.data = nil
        self.error = (ok and err) or tostring(data)
        logger.warn("mandragora: mpd: fetch failed:", self.error)
    end
    self:build()
end

function MPDPlayer:refresh()
    self:fetchAndBuild()
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

function MPDPlayer:sendAndRefresh(command)
    local ok, cerr = pcall(sendCommand, self.cfg, command)
    if not ok or cerr == false then
        logger.warn("mandragora: mpd: command failed:", command)
    end
    self:refresh()
end

function MPDPlayer:build()
    local width = Screen:getWidth()
    local height = Screen:getHeight()
    local content
    if self.error then
        content = self:buildErrorView(width)
    else
        content = self:buildPlayerView(width)
    end

    self[1] = FrameContainer:new{
        width = width,
        height = height,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            content,
        },
    }
end

function MPDPlayer:buildErrorView(width)
    local text_width = width - Screen:scaleBySize(140)
    return VerticalGroup:new{
        align = "center",
        TextBoxWidget:new{
            text = "MPD unreachable",
            face = Font:getFace("tfont", 48),
            alignment = "center",
            width = text_width,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(28) },
        TextBoxWidget:new{
            text = tostring(self.error),
            face = Font:getFace("infofont", 26),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            alignment = "center",
            width = text_width,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(56) },
        Button:new{
            text = "Retry",
            width = Screen:scaleBySize(260),
            text_font_size = 30,
            callback = function() self:refresh() end,
        },
    }
end

function MPDPlayer:buildPlayerView(width)
    local content_width = width - Screen:scaleBySize(160)
    local data = self.data
    local current = data.current or {}
    local status = data.status or {}
    local queue = data.queue or {}

    local title = current.Title or current.file or "Nothing playing"
    local artist = current.Artist or ""
    local album = current.Album or ""
    local subtitle = artist
    if album ~= "" then
        subtitle = (artist ~= "" and (artist .. " — " .. album)) or album
    end

    local elapsed = tonumber(status.elapsed) or 0
    local duration = tonumber(current.duration) or tonumber(status.duration) or 0
    local percentage = 0
    if duration > 0 then
        percentage = math.min(1, math.max(0, elapsed / duration))
    end

    local state = status.state or "stop"
    local state_label = "Stopped"
    if state == "play" then state_label = "Playing"
    elseif state == "pause" then state_label = "Paused" end

    local volume = tonumber(status.volume) or -1
    local volume_label = volume >= 0 and (volume .. "%") or "n/a"

    local group = VerticalGroup:new{ align = "center" }

    table.insert(group, TextBoxWidget:new{
        text = title,
        face = Font:getFace("tfont", 60),
        alignment = "center",
        width = content_width,
    })

    if subtitle ~= "" then
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(16) })
        table.insert(group, TextBoxWidget:new{
            text = subtitle,
            face = Font:getFace("cfont", 38),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            alignment = "center",
            width = content_width,
        })
    end

    table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(40) })
    table.insert(group, ProgressWidget:new{
        width = content_width,
        height = Screen:scaleBySize(16),
        percentage = percentage,
    })
    table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(12) })
    table.insert(group, TextWidget:new{
        text = formatTime(elapsed) .. " / " .. formatTime(duration),
        face = Font:getFace("cfont", 30),
    })

    table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(20) })
    table.insert(group, TextWidget:new{
        text = state_label .. "   ·   Vol " .. volume_label,
        face = Font:getFace("cfont", 30),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    })

    table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(32) })
    table.insert(group, LineWidget:new{
        background = Blitbuffer.COLOR_GRAY,
        dimen = Geom:new{ w = content_width, h = Size.line.medium },
    })
    table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(24) })

    if #queue > 0 then
        table.insert(group, TextWidget:new{
            text = "Up next",
            face = Font:getFace("cfont", 28),
            bold = true,
        })
        table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(12) })
        for i, track in ipairs(queue) do
            local label = track.Title or track.file or "unknown"
            if track.Artist then label = label .. " — " .. track.Artist end
            table.insert(group, TextBoxWidget:new{
                text = i .. ". " .. label,
                face = Font:getFace("infofont", 26),
                width = content_width,
            })
        end
    else
        table.insert(group, TextWidget:new{
            text = "Queue is empty",
            face = Font:getFace("infofont", 26),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })
    end

    table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(56) })
    table.insert(group, self:buildControls(state))

    return group
end

function MPDPlayer:buildControls(state)
    local button_width = Screen:scaleBySize(230)
    local play_label = state == "play" and "Pause" or "Play"

    local prev_button = Button:new{
        text = "<< Prev",
        width = button_width,
        text_font_size = 32,
        callback = function() self:sendAndRefresh("previous") end,
    }
    local play_button = Button:new{
        text = play_label,
        width = button_width,
        text_font_size = 32,
        callback = function() self:sendAndRefresh(playPauseCommand(state)) end,
    }
    local next_button = Button:new{
        text = "Next >>",
        width = button_width,
        text_font_size = 32,
        callback = function() self:sendAndRefresh("next") end,
    }

    local row = HorizontalGroup:new{
        prev_button,
        HorizontalSpan:new{ width = Screen:scaleBySize(24) },
        play_button,
        HorizontalSpan:new{ width = Screen:scaleBySize(24) },
        next_button,
    }

    local refresh_button = Button:new{
        text = "Refresh",
        width = Screen:scaleBySize(190),
        text_font_size = 26,
        callback = function() self:refresh() end,
    }

    return VerticalGroup:new{
        align = "center",
        row,
        VerticalSpan:new{ width = Screen:scaleBySize(28) },
        refresh_button,
    }
end

function MPDPlayer:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    return true
end

function MPDPlayer:onClose()
    self._closed = true
    UIManager:close(self)
    return true
end

function MPDPlayer:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

function MPDPlayer:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function MPDPlayer.open()
    local player = MPDPlayer:new{}
    UIManager:show(player)
    return player
end

return MPDPlayer
