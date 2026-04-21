local unpack = table.unpack or unpack

keys = keyleds.groups[keyleds.config.group] or keyleds.db
width = tonumber(keyleds.config.width) or 13
height = tonumber(keyleds.config.height) or 5
maxIterations = tonumber(keyleds.config.maxIterations) or 100
escapeRadius = tonumber(keyleds.config.escapeRadius) or 2
delay = tonumber(keyleds.config.delay) or 100

transparent = tocolor(0, 0, 0, 0)

local initialMinX, initialMaxX = -2.5, 1.5
local initialMinY, initialMaxY = -1, 1
local minX, maxX = initialMinX, initialMaxX
local minY, maxY = initialMinY, initialMaxY
local zoomFactor = 0.98
local centerX, centerY = -0.5, 0

function init()
    buffer = RenderTarget:new()
    lastUpdate = 0
    drawMandelbrot()
end

function mandelbrot(c)
    local z = {r = 0, i = 0}
    local iterations = 0
    while z.r * z.r + z.i * z.i < escapeRadius * escapeRadius and iterations < maxIterations do
        local zr = z.r * z.r - z.i * z.i + c.r
        z.i = 2 * z.r * z.i + c.i
        z.r = zr
        iterations = iterations + 1
    end
    return iterations
end

function drawMandelbrot()
    buffer:fill(tocolor('black'))
    local totalIterations = 0

    for y = 1, height do
        for x = 1, width do
            local cx = minX + (x - 1) / (width - 1) * (maxX - minX)
            local cy = minY + (y - 1) / (height - 1) * (maxY - minY)
            local c = {r = cx, i = cy}
            local iterations = mandelbrot(c)
            totalIterations = totalIterations + iterations
            local color = getColor(iterations)
            setPixel(x, y, color)
        end
    end

    return totalIterations / (width * height)
end

function getColor(iterations)
    if iterations == maxIterations then
        return tocolor(0, 0, 0)  -- Points inside the Mandelbrot set are black
    else
        local hue = math.floor((iterations / maxIterations) * 360)
        return hsvToRgb(hue, 1, 1)  -- Convert hue to RGB
    end
end

function hsvToRgb(h, s, v)
    local r, g, b

    local i = math.floor(h / 60) % 6
    local f = (h / 60) - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)

    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
    end

    return tocolor(r * 255, g * 255, b * 255)
end

function setPixel(x, y, color)
    if x < 1 or x > width or y < 1 or y > height then
        return
    end
    local coords = getCoordsOnGrid(x, y)
    if coords > #keys then
        return
    end
    local key = keys[coords]
    buffer[key] = color
end

function getCoordsOnGrid(x, y)
    return (y - 1) * width + x
end

function updateZoom(avgIterations)
    local widthDiff = (maxX - minX) * (1 - zoomFactor)
    local heightDiff = (maxY - minY) * (1 - zoomFactor)

    minX = centerX - (centerX - minX) * zoomFactor
    maxX = centerX + (maxX - centerX) * zoomFactor
    minY = centerY - (centerY - minY) * zoomFactor
    maxY = centerY + (maxY - centerY) * zoomFactor

    -- Reset to a random point if the region is too homogeneous
    if avgIterations < maxIterations / 10 or avgIterations > maxIterations * 0.9 then
        resetZoom()
    else
        -- Adjust the center to keep within interesting regions
        centerX = centerX + (math.random() - 0.5) * 0.1
        centerY = centerY + (math.random() - 0.5) * 0.1
    end
end

function resetZoom()
    minX, maxX = initialMinX, initialMaxX
    minY, maxY = initialMinY, initialMaxY
    centerX = minX + math.random() * (maxX - minX)
    centerY = minY + math.random() * (maxY - minY)
    print("Resetting zoom to new random region")
end

function render(ms, target)
    lastUpdate = lastUpdate + ms
    if lastUpdate >= delay then
        local avgIterations = drawMandelbrot()
        updateZoom(avgIterations)
        lastUpdate = lastUpdate - delay
    end
    target:blend(buffer)
end

init()

