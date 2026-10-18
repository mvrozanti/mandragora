import { Gtk } from "ags/gtk4"
import { createComputed, For } from "ags"
import Notifd from "gi://AstalNotifd"
import Popup from "../widget/Popup"
import NotificationCard from "../widget/NotificationCard"
import { Empty, IconButton, Scroll } from "../widget/parts"
import { clearAll, dnd, notifd, notifications } from "../lib/notifications"
import { close } from "../lib/popups"
import { toastControl } from "../widget/Toasts"

export default function NotificationsPopup() {
  return (
    <Popup
      name="notifications"
      width={430}
      icon={dnd((d) => (d ? "notifications_paused" : "notifications"))}
      title="Notifications"
      subtitle={createComputed(() => {
        const count = notifications().length
        const text = count === 0 ? "Nothing new" : count === 1 ? "1 notification" : `${count} notifications`
        return dnd() ? `${text} · Do not disturb is on` : text
      })}
      onOpen={() => {
        toastControl.muted = true
        toastControl.clear()
      }}
      onClose={() => (toastControl.muted = false)}
      actions={[
        <IconButton
          icon={dnd((d) => (d ? "notifications_off" : "notifications_active"))}
          tooltip="Do not disturb"
          class={dnd((d) => (d ? "on" : ""))}
          onClicked={() => (notifd.dontDisturb = !notifd.dontDisturb)}
        />,
        <IconButton
          icon="delete_sweep"
          tooltip="Clear all"
          sensitive={notifications((l) => l.length > 0)}
          onClicked={clearAll}
        />,
      ]}
    >
      <Scroll maxHeight={560}>
        <box orientation={Gtk.Orientation.VERTICAL} spacing={8}>
          <For each={notifications} id={(n: Notifd.Notification) => n.id}>
            {(n: Notifd.Notification) => (
              <NotificationCard n={n} onActivate={() => close("notifications")} />
            )}
          </For>
        </box>
      </Scroll>
      <box visible={notifications((l) => l.length === 0)}>
        <Empty
          icon={dnd((d) => (d ? "notifications_paused" : "notifications_none"))}
          label="All caught up"
          detail={dnd((d) => (d ? "Pop-ups are muted until you turn Do not disturb off" : "New notifications land here"))}
        />
      </box>
    </Popup>
  )
}
