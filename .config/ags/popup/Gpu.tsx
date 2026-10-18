import { Gtk } from "ags/gtk4"
import { createState, For } from "ags"
import Popup from "../widget/Popup"
import { Chip, Empty, Icon, IconButton, Meter, SectionLabel } from "../widget/parts"
import { duration, every, json, spawn } from "../lib/run"

type Gpu = {
  util: number | null
  mem_used: number | null
  mem_total: number | null
  temp: number | null
  power: number | null
  power_limit: number | null
}
type Proc = { pid: string; mem: string; name: string; cmd: string }
type Holder = {
  name?: string
  pid?: number
  held_for?: number
  expected_remaining?: number
  cmd?: string
}
type Data = { holder: Holder | null; gpu: Gpu | null; procs: Proc[] }

const base = (p: string) => p.split(/[\\/]/).pop() ?? p

export default function GpuPopup() {
  const [data, setData] = createState<Data>({ holder: null, gpu: null, procs: [] })
  let stop: (() => void) | null = null

  const poll = () =>
    json<Data>(["gpu-menu", "json"]).then(setData).catch((e) => console.error(e))

  const g = data((d) => d.gpu)
  const num = (f: (x: Gpu) => number | null | undefined) => g((x) => (x ? f(x) ?? 0 : 0))

  return (
    <Popup
      name="gpu"
      width={380}
      icon="memory"
      title="RTX 5070 Ti"
      subtitle={data((d) =>
        d.gpu
          ? `${Math.round(d.gpu.power ?? 0)} W of ${Math.round(d.gpu.power_limit ?? 0)} W · ${d.procs.length} compute ${d.procs.length === 1 ? "process" : "processes"}`
          : "nvidia-smi unavailable",
      )}
      actions={<IconButton icon="monitoring" tooltip="Open nvtop" onClicked={() => spawn(["kitty", "-e", "nvtop"])} />}
      onOpen={() => (stop = every(1500, poll))}
      onClose={() => {
        stop?.()
        stop = null
      }}
    >
      <box
        class={data((d) => (d.holder ? "lock-banner held" : "lock-banner"))}
        spacing={12}
      >
        <Icon name={data((d) => (d.holder ? "lock" : "lock_open_right"))} class="filled" />
        <box orientation={Gtk.Orientation.VERTICAL} hexpand>
          <label
            class="lock-title"
            xalign={0}
            label={data((d) => (d.holder ? `Held by ${d.holder.name ?? "unknown"}` : "gpu-lock is free"))}
          />
          <label
            class="caption"
            xalign={0}
            ellipsize={3}
            label={data((d) => {
              const h = d.holder
              if (!h) return "Any job can take the GPU"
              const eta = h.expected_remaining != null ? ` · ~${duration(h.expected_remaining)} left` : ""
              return `pid ${h.pid ?? "?"} · held ${duration(h.held_for)}${eta}`
            })}
            tooltipText={data((d) => d.holder?.cmd ?? "")}
          />
        </box>
      </box>

      <box spacing={10} homogeneous class="stat-row">
        <box class="tile" orientation={Gtk.Orientation.VERTICAL} spacing={8}>
          <box spacing={8}>
            <Icon name="speed" class="tile-glyph" />
            <label class="caption" label="Load" xalign={0} hexpand />
          </box>
          <box>
            <label class="figure" label={num((x) => x.util)((v) => `${Math.round(v)}`)} />
            <label class="unit" label="%" valign={Gtk.Align.END} />
          </box>
          <Meter value={num((x) => x.util)((v) => v / 100)} />
        </box>
        <box class="tile" orientation={Gtk.Orientation.VERTICAL} spacing={8}>
          <box spacing={8}>
            <Icon name="thermostat" class="tile-glyph" />
            <label class="caption" label="Temperature" xalign={0} hexpand />
          </box>
          <box>
            <label class="figure" label={num((x) => x.temp)((v) => `${Math.round(v)}`)} />
            <label class="unit" label="°C" valign={Gtk.Align.END} />
          </box>
          <Meter
            value={num((x) => x.temp)((v) => Math.min(v / 90, 1))}
            class={num((x) => x.temp)((v) => (v >= 80 ? "warn" : "tertiary")).peek()}
          />
        </box>
      </box>

      <box class="tile vram" orientation={Gtk.Orientation.VERTICAL} spacing={8}>
        <box spacing={8}>
          <Icon name="memory_alt" class="tile-glyph" />
          <label class="caption" label="Video memory" xalign={0} hexpand />
          <label
            class="caption strong"
            label={g((x) =>
              x && x.mem_total ? `${Math.round((100 * (x.mem_used ?? 0)) / x.mem_total)}%` : "",
            )}
          />
        </box>
        <box>
          <label class="figure" label={num((x) => x.mem_used)((v) => (v / 1024).toFixed(1))} />
          <label
            class="unit"
            valign={Gtk.Align.END}
            label={num((x) => x.mem_total)((v) => `/ ${(v / 1024).toFixed(0)} GiB`)}
          />
        </box>
        <Meter value={g((x) => (x && x.mem_total ? (x.mem_used ?? 0) / x.mem_total : 0))} class="secondary" />
      </box>

      <SectionLabel label="COMPUTE PROCESSES" />
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
        <For each={data((d) => d.procs)} id={(p: Proc) => p.pid}>
          {(p: Proc) => (
            <box class="row" spacing={12} tooltipText={p.cmd || p.name}>
              <Icon name="terminal" />
              <box orientation={Gtk.Orientation.VERTICAL} hexpand>
                <label class="row-title" xalign={0} ellipsize={3} maxWidthChars={30} label={base(p.name)} />
                <label class="row-detail" xalign={0} label={`pid ${p.pid}`} />
              </box>
              <Chip label={`${p.mem} MiB`} class="tonal" />
            </box>
          )}
        </For>
        <box visible={data((d) => d.procs.length === 0)}>
          <Empty icon="bedtime" label="Nothing running on CUDA" />
        </box>
      </box>
    </Popup>
  )
}
