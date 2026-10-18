import { Gdk, Gtk } from "ags/gtk4"
import Gio from "gi://Gio"
import Notifd from "gi://AstalNotifd"
import GLib from "gi://GLib"
import Pango from "gi://Pango"
import { Icon } from "./parts"
import { ago, now } from "../lib/run"
import { invokeDefault } from "../lib/notifications"

const isFile = (p: string) => !!p && GLib.file_test(p.replace(/^file:\/\//, ""), GLib.FileTest.EXISTS)
const path = (p: string) => p.replace(/^file:\/\//, "")

function markup(text: string): string {
  try {
    Pango.parse_markup(text, -1, "\0")
    return text
  } catch {
    return GLib.markup_escape_text(text, -1)
  }
}

function AppIcon({ n }: { n: Notifd.Notification }) {
  const theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default()!)
  const name = [n.appIcon, n.desktopEntry, n.appName.toLowerCase()].find(
    (i) => i && !isFile(i) && theme.has_icon(i),
  )
  if (isFile(n.appIcon))
    return <Gtk.Image class="app-icon" file={path(n.appIcon)} pixelSize={40} valign={Gtk.Align.START} />
  if (name) return <Gtk.Image class="app-icon" iconName={name} pixelSize={40} valign={Gtk.Align.START} />
  return (
    <box class="app-icon glyph" valign={Gtk.Align.START}>
      <Icon name="notifications" class="filled" />
    </box>
  )
}

export default function NotificationCard(props: {
  n: Notifd.Notification
  onDismiss?: () => void
  onActivate?: () => void
  toast?: boolean
}) {
  const { n } = props
  const critical = n.urgency === Notifd.Urgency.CRITICAL
  const buttons = n.actions.filter((a) => a.id !== "default")
  return (
    <box
      class={`notification${critical ? " critical" : ""}${props.toast ? " toast" : ""}`}
      spacing={12}
      $={(self) => {
        const click = new Gtk.GestureClick()
        click.connect("released", () => {
          invokeDefault(n)
          props.onActivate?.()
        })
        self.add_controller(click)
      }}
    >
      <AppIcon n={n} />
      <box orientation={Gtk.Orientation.VERTICAL} hexpand spacing={2}>
        <box spacing={6}>
          <label class="n-app" xalign={0} ellipsize={3} label={n.appName || "Notification"} />
          <label class="n-time" xalign={0} hexpand label={`· ${ago(now() - n.time)}`} />
          <button
            class="icon-button n-close"
            tooltipText="Dismiss"
            valign={Gtk.Align.START}
            onClicked={() => {
              n.dismiss()
              props.onDismiss?.()
            }}
          >
            <Icon name="close" />
          </button>
        </box>
        <label class="n-summary" xalign={0} wrap lines={2} ellipsize={3} maxWidthChars={40} label={n.summary} />
        {n.body !== "" && (
          <label
            class="n-body"
            xalign={0}
            wrap
            lines={4}
            ellipsize={3}
            maxWidthChars={44}
            useMarkup
            label={markup(n.body)}
          />
        )}
        {isFile(n.image) && n.image !== n.appIcon && (
          <Gtk.Picture
            class="n-image"
            file={Gio.File.new_for_path(path(n.image))}
            contentFit={Gtk.ContentFit.COVER}
            canShrink
            heightRequest={140}
            overflow={Gtk.Overflow.HIDDEN}
          />
        )}
        {buttons.length > 0 && (
          <box class="n-actions" spacing={6} homogeneous>
            {buttons.map((a) => (
              <button
                class="button tonal"
                onClicked={() => {
                  n.invoke(a.id)
                  if (!n.resident) n.dismiss()
                  props.onActivate?.()
                }}
              >
                <label label={a.label} ellipsize={3} />
              </button>
            ))}
          </box>
        )}
      </box>
    </box>
  )
}
