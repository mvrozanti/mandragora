package ac.mvr.phone.logic

import ac.mvr.phone.net.ExpectedApp
import ac.mvr.phone.net.HostCheck

const val TAILSCALE_PACKAGE = "com.tailscale.ipn"

data class PhoneFacts(
    val self: String,
    val installed: Set<String>,
    val unrestricted: Set<String>,
    val listening: Boolean,
    val allFiles: Boolean,
    val notifications: Boolean,
    val installs: Boolean,
    val vpnUp: Boolean,
    val alwaysOnReadable: Boolean,
    val alwaysOnVpn: String?,
)

private fun check(id: String, label: String, ok: Boolean?, problem: String, fix: String?): HostCheck =
    HostCheck(id, label, ok, if (ok == false) problem else "", fix)

private fun appChecks(app: ExpectedApp, facts: PhoneFacts): List<HostCheck> {
    val pkg = app.`package`
    val present = pkg in facts.installed
    val installed = check("app:$pkg", "${app.name} is installed", present, "${app.name} is not installed", null)
    if (!app.unrestricted || !present) return listOf(installed)
    val battery = check(
        "battery:$pkg",
        "${app.name} runs unrestricted",
        pkg in facts.unrestricted,
        "${app.name} is battery optimised; Android stops it while the phone sleeps",
        "battery:$pkg",
    )
    return listOf(installed, battery)
}

private fun alwaysOnCheck(facts: PhoneFacts): HostCheck {
    val label = "Tailscale is the always-on VPN"
    if (!facts.alwaysOnReadable) return HostCheck("always-on", label, null, "Android does not let apps read this; VPN settings show it", "vpn-settings")
    val current = facts.alwaysOnVpn.orEmpty()
    val problem = if (current.isEmpty()) "no always-on VPN; Android may drop the tailnet" else "the always-on VPN is $current, not Tailscale"
    return check("always-on", label, current == TAILSCALE_PACKAGE, problem, "vpn-settings")
}

fun hostChecks(expected: List<ExpectedApp>, facts: PhoneFacts): List<HostCheck> = buildList {
    expected.forEach { addAll(appChecks(it, facts)) }
    if (facts.listening) {
        val listener = facts.self in facts.unrestricted
        add(check("battery:self", "the inbox listener runs unrestricted", listener, "this app is battery optimised; desktop alerts stop while the phone sleeps", "battery:self"))
        add(check("notifications", "this app may notify", facts.notifications, "notifications are off for this app; desktop alerts arrive silently", "notifications"))
    }
    add(check("all-files", "the desktop reaches photos and videos", facts.allFiles, "all files access is off; the photo drain has stopped", "all-files"))
    add(check("installs", "updates install in place", facts.installs, "this app may not install updates; the update line cannot finish", "installs"))
    add(check("vpn", "the tailnet is up", facts.vpnUp, "no VPN is up; nothing reaches the desktop", "tailscale"))
    add(alwaysOnCheck(facts))
}

fun failing(checks: List<HostCheck>): List<HostCheck> = checks.filter { it.ok == false }

fun auditLine(checks: List<HostCheck>): String? {
    val bad = failing(checks)
    return when (bad.size) {
        0 -> null
        1 -> bad.first().detail
        else -> "${bad.size} things this phone needs are off"
    }
}
