--- @sync entry

local IMG = {
  jpg=1, jpeg=1, png=1, gif=1, webp=1, bmp=1,
  tiff=1, tif=1, avif=1, jxl=1, heic=1, heif=1,
  svg=1, ico=1,
}

-- WORKAROUND (yazi 26.9.1): ya.emit("open", { hovered = true }) and the in-place
-- block openers (ui.hide()) both no-op from a plugin entry, so non-image files are
-- spawned directly here. Video/audio/pdf/office open in place; text/archive open in a
-- new kitty window, since the in-terminal block path is unavailable. When a yazi
-- release fixes emit-open, delete the *_PROG tables and the open_* helpers, then
-- restore `ya.emit("open", { hovered = true })` in both fallback branches below.
local VIDEO = { mp4=1, mkv=1, webm=1, avi=1, mov=1, flv=1, wmv=1, m4v=1, mpg=1, mpeg=1, ts=1, ogv=1, ["3gp"]=1 }
local AUDIO = { mp3=1, flac=1, ogg=1, opus=1, m4a=1, wav=1, aac=1, wma=1 }
local PDF   = { pdf=1, epub=1 }
local OFFICE= { doc=1, docx=1, xls=1, xlsx=1, ppt=1, pptx=1, odt=1, ods=1, odp=1 }
local ARCH  = { zip=1, tar=1, gz=1, tgz=1, bz2=1, tbz2=1, txz=1, xz=1, zst=1, ["7z"]=1, rar=1, z=1, lz=1, lzma=1, cab=1, iso=1, rpm=1, deb=1, apk=1 }
local TEXT  = {
  txt=1, md=1, markdown=1, mdown=1, rst=1, org=1, nix=1, conf=1, config=1, cfg=1, ini=1,
  toml=1, yaml=1, yml=1, json=1, jsonc=1, lua=1, sh=1, bash=1, zsh=1, fish=1, py=1, pyw=1,
  rs=1, c=1, h=1, cpp=1, hpp=1, cc=1, cxx=1, js=1, mjs=1, cjs=1, ts=1, tsx=1, jsx=1,
  css=1, scss=1, sass=1, less=1, html=1, htm=1, xml=1, log=1, tex=1, bib=1, csv=1, tsv=1,
  diff=1, patch=1, vim=1, xmp=1, env=1, service=1, socket=1, timer=1, target=1, desktop=1,
}

local function ext(name)
  return tostring(name):lower():match("%.([^%.]+)$")
end

local function open_orphan(prog, url)
  Command("sh"):arg("-c"):arg('exec "' .. prog .. '" "$@"')
    :arg(prog):arg("--"):arg(url)
    :stdin(Command.NULL):stdout(Command.NULL):spawn()
end

local function open_term(prog, url)
  Command("kitty"):arg("-e"):arg(prog):arg(url)
    :stdin(Command.NULL):stdout(Command.NULL):spawn()
end

local function open_archive(url)
  Command("kitty"):arg("-e"):arg("sh"):arg("-c"):arg('atool --list -- "$@" | ${PAGER:-less}')
    :arg("atool"):arg(url)
    :stdin(Command.NULL):stdout(Command.NULL):spawn()
end

local function entry(self)
  local h = cx.active.current.hovered
  if not h then return end

  if h.cha.is_dir then
    ya.emit("enter", {})
    return
  end

  local e = ext(h.name) or ""
  local url = tostring(h.url)

  if not IMG[e] then
    if VIDEO[e] or AUDIO[e] then
      open_orphan("mpv", url)
    elseif PDF[e] then
      open_orphan("zathura", url)
    elseif OFFICE[e] then
      open_orphan("libreoffice", url)
    elseif ARCH[e] then
      open_archive(url)
    elseif TEXT[e] then
      open_term(os.getenv("EDITOR") or "nvim", url)
    else
      open_orphan("xdg-open", url)
    end
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
    open_orphan("xdg-open", url)
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
