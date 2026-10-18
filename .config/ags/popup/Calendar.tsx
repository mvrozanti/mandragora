import { Gtk } from "ags/gtk4"
import { createState, With } from "ags"
import GLib from "gi://GLib"
import Popup from "../widget/Popup"
import { IconButton } from "../widget/parts"

type View = { year: number; month: number }

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function today(): GLib.DateTime {
  return GLib.DateTime.new_now_local()
}

function current(): View {
  const t = today()
  return { year: t.get_year(), month: t.get_month() }
}

function shift(v: View, by: number): View {
  const index = v.year * 12 + (v.month - 1) + by
  return { year: Math.floor(index / 12), month: (index % 12) + 1 }
}

function monthTitle(v: View): string {
  return GLib.DateTime.new_local(v.year, v.month, 1, 0, 0, 0).format("%B %Y") ?? ""
}

function Month({ view }: { view: View }) {
  const grid = new Gtk.Grid({ cssClasses: ["month-grid"], columnHomogeneous: true, rowSpacing: 2, columnSpacing: 2 })
  WEEKDAYS.forEach((d, col) => grid.attach(new Gtk.Label({ label: d, cssClasses: ["weekday"] }), col, 0, 1, 1))

  const first = GLib.DateTime.new_local(view.year, view.month, 1, 0, 0, 0)
  const lead = first.get_day_of_week() % 7
  const start = first.add_days(-lead)!
  const t = today()

  for (let i = 0; i < 42; i++) {
    const day = start.add_days(i)!
    const outside = day.get_month() !== view.month
    const isToday =
      day.get_year() === t.get_year() && day.get_month() === t.get_month() && day.get_day_of_month() === t.get_day_of_month()
    const weekend = i % 7 === 0 || i % 7 === 6
    const classes = ["day"]
    if (outside) classes.push("outside")
    if (weekend) classes.push("weekend")
    if (isToday) classes.push("today")
    const cell = new Gtk.Label({ label: String(day.get_day_of_month()), cssClasses: classes })
    grid.attach(cell, i % 7, 1 + Math.floor(i / 7), 1, 1)
  }
  return grid
}

export default function CalendarPopup() {
  const [view, setView] = createState<View>(current())
  const [now, setNow] = createState(today())

  return (
    <Popup
      name="calendar"
      width={340}
      icon="calendar_month"
      title={now((t) => t.format("%A, %-d %B") ?? "")}
      subtitle={now((t) => `Week ${t.get_week_of_year()} · day ${t.get_day_of_year()} of ${t.get_year()}`)}
      onOpen={() => {
        setNow(today())
        setView(current())
      }}
    >
      <box class="month-bar" spacing={4}>
        <label class="month-title" xalign={0} hexpand label={view(monthTitle)} />
        <button
          class="today-chip"
          visible={view((v) => v.year !== current().year || v.month !== current().month)}
          onClicked={() => setView(current())}
        >
          <label label="Today" />
        </button>
        <IconButton icon="chevron_left" tooltip="Previous month" onClicked={() => setView(shift(view.peek(), -1))} />
        <IconButton icon="chevron_right" tooltip="Next month" onClicked={() => setView(shift(view.peek(), 1))} />
      </box>
      <box
        class="month"
        $={(self) => {
          const scroll = new Gtk.EventControllerScroll({ flags: Gtk.EventControllerScrollFlags.VERTICAL })
          scroll.connect("scroll", (_c, _dx, dy) => {
            setView(shift(view.peek(), dy > 0 ? 1 : -1))
            return true
          })
          self.add_controller(scroll)
        }}
      >
        <With value={view}>{(v: View) => <Month view={v} />}</With>
      </box>
    </Popup>
  )
}
