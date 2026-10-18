import { Gtk } from "ags/gtk4"
import { createComputed, createState, For } from "ags"
import Popup from "../widget/Popup"
import { Chip, Empty, Icon, IconButton, Scroll, SectionLabel, Segmented } from "../widget/parts"
import { every, json, quiet, spawn } from "../lib/run"
import { closeCurrent } from "../lib/popups"

type Net = { ssid: string; security: string; connected: boolean; bars: number }
type Data = {
  mode: "lan" | "wifi" | "auto"
  state: string
  online: boolean
  iface: string | null
  networks: Net[]
}

const SIGNAL = [
  "signal_wifi_0_bar",
  "network_wifi_1_bar",
  "network_wifi_2_bar",
  "network_wifi_3_bar",
  "signal_wifi_4_bar",
]

function uplink(d: Data): string {
  if (!d.online) return "Offline"
  if (d.state.startsWith("wifi") || d.iface === "wlan0") return "Online through Wi-Fi"
  if (d.state === "lan" || d.iface?.startsWith("enp")) return "Online through Ethernet"
  return `Online through ${d.iface ?? "unknown"}`
}

export default function NetworkPopup() {
  const [data, setData] = createState<Data>({
    mode: "auto",
    state: "",
    online: true,
    iface: null,
    networks: [],
  })
  const [busy, setBusy] = createState("")
  let stop: (() => void) | null = null

  const poll = () => json<Data>(["network-menu", "json"]).then(setData).catch(console.error)

  const run = async (label: string, args: string[]) => {
    setBusy(label)
    await quiet(["network-menu", ...args])
    setBusy("")
    poll()
  }

  return (
    <Popup
      name="network"
      width={380}
      icon={data((d) => (!d.online ? "wifi_off" : d.iface?.startsWith("wlan") ? "wifi" : "lan"))}
      title="Network"
      subtitle={createComputed(() => {
        const d = data()
        const b = busy()
        if (b === "scan") return "Scanning…"
        if (b && b !== "prefer" && b !== "disconnect") return `Connecting to ${b}…`
        return uplink(d)
      })}
      actions={[
        <IconButton
          icon="refresh"
          tooltip="Scan for Wi-Fi networks"
          class={busy((b) => (b === "scan" ? "spinning" : ""))}
          onClicked={() => run("scan", ["rescan"])}
        />,
        <IconButton
          icon="settings"
          tooltip="Open the Wi-Fi manager"
          onClicked={() => {
            closeCurrent()
            spawn(["network-menu", "manager"])
          }}
        />,
      ]}
      onOpen={() => (stop = every(5000, poll))}
      onClose={() => {
        stop?.()
        stop = null
      }}
    >
      <SectionLabel label="PREFERRED UPLINK" />
      <Segmented
        options={[
          { value: "lan", label: "Ethernet", icon: "lan" },
          { value: "wifi", label: "Wi-Fi", icon: "wifi" },
          { value: "auto", label: "Auto", icon: "swap_vert" },
        ]}
        selected={data((d) => d.mode)}
        onSelect={(mode) => {
          setData({ ...data.peek(), mode })
          run("prefer", ["prefer", mode])
        }}
      />
      <SectionLabel label="WI-FI NETWORKS">
        <label class="caption" label={data((d) => `${d.networks.length} in range`)} />
      </SectionLabel>
      <Scroll maxHeight={360}>
        <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
          <For each={data((d) => d.networks)} id={(n: Net) => n.ssid}>
            {(n: Net) => (
              <button
                class={n.connected ? "row current" : "row"}
                onClicked={() => run(n.ssid, ["connect", n.ssid])}
                tooltipText={n.connected ? "Connected" : `Connect to ${n.ssid}`}
              >
                <box spacing={12}>
                  <Icon name={SIGNAL[n.bars] ?? SIGNAL[0]} class="filled" />
                  <label class="row-title" xalign={0} hexpand ellipsize={3} label={n.ssid} />
                  {n.connected && <Chip label="Connected" class="primary" />}
                  {n.security !== "open" && <Icon name="lock" class="trail-lock" />}
                </box>
              </button>
            )}
          </For>
          <box visible={data((d) => d.networks.length === 0)}>
            <Empty icon="wifi_find" label="No networks found" detail="Scan again or check that the radio is on" />
          </box>
        </box>
      </Scroll>
      <box class="footer" spacing={8} visible={data((d) => d.networks.some((n) => n.connected))}>
        <button class="button" hexpand onClicked={() => run("disconnect", ["disconnect"])}>
          <box spacing={6} halign={Gtk.Align.CENTER}>
            <Icon name="link_off" />
            <label label="Disconnect Wi-Fi" />
          </box>
        </button>
      </box>
    </Popup>
  )
}
