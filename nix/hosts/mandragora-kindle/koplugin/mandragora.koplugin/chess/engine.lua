local logger = require("logger")

local Engine = {}

local DEFAULTS = {
    host = "192.168.0.27",
    port = 6613,
    skill = 8,
    movetime = 1200,
    timeout = 12,
}

local CONFIG_PATH = "/mnt/us/mandragora/chess.conf"

local function numberOr(values, key, fallback, low, high)
    local raw = tonumber(values[key])
    if not raw then return fallback end
    if low and raw < low then return low end
    if high and raw > high then return high end
    return raw
end

function Engine.readConfig(path)
    local cfg = {}
    for k, v in pairs(DEFAULTS) do cfg[k] = v end

    local fh = io.open(path or CONFIG_PATH, "r")
    if not fh then return cfg end

    local values = {}
    for line in fh:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key and not line:match("^%s*#") then values[key] = value end
    end
    fh:close()

    if values.host and values.host ~= "" then cfg.host = values.host end
    cfg.port = numberOr(values, "port", cfg.port, 1, 65535)
    cfg.skill = numberOr(values, "skill", cfg.skill, 0, 20)
    cfg.movetime = numberOr(values, "movetime", cfg.movetime, 50, 20000)
    cfg.timeout = numberOr(values, "timeout", cfg.timeout, 2, 60)
    return cfg
end

local function request(cfg, line)
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

    sock:send(line .. "\n")
    local reply, rerr = sock:receive("*l")
    sock:send("QUIT\n")
    sock:close()

    if not reply then return nil, rerr or "no reply" end
    return reply
end

function Engine.ping(cfg)
    local reply, err = request(cfg, "PING")
    if not reply then return false, err end
    return reply == "PONG", reply
end

function Engine.bestMove(cfg, fen)
    local reply, err = request(cfg,
        string.format("BESTMOVE %d %d %s", cfg.skill, cfg.movetime, fen))
    if not reply then return nil, err end

    local uci = reply:match("^MOVE%s+(%S+)$")
    if not uci then
        logger.warn("mandragora: chess: engine said", reply)
        return nil, reply
    end
    if uci == "none" then return nil, "none" end
    return uci
end

function Engine.evaluate(cfg, fen)
    local reply, err = request(cfg, string.format("EVAL %d %s", cfg.movetime, fen))
    if not reply then return nil, err end

    local cp = reply:match("^CP%s+(-?%d+)$")
    if cp then return { cp = tonumber(cp) } end

    local mate = reply:match("^MATE%s+(-?%d+)$")
    if mate then return { mate = tonumber(mate) } end

    return nil, reply
end

function Engine.describe(cfg)
    return string.format("%s:%d skill %d", cfg.host, cfg.port, cfg.skill)
end

Engine.DEFAULTS = DEFAULTS
Engine.CONFIG_PATH = CONFIG_PATH

return Engine
