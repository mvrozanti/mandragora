import app from "ags/gtk4/app"
import style from "./style/main.css"
import popupStyle from "./style/popups.css"
import { applyTheme } from "./lib/theme"
import { close, closeCurrent, names, open, toggle } from "./lib/popups"
import { initNotifications, request as notificationRequest } from "./lib/notifications"
import Toasts from "./widget/Toasts"
import MoneyPopup from "./popup/Money"
import CalendarPopup from "./popup/Calendar"
import CapturePopup from "./popup/Capture"
import ClipboardPopup from "./popup/Clipboard"
import GpuPopup from "./popup/Gpu"
import MonitorPopup from "./popup/Monitor"
import NotificationsPopup from "./popup/Notifications"
import NetworkPopup from "./popup/Network"
import PowerPopup from "./popup/Power"
import RssPopup from "./popup/Rss"
import SecurityPopup from "./popup/Security"
import WeatherPopup from "./popup/Weather"

const popups = [
  GpuPopup,
  NetworkPopup,
  WeatherPopup,
  MoneyPopup,
  MonitorPopup,
  SecurityPopup,
  RssPopup,
  ClipboardPopup,
  PowerPopup,
  CapturePopup,
  CalendarPopup,
  NotificationsPopup,
]

app.start({
  instanceName: "mandragora-shell",
  main() {
    applyTheme(style + popupStyle)
    initNotifications()
    for (const make of popups) make()
    Toasts()
  },
  requestHandler(argv, respond) {
    const verbs = ["list", "open", "close", "toggle", "notif"]
    const args = verbs.includes(argv[0]) ? argv : argv.slice(1)
    const [verb, name, x] = args
    const at = x === undefined ? undefined : Number(x)
    if (verb === "list") return respond(names().join("\n"))
    if (verb === "notif") return respond(notificationRequest(args.slice(1)))
    if (verb === "close") {
      if (name) close(name)
      else closeCurrent()
      return respond("ok")
    }
    if (!name || !names().includes(name)) return respond(`unknown popup: ${name ?? ""}`)
    if (verb === "open") open(name, at)
    else if (verb === "toggle") toggle(name, at)
    else return respond(`unknown verb: ${verb}`)
    respond("ok")
  },
})
