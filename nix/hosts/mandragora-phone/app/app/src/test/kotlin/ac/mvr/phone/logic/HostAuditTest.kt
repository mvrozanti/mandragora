package ac.mvr.phone.logic

import ac.mvr.phone.net.ExpectedApp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HostAuditTest {
    private val apps = listOf(
        ExpectedApp(TAILSCALE_PACKAGE, "Tailscale", unrestricted = true),
        ExpectedApp("md.obsidian", "Obsidian"),
    )

    private val healthy = PhoneFacts(
        self = "ac.mvr.phone",
        installed = setOf(TAILSCALE_PACKAGE, "md.obsidian"),
        unrestricted = setOf(TAILSCALE_PACKAGE, "ac.mvr.phone"),
        listening = true,
        allFiles = true,
        notifications = true,
        installs = true,
        vpnUp = true,
        alwaysOnReadable = true,
        alwaysOnVpn = TAILSCALE_PACKAGE,
    )

    @Test
    fun aHealthyPhonePassesEveryCheckAndSaysNothing() {
        val checks = hostChecks(apps, healthy)
        assertEquals(
            listOf("app:$TAILSCALE_PACKAGE", "battery:$TAILSCALE_PACKAGE", "app:md.obsidian", "battery:self", "notifications", "all-files", "installs", "vpn", "always-on"),
            checks.map { it.id },
        )
        assertEquals(emptyList<String>(), failing(checks).map { it.id })
        assertEquals(setOf(""), checks.map { it.detail }.toSet())
        assertNull(auditLine(checks))
    }

    @Test
    fun aBatteryOptimisedTailscaleIsTheOneLineShown() {
        val checks = hostChecks(apps, healthy.copy(unrestricted = setOf("ac.mvr.phone")))
        val bad = failing(checks).single()
        assertEquals("battery:$TAILSCALE_PACKAGE", bad.fix)
        assertEquals("Tailscale is battery optimised; Android stops it while the phone sleeps", auditLine(checks))
    }

    @Test
    fun aMissingAppIsNotAlsoCheckedForBattery() {
        val checks = hostChecks(apps, healthy.copy(installed = setOf("md.obsidian")))
        assertEquals(listOf("app:$TAILSCALE_PACKAGE"), failing(checks).map { it.id })
        assertEquals(null, checks.firstOrNull { it.id == "battery:$TAILSCALE_PACKAGE" })
    }

    @Test
    fun theListenerChecksAppearOnlyWhileListening() {
        val quiet = hostChecks(apps, healthy.copy(listening = false, unrestricted = setOf(TAILSCALE_PACKAGE), notifications = false))
        assertEquals(emptyList<String>(), failing(quiet).map { it.id })
        val loud = hostChecks(apps, healthy.copy(unrestricted = setOf(TAILSCALE_PACKAGE), notifications = false, allFiles = false, installs = false, vpnUp = false))
        assertEquals(listOf("battery:self", "notifications", "all-files", "installs", "vpn"), failing(loud).map { it.id })
        assertEquals("5 things this phone needs are off", auditLine(loud))
    }

    @Test
    fun anUnreadableAlwaysOnSettingIsUnknownNotFailing() {
        val unknown = hostChecks(apps, healthy.copy(alwaysOnReadable = false, alwaysOnVpn = null)).last()
        assertEquals(null, unknown.ok)
        assertEquals("vpn-settings", unknown.fix)
        val none = hostChecks(apps, healthy.copy(alwaysOnVpn = null)).last()
        assertEquals("no always-on VPN; Android may drop the tailnet", none.detail)
        val other = hostChecks(apps, healthy.copy(alwaysOnVpn = "com.other.vpn")).last()
        assertEquals("the always-on VPN is com.other.vpn, not Tailscale", other.detail)
    }
}
