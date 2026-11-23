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
    val forwarding: Boolean,
    val installs: Boolean,
)

private fun check(id: String, label: String, ok: Boolean?, problem: String, fix: String?): HostCheck =
    HostCheck(id, label, ok, if (ok == false) problem else "", fix)

private fun batteryCheck(app: ExpectedApp, facts: PhoneFacts): HostCheck {
    val pkg = app.`package`
    val present = pkg in facts.installed
    val problem = if (present) "${app.name} is battery optimised; Android stops it while the phone sleeps" else "${app.name} is not installed"
    return check("battery:$pkg", "${app.name} runs unrestricted", pkg in facts.unrestricted, problem, if (present) "battery:$pkg" else null)
}

fun hostChecks(expected: List<ExpectedApp>, facts: PhoneFacts): List<HostCheck> = buildList {
    expected.filter { it.unrestricted }.forEach { add(batteryCheck(it, facts)) }
    if (facts.listening) {
        val listener = facts.self in facts.unrestricted
        add(check("battery:self", "the inbox listener runs unrestricted", listener, "this app is battery optimised; desktop alerts stop while the phone sleeps", "battery:self"))
        add(check("notifications", "this app may notify", facts.notifications, "notifications are off for this app; desktop alerts arrive silently", "notifications"))
    }
    add(
        check(
            "forward",
            "the desktop shows this phone's notifications",
            facts.forwarding,
            "notification access is off for this app; this phone's notifications no longer reach the desktop",
            "forward",
        ),
    )
    add(check("all-files", "the app reaches photos, videos and music", facts.allFiles, "all files access is off; the photo drain and the music copy have stopped", "all-files"))
    add(check("installs", "updates install in place", facts.installs, "this app may not install updates; the update line cannot finish", "installs"))
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
