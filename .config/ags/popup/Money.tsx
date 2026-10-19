import { Gtk } from "ags/gtk4"
import { createComputed, createState, For } from "ags"
import Popup from "../widget/Popup"
import { Chip, Icon, IconButton, Meter, Scroll, SectionLabel, Segmented } from "../widget/parts"
import { ago, json, now, quiet } from "../lib/run"

type Unit = "btc" | "usd" | "brl"
type Fx = { btc_usd?: number | null; usd_brl?: number | null }
type Holding = { label: string; asset: string; amount: number | null; usd: number | null; note: string | null }
type Venue = {
  id: string
  label: string
  usd: number
  holdings: Holding[]
  error: string | null
  note: string | null
  missing?: boolean
  stale_since?: number
}
type Data = {
  total_usd: number | null
  fx: Fx
  prices: Record<string, number>
  venues: Venue[]
  error: string | null
  fetched_at?: number
  unit: Unit
  stale?: boolean
}

const UNITS: Unit[] = ["btc", "usd", "brl"]
const UNIT_NAMES: Record<Unit, string> = { btc: "bitcoin", usd: "US dollars", brl: "Brazilian reais" }

const btc = (value: number) => value.toFixed(8).replace(/0+$/, "").replace(/\.$/, "")

const fiat = (value: number, symbol: string) =>
  `${symbol} ${value.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

function convert(usd: number | null | undefined, unit: Unit, fx: Fx): number | null {
  if (usd == null) return null
  if (unit === "usd") return usd
  if (unit === "brl") return fx.usd_brl ? usd * fx.usd_brl : null
  return fx.btc_usd ? usd / fx.btc_usd : null
}

function money(usd: number | null | undefined, unit: Unit, fx: Fx): string {
  const value = convert(usd, unit, fx)
  if (value == null) return "—"
  if (unit === "usd") return fiat(value, "$")
  if (unit === "brl") return fiat(value, "R$")
  return `₿ ${btc(value)}`
}

const qty = (n: number) =>
  n >= 1000
    ? n.toLocaleString("en-US", { maximumFractionDigits: 2 })
    : n >= 1
      ? n.toLocaleString("en-US", { maximumFractionDigits: 4 })
      : String(Number(n.toPrecision(4)))

const holdingIcon = (h: Holding) =>
  h.asset === "dust"
    ? "grain"
    : /earn|lended|staked|vaults/.test(h.label)
      ? "savings"
      : h.asset === "BTC"
        ? "currency_bitcoin"
        : "toll"

const venueState = (v: Venue) => (v.missing ? "unavailable" : v.stale_since ? "stale" : v.holdings.length ? "" : v.note ?? "")

export default function MoneyPopup() {
  const [data, setData] = createState<Data>({
    total_usd: null,
    fx: {},
    prices: {},
    venues: [],
    error: null,
    unit: "btc",
  })
  const [busy, setBusy] = createState(false)
  const [hidden, setHidden] = createState(false)

  const load = () => json<Data>(["money-menu", "json"]).then(setData).catch(console.error)
  let refreshing = false
  const refresh = async () => {
    if (refreshing) return
    refreshing = true
    setBusy(true)
    await quiet(["money-menu", "refresh"])
    await load()
    setBusy(false)
    refreshing = false
  }
  const setUnit = async (unit: Unit) => {
    setData({ ...data.peek(), unit })
    for (let i = 0; i < UNITS.length && (await json<Data>(["money-menu", "json"])).unit !== unit; i++)
      await quiet(["money-menu", "cycle-unit"])
  }
  const mask = (s: string) => (hidden.peek() ? s.replace(/[0-9]/g, "•") : s)

  const holdingRow = (h: Holding) => (
    <box class="row" spacing={12}>
      <Icon name={holdingIcon(h)} />
      <box orientation={Gtk.Orientation.VERTICAL} hexpand spacing={4}>
        <box>
          <label class="row-title" xalign={0} hexpand label={h.asset} />
          <label
            class="row-title mono"
            label={data((d) => mask(h.usd == null ? h.note ?? "—" : money(h.usd, d.unit, d.fx)))}
          />
        </box>
        <box>
          <label class="caption" xalign={0} hexpand ellipsize={3} label={h.asset === "dust" ? h.note ?? "" : h.label} />
          <label
            class="caption mono"
            visible={h.amount != null}
            label={data(() => mask(h.amount == null ? "" : `${qty(h.amount)} ${h.asset}`))}
          />
        </box>
        <Meter
          class="thin"
          value={data((d) => (h.usd != null && d.total_usd ? Math.min(1, h.usd / d.total_usd) : 0))}
        />
      </box>
    </box>
  )

  return (
    <Popup
      name="money"
      width={420}
      icon="account_balance_wallet"
      title="Money"
      subtitle={createComputed(() => {
        const d = data()
        if (busy()) return "Refreshing balances…"
        if (!d.fetched_at) return "No balance cached yet"
        const stale = d.venues.filter((v) => v.stale_since).map((v) => v.label)
        return `Balances ${ago(now() - d.fetched_at)}${d.stale ? " · stale" : ""}${stale.length ? ` · last known ${stale.join(", ")}` : ""}`
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
      onOpen={() => {
        load()
        refresh()
      }}
    >
      <box class="money-hero" orientation={Gtk.Orientation.VERTICAL} spacing={2}>
        <label class="caption" xalign={0} label={data((d) => `Total in ${UNIT_NAMES[d.unit]}`)} />
        <label class="money-amount" xalign={0} label={data((d) => mask(money(d.total_usd, d.unit, d.fx)))} />
        <box spacing={6} class="money-others">
          {UNITS.map((u) => (
            <label
              class="caption"
              visible={data((d) => d.unit !== u)}
              label={data((d) => mask(money(d.total_usd, u, d.fx)))}
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

      <Scroll maxHeight={460}>
        <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
          <For each={data((d) => d.venues)}>
            {(v: Venue) => (
              <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
                <SectionLabel label={v.label.toUpperCase()}>
                  <box visible={venueState(v) !== ""}>
                    <Chip label={venueState(v)} class={v.missing ? "error" : "quiet"} />
                  </box>
                  <label
                    class="caption strong mono"
                    visible={!v.missing && v.holdings.length > 0}
                    label={data((d) => mask(money(v.usd, d.unit, d.fx)))}
                  />
                </SectionLabel>
                {v.holdings.map(holdingRow)}
              </box>
            )}
          </For>
        </box>
      </Scroll>

      <box class="price-row" spacing={8} homogeneous>
        <For each={data((d) => Object.entries(d.prices ?? {}).slice(0, 3))}>
          {([asset, usd]: [string, number]) => (
            <box class="tile tight" orientation={Gtk.Orientation.VERTICAL}>
              <label class="caption" xalign={0} label={data((d) => `1 ${asset} in ${d.unit === "brl" ? "BRL" : d.unit === "btc" && asset !== "BTC" ? "BTC" : "USD"}`)} />
              <label
                class="caption strong"
                xalign={0}
                label={data((d) => money(usd, d.unit === "btc" && asset === "BTC" ? "usd" : d.unit, d.fx))}
              />
            </box>
          )}
        </For>
      </box>
      <box visible={data((d) => !!d.error)} class="error-note" spacing={8}>
        <Icon name="error" />
        <label class="caption" wrap xalign={0} hexpand label={data((d) => d.error ?? "")} />
      </box>
    </Popup>
  )
}
