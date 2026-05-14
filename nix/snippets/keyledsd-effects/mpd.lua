unpack = table.unpack or unpack

fifo_path = "/tmp/mpd.fifo"
keys = keyleds.groups[keyleds.config.group] or keyleds.db
width = tonumber(keyleds.config.width) or 13
height = tonumber(keyleds.config.height) or 5
colors = keyleds.config.colors

buffer = RenderTarget:new()

amplitude_buffer = {}
for i = 1, height do
    amplitude_buffer[i] = 0
end

function open_fifo(path)
    fifo = io.open(path, "rb")
    if not fifo then
        error("Could not open FIFO at " .. path)
    end
    return fifo
end

fifo = open_fifo(fifo_path)

function calculate_amplitude(data)
    sum = 0
    count = 0
    data_len = #data

    for i = 1, data_len - 1, 2 do
        sample = (data:byte(i) or 0) + (data:byte(i + 1) or 0) * 256
        if sample > 32767 then
            sample = sample - 65536
        end
        sum = sum + math.abs(sample)
        count = count + 1
    end

    if count > 0 then
        return sum / count
    else
        return 0
    end
end

function get_coords_on_grid(x, y)
    return (height - y) * width + x
end

function update_leds(amplitude)
    max_bars = width
    bar_width = math.floor(amplitude / 1000)
    bar_width = math.min(bar_width, width)
    for y = 1, height - 1 do
        amplitude_buffer[y] = amplitude_buffer[y + 1]
    end
    amplitude_buffer[height] = bar_width
    for i = 1, #keys do
        buffer[keys[i]] = tocolor(0, 0, 0) 
    end
    for y = 1, height do
        bars = amplitude_buffer[y]
        for x = 1, width do
            if x <= bars then
                color = tocolor(colors[x-1])
            else
                color = tocolor('black')
            end
            key_idx = get_coords_on_grid(x, y)
            buffer[keys[key_idx]] = color
        end
    end
end

function render(ms, target)
    buffer:fill(tocolor('black'))

    chunk_size = 44100 * 2 * 2 / 10
    data = fifo:read(chunk_size)

    if data then
        amplitude = calculate_amplitude(data)
        update_leds(amplitude)
    else
        print("No data read from FIFO.")
    end

    target:blend(buffer)
end
