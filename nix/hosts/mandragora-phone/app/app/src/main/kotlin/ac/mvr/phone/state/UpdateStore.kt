package ac.mvr.phone.state

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import ac.mvr.phone.BuildConfig
import ac.mvr.phone.net.AppBuild
import androidx.core.content.FileProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File
import java.security.MessageDigest

class UpdateStore(private val store: Store, private val app: Application) {
    private val availableFlow = MutableStateFlow<AppBuild?>(null)
    val available: StateFlow<AppBuild?> = availableFlow

    private val progressFlow = MutableStateFlow<Float?>(null)
    val progress: StateFlow<Float?> = progressFlow

    suspend fun refresh() {
        val build = store.bridge.app()
        availableFlow.value = build.takeIf { it.error == null && it.versionCode > BuildConfig.VERSION_CODE }
    }

    fun install() {
        val build = availableFlow.value ?: return
        if (progressFlow.value != null) return
        if (!app.packageManager.canRequestPackageInstalls()) {
            app.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            store.report(IllegalStateException("allow installs from mandragora, then tap again"))
            return
        }
        progressFlow.value = 0f
        store.act {
            try {
                val dir = File(app.cacheDir, "updates").apply { mkdirs() }
                val file = File(dir, "mandragora-phone.apk")
                store.bridge.downloadApk(file) { done, total -> progressFlow.value = if (total > 0) done.toFloat() / total else 0f }
                if (sha256(file) != build.sha256) {
                    file.delete()
                    throw IllegalStateException("the download did not match the desktop's build")
                }
                val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", file)
                app.startActivity(
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } finally {
                progressFlow.value = null
            }
        }
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
}
