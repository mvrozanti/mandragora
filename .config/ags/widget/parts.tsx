import { Gtk } from "ags/gtk4"
import GLib from "gi://GLib"
import { Accessor, For } from "ags"

type Str = string | Accessor<string>

export function Icon({ name, class: cls = "" }: { name: Str; class?: Str }) {
  const classes =
    typeof cls === "string" ? `icon ${cls}` : cls.as((c) => `icon ${c}`)
  return <label class={classes} label={name} />
}

export function IconButton(props: {
  icon: Str
  tooltip?: string
  class?: Str
  sensitive?: boolean | Accessor<boolean>
  onClicked: () => void
}) {
  const classes =
    props.class === undefined
      ? "icon-button"
      : typeof props.class === "string"
        ? `icon-button ${props.class}`
        : props.class.as((c) => `icon-button ${c}`)
  return (
    <button
      class={classes}
      tooltipText={props.tooltip}
      sensitive={props.sensitive ?? true}
      onClicked={props.onClicked}
      valign={Gtk.Align.CENTER}
    >
      <Icon name={props.icon} />
    </button>
  )
}

export function Chip({ label, icon, class: cls = "" }: { label: Str; icon?: Str; class?: Str }) {
  const classes = typeof cls === "string" ? `chip ${cls}` : cls.as((c) => `chip ${c}`)
  return (
    <box class={classes} spacing={4} valign={Gtk.Align.CENTER}>
      {icon !== undefined && <Icon name={icon} />}
      <label label={label} />
    </box>
  )
}

export function Meter({ value, class: cls = "" }: { value: number | Accessor<number>; class?: string }) {
  return (
    <levelbar
      class={`meter ${cls}`}
      valign={Gtk.Align.CENTER}
      heightRequest={cls.includes("thin") ? 4 : 8}
      minValue={0}
      maxValue={1}
      value={value}
      $={(self) => {
        self.remove_offset_value(Gtk.LEVEL_BAR_OFFSET_LOW)
        self.remove_offset_value(Gtk.LEVEL_BAR_OFFSET_HIGH)
        self.remove_offset_value(Gtk.LEVEL_BAR_OFFSET_FULL)
      }}
    />
  )
}

export function Segmented<T extends string>(props: {
  options: { value: T; label: string; icon?: string }[]
  selected: Accessor<T>
  onSelect: (value: T) => void
  class?: string
}) {
  return (
    <box class={`segmented ${props.class ?? ""}`} homogeneous>
      {props.options.map((o) => (
        <button
          class={props.selected((s) => (s === o.value ? "segment active" : "segment"))}
          onClicked={() => props.onSelect(o.value)}
        >
          <box spacing={6} halign={Gtk.Align.CENTER}>
            {o.icon && <Icon name={o.icon} />}
            <label label={o.label} />
          </box>
        </button>
      ))}
    </box>
  )
}

export function SectionLabel({ label, children }: { label: Str; children?: JSX.Element | JSX.Element[] }) {
  return (
    <box class="section-label" spacing={8}>
      <label label={label} xalign={0} hexpand />
      {children}
    </box>
  )
}

export function Empty({ icon, label, detail }: { icon: string; label: Str; detail?: Str }) {
  return (
    <box class="empty-state" orientation={Gtk.Orientation.VERTICAL} spacing={6} valign={Gtk.Align.CENTER}>
      <Icon name={icon} class="empty-icon" />
      <label class="empty-label" label={label} />
      {detail !== undefined && <label class="empty-detail" label={detail} wrap justify={Gtk.Justification.CENTER} />}
    </box>
  )
}

export function Scroll({
  maxHeight,
  children,
}: {
  maxHeight: number
  children?: JSX.Element | JSX.Element[]
}) {
  return (
    <scrolledwindow
      class="scroll"
      hscrollbarPolicy={Gtk.PolicyType.NEVER}
      propagateNaturalHeight
      maxContentHeight={maxHeight}
    >
      {children}
    </scrolledwindow>
  )
}

export function List<T>({
  each,
  id,
  children,
}: {
  each: Accessor<T[]>
  id?: (item: T) => unknown
  children: (item: T) => JSX.Element
}) {
  return (
    <box class="list" orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      <For each={each} id={id as any}>
        {(item: T) => children(item)}
      </For>
    </box>
  )
}

export function ConfirmButton(props: {
  icon: string
  label: string
  confirm: string
  class?: string
  onConfirm: () => void
}) {
  let armed = false
  let timer = 0
  return (
    <button
      class={`confirm ${props.class ?? ""}`}
      $={(self) => {
        const box = self.get_child() as Gtk.Box
        const text = box.get_last_child() as Gtk.Label
        self.connect("clicked", () => {
          if (armed) {
            props.onConfirm()
            return
          }
          armed = true
          self.add_css_class("armed")
          text.label = props.confirm
          if (timer) GLib.source_remove(timer)
          timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 3000, () => {
            armed = false
            timer = 0
            self.remove_css_class("armed")
            text.label = props.label
            return false
          })
        })
      }}
    >
      <box orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER} spacing={4}>
        <Icon name={props.icon} class="tile-icon" />
        <label class="tile-label" label={props.label} />
      </box>
    </button>
  )
}
