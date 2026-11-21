package ac.mvr.phone.state

import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import ac.mvr.phone.logic.PhoneMediaItem
import ac.mvr.phone.logic.indexDue
import ac.mvr.phone.logic.indexSignature
import ac.mvr.phone.logic.removeVerdict
import ac.mvr.phone.media.PhoneMedia
import ac.mvr.phone.net.PhoneMediaApi
import ac.mvr.phone.net.PhoneMediaJobs
import ac.mvr.phone.net.RemoveJob
import ac.mvr.phone.net.Unreachable
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.InterruptedIOException
import java.net.SocketException
import java.net.UnknownHostException

private const val PREFS = "phone-media"
private const val KEY_SIGNATURE = "signature"
private const val KEY_POSTED_AT = "postedAt"
private const val KEY_CONTACT_AT = "contactAt"

class PhoneMediaStore(private val app: Application, private val api: PhoneMediaApi) {
    private val media = PhoneMedia(app)
    private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val mutex = Mutex()

    private val allowedFlow = MutableStateFlow(media.allowed())
    val allowed: StateFlow<Boolean> = allowedFlow

    private val contactFlow = MutableStateFlow(prefs.getLong(KEY_CONTACT_AT, 0L))
    val lastContactMs: StateFlow<Long> = contactFlow

    private val movedFlow = MutableStateFlow(0)
    val moved: StateFlow<Int> = movedFlow

    fun refreshAllowed(): Boolean = media.allowed().also { allowedFlow.value = it }

    fun accessSettings(): Intent {
        val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
        } else {
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS
        }
        return Intent(action, Uri.parse("package:${app.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    suspend fun sync(deadlineMs: Long = Long.MAX_VALUE): Boolean = mutex.withLock {
        withContext(Dispatchers.IO) {
            if (!refreshAllowed()) return@withContext false
            val items = media.list()
            val byId = items.associateBy { it.id.toString() }
            val signature = indexSignature(items)
            val now = System.currentTimeMillis()
            val due = indexDue(signature, prefs.getString(KEY_SIGNATURE, null), prefs.getLong(KEY_POSTED_AT, 0L), now)
            val asked = if (due) null else api.jobs()
            val jobs = if (asked == null || asked.reindex) {
                api.postIndex(items).also { prefs.edit().putString(KEY_SIGNATURE, signature).putLong(KEY_POSTED_AT, now).apply() }
            } else {
                asked
            }
            contactFlow.value = now
            prefs.edit().putLong(KEY_CONTACT_AT, now).apply()
            if (!jobs.empty) work(jobs, byId, deadlineMs)
            true
        }
    }

    private suspend fun work(jobs: PhoneMediaJobs, byId: Map<String, PhoneMediaItem>, deadlineMs: Long) {
        for (id in jobs.thumbs.takeWhile { System.currentTimeMillis() < deadlineMs }) {
            attempt(id, "thumbs") { api.thumb(id, media.thumbnail(present(byId, id))) }
        }
        for (id in jobs.pull.takeWhile { System.currentTimeMillis() < deadlineMs }) {
            attempt(id, "pull") {
                val item = present(byId, id)
                val digest = media.digest(item)
                api.upload(id, digest.sha256, digest.length) { media.open(item) }
            }
        }
        val removed = jobs.remove.takeWhile { System.currentTimeMillis() < deadlineMs }.count { remove(it, byId[it.id]) }
        if (removed > 0) {
            movedFlow.value += removed
            prefs.edit().remove(KEY_SIGNATURE).apply()
        }
    }

    private fun present(byId: Map<String, PhoneMediaItem>, id: String): PhoneMediaItem = byId[id] ?: error("no longer on the phone")

    private suspend fun remove(job: RemoveJob, item: PhoneMediaItem?): Boolean {
        val actual = item?.let { runCatching { media.digest(it).sha256 }.getOrNull() }
        val verdict = removeVerdict(job.sha256, present = item != null, actual = actual)
        val error = when {
            !verdict.delete -> verdict.error
            item != null && media.delete(item) -> null
            else -> "Android refused to delete it"
        }
        runCatching { api.report(job.id, "remove", error) }
        return error == null
    }

    private suspend fun attempt(id: String, job: String, block: suspend () -> Unit) {
        val failure = runCatching { block() }.exceptionOrNull() ?: return
        if (failure is CancellationException || transient(failure)) throw failure
        runCatching { api.report(id, job, failure.message ?: failure.javaClass.simpleName) }
    }

    private fun transient(err: Throwable): Boolean =
        err is Unreachable || err is SocketException || err is InterruptedIOException || err is UnknownHostException
}
