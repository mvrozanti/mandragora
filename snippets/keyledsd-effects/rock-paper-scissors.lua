local unpack = table.unpack or unpack

graph = {
    ["ESC"] = {"F1", "GRAVE", "1"},
    ["F1"] = {"ESC", "F2", "1", "2", "3"},
    ["F2"] = {"F1", "F3", "2", "3"},
    ["F3"] = {"F2", "F4", "3", "4", "5"},
    ["F4"] = {"F3", "F5", "4", "5", "6"},
    ["F5"] = {"F4", "5", "6", "7", "F6"},
    ["F6"] = {"F5", "F7", "6", "7", "8"},
    ["F7"] = {"F6", "F8", "7", "8", "9"},
    ["F8"] = {"F7", "F9", "8", "9", "MINUS"},
    ["F9"] = {"F8", "F10", "0", "MINUS", "EQUAL"},
    ["F10"] = {"F9", "F11", "MINUS", "EQUAL", "BACKSPACE"},
    ["F11"] = {"F10", "F12", "EQUAL", "BACKSPACE"},
    ["F12"] = {"F11", "SYSRQ", "BACKSPACE", "INSERT"},
    ["SYSRQ"] = {"F12", "BACKSPACE", "INSERT", "SCROLLLOCK", "HOME"},
    ["SCROLLLOCK"] = {"SYSRQ", "PAUSE", "INSERT", "HOME", "PAGEUP"},
    ["PAUSE"] = {"SCROLLLOCK", "HOME", "PAGEUP"},
    ["GRAVE"] = {"ESC", "1", "Q", "TAB", "F1"},
    ["1"] = {"GRAVE", "2", "W", "Q", "TAB", "ESC", "F1"},
    ["2"] = {"1", "3", "F1", "F2", "Q", "W"},
    ["3"] = {"2", "4", "F1", "F2", "F3", "W", "E", "R"},
    ["4"] = {"3", "5", "F3", "F4", "E", "R"},
    ["5"] = {"4", "6", "F4", "F5", "R", "T"},
    ["6"] = {"5", "7", "F5", "F6", "T", "Y"},
    ["7"] = {"6", "8", "F6", "F7", "Y", "U"},
    ["8"] = {"7", "9", "F7", "F8", "U", "I"},
    ["9"] = {"8", "0", "F8", "F9", "I", "O"},
    ["0"] = {"9", "MINUS", "F9", "F10", "O", "P"},
    ["MINUS"] = {"0", "EQUAL", "F8", "F9", "F10", "P", "LBRACE"},
    ["EQUAL"] = {"MINUS", "BACKSPACE", "F10", "F11", "LBRACE", "RBRACE"},
    ["BACKSPACE"] = {"EQUAL", "F11", "F12", "INSERT", "RBRACE", "BACKSLASH"},
    ["TAB"] = {"Q", "W", "1", "GRAVE", "CAPSLOCK"},
    ["Q"] = {"TAB", "W", "1", "2", "A"},
    ["W"] = {"Q", "E", "2", "3", "A", "S"},
    ["E"] = {"W", "R", "3", "4", "S", "D"},
    ["R"] = {"E", "T", "4", "5", "D", "F"},
    ["T"] = {"R", "Y", "5", "6", "F", "G"},
    ["Y"] = {"T", "U", "6", "7", "G", "H"},
    ["U"] = {"Y", "I", "7", "8", "H", "J"},
    ["I"] = {"U", "O", "8", "9", "J", "K"},
    ["O"] = {"I", "P", "9", "0", "K", "L"},
    ["P"] = {"O", "LBRACE", "0", "MINUS", "L", "SEMICOLON"},
    ["BACKSLASH"] = {"BACKSPACE", "RBRACE", "ENTER"},
    ["LBRACE"] = {"P", "RBRACE", "MINUS", "EQUAL", "SEMICOLON", "APOSTROPHE"},
    ["RBRACE"] = {"LBRACE", "BACKSPACE", "EQUAL", "APOSTROPHE", "ENTER"},
    ["A"] = {"Q", "S", "TAB", "CAPSLOCK", "Z"},
    ["S"] = {"A", "D", "W", "E", "Z", "X"},
    ["D"] = {"S", "F", "E", "R", "X", "C"},
    ["F"] = {"D", "G", "R", "T", "C", "V"},
    ["G"] = {"F", "H", "T", "Y", "V", "B"},
    ["H"] = {"G", "J", "Y", "U", "B", "N"},
    ["J"] = {"H", "K", "U", "I", "N", "M"},
    ["K"] = {"J", "L", "I", "O", "M", "COMMA"},
    ["L"] = {"K", "SEMICOLON", "O", "P", "COMMA", "DOT"},
    ["SEMICOLON"] = {"L", "APOSTROPHE", "P", "LBRACE", "DOT", "SLASH"},
    ["APOSTROPHE"] = {"SEMICOLON", "ENTER", "LBRACE", "RBRACE", "SLASH"},
    ["ENTER"] = {"APOSTROPHE", "RBRACE", "BACKSLASH", "RSHIFT"},
    ["CAPSLOCK"] = {"A", "TAB", "LSHIFT"},
    ["LSHIFT"] = {"CAPSLOCK", "A", "Z", "LCTRL"},
    ["Z"] = {"A", "S", "LSHIFT", "X", "LCTRL"},
    ["X"] = {"Z", "D", "LSHIFT", "C", "LALT"},
    ["C"] = {"X", "F", "V", "LALT"},
    ["V"] = {"C", "B", "F", "G"},
    ["B"] = {"V", "N", "G", "H"},
    ["N"] = {"B", "M", "H", "J"},
    ["M"] = {"N", "COMMA", "J", "K"},
    ["COMMA"] = {"M", "DOT", "K", "L"},
    ["DOT"] = {"COMMA", "SLASH", "L", "SEMICOLON"},
    ["SLASH"] = {"DOT", "APOSTROPHE", "SEMICOLON", "RSHIFT"},
    ["RSHIFT"] = {"SLASH", "RCTRL", "ENTER", "APOSTROPHE"},
    ["RCTRL"] = {"RSHIFT", "COMPOSE", "LEFT"},
    ["LEFT"] = {"RCTRL", "UP", "DOWN", "RIGHT", "RSHIFT"},
    ["UP"] = {"END", "LEFT", "DOWN", "RIGHT"},
    ["DOWN"] = {"LEFT", "UP", "RIGHT"},
    ["RIGHT"] = {"UP", "DOWN", "LEFT"},
    ["LALT"] = {"Z", "X", "C", "LMETA", "SPACE"},
    ["SPACE"] = {"LALT", "RALT", "Z", "X", "C", "V", "B", "N", "M", "COMMA"},
    ["LCTRL"] = {"LSHIFT", "LMETA"},
    ["LMETA"] = {"LCTRL", "LALT", "LSHIFT", "Z"},
    ["DELETE"] = {"INSERT", "BACKSPACE", "BACKSLASH", "HOME", "END"},
    ["HOME"] = {"INSERT", "DELETE", "SYSRQ", "SCROLLLOCK", "PAUSE", "PAGEUP", "PAGEDOWN"},
    ["END"] = {"DELETE", "INSERT", "HOME", "END", "PAGEUP", "PAGEDOWN"},
    ["PAGEUP"] = {"HOME", "SCROLLLOCK", "PAUSE", "END", "PAGEDOWN"},
    ["PAGEDOWN"] = {"HOME", "PAGEUP", "END"},
    ["COMPOSE"] = {"SLASH", "RSHIFT", "RCTRL", "FN"},
    ["FN"] = {"RALT", "DOT", "SLASH", "RSHIFT", "COMPOSE"},
    ["RALT"] = {"SPACE", "COMMA", "DOT", "FN", "SLASH"},
    ["INSERT"] = {"BACKSPACE", "BACKSLASH", "F12", "SYSRQ", "DELETE", "HOME", "END", "SCROLLLOCK"}
}

states = {"rock", "paper", "scissors"}
fadeTime = tonumber(keyleds.config.fadeTime) or 0.2
stateColors = {
    rock =  tocolor(keyleds.config.rock or 'red'),
    paper = tocolor(keyleds.config.paper or 'orange'),
    scissors = tocolor(keyleds.config.scissors or 'white')
}

function initialize_nodes(graph)
    local nodes = {}
    for node, _ in pairs(graph) do
        nodes[node] = states[math.random(#states)]
    end
    return nodes
end

function determine_winner(current_state, neighbor_state)
    if current_state == neighbor_state then
        return current_state
    elseif (current_state == "rock" and neighbor_state == "scissors") or
           (current_state == "scissors" and neighbor_state == "paper") or
           (current_state == "paper" and neighbor_state == "rock") then
        return current_state
    else
        return neighbor_state
    end
end

function update_nodes(graph, nodes)
    local new_nodes = {}
    for node, state in pairs(nodes) do
        local neighbors = graph[node]
        local new_state = state
        for _, neighbor in ipairs(neighbors) do
            local neighbor_state = nodes[neighbor]
            new_state = determine_winner(new_state, neighbor_state)
        end
        new_nodes[node] = new_state
    end
    return new_nodes
end

delay = tonumber(keyleds.config.delay) or 200
keys = keyleds.db
if type(keys) ~= "table" then
    local tempKeys = {}
    for i = 1, #keys do
        table.insert(tempKeys, keys[i])
    end
    keys = tempKeys
end

transparent = tocolor(0, 0, 0, 0)

function getKeyFromName(keyName)
    for _, key in ipairs(keys) do
        if key.name == keyName then
            return key
        end
    end
end

function onKeyEvent(key, isPress)
    nodes[key.name] = states[math.random(#states)]
end

function updateColors()
    for node, state in pairs(nodes) do
        local key = getKeyFromName(node)
        buffer[key] = fade(fadeTime, buffer[key], stateColors[state])
    end
end

function render(ms, target)
    lastUpdate = lastUpdate + ms
    if lastUpdate >= delay then
        nodes = update_nodes(graph, nodes)
        updateColors()
        lastUpdate = lastUpdate - delay
    end
    target:blend(buffer)
end

function init()
    nodes = initialize_nodes(graph)
    lastUpdate = 0
    buffer = RenderTarget:new()
end

init()
