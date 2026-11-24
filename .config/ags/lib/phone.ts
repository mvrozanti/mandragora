import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { createState } from "ags"

const [phoneOn, setPhoneOn] = createState(true)
const [phoneKnown, setPhoneKnown] = createState(false)
export { phoneOn, phoneKnown }

let monitor: Gio.FileMonitor | null = null

function forwardPath(): string {
  try {
    const [ok, out, , status] = GLib.spawn_command_line_sync("phone-forward path")
    return ok && status === 0 && out ? new TextDecoder().decode(out).trim() : ""
  } catch {
    return ""
  }
}

function read(path: string) {
  try {
    const [ok, bytes] = GLib.file_get_contents(path)
    setPhoneOn(!(ok && JSON.parse(new TextDecoder().decode(bytes)).on === false))
  } catch {
    setPhoneOn(true)
  }
}

export function initPhone() {
  const path = forwardPath()
  if (!path) return
  read(path)
  setPhoneKnown(true)
  monitor = Gio.File.new_for_path(path).monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, null)
  monitor.connect("changed", () => read(path))
}

export function togglePhone() {
  setPhoneOn(!phoneOn())
  GLib.spawn_command_line_async("phone-forward toggle")
}
