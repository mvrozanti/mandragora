import app from "ags/gtk4/app"
import { Astal, Gdk, Gtk } from "ags/gtk4"
import GLib from "gi://GLib"
import { exec } from "ags/process"

export type Registered = {
  name: string
  width: number
  window: Astal.Window
  revealer: Gtk.Revealer
  card: Gtk.Widget
  onOpen?: () => void
  onClose?: () => void
  focus?: () => void
}

const registry = new Map<string, Registered>()
let current: string | null = null
const EDGE = 12

export function register(entry: Registered) {
  registry.set(entry.name, entry)
}

export function names(): string[] {
  return [...registry.keys()]
}

type Placement = { monitor: Gdk.Monitor | null; x: number | null }

function placement(): Placement {
  try {
    const cursor = JSON.parse(exec(["hyprctl", "-j", "cursorpos"]))
    const mons = JSON.parse(exec(["hyprctl", "-j", "monitors"])) as Array<{
      name: string
      x: number
      y: number
      width: number
      height: number
      scale: number
      transform: number
    }>
    for (const m of mons) {
      const rotated = m.transform % 2 === 1
      const w = (rotated ? m.height : m.width) / m.scale
      const h = (rotated ? m.width : m.height) / m.scale
      if (cursor.x >= m.x && cursor.x < m.x + w && cursor.y >= m.y && cursor.y < m.y + h) {
        const gdk = app.get_monitors().find((g) => g.get_connector() === m.name) ?? null
        return { monitor: gdk, x: cursor.x - m.x }
      }
    }
  } catch {}
  return { monitor: null, x: null }
}

function place(entry: Registered, at: Placement) {
  if (at.monitor) entry.window.gdkmonitor = at.monitor
  const monitor = at.monitor ?? entry.window.gdkmonitor ?? app.get_monitors()[0]
  const width = monitor?.get_geometry().width ?? 1920
  const anchorX = at.x ?? width
  const left = Math.round(anchorX - entry.width / 2)
  entry.card.marginStart = Math.max(EDGE, Math.min(left, width - entry.width - EDGE))
}

export function open(name: string, x?: number) {
  const entry = registry.get(name)
  if (!entry) return
  if (current && current !== name) close(current, true)
  const at = placement()
  if (x !== undefined && !Number.isNaN(x)) at.x = x
  place(entry, at)
  current = name
  entry.window.visible = true
  entry.revealer.revealChild = true
  entry.onOpen?.()
  GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
    entry.focus?.()
    return GLib.SOURCE_REMOVE
  })
}

export function close(name: string, instant = false) {
  const entry = registry.get(name)
  if (!entry || !entry.window.visible) return
  if (current === name) current = null
  entry.revealer.revealChild = false
  entry.onClose?.()
  const hide = () => {
    if (!entry.revealer.revealChild) entry.window.visible = false
  }
  if (instant) hide()
  else
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, entry.revealer.transitionDuration + 20, () => {
      hide()
      return GLib.SOURCE_REMOVE
    })
}

export function closeCurrent() {
  if (current) close(current)
}

export function toggle(name: string, x?: number) {
  if (current === name) close(name)
  else open(name, x)
}
