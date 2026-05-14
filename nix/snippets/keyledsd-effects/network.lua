local unpack = table.unpack or unpack
keys = keyleds.db
minColor = tocolor(keyleds.config.minColor) or tocolor(0, 0, 0)
maxColor = tocolor(keyleds.config.maxColor) or tocolor(1, 0, 0)
smoothingFactor = 0.1

if type(keys) ~= "table" then
    local tempKeys = {}
    for i = 1, #keys do
        table.insert(tempKeys, keys[i])
    end
    keys = tempKeys
end

function getKeyFromName(keyName)
    for _, key in ipairs(keys) do
        if key.name == keyName then
            return key
        end
    end
    return nil
end

function getNetworkStats()
    local handle = io.popen("ifstat eno1")
    local result = handle:read("*a")
    handle:close()
    return result
end

function parseNetworkStats(stats)
    local lines = {}
    for line in stats:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    if #lines >= 4 then
        local data = {}
        for value in lines[4]:gmatch("%S+") do
            table.insert(data, tonumber(value))
        end
        if #data >= 8 then
            return data[5], data[7]
        end
    end
    return nil, nil
end

local avgRx, avgTx = 0, 0

function updateLEDColor(rx, tx)
    local scrollLockKey = getKeyFromName("SCROLLLOCKLED")
    if not scrollLockKey then return end

    avgRx = avgRx * (1 - smoothingFactor) + rx * smoothingFactor
    avgTx = avgTx * (1 - smoothingFactor) + tx * smoothingFactor

    local intensity = math.min(math.max(avgRx, avgTx) / 128000, 1)
    local color = interpolate(minColor, maxColor, intensity)
    buffer[scrollLockKey] = color
end

function interpolate(color1, color2, percentage)
    local r1, g1, b1 = color1.red, color1.green, color1.blue
    local r2, g2, b2 = color2.red, color2.green, color2.blue

    local red = r1 * (1 - percentage) + r2 * percentage
    local green = g1 * (1 - percentage) + g2 * percentage
    local blue = b1 * (1 - percentage) + b2 * percentage
    return tocolor(red, green, blue)
end

function init()
    buffer = RenderTarget:new()
end

function render(ms, target)
    local stats = getNetworkStats()
    local rx, tx = parseNetworkStats(stats)
    if rx and tx then
        thread(updateLEDColor, rx, tx)
    end
    target:blend(buffer)
end

init()
