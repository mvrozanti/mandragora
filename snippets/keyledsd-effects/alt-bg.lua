math = require("math")

local unpack = table.unpack or unpack
keys = keyleds.db

timestamp = 0

if type(keys) ~= "table" then
    local tempKeys = {}
    for i = 1, #keys do
        table.insert(tempKeys, keys[i])
    end
    keys = tempKeys
end

local function readFile()
    local handle = io.popen("cat /home/m/.cache/matugen/wal")
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result
end

function init()
    buffer = RenderTarget:new()
end

function render(ms, target)
    if ms % 1000 < 50 then print("ALT-BG: render called at " .. ms) end
    local wallpaper_path = readFile()
    if math.fmod(timestamp, 300) == 0 then
        if wallpaper_path:find('/sss') then
            buffer:fill(tocolor('magenta'))
        end 
    end
    timestamp = timestamp + 1
    target:blend(buffer)
end

init()
