import Notifd from "gi://AstalNotifd"
import GLib from "gi://GLib"
import { createState } from "ags"

export const notifd = Notifd.get_default()
notifd.ignoreTimeout = true

const newestFirst = () => [...notifd.get_notifications()].sort((a, b) => b.time - a.time)

const [list, setList] = createState<Notifd.Notification[]>(newestFirst())
const [dnd, setDnd] = createState(notifd.dontDisturb)
export { list as notifications, dnd }

const stateDir = `${GLib.get_user_runtime_dir()}/mandragora-shell`
GLib.mkdir_with_parents(stateDir, 0o700)

let pending = 0
function publish() {
  if (pending) return
  pending = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 80, () => {
    pending = 0
    const count = notifd.get_notifications().length
    GLib.file_set_contents(`${stateDir}/notification-count`, `${count}\n`)
    GLib.file_set_contents(
      `${stateDir}/notifications.json`,
      JSON.stringify({ count, dnd: notifd.dontDisturb }) + "\n",
    )
    GLib.spawn_command_line_async("pkill -RTMIN+16 -x waybar")
    return GLib.SOURCE_REMOVE
  })
}

notifd.connect("notify::notifications", () => {
  setList(newestFirst())
  publish()
})
notifd.connect("notify::dont-disturb", () => {
  setDnd(notifd.dontDisturb)
  publish()
})
publish()

export function clearAll() {
  for (const n of notifd.get_notifications()) n.dismiss()
}

export function latest(): Notifd.Notification | undefined {
  return newestFirst()[0]
}

export function invokeDefault(n: Notifd.Notification) {
  const action = n.actions.find((a) => a.id === "default") ?? n.actions[0]
  if (action) n.invoke(action.id)
  if (!n.resident) n.dismiss()
}

export function request(args: string[]): string {
  const [verb, arg] = args
  switch (verb) {
    case "count":
      return String(notifd.get_notifications().length)
    case "dnd":
      if (arg === "on") notifd.dontDisturb = true
      else if (arg === "off") notifd.dontDisturb = false
      else if (arg === "toggle") notifd.dontDisturb = !notifd.dontDisturb
      return notifd.dontDisturb ? "on" : "off"
    case "clear":
      clearAll()
      return "ok"
    case "close-latest":
      latest()?.dismiss()
      return "ok"
    case "invoke-latest": {
      const n = latest()
      if (n) invokeDefault(n)
      return "ok"
    }
    default:
      return `unknown notification verb: ${verb ?? ""}`
  }
}
