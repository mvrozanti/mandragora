import { Gtk } from "ags/gtk4"
import { createComputed, createState, For } from "ags"
import Popup from "../widget/Popup"
import { Chip, Icon, IconButton, Meter, SectionLabel, Segmented } from "../widget/parts"
import { ago, json, now, quiet } from "../lib/run"

type Unit = "btc" | "usd" | "brl"
type Account = { label: string; sats: number | null; note: string | null }
type Data = {
  sats: number | null
  usd: number | null
  brl: number | null
  accounts: Account[]
  error: string | null
  fetched_at?: number
  unit: Unit
  stale?: boolean
}

const btc = (sats: number | null) =>
  sats == null ? "—" : (sats / 1e8).toFixed(8).replace(/0+$/, "").replace(/\.$/, "")

const money = (sats: number | null, price: number | null, symbol: string) =>
  sats == null || price == null
    ? "—"
    : `${symbol} ${((sats / 1e8) * price).toLocaleString("en-US", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`

function primary(d: Data): [string, string] {
  if (d.unit === "usd") return [money(d.sats, d.usd, "$"), "US dollars"]
  if (d.unit === "brl") return [money(d.sats, d.brl, "R$"), "Brazilian reais"]
  return [`₿ ${btc(d.sats)}`, "bitcoin"]
}

export default function BtcPopup() {
  const [data, setData] = createState<Data>({
    sats: null,
    usd: null,
    brl: null,
    accounts: [],
    error: null,
    unit: "btc",
  })
  const [busy, setBusy] = createState(false)
  const [hidden, setHidden] = createState(false)

  const load = () => json<Data>(["btc-menu", "json"]).then(setData).catch(console.error)
  const refresh = async () => {
    setBusy(true)
    await quiet(["btc-menu", "refresh"])
    await load()
    setBusy(false)
  }
  const setUnit = async (unit: Unit) => {
    setData({ ...data.peek(), unit })
    for (let i = 0; i < 3 && (await json<Data>(["btc-menu", "json"])).unit !== unit; i++)
      await quiet(["btc-menu", "cycle-unit"])
  }
  const mask = (s: string) => (hidden.peek() ? s.replace(/[0-9]/g, "•") : s)

  return (
    <Popup
      name="btc"
      width={400}
      icon="currency_bitcoin"
      title="Bitcoin"
      subtitle={createComputed(() => {
        const d = data()
        if (busy()) return "Refreshing balances…"
        if (!d.fetched_at) return "No balance cached yet"
        return `Balances ${ago(now() - d.fetched_at)}${d.stale ? " · stale" : ""}`
      })}
      actions={[
        <IconButton
          icon={hidden((h) => (h ? "visibility_off" : "visibility"))}
          tooltip="Hide amounts"
          class={hidden((h) => (h ? "on" : ""))}
          onClicked={() => {
            setHidden(!hidden.peek())
            setData({ ...data.peek() })
          }}
        />,
        <IconButton
          icon="refresh"
          tooltip="Fetch balances and prices"
          class={busy((b) => (b ? "spinning" : ""))}
          sensitive={busy((b) => !b)}
          onClicked={refresh}
        />,
      ]}
      onOpen={load}
    >
      <box class="btc-hero" orientation={Gtk.Orientation.VERTICAL} spacing={2}>
        <label class="caption" xalign={0} label={data((d) => `Total in ${primary(d)[1]}`)} />
        <label class="btc-amount" xalign={0} label={data((d) => mask(primary(d)[0]))} />
        <box spacing={6} class="btc-others">
          {(["btc", "usd", "brl"] as Unit[]).map((u) => (
            <label
              class="caption"
              visible={data((d) => d.unit !== u)}
              label={data((d) =>
                mask(u === "btc" ? `₿ ${btc(d.sats)}` : u === "usd" ? money(d.sats, d.usd, "$") : money(d.sats, d.brl, "R$")),
              )}
            />
          ))}
        </box>
      </box>

      <Segmented
        options={[
          { value: "btc", label: "BTC" },
          { value: "usd", label: "USD" },
          { value: "brl", label: "BRL" },
        ]}
        selected={data((d) => d.unit)}
        onSelect={setUnit}
      />

      <SectionLabel label="WALLETS" />
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
        <For each={data((d) => d.accounts)} id={(a: Account) => a.label}>
          {(a: Account) => (
            <box class="row" spacing={12}>
              <Icon name={a.label === "multisig" ? "key" : "account_balance_wallet"} />
              <box orientation={Gtk.Orientation.VERTICAL} hexpand spacing={6}>
                <box>
                  <label class="row-title" xalign={0} hexpand label={a.label} />
                  <label
                    class="row-title mono"
                    label={data((d) => mask(a.sats == null ? a.note ?? "—" : `${btc(a.sats)} BTC`))}
                  />
                </box>
                <Meter
                  class="thin"
                  value={data((d) => (a.sats != null && d.sats ? a.sats / d.sats : 0))}
                />
              </box>
            </box>
          )}
        </For>
      </box>

      <box class="price-row" spacing={8} homogeneous>
        <box class="tile tight" orientation={Gtk.Orientation.VERTICAL}>
          <label class="caption" xalign={0} label="1 BTC in USD" />
          <label class="caption strong" xalign={0} label={data((d) => (d.usd ? `$ ${d.usd.toLocaleString("en-US")}` : "—"))} />
        </box>
        <box class="tile tight" orientation={Gtk.Orientation.VERTICAL}>
          <label class="caption" xalign={0} label="1 BTC in BRL" />
          <label class="caption strong" xalign={0} label={data((d) => (d.brl ? `R$ ${d.brl.toLocaleString("en-US")}` : "—"))} />
        </box>
      </box>
      <box visible={data((d) => !!d.error)} class="error-note" spacing={8}>
        <Icon name="error" />
        <label class="caption" wrap xalign={0} hexpand label={data((d) => d.error ?? "")} />
      </box>
    </Popup>
  )
}
