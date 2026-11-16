package ac.mvr.phone.state

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import ac.mvr.phone.BuildConfig
import ac.mvr.phone.R
import ac.mvr.phone.net.AppBuild
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.security.MessageDigest

class UpdateStore(private val store: Store, private val app: Application) {
    private val availableFlow = MutableStateFlow<AppBuild?>(null)
    val available: StateFlow<AppBuild?> = availableFlow

    private val progressFlow = MutableStateFlow<Float?>(null)
    val progress: StateFlow<Float?> = progressFlow

    private val readyFlow = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = readyFlow

    private val dir: File get() = File(app.cacheDir, "updates").apply { mkdirs() }
    private val apk: File get() = File(dir, "mandragora-phone.apk")
    private val stamp: File get() = File(dir, "mandragora-phone.apk.sha256")

    suspend fun refresh() {
        val build = store.bridge.app().takeIf { it.error == null && it.versionCode > BuildConfig.VERSION_CODE }
        availableFlow.value = build
        readyFlow.value = build != null && downloaded(build)
        if (build == null) withContext(Dispatchers.IO) { apk.delete(); stamp.delete() }
    }

    private fun downloaded(build: AppBuild): Boolean =
        apk.isFile && apk.length() == build.size && runCatching { stamp.readText().trim() }.getOrNull() == build.sha256

    fun install() {
        val build = availableFlow.value ?: return
        if (progressFlow.value != null) return
        if (!app.packageManager.canRequestPackageInstalls()) {
            app.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            store.report(IllegalStateException("allow installs from mandragora, then tap again"))
            return
        }
        if (downloaded(build)) {
            readyFlow.value = true
            app.startActivity(installer())
            return
        }
        progressFlow.value = 0f
        store.act {
            try {
                val partial = File(dir, "mandragora-phone.apk.part")
                stamp.delete()
                store.bridge.downloadApk(partial) { done, total -> progressFlow.value = if (total > 0) done.toFloat() / total else 0f }
                val sum = withContext(Dispatchers.IO) { sha256(partial) }
                if (sum != build.sha256) {
                    partial.delete()
                    throw IllegalStateException("the download did not match the desktop's build")
                }
                withContext(Dispatchers.IO) {
                    apk.delete()
                    partial.renameTo(apk)
                    stamp.writeText(build.sha256)
                }
                readyFlow.value = true
                if (store.foreground.value) app.startActivity(installer()) else notifyReady(build)
            } finally {
                progressFlow.value = null
            }
        }
    }

    private fun installer(): Intent {
        val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", apk)
        return Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun notifyReady(build: AppBuild) {
        val manager = app.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "app updates", NotificationManager.IMPORTANCE_DEFAULT))
        val tap = PendingIntent.getActivity(app, 7, installer(), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(app, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_mono)
            .setContentTitle("mandragora update downloaded")
            .setContentText("${build.versionName} · tap to install")
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        runCatching { manager.notify(NOTIFICATION_ID, notification) }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val CHANNEL = "updates"
        private const val NOTIFICATION_ID = 7107
    }
}
