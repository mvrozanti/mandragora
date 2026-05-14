transparent = tocolor(0, 0, 0, 0)

rows = {
    {"ESC","F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"},
    {"1","2","3","4","5","6","7","8","9","0","MINUS","EQUAL","BACKSPACE"},
    {"TAB","Q","W","E","R","T","Y","U","I","O","P","LBRACE","RBRACE"},
    {"CAPSLOCK","A","S","D","F","G","H","J","K","L","SEMICOLON","APOSTROPHE","ENTER"},
    {"LSHIFT","Z","X","C","V","B","N","M","COMMA","DOT","SLASH","RSHIFT"},
    {"LCTRL","FN","LMETA","LALT","SPACE","RALT","COMPOSE","RCTRL"},
}

function strike(buffer)
    local startColor = tocolor(keyleds.config.startColor) or tocolor(1, 1, 1, 1)
    local endColor   = tocolor(keyleds.config.endColor)   or tocolor(0, 0.04, 0.25, 1)
    local numJumps   = tonumber(keyleds.config.numJumps)  or 8
    local fadeTime   = tonumber(keyleds.config.fadeTime)  or 0.5

    local grid = {}
    for r, row in ipairs(rows) do
        grid[r] = {}
        for c, name in ipairs(row) do
            grid[r][c] = keyleds.db:findName(name)
        end
    end
    local nrows = #grid

    while true do
        wait(0.2 + math.random() * 1.8)

        local path, seen = {}, {}
        local r, c = 1, math.random(#grid[1])

        for _ = 1, numJumps do
            if r > nrows then r = 1 end
            local row = grid[r]
            if row and #row > 0 then
                c = math.max(1, math.min(#row, c))
                local key = row[c]
                if key and not seen[key] then
                    path[#path + 1] = key
                    seen[key] = true
                end
                if math.random() < 0.75 then r = r + 1 end
                c = c + math.random(-2, 2)
            end
        end

        if #path > 0 then
            for _, k in ipairs(path) do buffer[k] = startColor end
            wait(0.035)
            for _, k in ipairs(path) do
                buffer[k] = fade(fadeTime * 0.35, startColor, endColor)
            end
            wait(fadeTime * 0.35)
            for _, k in ipairs(path) do
                buffer[k] = fade(fadeTime * 0.65, endColor, transparent)
            end
            wait(fadeTime * 0.65)
            for _, k in ipairs(path) do buffer[k] = transparent end
        end
    end
end

buffer = RenderTarget:new()
thread(strike, buffer)
thread(strike, buffer)

function render(ms, target) target:blend(buffer) end
