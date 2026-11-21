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
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.security.MessageDigest

class UpdateStore(private val store: Store, private val app: Application) {
    private val availableFlow = MutableStateFlow<AppBuild?>(null)
    val available: StateFlow<AppBuild?> = availableFlow

    private val progressFlow = MutableStateFlow<Float?>(null)
    val progress: StateFlow<Float?> = progressFlow

    private val dir: File get() = File(app.cacheDir, "updates").apply { mkdirs() }
    private val apk: File get() = File(dir, "mandragora-phone.apk")
    private val stamp: File get() = File(dir, "mandragora-phone.apk.sha256")

    private var job: Job? = null

    private suspend fun latest(): AppBuild? = store.bridge.app().takeIf { it.error == null && it.versionCode > BuildConfig.VERSION_CODE }

    suspend fun refresh() {
        val build = latest()
        availableFlow.value = build
        if (build == null) withContext(Dispatchers.IO) { apk.delete(); stamp.delete() }
    }

    private fun downloaded(build: AppBuild): Boolean =
        apk.isFile && apk.length() == build.size && runCatching { stamp.readText().trim() }.getOrNull() == build.sha256

    fun install() {
        val known = availableFlow.value ?: return
        if (job?.isActive == true) return
        if (!app.packageManager.canRequestPackageInstalls()) {
            app.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            store.report(IllegalStateException("allow installs from mandragora, then tap again"))
            return
        }
        job = store.act {
            val build = try {
                latest()
            } catch (err: IOException) {
                if (downloaded(known)) known else throw err
            }
            availableFlow.value = build
            if (build == null) {
                withContext(Dispatchers.IO) { apk.delete(); stamp.delete() }
                return@act
            }
            if (downloaded(build)) {
                app.startActivity(installer())
                return@act
            }
            progressFlow.value = 0f
            val partial = File(dir, "mandragora-phone.apk.part")
            try {
                stamp.delete()
                store.bridge.downloadApk(partial) { done, total -> progressFlow.value = if (total > 0) done.toFloat() / total else 0f }
                val sum = withContext(Dispatchers.IO) { sha256(partial) }
                val verified = if (sum == build.sha256) build else republished(sum)
                    ?: throw IllegalStateException("the download did not match the desktop's build")
                withContext(Dispatchers.IO) {
                    apk.delete()
                    partial.renameTo(apk)
                    stamp.writeText(verified.sha256)
                }
                availableFlow.value = verified
                if (store.foreground.value) app.startActivity(installer()) else notifyReady(verified)
            } finally {
                partial.delete()
                progressFlow.value = null
            }
        }
    }

    private suspend fun republished(sum: String): AppBuild? =
        try {
            latest()?.takeIf { it.sha256 == sum }
        } catch (err: IOException) {
            null
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
            .setContentTitle("mandragora update")
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
