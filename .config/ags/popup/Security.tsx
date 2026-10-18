import { Gtk } from "ags/gtk4"
import { createComputed, createState, For } from "ags"
import Popup from "../widget/Popup"
import { Empty, Icon, IconButton, Scroll } from "../widget/parts"
import { json, quiet, spawn } from "../lib/run"
import { closeCurrent } from "../lib/popups"

type Severity = "critical" | "high" | "medium" | "low" | "unknown"
type Item = {
  severity: Severity
  score: number | null
  pname: string
  version: string
  cve: string | null
  desc: string
  url: string | null
}
type Data = {
  report: boolean
  running: boolean
  scanned?: string | null
  counts?: Record<Severity, number>
  suppressed?: number
  items?: Item[]
}

const LEVELS: { key: Severity; label: string }[] = [
  { key: "critical", label: "Critical" },
  { key: "high", label: "High" },
  { key: "medium", label: "Medium" },
  { key: "low", label: "Low" },
]
const LIMIT = 120

export default function SecurityPopup() {
  const [data, setData] = createState<Data>({ report: false, running: false })
  const [filter, setFilter] = createState<Severity | "all">("all")
  const [query, setQuery] = createState("")
  const [suppressed, setSuppressed] = createState(false)
  let search!: Gtk.SearchEntry

  const load = () =>
    json<Data>(["security-menu", "json", ...(suppressed.peek() ? ["--show-suppressed"] : [])])
      .then(setData)
      .catch(console.error)

  const visible = createComputed(() => {
    const f = filter()
    const q = query().toLowerCase()
    return (data().items ?? [])
      .filter((i) => f === "all" || i.severity === f)
      .filter((i) => !q || i.pname.toLowerCase().includes(q) || (i.cve ?? "").toLowerCase().includes(q))
      .slice(0, LIMIT)
  })

  return (
    <Popup
      name="security"
      width={480}
      icon="shield"
      title="Vulnerabilities"
      subtitle={data((d) =>
        d.running
          ? "Scan in progress…"
          : !d.report
            ? "No scan report yet"
            : `Scanned ${d.scanned} · ${d.suppressed ?? 0} suppressed`,
      )}
      actions={[
        <IconButton
          icon={suppressed((s) => (s ? "visibility" : "visibility_off"))}
          tooltip="Show suppressed matches"
          class={suppressed((s) => (s ? "on" : ""))}
          onClicked={() => {
            setSuppressed(!suppressed.peek())
            load()
          }}
        />,
        <IconButton
          icon="radar"
          tooltip="Run a new scan"
          class={data((d) => (d.running ? "spinning" : ""))}
          onClicked={async () => {
            await quiet(["security-menu", "rescan"])
            setData({ ...data.peek(), running: true })
          }}
        />,
      ]}
      onOpen={load}
      focus={() => search}
    >
      <box class="severity-grid" spacing={6} homogeneous>
        {LEVELS.map((l) => (
          <button
            class={createComputed(() => `sev-tile ${l.key}${filter() === l.key ? " active" : ""}`)}
            onClicked={() => setFilter(filter.peek() === l.key ? "all" : l.key)}
          >
            <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
              <label class="sev-count" xalign={0} label={data((d) => String(d.counts?.[l.key] ?? 0))} />
              <label class="sev-label" xalign={0} label={l.label} />
            </box>
          </button>
        ))}
      </box>
      <Gtk.SearchEntry
        $={(self) => {
          search = self
          self.connect("search-changed", () => setQuery(self.text))
        }}
        class="search"
        placeholderText="Filter by package or CVE"
      />
      <Scroll maxHeight={420}>
        <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
          <For each={visible} id={(i: Item) => `${i.pname}|${i.version}|${i.cve}`}>
            {(i: Item) => (
              <button
                class="row cve"
                tooltipText={i.desc || i.cve || ""}
                onClicked={() => {
                  if (!i.url) return
                  closeCurrent()
                  spawn(["xdg-open", i.url])
                }}
              >
                <box spacing={12}>
                  <label class={`score ${i.severity}`} valign={Gtk.Align.START} label={i.score != null ? i.score.toFixed(1) : "—"} />
                  <box orientation={Gtk.Orientation.VERTICAL} hexpand spacing={1}>
                    <box spacing={6}>
                      <label class="row-title" xalign={0} ellipsize={3} label={i.pname} />
                      <label class="row-detail" xalign={0} hexpand ellipsize={3} label={i.version} />
                    </box>
                    <label class="row-detail mono" xalign={0} label={i.cve ?? "no CVE id"} />
                    <label class="row-detail desc" xalign={0} wrap lines={2} ellipsize={3} maxWidthChars={58} label={i.desc} />
                  </box>
                  <Icon name="open_in_new" class="trail" />
                </box>
              </button>
            )}
          </For>
          </box>
          <box visible={visible((v) => v.length === 0)}>
            <Empty
              icon="verified_user"
              label={data((d) => (d.report ? "Nothing matches" : "No report yet"))}
              detail={data((d) => (d.report ? "Clear the filter to see every finding" : "Run a scan to check the system closure"))}
            />
          </box>
          <label
            class="caption more"
            visible={createComputed(() => (data().items?.length ?? 0) > LIMIT && visible().length === LIMIT)}
            label={`Showing the first ${LIMIT}. Filter to narrow it down.`}
          />
        </box>
      </Scroll>
    </Popup>
  )
}
