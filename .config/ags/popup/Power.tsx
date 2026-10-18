import { Gtk } from "ags/gtk4"
import { createState } from "ags"
import { readFile } from "ags/file"
import Popup from "../widget/Popup"
import { ConfirmButton, Icon } from "../widget/parts"
import { closeCurrent } from "../lib/popups"
import { spawn } from "../lib/run"

function uptime(): string {
  const secs = Number(readFile("/proc/uptime").split(" ")[0])
  const d = Math.floor(secs / 86400)
  const h = Math.floor((secs % 86400) / 3600)
  const m = Math.floor((secs % 3600) / 60)
  return d > 0 ? `${d} d ${h} h` : h > 0 ? `${h} h ${m} min` : `${m} min`
}

function Action(props: { icon: string; label: string; run: string[] }) {
  return (
    <button
      class="power-tile"
      onClicked={() => {
        closeCurrent()
        spawn(props.run, 250)
      }}
    >
      <box orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER} spacing={4}>
        <Icon name={props.icon} class="tile-icon" />
        <label class="tile-label" label={props.label} />
      </box>
    </button>
  )
}

export default function PowerPopup() {
  const [up, setUp] = createState(uptime())
  return (
    <Popup
      name="power"
      width={520}
      icon="power_settings_new"
      title="Session"
      subtitle={up((u) => `Up for ${u}`)}
      onOpen={() => setUp(uptime())}
    >
      <box class="power-grid" spacing={8} homogeneous>
        <Action icon="lock" label="Lock" run={["hyprlock"]} />
        <Action icon="bedtime" label="Suspend" run={["systemctl", "suspend"]} />
        <Action icon="ac_unit" label="Hibernate" run={["systemctl", "hibernate"]} />
        <ConfirmButton
          icon="restart_alt"
          label="Reboot"
          confirm="Again to reboot"
          class="power-tile danger"
          onConfirm={() => {
            closeCurrent()
            spawn(["systemctl", "reboot"], 250)
          }}
        />
        <ConfirmButton
          icon="power_settings_new"
          label="Power off"
          confirm="Again to power off"
          class="power-tile danger"
          onConfirm={() => {
            closeCurrent()
            spawn(["systemctl", "poweroff"], 250)
          }}
        />
      </box>
    </Popup>
  )
}
