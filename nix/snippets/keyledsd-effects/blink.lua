config = {
    blinkInterval = 1000,  -- Time in milliseconds between blinks
    onColor = tocolor(1, 0, 0),  -- White color
    offColor = tocolor(0, 0, 0)  -- Black color (off)
}

buffer = RenderTarget:new()
isOn = false
nextBlink = config.blinkInterval

function init()
    buffer:fill(config.offColor)
end

function render(ms, target)
    nextBlink = nextBlink - ms
    if nextBlink <= 0 then
        if isOn then
            buffer:fill(config.offColor)
        else
            buffer:fill(config.onColor)
        end
        isOn = not isOn
        nextBlink = config.blinkInterval
    end
    target:blend(buffer)
end
