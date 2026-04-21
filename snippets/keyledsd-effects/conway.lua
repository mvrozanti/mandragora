-- conway.lua
-- Conway's Game of Life keyboard effect with persistence fading.

local delay = tonumber(keyleds.config.delay) or 0.15
local fadeSpeed = tonumber(keyleds.config.fadeSpeed) or 0.05

-- Use dynamic keys mapping like snake.lua to support any keyboard or group
keys = keyleds.groups[keyleds.config.group] or keyleds.db
local width = tonumber(keyleds.config.width) or 17
local height = tonumber(keyleds.config.height) or 6

local function tocolorSafe(str, default)
    if str then
        local c = tocolor(str)
        if c then return c end
    end
    return default
end

local colorLive = tocolorSafe(keyleds.config.colorLive, tocolor(0, 1, 0, 1))
local transparent = tocolor(0, 0, 0, 0)

-- Stable grid tables
local grid = {}
local backGrid = {}
local brightness = {}

for y = 1, height do
    grid[y] = {}
    backGrid[y] = {}
    brightness[y] = {}
    for x = 1, width do
        grid[y][x] = (math.random() > 0.85)
        backGrid[y][x] = false
        brightness[y][x] = 0
    end
end

function onKeyEvent(key, isPress)
    if isPress then
        local kx, ky
        for i, k in ipairs(keys) do
            if k == key then
                kx = (i - 1) % width + 1
                ky = math.floor((i - 1) / width) + 1
                break
            end
        end
        if kx and ky then
            -- Spawn life in a 3x3 area
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local ny = (ky + dy - 1) % height + 1
                    local nx = (kx + dx - 1) % width + 1
                    grid[ny][nx] = true
                end
            end
        end
    end
end

local function countNeighbors(x, y)
    local n = 0
    for dy = -1, 1 do
        for dx = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local nx = (x + dx - 1) % width + 1
                local ny = (y + dy - 1) % height + 1
                if grid[ny][nx] then n = n + 1 end
            end
        end
    end
    return n
end

local lastUpdate = 0
local delayMs = delay
if delay < 10 then
    delayMs = delay * 1000
end

local function stepGameLogic()
    local alive = 0
    -- Compute next state into backGrid
    for y = 1, height do
        for x = 1, width do
            local n = countNeighbors(x, y)
            if grid[y][x] then
                backGrid[y][x] = (n == 2 or n == 3)
            else
                backGrid[y][x] = (n == 3)
            end
            if backGrid[y][x] then alive = alive + 1 end
        end
    end
    
    -- Copy backGrid to grid
    for y = 1, height do
        for x = 1, width do
            grid[y][x] = backGrid[y][x]
        end
    end
    
    -- Auto-respawn if dead
    if alive == 0 then
        for i = 1, 15 do
            grid[math.random(1, height)][math.random(1, width)] = true
        end
    end
end

function init()
    buffer = RenderTarget:new()
    if type(keys) ~= "table" then
        local t = {} for i = 1, #keys do table.insert(t, keys[i]) end keys = t
    end
end

function render(ms, target)
    lastUpdate = lastUpdate + ms
    if lastUpdate >= delayMs then
        stepGameLogic()
        lastUpdate = lastUpdate - delayMs
    end

    buffer:fill(transparent)
    
    for i, key in ipairs(keys) do
        local x = (i - 1) % width + 1
        local y = math.floor((i - 1) / width) + 1
        
        if y <= height and x <= width then
            if grid[y][x] then
                brightness[y][x] = 1.0
            else
                -- Smooth fade out
                brightness[y][x] = math.max(0, brightness[y][x] - fadeSpeed)
            end
            
            if brightness[y][x] > 0.01 then
                local b = brightness[y][x]
                buffer[key] = tocolor(colorLive.red * b, colorLive.green * b, colorLive.blue * b, b)
            end
        end
    end
    
    target:blend(buffer)
end

init()
