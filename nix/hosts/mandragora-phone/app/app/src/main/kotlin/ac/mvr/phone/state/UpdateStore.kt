package ac.mvr.phone.state

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import ac.mvr.phone.BuildConfig
import ac.mvr.phone.R
import ac.mvr.phone.net.AppBuild
import androidx.core.app.NotificationCompat
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
                handOver(build)
                return@act
            }
            progressFlow.value = 0f
            val partial = File(dir, "mandragora-phone.apk.part")
            val verified = try {
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
                verified
            } finally {
                partial.delete()
                progressFlow.value = null
            }
            availableFlow.value = verified
            handOver(verified)
        }
    }

    private suspend fun republished(sum: String): AppBuild? =
        try {
            latest()?.takeIf { it.sha256 == sum }
        } catch (err: IOException) {
            null
        }

    private suspend fun handOver(build: AppBuild) = withContext(Dispatchers.IO) {
        progressFlow.value = 1f
        val installer = app.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(app.packageName)
            setSize(build.size)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        try {
            commit(installer, installer.createSession(params))
        } catch (err: IOException) {
            progressFlow.value = null
            throw err
        }
    }

    private fun commit(installer: PackageInstaller, id: Int) {
        installer.openSession(id).use { session ->
            session.openWrite("base.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val status = Intent(app, InstallReceiver::class.java).setAction(ACTION_STATUS)
            val flags = PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            session.commit(PendingIntent.getBroadcast(app, id, status, flags).intentSender)
        }
    }

    fun settle(status: Int, prompt: Intent?, message: String?) {
        if (status == PackageInstaller.STATUS_SUCCESS) return
        progressFlow.value = null
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> prompt?.let(::ask)
            PackageInstaller.STATUS_FAILURE_ABORTED -> Unit
            else -> store.report(IllegalStateException("the update did not install: ${message ?: "status $status"}"))
        }
    }

    private fun ask(prompt: Intent) {
        val intent = prompt.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (store.foreground.value) {
            app.startActivity(intent)
            return
        }
        val manager = app.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "app updates", NotificationManager.IMPORTANCE_DEFAULT))
        val tap = PendingIntent.getActivity(app, 7, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(app, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_mono)
            .setContentTitle("mandragora update")
            .setContentText("${availableFlow.value?.versionName.orEmpty()} · tap to install")
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
        const val ACTION_STATUS = "ac.mvr.phone.INSTALL_STATUS"
        private const val CHANNEL = "updates"
        private const val NOTIFICATION_ID = 7107
    }
}
