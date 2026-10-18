import app from "ags/gtk4/app"
import { Astal, Gdk, Gtk } from "ags/gtk4"
import { Accessor } from "ags"
import { close, register } from "../lib/popups"
import { Icon } from "./parts"

type Props = {
  name: string
  width: number
  icon: string | Accessor<string>
  title: string | Accessor<string>
  subtitle?: string | Accessor<string>
  tone?: string | Accessor<string>
  actions?: JSX.Element | JSX.Element[]
  onOpen?: () => void
  onClose?: () => void
  focus?: () => Gtk.Widget | null | undefined
  children?: JSX.Element | JSX.Element[]
}

export default function Popup(props: Props) {
  const { TOP, BOTTOM, LEFT, RIGHT } = Astal.WindowAnchor
  let revealer!: Gtk.Revealer
  let card!: Gtk.Box
  let root!: Gtk.Box

  const outside = (x: number, y: number) => {
    const [ok, bounds] = card.compute_bounds(root)
    if (!ok) return true
    const ox = bounds.get_x()
    const oy = bounds.get_y()
    return x < ox || y < oy || x > ox + bounds.get_width() || y > oy + bounds.get_height()
  }

  return (
    <window
      visible={false}
      name={props.name}
      namespace="mandragora-popup"
      class="popup-window"
      application={app}
      layer={Astal.Layer.TOP}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.EXCLUSIVE}
      anchor={TOP | BOTTOM | LEFT | RIGHT}
      $={(win) => {
        const keys = new Gtk.EventControllerKey({ propagationPhase: Gtk.PropagationPhase.CAPTURE })
        keys.connect("key-pressed", (_c, keyval) => {
          if (keyval === Gdk.KEY_Escape) {
            close(props.name)
            return true
          }
          return false
        })
        win.add_controller(keys)
        register({
          name: props.name,
          width: props.width,
          window: win,
          revealer,
          card,
          onOpen: props.onOpen,
          onClose: props.onClose,
          focus: () => props.focus?.()?.grab_focus(),
        })
      }}
    >
      <box
        $={(self) => {
          root = self
          const click = new Gtk.GestureClick({ button: 0 })
          click.connect("pressed", (_g, _n, x, y) => {
            if (outside(x, y)) close(props.name)
          })
          self.add_controller(click)
        }}
        hexpand
        vexpand
      >
        <revealer
          $={(self) => (revealer = self)}
          transitionType={Gtk.RevealerTransitionType.SLIDE_UP}
          transitionDuration={220}
          valign={Gtk.Align.END}
          halign={Gtk.Align.START}
        >
          <box
            $={(self) => (card = self)}
            class={props.tone ? (props.tone as any) : "card"}
            orientation={Gtk.Orientation.VERTICAL}
            widthRequest={props.width}
            valign={Gtk.Align.END}
            marginBottom={50}
            marginTop={12}
          >
            <box class="header" spacing={12}>
              <box class="header-icon" valign={Gtk.Align.CENTER}>
                <Icon name={props.icon} />
              </box>
              <box orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER} hexpand>
                <label class="title" xalign={0} label={props.title} ellipsize={3} />
                {props.subtitle !== undefined && (
                  <label class="subtitle" xalign={0} label={props.subtitle} ellipsize={3} />
                )}
              </box>
              <box class="header-actions" spacing={4} valign={Gtk.Align.CENTER}>
                {props.actions}
              </box>
            </box>
            {props.children}
          </box>
        </revealer>
      </box>
    </window>
  )
}
