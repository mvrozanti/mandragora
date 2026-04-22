print("LIGHTNING: top-level load")

buffer = RenderTarget:new()
buffer:fill(tocolor(1, 0, 1))

renderCount = 0
function render(ms, target)
    renderCount = renderCount + 1
    if renderCount <= 3 then
        print("LIGHTNING: render " .. renderCount)
    end
    target:blend(buffer)
end

print("LIGHTNING: script complete")
