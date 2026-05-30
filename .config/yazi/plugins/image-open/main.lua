local M = {}

local IMG = {
  jpg=1, jpeg=1, png=1, gif=1, webp=1, bmp=1,
  tiff=1, tif=1, avif=1, jxl=1, heic=1, heif=1,
  svg=1, ico=1,
}

local function ext(name)
  return tostring(name):lower():match("%.([^%.]+)$")
end

function M:entry()
  local h = cx.active.current.hovered
  if not h then return end

  if h.cha.is_dir then
    ya.mgr_emit("enter", {})
    return
  end

  if not IMG[ext(h.name) or ""] then
    ya.mgr_emit("open", { hovered = true })
    return
  end

  local urls, idx = {}, 1
  local hurl = tostring(h.url)
  for _, f in ipairs(cx.active.current.files) do
    if IMG[ext(f.name) or ""] then
      urls[#urls+1] = tostring(f.url)
      if tostring(f.url) == hurl then idx = #urls end
    end
  end

  local cmd = Command("nsxiv"):arg("-ab"):arg("-n"):arg(tostring(idx)):arg("--")
  for _, u in ipairs(urls) do cmd = cmd:arg(u) end
  cmd:stdin(Command.NULL):stdout(Command.NULL):stderr(Command.NULL):spawn()
end

return M
