local unpack = table.unpack or unpack

keys = keyleds.groups[keyleds.config.group] or keyleds.db
width = tonumber(keyleds.config.width) or 13
height = tonumber(keyleds.config.height) or 5
snakeColor = tocolor(keyleds.config.snakeColor) or tocolor('green')
foodColor = tocolor(keyleds.config.foodColor) or tocolor('red')
snakeHeadColor = tocolor(keyleds.config.snakeHeadColor) or tocolor('orange')
snakeTailColor = tocolor(keyleds.config.snakeTailColor) or tocolor('purple')
delay = tonumber(keyleds.config.delay) or 100
onKey = keyleds.config.onKey or true

transparent = tocolor(0, 0, 0, 0)

function precomputeHamiltonianCycle(width, height)
    local cycle = {}
    for y = 1, height do
        if y % 2 == 1 then
            for x = 1, width do
                table.insert(cycle, {x = x, y = y})
            end
        else
            for x = width, 1, -1 do
                table.insert(cycle, {x = x, y = y})
            end
        end
    end
    table.insert(cycle, cycle[1])
    return cycle
end

hamiltonianCycle = precomputeHamiltonianCycle(width, height)

function init()
    initGame()
    lastUpdate = 0
    if type(keys) ~= "table" then
        local tempKeys = {}
        for i = 1, #keys do
            table.insert(tempKeys, keys[i])
        end
        keys = tempKeys
    end
end

function initGame()
    snake = {{x = 4, y = 1}, {x = 3, y = 1}, {x = 2, y = 1}}
    direction = {x = 1, y = 0}
    placeFood()
    buffer = RenderTarget:new()
end

function collides(a, b)
    return a.x == b.x and a.y == b.y
end

function bfs(start, goal)
    local queue = {{start}}
    local visited = {}
    visited[getCoordsOnGrid(start.x, start.y)] = true

    while #queue > 0 do
        local path = table.remove(queue, 1)
        local current = path[#path]

        if current.x == goal.x and current.y == goal.y then
            return path
        end

        for _, dir in ipairs({{x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}}) do
            local next = {x = current.x + dir.x, y = current.y + dir.y}

            if next.x < 1 or next.x > width or next.y < 1 or next.y > height then
                goto continue
            end

            local nextCoords = getCoordsOnGrid(next.x, next.y)

            if not visited[nextCoords] and not collidesWithSnake(next, path) then
                visited[nextCoords] = true
                local newPath = {unpack(path)}
                table.insert(newPath, next)
                table.insert(queue, newPath)
            end
            ::continue::
        end
    end
end

function collidesWithSnake(pos, path)
    for i = 1, #snake do
        if collides(snake[i], pos) then
            return true
        end
    end
    for _, step in ipairs(path) do
        if collides(step, pos) then
            return true
        end
    end
    return false
end

function isFoodReachable(food)
    local head = snake[1]
    local path = bfs(head, food)
    return path ~= nil
end

function placeFood()
    local attempts = 0
    repeat
        food = {x = math.random(1, width), y = math.random(1, height)}
        attempts = attempts + 1
    until isFoodReachable(food) or attempts > 10000
end

function updateDirection()
    local head = snake[1]
    local path = bfs(head, food)
    if path and #path > 1 then
        local nextPos = path[2]
        direction = {x = nextPos.x - head.x, y = nextPos.y - head.y}
    else
        local nextIndex
        for i, pos in ipairs(hamiltonianCycle) do
            if pos.x == head.x and pos.y == head.y then
                nextIndex = i + 1
                break
            end
        end
        if nextIndex > #hamiltonianCycle then
            nextIndex = 1
        end
        local nextPos = hamiltonianCycle[nextIndex]
        direction = {x = nextPos.x - head.x, y = nextPos.y - head.y}
    end
end

function updateSnake()
    updateDirection()
    local head = snake[1]
    local newHead = {x = head.x + direction.x, y = head.y + direction.y}

    if newHead.x < 1 or newHead.x > width or newHead.y < 1 or newHead.y > height then
        initGame()
        return
    end

    local ateFood = (newHead.x == food.x and newHead.y == food.y)

    if ateFood then
        if #snake + 4 >= width * height then
            initGame()
            return
        else
            placeFood()
        end
    else
        table.remove(snake)
    end

    for i = 2, #snake do
        local segment = snake[i]
        if collides(segment, newHead) then
            initGame()
            return
        end
    end

    table.insert(snake, 1, newHead)
end

function getCoordsOnGrid(x, y)
    return (y - 1) * width + x
end

function renderFood()
    local foodCoords = getCoordsOnGrid(food.x, food.y)
    if foodCoords >= #keys then
        foodCoords = #keys
    end
    local foodKey = keys[foodCoords]
    buffer[foodKey] = foodColor
end

function renderSnake()
    for i, segment in ipairs(snake) do
        local segmentCoords = getCoordsOnGrid(segment.x, segment.y)
        if segmentCoords >= #keys then
            segmentCoords = #keys
        end
        local key = keys[segmentCoords]
        if i == 1 then
            buffer[key] = snakeHeadColor
        elseif i == #snake then
            buffer[key] = snakeTailColor
        else
            buffer[key] = snakeColor
        end
    end
end

function onKeyEvent(key, isPress)
    if not isPress then return end

    for i, k in ipairs(keys) do
        if k == key then
            local foodPosition = {x = (i - 1) % width + 1, y = math.floor((i - 1) / width) + 1}
            if not collidesWithSnake(foodPosition, {}) then
                food = foodPosition
            end
            break
        end
    end
end

function render(ms, target)
    buffer:fill(tocolor('black'))
    lastUpdate = lastUpdate + ms
    if lastUpdate >= delay then
        updateSnake()
        lastUpdate = lastUpdate - delay
    end
    renderFood()
    renderSnake()
    target:blend(buffer)
end

