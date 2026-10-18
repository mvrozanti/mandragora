import app from "ags/gtk4/app"
import { Astal, Gtk } from "ags/gtk4"
import Notifd from "gi://AstalNotifd"
import GLib from "gi://GLib"
import { createRoot } from "ags"
import NotificationCard from "./NotificationCard"
import { notifd } from "../lib/notifications"

const MAX = 4
const TIMEOUT = { [Notifd.Urgency.LOW]: 5000, [Notifd.Urgency.NORMAL]: 8000, [Notifd.Urgency.CRITICAL]: 0 }

export const toastControl = { muted: false, clear: () => {} }

type Toast = { revealer: Gtk.Revealer; timer: number; hovered: boolean; dispose: () => void }

export default function Toasts() {
  const toasts = new Map<number, Toast>()
  let stack!: Gtk.Box
  let win!: Astal.Window

  const remove = (id: number) => {
    const t = toasts.get(id)
    if (!t) return
    toasts.delete(id)
    if (t.timer) GLib.source_remove(t.timer)
    t.revealer.revealChild = false
    t.dispose()
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, t.revealer.transitionDuration + 20, () => {
      stack.remove(t.revealer)
      if (toasts.size === 0) win.visible = false
      return GLib.SOURCE_REMOVE
    })
  }

  const arm = (id: number, n: Notifd.Notification) => {
    const t = toasts.get(id)
    if (!t) return
    if (t.timer) GLib.source_remove(t.timer)
    t.timer = 0
    const ms = n.expireTimeout > 0 ? n.expireTimeout : TIMEOUT[n.urgency]
    if (ms <= 0) return
    t.timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
      t.timer = 0
      if (t.hovered) return GLib.SOURCE_REMOVE
      if (n.transient) n.dismiss()
      remove(id)
      return GLib.SOURCE_REMOVE
    })
  }

  const show = (id: number) => {
    const n = notifd.get_notification(id)
    if (!n) return
    if (toastControl.muted) return
    if (notifd.dontDisturb && n.urgency !== Notifd.Urgency.CRITICAL) return
    const existing = toasts.get(id)
    if (existing) {
      if (existing.timer) GLib.source_remove(existing.timer)
      existing.dispose()
      stack.remove(existing.revealer)
      toasts.delete(id)
    }
    const revealer = new Gtk.Revealer({
      transitionType: Gtk.RevealerTransitionType.SLIDE_UP,
      transitionDuration: 200,
    })
    let dispose = () => {}
    revealer.set_child(
      createRoot((d) => {
        dispose = d
        return NotificationCard({ n, toast: true, onDismiss: () => remove(id), onActivate: () => remove(id) }) as Gtk.Widget
      }),
    )
    const t: Toast = { revealer, timer: 0, hovered: false, dispose }
    const motion = new Gtk.EventControllerMotion()
    motion.connect("enter", () => {
      t.hovered = true
      if (t.timer) GLib.source_remove(t.timer)
      t.timer = 0
    })
    motion.connect("leave", () => {
      t.hovered = false
      arm(id, n)
    })
    revealer.add_controller(motion)
    toasts.set(id, t)
    stack.append(revealer)
    win.visible = true
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      revealer.revealChild = true
      return GLib.SOURCE_REMOVE
    })
    arm(id, n)
    while (toasts.size > MAX) remove(toasts.keys().next().value!)
  }

  toastControl.clear = () => [...toasts.keys()].forEach(remove)
  notifd.connect("notified", (_n, id) => show(id))
  notifd.connect("resolved", (_n, id) => remove(id))

  const { BOTTOM, RIGHT } = Astal.WindowAnchor
  return (
    <window
      $={(self) => (win = self)}
      visible={false}
      name="toasts"
      namespace="mandragora-toast"
      class="toast-window"
      application={app}
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.NORMAL}
      keymode={Astal.Keymode.NONE}
      anchor={BOTTOM | RIGHT}
      marginRight={12}
      marginBottom={10}
    >
      <box
        $={(self) => (stack = self)}
        class="toast-stack"
        orientation={Gtk.Orientation.VERTICAL}
        spacing={8}
        widthRequest={400}
        valign={Gtk.Align.END}
      />
    </window>
  )
}
