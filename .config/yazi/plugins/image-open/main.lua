--- @sync entry

local IMG = {
  jpg=1, jpeg=1, png=1, gif=1, webp=1, bmp=1,
  tiff=1, tif=1, avif=1, jxl=1, heic=1, heif=1,
  svg=1, ico=1,
}

local function ext(name)
  return tostring(name):lower():match("%.([^%.]+)$")
end

local function entry(self)
  local h = cx.active.current.hovered
  if not h then return end

  if h.cha.is_dir then
    ya.emit("enter", {})
    return
  end

  if not IMG[ext(h.name) or ""] then
    ya.emit("open", { hovered = true })
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

  if #urls == 0 then
    ya.emit("open", { hovered = true })
    return
  end

  local log = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/image-open-yazi.log"
  local cmd = Command("sh"):arg("-c"):arg('exec nsxiv "$@" 2>>"' .. log .. '"')
    :arg("nsxiv"):arg("-ab"):arg("-n"):arg(tostring(idx)):arg("--")
  for _, u in ipairs(urls) do cmd = cmd:arg(u) end
  local child, err = cmd:stdin(Command.NULL):stdout(Command.NULL):spawn()
  if not child then
    ya.notify { title = "image-open", content = tostring(err), level = "error", timeout = 5 }
  end
end

return { entry = entry }
