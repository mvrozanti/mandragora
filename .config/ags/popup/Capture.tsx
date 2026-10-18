import { Gtk } from "ags/gtk4"
import { createState } from "ags"
import GLib from "gi://GLib"
import { readFile } from "ags/file"
import Popup from "../widget/Popup"
import { Icon, SectionLabel, Segmented } from "../widget/parts"
import { closeCurrent } from "../lib/popups"
import { quiet, spawn } from "../lib/run"

type Mode = "shot" | "vid-none" | "vid-mic" | "vid-sys"
type Target = "region" | "window" | "full"

const USAGE = `${GLib.get_user_cache_dir()}/rofi-capture-menu-usage`

const MODES: { value: Mode; label: string; icon: string }[] = [
  { value: "shot", label: "Photo", icon: "photo_camera" },
  { value: "vid-none", label: "Silent", icon: "videocam" },
  { value: "vid-mic", label: "Mic", icon: "mic" },
  { value: "vid-sys", label: "System", icon: "volume_up" },
]

const TARGETS: { value: Target; label: string; icon: string; hint: string }[] = [
  { value: "region", label: "Region", icon: "screenshot_region", hint: "Drag a rectangle" },
  { value: "window", label: "Window", icon: "select_window", hint: "Pick a window" },
  { value: "full", label: "Screen", icon: "fullscreen", hint: "Everything visible" },
]

function usage(): string[] {
  try {
    return readFile(USAGE).split("\n").filter(Boolean)
  } catch {
    return []
  }
}

function favourite(): Mode {
  const counts = new Map<Mode, number>()
  for (const action of usage()) {
    const mode = action.replace(/-(region|window|full)$/, "") as Mode
    counts.set(mode, (counts.get(mode) ?? 0) + 1)
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? "shot"
}

function record(action: string) {
  const lines = [...usage(), action].slice(-100)
  GLib.file_set_contents(USAGE, lines.join("\n") + "\n")
}

export default function CapturePopup() {
  const [mode, setMode] = createState<Mode>("shot")
  const [mic, setMic] = createState(true)

  const shoot = (target: Target) => {
    const action = `${mode.peek()}-${target}`
    record(action)
    closeCurrent()
    spawn(["screencap", action], 350)
  }

  return (
    <Popup
      name="capture"
      width={400}
      icon="screenshot_monitor"
      title="Capture"
      subtitle={mode((m) =>
        m === "shot" ? "Screenshot to clipboard and ~/Pictures" : "Recording to ~/Videos · click the bar icon again to stop",
      )}
      onOpen={() => {
        setMode(favourite())
        quiet(["screencap", "has-mic"]).then((out) => setMic(out.trim() === "yes"))
      }}
    >
      <Segmented
        options={MODES}
        selected={mode}
        onSelect={(m) => (m === "vid-mic" && !mic.peek() ? null : setMode(m))}
      />
      <SectionLabel label="WHAT TO CAPTURE" />
      <box class="capture-grid" spacing={8} homogeneous>
        {TARGETS.map((t) => (
          <button class="capture-tile" onClicked={() => shoot(t.value)} tooltipText={t.hint}>
            <box orientation={Gtk.Orientation.VERTICAL} spacing={6} valign={Gtk.Align.CENTER}>
              <Icon name={t.icon} class="tile-icon" />
              <label class="tile-label" label={t.label} />
              <label class="tile-hint" label={t.hint} />
            </box>
          </button>
        ))}
      </box>
      <label
        class="caption hint"
        visible={mic((m) => !m)}
        label="No microphone found, so mic recording is unavailable"
      />
    </Popup>
  )
}
