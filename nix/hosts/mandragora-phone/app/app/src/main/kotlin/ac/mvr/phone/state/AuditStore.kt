package ac.mvr.phone.state

import android.Manifest
import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import ac.mvr.phone.BuildConfig
import ac.mvr.phone.logic.PhoneFacts
import ac.mvr.phone.logic.hostChecks
import ac.mvr.phone.net.HostCheck
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

private const val REPORT_EVERY_MS = 30 * 60 * 1000L

class AuditStore(private val store: Store, private val app: Application) {
    private val checksFlow = MutableStateFlow<List<HostCheck>>(emptyList())
    val checks: StateFlow<List<HostCheck>> = checksFlow

    private var reported: List<HostCheck>? = null
    private var reportedAtMs = 0L

    suspend fun refresh() {
        val config = store.config.value
        val next = hostChecks(config?.phone?.apps.orEmpty(), facts())
        checksFlow.value = next
        if (config == null) return
        val due = SystemClock.elapsedRealtime() - reportedAtMs > REPORT_EVERY_MS
        if (next == reported && !due) return
        store.bridge.reportAudit(BuildConfig.VERSION_CODE, next)
        reported = next
        reportedAtMs = SystemClock.elapsedRealtime()
    }

    private fun facts(): PhoneFacts {
        val pm = app.packageManager
        val power = app.getSystemService(PowerManager::class.java)
        val packages = store.config.value?.phone?.apps.orEmpty().map { it.`package` } + app.packageName
        return PhoneFacts(
            self = app.packageName,
            installed = packages.filter { installed(pm, it) }.toSet(),
            unrestricted = packages.filter { power?.isIgnoringBatteryOptimizations(it) == true }.toSet(),
            listening = store.prefs.inboxListen.value,
            allFiles = store.photos.refreshAllowed(),
            notifications = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED,
            installs = pm.canRequestPackageInstalls(),
        )
    }

    private fun installed(pm: PackageManager, pkg: String): Boolean = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION") pm.getPackageInfo(pkg, 0)
        }
    }.isSuccess

    fun fix(context: Context, check: HostCheck) {
        check.fix?.let(::fixIntent)?.let { runCatching { context.startActivity(it) } }
    }

    @SuppressLint("BatteryLife")
    private fun fixIntent(fix: String): Intent? {
        val self = app.packageName
        return when {
            fix == "all-files" -> store.photos.accessSettings()
            fix == "battery:self" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$self"))
            fix.startsWith("battery:") -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${fix.removePrefix("battery:")}"))
            fix == "notifications" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, self)
            fix == "installs" -> Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$self"))
            else -> null
        }
    }
}
