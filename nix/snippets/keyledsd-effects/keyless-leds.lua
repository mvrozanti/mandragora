keys = keyleds.db
colorCapsLock = tocolor(keyleds.config.colorCapsLock)
colorScrollLock = tocolor(keyleds.config.colorScrollLock)


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
end

buffer = RenderTarget:new()

function update(buffer)
    if colorCapsLock then
        buffer[getKeyFromName("CAPSLOCKLED")] = colorCapsLock
    end
    if colorScrollLock then
        buffer[getKeyFromName("SCROLLLOCKLED")] = colorScrollLock
    end
end

update(buffer)

function render(ms, target)
    update(buffer)
    target:blend(buffer)
end
