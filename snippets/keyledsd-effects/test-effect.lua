function init()
    local k = keyleds.db[1]
    local props = {}
    for k, v in pairs(k) do table.insert(props, k) end
    print("TEST: Key properties: " .. table.concat(props, ", "))
end
function render() end
init()
