--- @sync entry

local IMG = {
  jpg=1, jpeg=1, png=1, gif=1, webp=1, bmp=1,
  tiff=1, tif=1, avif=1, jxl=1, heic=1, heif=1,
  svg=1, ico=1,
}

-- WORKAROUND (yazi 26.9.1): ya.emit("open", { hovered = true }) silently no-ops,
-- so non-image files never open. Spawn the opener directly instead. When a yazi
-- release fixes emit-open, delete the *_PROG tables and open_with(), then restore
--   ya.emit("open", { hovered = true })
-- in both fallback branches below. text/* and archive block openers are not
-- replicated here; those fall back to xdg-open.
local VIDEO = { mp4=1, mkv=1, webm=1, avi=1, mov=1, flv=1, wmv=1, m4v=1, mpg=1, mpeg=1, ts=1, ogv=1, ["3gp"]=1 }
local AUDIO = { mp3=1, flac=1, ogg=1, opus=1, m4a=1, wav=1, aac=1, wma=1 }
local PDF   = { pdf=1, epub=1 }
local OFFICE= { doc=1, docx=1, xls=1, xlsx=1, ppt=1, pptx=1, odt=1, ods=1, odp=1 }

local function ext(name)
  return tostring(name):lower():match("%.([^%.]+)$")
end

local function open_prog(e)
  if VIDEO[e] or AUDIO[e] then return "mpv" end
  if PDF[e] then return "zathura" end
  if OFFICE[e] then return "libreoffice" end
  return "xdg-open"
end

local function open_with(prog, url)
  Command("sh"):arg("-c"):arg('exec "' .. prog .. '" "$@"')
    :arg(prog):arg("--"):arg(url)
    :stdin(Command.NULL):stdout(Command.NULL):spawn()
end

local function entry(self)
  local h = cx.active.current.hovered
  if not h then return end

  if h.cha.is_dir then
    ya.emit("enter", {})
    return
  end

  if not IMG[ext(h.name) or ""] then
    open_with(open_prog(ext(h.name) or ""), tostring(h.url))
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
    open_with(open_prog(ext(h.name) or ""), tostring(h.url))
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
