import { Gtk } from "ags/gtk4"
import { createState, For, With } from "ags"
import Popup from "../widget/Popup"
import { Chip, Icon, IconButton } from "../widget/parts"
import { json, quiet, spawn } from "../lib/run"
import { closeCurrent } from "../lib/popups"

type Mon = {
  name: string
  description: string
  width: number
  height: number
  refresh: number
  mode: string
  scale: number
  x: number
  y: number
  logical: [number, number]
  disabled: boolean
  focused: boolean
  modes: string[]
}
type Data = { monitors: Mon[]; scales: string[] }

const RELATIONS = [
  ["left", "Left of", "west"],
  ["right", "Right of", "east"],
  ["above", "Above", "north"],
  ["below", "Below", "south"],
] as const

function Layout({ mons }: { mons: Mon[] }) {
  const active = mons.filter((m) => !m.disabled)
  const W = 360
  const H = 120
  const minX = Math.min(...active.map((m) => m.x))
  const minY = Math.min(...active.map((m) => m.y))
  const maxX = Math.max(...active.map((m) => m.x + m.logical[0]))
  const maxY = Math.max(...active.map((m) => m.y + m.logical[1]))
  const k = Math.min(W / Math.max(1, maxX - minX), H / Math.max(1, maxY - minY))
  const ox = (W - (maxX - minX) * k) / 2
  const oy = (H - (maxY - minY) * k) / 2
  const fixed = new Gtk.Fixed({ widthRequest: W, heightRequest: H })
  for (const m of active) {
    const box = new Gtk.Box({
      cssClasses: m.focused ? ["layout-mon", "focused"] : ["layout-mon"],
      widthRequest: Math.round(m.logical[0] * k) - 4,
      heightRequest: Math.round(m.logical[1] * k) - 4,
    })
    box.append(new Gtk.Label({ label: m.name, hexpand: true, vexpand: true }))
    fixed.put(box, ox + (m.x - minX) * k + 2, oy + (m.y - minY) * k + 2)
  }
  return (
    <box class="layout" halign={Gtk.Align.CENTER}>
      {fixed}
    </box>
  )
}

function dropdown(options: string[], current: string, onPick: (value: string) => void) {
  const dd = Gtk.DropDown.new_from_strings(options)
  dd.selected = Math.max(0, options.indexOf(current))
  dd.connect("notify::selected", () => {
    const value = options[dd.selected]
    if (value && value !== current) onPick(value)
  })
  return dd
}

export default function MonitorPopup() {
  const [data, setData] = createState<Data>({ monitors: [], scales: [] })
  const load = () => json<Data>(["monitor-menu", "json"]).then(setData).catch(console.error)
  const act = async (...args: string[]) => {
    await quiet(["monitor-menu", "act", ...args])
    setTimeout(load, 300)
  }

  return (
    <Popup
      name="monitor"
      width={420}
      icon="desktop_windows"
      title="Displays"
      subtitle={data((d) => {
        const on = d.monitors.filter((m) => !m.disabled).length
        return `${on} of ${d.monitors.length} active`
      })}
      actions={
        <IconButton
          icon="open_in_new"
          tooltip="Open the drag-and-drop arranger"
          onClicked={() => {
            closeCurrent()
            spawn(["nwg-displays"])
          }}
        />
      }
      onOpen={load}
    >
      <box orientation={Gtk.Orientation.VERTICAL}>
        <With value={data((d) => d.monitors)}>{(mons: Mon[]) => mons.length > 0 && <Layout mons={mons} />}</With>
      </box>
      <box class="monitor-actions" spacing={8} homogeneous>
        <button class="button tonal" onClicked={() => act("extend")}>
          <box spacing={6} halign={Gtk.Align.CENTER}>
            <Icon name="width_wide" />
            <label label="Extend all" />
          </box>
        </button>
        <button class="button" onClicked={() => act("mirror-all")}>
          <box spacing={6} halign={Gtk.Align.CENTER}>
            <Icon name="flip" />
            <label label="Mirror all" />
          </box>
        </button>
      </box>
      <For each={data((d) => d.monitors.map((m) => ({ m, all: d.monitors, scales: d.scales })))} id={(x: any) => JSON.stringify(x.m)}>
        {({ m, all, scales }: { m: Mon; all: Mon[]; scales: string[] }) => (
          <box class="monitor-card" orientation={Gtk.Orientation.VERTICAL} spacing={10}>
            <box spacing={10}>
              <Icon name={m.disabled ? "desktop_access_disabled" : "monitor"} class="tile-glyph" />
              <box orientation={Gtk.Orientation.VERTICAL} hexpand>
                <label class="row-title" xalign={0} label={m.name} />
                <label class="row-detail" xalign={0} ellipsize={3} maxWidthChars={34} label={m.description} />
              </box>
              {m.focused && <Chip label="Focused" class="tonal" />}
              {m.x === 0 && m.y === 0 && !m.disabled && <Chip label="Primary" class="primary" />}
            </box>
            <box spacing={8} visible={!m.disabled}>
              <box orientation={Gtk.Orientation.VERTICAL} spacing={4} hexpand>
                <label class="caption" xalign={0} label="Mode" />
                {dropdown(m.modes, m.modes.find((x) => x.startsWith(`${m.width}x${m.height}@${m.refresh.toFixed(2)}`)) ?? m.mode, (v) => act("mode", m.name, v))}
              </box>
              <box orientation={Gtk.Orientation.VERTICAL} spacing={4}>
                <label class="caption" xalign={0} label="Scale" />
                {dropdown(scales, scales.find((s) => Number(s) === m.scale) ?? String(m.scale), (v) => act("scale", m.name, v))}
              </box>
            </box>
            <box spacing={6} visible={!m.disabled && all.filter((o) => !o.disabled).length > 1}>
              {all
                .filter((o) => o.name !== m.name && !o.disabled)
                .flatMap((o) =>
                  RELATIONS.map(([rel, label, icon]) => (
                    <IconButton icon={icon} tooltip={`${label} ${o.name}`} onClicked={() => act("place", m.name, rel, o.name)} />
                  )),
                )}
              <box hexpand />
              <IconButton icon="star" tooltip="Make primary" onClicked={() => act("primary", m.name)} />
            </box>
            <button class={m.disabled ? "button filled" : "button"} onClicked={() => act("toggle", m.name)}>
              <box spacing={6} halign={Gtk.Align.CENTER}>
                <Icon name={m.disabled ? "power" : "power_off"} />
                <label label={m.disabled ? "Turn on" : "Turn off"} />
              </box>
            </button>
          </box>
        )}
      </For>
    </Popup>
  )
}
