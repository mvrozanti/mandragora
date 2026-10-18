import GLib from "gi://GLib"
import { execAsync } from "ags/process"

export async function json<T>(cmd: string[]): Promise<T> {
  return JSON.parse(await execAsync(cmd)) as T
}

export function spawn(cmd: string[], delayMs = 0) {
  const line = cmd.map((a) => GLib.shell_quote(a)).join(" ")
  const script = delayMs > 0 ? `sleep ${delayMs / 1000}; exec ${line}` : `exec ${line}`
  GLib.spawn_command_line_async(`setsid -f sh -c ${GLib.shell_quote(script)}`)
}

export function quiet(cmd: string[]): Promise<string> {
  return execAsync(cmd).catch((e) => {
    console.error(`${cmd.join(" ")}: ${e}`)
    return ""
  })
}

export function every(ms: number, fn: () => void): () => void {
  fn()
  const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
    fn()
    return GLib.SOURCE_CONTINUE
  })
  return () => GLib.source_remove(id)
}

export function ago(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds))
  if (s < 60) return "just now"
  if (s < 3600) return `${Math.floor(s / 60)} min ago`
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`
  return `${Math.floor(s / 86400)} d ago`
}

export function duration(seconds: number | null | undefined): string {
  if (seconds == null) return "?"
  const s = Math.floor(seconds)
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s`
  return `${Math.floor(s / 3600)}h ${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}m`
}

export function now(): number {
  return Date.now() / 1000
}
