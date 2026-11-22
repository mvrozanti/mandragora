package ac.mvr.phone.logic

import ac.mvr.phone.net.ExpectedApp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HostAuditTest {
    private val apps = listOf(
        ExpectedApp(TAILSCALE_PACKAGE, "Tailscale", unrestricted = true),
        ExpectedApp("org.example.listed", "Listed"),
    )

    private val healthy = PhoneFacts(
        self = "ac.mvr.phone",
        installed = setOf(TAILSCALE_PACKAGE),
        unrestricted = setOf(TAILSCALE_PACKAGE, "ac.mvr.phone"),
        listening = true,
        allFiles = true,
        notifications = true,
        installs = true,
    )

    @Test
    fun aHealthyPhonePassesEveryCheckAndSaysNothing() {
        val checks = hostChecks(apps, healthy)
        assertEquals(
            listOf("battery:$TAILSCALE_PACKAGE", "battery:self", "notifications", "all-files", "installs"),
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
    fun aMissingTailscaleSaysSoAndOffersNoBatteryFix() {
        val checks = hostChecks(apps, healthy.copy(installed = emptySet(), unrestricted = setOf("ac.mvr.phone")))
        val bad = failing(checks).single()
        assertEquals("Tailscale is not installed", bad.detail)
        assertNull(bad.fix)
    }

    @Test
    fun theListenerChecksAppearOnlyWhileListening() {
        val quiet = hostChecks(apps, healthy.copy(listening = false, unrestricted = setOf(TAILSCALE_PACKAGE), notifications = false))
        assertEquals(emptyList<String>(), failing(quiet).map { it.id })
        val loud = hostChecks(apps, healthy.copy(unrestricted = setOf(TAILSCALE_PACKAGE), notifications = false, allFiles = false, installs = false))
        assertEquals(listOf("battery:self", "notifications", "all-files", "installs"), failing(loud).map { it.id })
        assertEquals("4 things this phone needs are off", auditLine(loud))
    }
}
