import Notifd from "gi://AstalNotifd"
import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { createState } from "ags"

export let notifd: Notifd.Notifd

const newestFirst = () => [...notifd.get_notifications()].sort((a, b) => b.time - a.time)

const [list, setList] = createState<Notifd.Notification[]>([])
const [dnd, setDnd] = createState(false)
export { list as notifications, dnd }

const stateDir = `${GLib.get_user_runtime_dir()}/mandragora-shell`
const historyDir = `${GLib.get_user_state_dir()}/mandragora-shell`
const historyPath = `${historyDir}/notification-history.jsonl`
const historyDays = 30
const historyDefaultCount = 20

const urgencyName = (u: Notifd.Urgency) =>
  u === Notifd.Urgency.CRITICAL ? "critical" : u === Notifd.Urgency.LOW ? "low" : "normal"

function readHistory(): string[] {
  try {
    const [ok, bytes] = GLib.file_get_contents(historyPath)
    return ok ? new TextDecoder().decode(bytes).split("\n").filter(Boolean) : []
  } catch {
    return []
  }
}

function record(id: number, replaced: boolean) {
  const n = notifd.get_notification(id)
  if (!n) return
  const entry = {
    time: n.time,
    app: n.appName,
    summary: n.summary,
    body: n.body,
    urgency: urgencyName(n.urgency),
    replaced,
  }
  try {
    const stream = Gio.File.new_for_path(historyPath).append_to(Gio.FileCreateFlags.PRIVATE, null)
    stream.write_all(new TextEncoder().encode(JSON.stringify(entry) + "\n"), null)
    stream.close(null)
  } catch (e) {
    printerr(`notification history: ${e}`)
  }
}

function prune() {
  const cutoff = Math.floor(GLib.get_real_time() / 1e6) - historyDays * 86400
  const lines = readHistory()
  const kept = lines.filter((line) => {
    try {
      return JSON.parse(line).time >= cutoff
    } catch {
      return false
    }
  })
  if (kept.length !== lines.length) {
    GLib.file_set_contents_full(
      historyPath,
      kept.map((line) => line + "\n").join(""),
      GLib.FileSetContentsFlags.CONSISTENT,
      0o600,
    )
  }
  return GLib.SOURCE_CONTINUE
}

function formatEntry(line: string): string {
  try {
    const e = JSON.parse(line)
    const when = GLib.DateTime.new_from_unix_local(e.time).format("%F %T")
    const body = String(e.body ?? "").replace(/\s+/g, " ").trim()
    const mark = e.urgency === "critical" ? "!" : " "
    return `${when} ${mark} ${e.app || "?"}: ${e.summary}${body ? ` — ${body}` : ""}`
  } catch {
    return line
  }
}

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
    GLib.spawn_command_line_async("pkill -RTMIN+16 -x '(\\.waybar-wrapped|waybar)'")
    return GLib.SOURCE_REMOVE
  })
}

export function initNotifications() {
  notifd = Notifd.get_default()
  notifd.ignoreTimeout = true
  GLib.mkdir_with_parents(stateDir, 0o700)
  GLib.mkdir_with_parents(historyDir, 0o700)
  prune()
  GLib.timeout_add_seconds(GLib.PRIORITY_LOW, 86400, prune)
  notifd.connect("notified", (_n, id, replaced) => record(id, replaced))
  setList(newestFirst())
  setDnd(notifd.dontDisturb)
  notifd.connect("notify::notifications", () => {
    setList(newestFirst())
    publish()
  })
  notifd.connect("notify::dont-disturb", () => {
    setDnd(notifd.dontDisturb)
    publish()
  })
  publish()
}

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
    case "history": {
      const count = Math.max(1, Math.floor(Number(arg)) || historyDefaultCount)
      return readHistory().slice(-count).map(formatEntry).join("\n") || "no notifications recorded"
    }
    case "invoke-latest": {
      const n = latest()
      if (n) invokeDefault(n)
      return "ok"
    }
    default:
      return `unknown notification verb: ${verb ?? ""}`
  }
}
