import { Gtk } from "ags/gtk4"
import { createState, With } from "ags"
import Popup from "../widget/Popup"
import { Chip, Empty, Icon, IconButton, SectionLabel } from "../widget/parts"
import { json } from "../lib/run"

type Slot = { time: string; temp: number; icon: string; desc: string; pop: number; wind: number }
type Day = { label: string; date: string; min: number; max: number; icon: string; pop: number; slots: Slot[] }
type Data = {
  error?: string
  city: string
  country: string
  desc: string
  icon: string
  temp: number
  feels: number
  humidity: number
  pressure: number
  wind: number
  wind_dir: string
  sunrise: string | null
  sunset: string | null
  updated: string | null
  days: Day[]
}

const GLYPH: Record<string, [string, string]> = {
  "01": ["clear_day", "clear_night"],
  "02": ["partly_cloudy_day", "partly_cloudy_night"],
  "03": ["cloud", "cloud"],
  "04": ["cloud", "cloud"],
  "09": ["rainy", "rainy"],
  "10": ["rainy_light", "rainy_light"],
  "11": ["thunderstorm", "thunderstorm"],
  "13": ["weather_snowy", "weather_snowy"],
  "50": ["foggy", "foggy"],
}

const glyph = (code: string) => (GLYPH[code.slice(0, 2)] ?? ["cloud", "cloud"])[code.endsWith("n") ? 1 : 0]

function RangeBar({ day, lo, hi }: { day: Day; lo: number; hi: number }) {
  const span = Math.max(1, hi - lo)
  const total = 120
  const start = Math.round(((day.min - lo) / span) * total)
  const width = Math.max(10, Math.round(((day.max - day.min) / span) * total))
  return (
    <box class="range-track" widthRequest={total} valign={Gtk.Align.CENTER}>
      <box class="range-fill" widthRequest={width} marginStart={Math.min(start, total - width)} />
    </box>
  )
}

export default function WeatherPopup() {
  const [data, setData] = createState<Data | null>(null)
  const [busy, setBusy] = createState(false)

  const load = (refresh = false) => {
    setBusy(true)
    json<Data>(["weather-menu", "json", ...(refresh ? ["--refresh"] : [])])
      .then(setData)
      .catch((e) => setData({ error: String(e) } as Data))
      .finally(() => setBusy(false))
  }

  return (
    <Popup
      name="weather"
      width={420}
      icon={data((d) => (d && !d.error ? glyph(d.icon) : "partly_cloudy_day"))}
      title={data((d) => (d && !d.error ? `${d.city}, ${d.country}` : "Weather"))}
      subtitle={data((d) =>
        !d ? "Loading…" : d.error ? d.error : d.updated ? `Updated at ${d.updated}` : "",
      )}
      actions={
        <IconButton
          icon="refresh"
          tooltip="Fetch a fresh forecast"
          class={busy((b) => (b ? "spinning" : ""))}
          onClicked={() => load(true)}
        />
      }
      onOpen={() => load(false)}
    >
      <With value={data}>
        {(d: Data | null) =>
          !d || d.error ? (
            <Empty icon="cloud_off" label={d?.error ? "Forecast unavailable" : "Loading forecast"} detail={d?.error} />
          ) : (
            <box orientation={Gtk.Orientation.VERTICAL}>
              <box class="weather-hero" spacing={16}>
                <Icon name={glyph(d.icon)} class="hero-glyph filled" />
                <box orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER} hexpand>
                  <label class="hero-temp" xalign={0} label={`${d.temp}°`} />
                  <label class="hero-desc" xalign={0} label={d.desc} />
                </box>
                <box orientation={Gtk.Orientation.VERTICAL} spacing={6} valign={Gtk.Align.CENTER}>
                  <Chip icon="device_thermostat" label={`Feels ${d.feels}°`} class="quiet" />
                  <Chip icon="humidity_percentage" label={`${d.humidity}%`} class="quiet" />
                  <Chip icon="air" label={`${d.wind} m/s ${d.wind_dir}`} class="quiet" />
                </box>
              </box>
              <box class="sun-row" spacing={8} homogeneous>
                <box class="tile tight" spacing={10}>
                  <Icon name="wb_twilight" class="tile-glyph" />
                  <box orientation={Gtk.Orientation.VERTICAL}>
                    <label class="caption" xalign={0} label="Sunrise" />
                    <label class="caption strong" xalign={0} label={d.sunrise ?? "—"} />
                  </box>
                </box>
                <box class="tile tight" spacing={10}>
                  <Icon name="nights_stay" class="tile-glyph" />
                  <box orientation={Gtk.Orientation.VERTICAL}>
                    <label class="caption" xalign={0} label="Sunset" />
                    <label class="caption strong" xalign={0} label={d.sunset ?? "—"} />
                  </box>
                </box>
                <box class="tile tight" spacing={10}>
                  <Icon name="compress" class="tile-glyph" />
                  <box orientation={Gtk.Orientation.VERTICAL}>
                    <label class="caption" xalign={0} label="Pressure" />
                    <label class="caption strong" xalign={0} label={`${d.pressure} hPa`} />
                  </box>
                </box>
              </box>

              <SectionLabel label="NEXT 24 HOURS" />
              <box class="hourly" homogeneous>
                {d.days
                  .flatMap((day) => day.slots)
                  .slice(0, 8)
                  .map((s) => (
                    <box class="hour" orientation={Gtk.Orientation.VERTICAL} spacing={4} tooltipText={s.desc}>
                      <label class="caption" label={s.time.slice(0, 2) + "h"} />
                      <Icon name={glyph(s.icon)} class="hour-glyph" />
                      <label class="hour-temp" label={`${s.temp}°`} />
                      <label class={s.pop >= 0.2 ? "hour-pop" : "hour-pop dim"} label={`${Math.round(s.pop * 100)}%`} />
                    </box>
                  ))}
              </box>

              <SectionLabel label="THIS WEEK" />
              <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
                {d.days.map((day) => {
                  const lo = Math.min(...d.days.map((x) => x.min))
                  const hi = Math.max(...d.days.map((x) => x.max))
                  return (
                    <box class="row day" spacing={12}>
                      <label class="row-title day-label" xalign={0} widthChars={6} label={day.label} />
                      <Icon name={glyph(day.icon)} class="filled" />
                      <label class={day.pop >= 0.2 ? "day-pop" : "day-pop dim"} widthChars={4} xalign={1} label={day.pop >= 0.2 ? `${Math.round(day.pop * 100)}%` : ""} />
                      <label class="day-min" widthChars={3} xalign={1} label={`${day.min}°`} />
                      <RangeBar day={day} lo={lo} hi={hi} />
                      <label class="day-max" widthChars={3} xalign={0} label={`${day.max}°`} hexpand />
                    </box>
                  )
                })}
              </box>
            </box>
          )
        }
      </With>
    </Popup>
  )
}
