print("BOLT: top-level load")
buffer = RenderTarget:new()
buffer:fill(tocolor(0, 1, 1))
function render(ms, target)
    target:blend(buffer)
end
print("BOLT: script complete")
