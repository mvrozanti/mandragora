local unpack = table.unpack or unpack

keys = keyleds.groups[keyleds.config.group] or keyleds.db
width = tonumber(keyleds.config.width) or 13
height = tonumber(keyleds.config.height) or 5
pixelColor = tocolor(keyleds.config.pixelColor) or tocolor('red')
delay = tonumber(keyleds.config.delay) or 100

transparent = tocolor(0, 0, 0, 0)

function init()
    initPixel()
    lastUpdate = 0
    if type(keys) ~= "table" then
        local tempKeys = {}
        for i = 1, #keys do
            table.insert(tempKeys, keys[i])
        end
        keys = tempKeys
    end
end

function initPixel()
    pixel = {x = math.random(1, width), y = math.random(1, height)}
    velocity = {x = math.random(0, 1) * 2 - 1, y = math.random(0, 1) * 2 - 1}
    buffer = RenderTarget:new()
end

function updatePixel()
    velocity.x = velocity.x + (math.random() * 0.4 - 0.2)
    velocity.y = velocity.y + (math.random() * 0.4 - 0.2)

    local length = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
    velocity.x = velocity.x / length
    velocity.y = velocity.y / length

    pixel.x = pixel.x + velocity.x
    pixel.y = pixel.y + velocity.y

    if pixel.x < 1 then
        pixel.x = 1
        velocity.x = -velocity.x
    elseif pixel.x > width then
        pixel.x = width
        velocity.x = -velocity.x
    end

    if pixel.y < 1 then
        pixel.y = 1
        velocity.y = -velocity.y
    elseif pixel.y > height then
        pixel.y = height
        velocity.y = -velocity.y
    end
end

function getCoordsOnGrid(x, y)
    return math.floor((y - 1) * width + x)
end

function renderPixel()
    local pixelCoords = getCoordsOnGrid(math.floor(pixel.x), math.floor(pixel.y))
    if pixelCoords >= #keys then
        pixelCoords = #keys
    end
    local pixelKey = keys[pixelCoords]
    buffer[pixelKey] = pixelColor
end

function render(ms, target)
    buffer:fill(tocolor('black'))
    lastUpdate = lastUpdate + ms
    if lastUpdate >= delay then
        updatePixel()
        lastUpdate = lastUpdate - delay
    end
    renderPixel()
    target:blend(buffer)
end

init()

