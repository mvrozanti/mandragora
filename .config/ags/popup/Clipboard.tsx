import { Gdk, Gtk } from "ags/gtk4"
import GdkPixbuf from "gi://GdkPixbuf"
import { createComputed, createState, For } from "ags"
import Popup from "../widget/Popup"
import { Empty, Icon, IconButton, Scroll } from "../widget/parts"
import { execAsync } from "ags/process"
import { quiet } from "../lib/run"
import { close } from "../lib/popups"

type Entry = { id: string; text: string; image: { kind: string; size: string; dims: string } | null }

const IMAGE = /^\[\[ binary data (.+?) (\w+) (\d+x\d+) \]\]$/

function parse(out: string): Entry[] {
  return out
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const tab = line.indexOf("\t")
      const id = line.slice(0, tab)
      const text = line.slice(tab + 1)
      const m = text.match(IMAGE)
      return { id, text, image: m ? { size: m[1], kind: m[2], dims: m[3] } : null }
    })
}

function Thumb({ id }: { id: string }) {
  return (
    <Gtk.Picture
      class="thumb"
      contentFit={Gtk.ContentFit.COVER}
      canShrink
      widthRequest={112}
      heightRequest={68}
      overflow={Gtk.Overflow.HIDDEN}
      $={(self) => {
        execAsync(["clipboard-menu", "thumb", id])
          .then((path) => {
            const pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path.trim(), 112, 68, false)
            self.set_paintable(Gdk.Texture.new_for_pixbuf(pixbuf))
          })
          .catch(() => {})
      }}
    />
  )
}

export default function ClipboardPopup() {
  const [entries, setEntries] = createState<Entry[]>([])
  const [query, setQuery] = createState("")
  let search!: Gtk.SearchEntry
  let list!: Gtk.ListBox

  const load = () =>
    execAsync(["clipboard-menu", "list", "300"])
      .then((out) => setEntries(parse(out)))
      .catch(() => setEntries([]))

  const shown = createComputed(() => {
    const q = query().toLowerCase()
    return entries()
      .filter((e) => !q || e.text.toLowerCase().includes(q))
      .slice(0, 60)
  })

  const copy = (e: Entry) => {
    close("clipboard")
    quiet(["clipboard-menu", "copy", e.id])
  }
  const remove = async (e: Entry) => {
    setEntries(entries.peek().filter((x) => x.id !== e.id))
    await quiet(["clipboard-menu", "delete", e.id])
  }

  return (
    <Popup
      name="clipboard"
      width={440}
      icon="content_paste"
      title="Clipboard"
      subtitle={entries((e) => `${e.length} items in history`)}
      actions={
        <IconButton
          icon="delete_sweep"
          tooltip="Clear the whole history"
          onClicked={async () => {
            await quiet(["clipboard-menu", "clear"])
            setEntries([])
          }}
        />
      }
      onOpen={() => {
        search.text = ""
        load()
      }}
      focus={() => search}
    >
      <Gtk.SearchEntry
        $={(self) => {
          search = self
          self.connect("search-changed", () => setQuery(self.text))
          self.connect("activate", () => {
            const first = shown.peek()[0]
            if (first) copy(first)
          })
          const keys = new Gtk.EventControllerKey()
          keys.connect("key-pressed", (_c, key) => {
            if (key === Gdk.KEY_Down) {
              list.get_row_at_index(0)?.grab_focus()
              return true
            }
            return false
          })
          self.add_controller(keys)
        }}
        class="search"
        placeholderText="Search history"
      />
      <Scroll maxHeight={480}>
        <Gtk.ListBox
          $={(self) => {
            list = self
            self.connect("row-activated", (_l, row) => {
              const e = shown.peek()[row.get_index()]
              if (e) copy(e)
            })
          }}
          class="clip-list"
          selectionMode={Gtk.SelectionMode.NONE}
        >
          <For each={shown} id={(e: Entry) => e.id}>
            {(e: Entry) => (
              <Gtk.ListBoxRow class="row clip">
                <box spacing={12}>
                  {e.image ? (
                    <box spacing={12} hexpand>
                      <Thumb id={e.id} />
                      <box orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER}>
                        <label class="row-title" xalign={0} label={`${e.image.kind.toUpperCase()} image`} />
                        <label class="row-detail" xalign={0} label={`${e.image.dims} · ${e.image.size}`} />
                      </box>
                    </box>
                  ) : (
                    <label
                      class="clip-text"
                      xalign={0}
                      hexpand
                      wrap
                      lines={3}
                      ellipsize={3}
                      maxWidthChars={48}
                      label={e.text.trim()}
                    />
                  )}
                  <button class="icon-button trail" valign={Gtk.Align.CENTER} tooltipText="Remove from history" onClicked={() => remove(e)}>
                    <Icon name="close" />
                  </button>
                </box>
              </Gtk.ListBoxRow>
            )}
          </For>
        </Gtk.ListBox>
      </Scroll>
      <box visible={shown((s) => s.length === 0)}>
        <Empty
          icon="content_paste_off"
          label={query((q) => (q ? "Nothing matches" : "History is empty"))}
          detail={query((q) => (q ? `No entry contains “${q}”` : "Copied text and images show up here"))}
        />
      </box>
      <label class="caption hint" label="Enter copies the top match · ↓ moves into the list" />
    </Popup>
  )
}
