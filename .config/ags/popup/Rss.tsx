import { Gtk } from "ags/gtk4"
import { createComputed, createState, For } from "ags"
import Popup from "../widget/Popup"
import { Empty, Icon, IconButton, Scroll, Segmented } from "../widget/parts"
import { ago, json, now, quiet, spawn } from "../lib/run"
import { closeCurrent } from "../lib/popups"

type Item = {
  id: string
  feed: string
  title: string
  summary: string
  urgency: number
  url: string
  read: boolean
  ts: number
}
type Data = { unread: number; feeds: string[]; items: Item[] }

const MARK = (u: number) => (u >= 3 ? "local_fire_department" : u >= 2 ? "star" : "")

export default function RssPopup() {
  const [data, setData] = createState<Data>({ unread: 0, feeds: [], items: [] })
  const [scope, setScope] = createState<"unread" | "all">("unread")
  const [feed, setFeed] = createState<string>("")
  const [busy, setBusy] = createState(false)

  const load = () =>
    json<Data>(["rss-menu", "json", ...(scope.peek() === "all" ? ["--all"] : [])])
      .then(setData)
      .catch(console.error)

  const items = createComputed(() => {
    const f = feed()
    return data().items.filter((i) => !f || i.feed === f).slice(0, 80)
  })

  return (
    <Popup
      name="rss"
      width={460}
      icon="rss_feed"
      title="Feeds"
      subtitle={createComputed(() =>
        busy() ? "Polling feeds…" : `${data().unread} unread across ${data().feeds.length} feeds`,
      )}
      actions={[
        <IconButton
          icon="sync"
          tooltip="Poll feeds now"
          class={busy((b) => (b ? "spinning" : ""))}
          onClicked={async () => {
            setBusy(true)
            await quiet(["systemctl", "--user", "start", "rss-menu-poll.service"])
            await load()
            setBusy(false)
          }}
        />,
        <IconButton
          icon="done_all"
          tooltip="Mark everything as read"
          onClicked={async () => {
            await quiet(["rss-menu", "mark-all-read"])
            load()
          }}
        />,
      ]}
      onOpen={load}
    >
      <Segmented
        options={[
          { value: "unread", label: "Unread", icon: "mark_email_unread" },
          { value: "all", label: "Everything", icon: "inbox" },
        ]}
        selected={scope}
        onSelect={(v) => {
          setScope(v)
          load()
        }}
      />
      <box class="feed-chips" spacing={6}>
        <button class={feed((f) => (f === "" ? "filter-chip active" : "filter-chip"))} onClicked={() => setFeed("")}>
          <label label="All feeds" />
        </button>
        <For each={data((d) => d.feeds)}>
          {(name: string) => (
            <button
              class={feed((f) => (f === name ? "filter-chip active" : "filter-chip"))}
              onClicked={() => setFeed(feed.peek() === name ? "" : name)}
            >
              <label label={name.replace(/ \(.*\)$/, "")} />
            </button>
          )}
        </For>
      </box>
      <Scroll maxHeight={460}>
        <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
          <For each={items} id={(i: Item) => i.id}>
            {(i: Item) => (
              <button
                class={i.read ? "row article read" : "row article"}
                tooltipText={i.summary}
                onClicked={() => {
                  closeCurrent()
                  spawn(["rss-menu", "open", i.id])
                }}
              >
                <box spacing={12}>
                  <box class={`urgency u${Math.min(i.urgency, 3)}`} valign={Gtk.Align.START}>
                    <Icon name={MARK(i.urgency) || "article"} class={i.urgency >= 2 ? "filled" : ""} />
                  </box>
                  <box orientation={Gtk.Orientation.VERTICAL} hexpand spacing={2}>
                    <label class="row-title" xalign={0} wrap lines={2} ellipsize={3} maxWidthChars={46} label={i.title} />
                    <label class="row-detail" xalign={0} label={`${i.feed} · ${ago(now() - i.ts)}`} />
                  </box>
                </box>
              </button>
            )}
          </For>
          <box visible={items((v) => v.length === 0)}>
            <Empty icon="mark_email_read" label="All caught up" detail="New items arrive every 15 minutes" />
          </box>
        </box>
      </Scroll>
    </Popup>
  )
}
