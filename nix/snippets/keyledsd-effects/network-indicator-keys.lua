-- network-indicator-keys.lua
-- Shows network activity on dedicated indicator keys.
-- Top row (Upload): sysrq, scrolllock, pause
-- Center row (Sum): insert, home, pageup
-- Bottom row (Download): delete, end, pagedown

local mode = keyleds.config.mode or "meter"
local interface = keyleds.config.interface or "eno1"
local pollInterval = tonumber(keyleds.config.pollInterval) or 1000
local smoothingFactor = tonumber(keyleds.config.smoothingFactor) or 0.5
local baseThreshold = tonumber(keyleds.config.threshold) or 131072 -- 128 KB/s minimum peak
local windowSize = tonumber(keyleds.config.windowSize) or 10 -- seconds for rolling peak

local function tocolorSafe(str, default)
    if str then
        local c = tocolor(str)
        if c then return c end
    end
    return default
end

local function parseColorList(str, defaultList)
    if type(str) ~= "string" or str == "" then return defaultList end
    local list = {}
    for c in str:gmatch("([^,]+)") do
        table.insert(list, tocolorSafe(c, tocolor(1, 1, 1)))
    end
    if #list == 0 then return defaultList end
    return list
end

local gradientColors = parseColorList(keyleds.config.gradientColors, {
    tocolor(0, 0.8, 0, 1), -- Green (Low)
    tocolor(1, 1, 0, 1),   -- Yellow (Medium)
    tocolor(1, 0, 0, 1)    -- Red (High)
})

-- Key groups (Horizontal Left-to-Right layout)
local uploadKeys = { "sysrq", "scrolllock", "pause" }
local sumKeys = { "insert", "home", "pageup" }
local downloadKeys = { "delete", "end", "pagedown" }

local keys = keyleds.db
if type(keys) ~= "table" then
    local tempKeys = {}
    for i = 1, #keys do table.insert(tempKeys, keys[i]) end
    keys = tempKeys
end

local keyCache = {}
local function getKey(keyName)
    if not keyCache[keyName] then
        for _, key in ipairs(keys) do
            if key.name:lower() == keyName:lower() then
                keyCache[keyName] = key
                break
            end
        end
    end
    return keyCache[keyName]
end

-- Thread-safe communication queue
local stateQueue = {}

-- Main render state
local state = {
    avgRx = 0, avgTx = 0,
    maxRx = baseThreshold, maxTx = baseThreshold,
    meterPeak = { tx = 0, rx = 0, sum = 0 }
}

-- Helpers
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function normalizeIntensity(val, peak)
    local effectivePeak = math.max(peak or baseThreshold, baseThreshold)
    return clamp(val / effectivePeak, 0, 1)
end

-- Network polling thread
local function updateNetworkStats()
    local lRx, lTx = 0, 0
    local lAvgRx, lAvgTx = 0, 0
    local historyRx, historyTx = {}, {}
    
    local rxFile = io.open("/sys/class/net/" .. interface .. "/statistics/rx_bytes", "r")
    local txFile = io.open("/sys/class/net/" .. interface .. "/statistics/tx_bytes", "r")
    if rxFile and txFile then
        lRx = tonumber(rxFile:read("*l")) or 0
        lTx = tonumber(txFile:read("*l")) or 0
        rxFile:close()
        txFile:close()
    end

    while true do
        rxFile = io.open("/sys/class/net/" .. interface .. "/statistics/rx_bytes", "r")
        txFile = io.open("/sys/class/net/" .. interface .. "/statistics/tx_bytes", "r")
        
        if rxFile and txFile then
            local rx = tonumber(rxFile:read("*l")) or lRx
            local tx = tonumber(txFile:read("*l")) or lTx
            rxFile:close()
            txFile:close()

            local deltaRx = math.max(0, rx - lRx)
            local deltaTx = math.max(0, tx - lTx)

            table.insert(historyRx, deltaRx)
            if #historyRx > windowSize then table.remove(historyRx, 1) end
            table.insert(historyTx, deltaTx)
            if #historyTx > windowSize then table.remove(historyTx, 1) end

            local maxRx, maxTx = baseThreshold, baseThreshold
            for _, v in ipairs(historyRx) do if v > maxRx then maxRx = v end end
            for _, v in ipairs(historyTx) do if v > maxTx then maxTx = v end end

            lAvgRx = lAvgRx * (1 - smoothingFactor) + deltaRx * smoothingFactor
            lAvgTx = lAvgTx * (1 - smoothingFactor) + deltaTx * smoothingFactor
            lRx = rx
            lTx = tx

            -- Push to queue safely
            table.insert(stateQueue, {
                avgRx = lAvgRx, avgTx = lAvgTx,
                maxRx = maxRx, maxTx = maxTx
            })
            -- Prevent queue from growing too large if render is blocked
            if #stateQueue > 10 then table.remove(stateQueue, 1) end
        end
        wait(pollInterval / 1000.0)
    end
end

local transparent = tocolor(0, 0, 0, 0)

local function renderMeter()
    local txI = normalizeIntensity(state.avgTx, state.maxTx)
    local rxI = normalizeIntensity(state.avgRx, state.maxRx)
    local sumI = normalizeIntensity(state.avgRx + state.avgTx, state.maxRx + state.maxTx)

    if txI > state.meterPeak.tx then state.meterPeak.tx = txI end
    if rxI > state.meterPeak.rx then state.meterPeak.rx = rxI end
    if sumI > state.meterPeak.sum then state.meterPeak.sum = sumI end

    local function meterKeys(keysArr, intensity, peak)
        for i = 1, 3 do
            local k = getKey(keysArr[i])
            if k then
                -- Each key represents a third of the meter (left to right)
                local keyStart = (i - 1) / 3.0
                local keyEnd = i / 3.0
                
                -- Determine how much of this key's "chunk" is filled
                local fill = clamp((intensity - keyStart) / (keyEnd - keyStart), 0, 1)
                local peakFill = clamp((peak - keyStart) / (keyEnd - keyStart), 0, 1)
                
                -- The color is strictly bound to the physical key position:
                -- 1st key = gradient 1 (e.g. Green)
                -- 2nd key = gradient 2 (e.g. Yellow)
                -- 3rd key = gradient 3 (e.g. Red)
                local colorIdx = math.min(i, #gradientColors)
                local baseColor = gradientColors[colorIdx]

                if fill > 0.01 then
                    -- Normal active bar
                    buffer[k] = tocolor(baseColor.red, baseColor.green, baseColor.blue, fill)
                elseif peakFill > 0.01 then
                    -- Dim peak marker (leaves a fading trail)
                    buffer[k] = tocolor(baseColor.red * 0.4, baseColor.green * 0.4, baseColor.blue * 0.4, peakFill * 0.5)
                end
            end
        end
    end

    -- Top Row = Upload
    meterKeys(uploadKeys, txI, state.meterPeak.tx)
    
    -- Center Row = Sum
    meterKeys(sumKeys, sumI, state.meterPeak.sum)
    
    -- Bottom Row = Download
    meterKeys(downloadKeys, rxI, state.meterPeak.rx)

    -- Slowly drop peak
    state.meterPeak.tx = math.max(0, state.meterPeak.tx - 0.002)
    state.meterPeak.rx = math.max(0, state.meterPeak.rx - 0.002)
    state.meterPeak.sum = math.max(0, state.meterPeak.sum - 0.002)
end

function init()
    buffer = RenderTarget:new()
    threadStarted = true
    thread(updateNetworkStats)
end

function render(ms, target)
    -- Drain updates from thread
    while #stateQueue > 0 do
        local update = table.remove(stateQueue, 1)
        state.avgRx = update.avgRx
        state.avgTx = update.avgTx
        state.maxRx = update.maxRx
        state.maxTx = update.maxTx
    end

    buffer:fill(transparent)
    renderMeter()
    target:blend(buffer)
end

init()