package ac.mvr.phone.state

import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import ac.mvr.phone.logic.MirrorFile
import ac.mvr.phone.logic.mirrorPlan
import ac.mvr.phone.logic.ownedAfter
import ac.mvr.phone.media.MusicFolder
import ac.mvr.phone.media.NoRoom
import ac.mvr.phone.net.BridgeClient
import ac.mvr.phone.net.MusicIndex
import ac.mvr.phone.net.Unreachable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.io.File
import java.io.IOException
import java.io.InterruptedIOException
import java.net.SocketException
import java.net.UnknownHostException

private const val PREFS = "music-mirror"
private const val KEY_VERSION = "version"
private const val KEY_WALKED_AT = "walkedAt"
private const val KEY_DONE_AT = "doneAt"
private const val KEY_HAVE = "have"
private const val KEY_TOTAL = "total"
private const val KEY_LEFT = "leftBytes"
private const val KEY_ERROR = "error"
private const val REWALK_MS = 6 * 60 * 60 * 1000L
private const val SAVE_EVERY = 25

data class MirrorStatus(
    val have: Int = 0,
    val total: Int = 0,
    val leftBytes: Long = 0,
    val doneAtMs: Long = 0,
    val error: String? = null,
    val running: Boolean = false,
)

class MusicMirrorStore(private val app: Application, private val bridge: BridgeClient, private val allowed: () -> Boolean) {
    private val folder = MusicFolder(app)
    private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val ownedFile = File(app.filesDir, "music-mirror.tsv")
    private val mutex = Mutex()
    private val statusFlow = MutableStateFlow(saved())
    val status: StateFlow<MirrorStatus> = statusFlow

    suspend fun sync(deadlineMs: Long = Long.MAX_VALUE): Boolean = mutex.withLock {
        withContext(Dispatchers.IO) {
            if (!allowed() || metered()) return@withContext false
            statusFlow.value = statusFlow.value.copy(running = true)
            try {
                pass(deadlineMs)
            } catch (err: IOException) {
                if (!transient(err)) record(statusFlow.value.copy(error = err.message ?: err.javaClass.simpleName))
                false
            } finally {
                statusFlow.value = statusFlow.value.copy(running = false)
            }
        }
    }

    private suspend fun pass(deadlineMs: Long): Boolean {
        val now = System.currentTimeMillis()
        val version = prefs.getString(KEY_VERSION, null)
        val fresh = version != null && now - prefs.getLong(KEY_WALKED_AT, 0L) < REWALK_MS
        val index = bridge.musicIndex(version.takeIf { fresh })
        if (index.unchanged) {
            record(statusFlow.value.copy(doneAtMs = now, error = null))
            return true
        }
        val owned = loadOwned()
        val plan = mirrorPlan(remote(index), folder.list(), owned)
        val dropped = plan.drop.filterTo(HashSet()) { folder.drop(it) }
        val fetched = HashSet<String>()
        var failure: String? = null
        var full = false
        for (file in plan.fetch) {
            yield()
            if (full || System.currentTimeMillis() >= deadlineMs) break
            try {
                folder.fetch(file, bridge.fileUrl(file.path))
                fetched.add(file.path)
                if (fetched.size % SAVE_EVERY == 0) saveOwned(ownedAfter(plan, owned, fetched, dropped))
            } catch (err: NoRoom) {
                failure = err.message
                full = true
            } catch (err: IOException) {
                if (transient(err)) throw err
                failure = err.message
            }
        }
        saveOwned(ownedAfter(plan, owned, fetched, dropped))
        val left = plan.fetch.filter { it.path !in fetched }
        val complete = left.isEmpty() && dropped.size == plan.drop.size
        val total = plan.kept.size + plan.adopt.size + plan.fetch.size
        val edit = prefs.edit().putLong(KEY_WALKED_AT, now)
        if (complete) edit.putString(KEY_VERSION, index.version) else edit.remove(KEY_VERSION)
        edit.apply()
        val doneAt = if (complete) now else statusFlow.value.doneAtMs
        record(MirrorStatus(have = total - left.size, total = total, leftBytes = left.sumOf { it.size }, doneAtMs = doneAt, error = failure))
        return complete
    }

    private fun remote(index: MusicIndex): List<MirrorFile> = index.files.mapNotNull { row ->
        runCatching { MirrorFile(row[0].jsonPrimitive.content, row[1].jsonPrimitive.long, row[2].jsonPrimitive.long) }.getOrNull()
    }

    private fun loadOwned(): Map<String, MirrorFile> {
        if (!ownedFile.isFile) return emptyMap()
        return ownedFile.readLines().mapNotNull { line ->
            val parts = line.split('\t', limit = 3)
            val size = parts.getOrNull(0)?.toLongOrNull()
            val mtime = parts.getOrNull(1)?.toLongOrNull()
            val path = parts.getOrNull(2)
            if (size == null || mtime == null || path.isNullOrEmpty()) null else path to MirrorFile(path, size, mtime)
        }.toMap()
    }

    private fun saveOwned(owned: Map<String, MirrorFile>) {
        val tmp = File(ownedFile.parentFile, "${ownedFile.name}.tmp")
        tmp.writeText(owned.values.sortedBy { it.path }.joinToString("") { "${it.size}\t${it.mtime}\t${it.path}\n" })
        if (!tmp.renameTo(ownedFile)) tmp.delete()
    }

    private fun record(next: MirrorStatus) {
        statusFlow.value = next.copy(running = statusFlow.value.running)
        prefs.edit()
            .putInt(KEY_HAVE, next.have)
            .putInt(KEY_TOTAL, next.total)
            .putLong(KEY_LEFT, next.leftBytes)
            .putLong(KEY_DONE_AT, next.doneAtMs)
            .putString(KEY_ERROR, next.error)
            .apply()
    }

    private fun saved(): MirrorStatus = MirrorStatus(
        have = prefs.getInt(KEY_HAVE, 0),
        total = prefs.getInt(KEY_TOTAL, 0),
        leftBytes = prefs.getLong(KEY_LEFT, 0L),
        doneAtMs = prefs.getLong(KEY_DONE_AT, 0L),
        error = prefs.getString(KEY_ERROR, null),
    )

    private fun metered(): Boolean = app.getSystemService(ConnectivityManager::class.java)?.isActiveNetworkMetered != false

    private fun transient(err: Throwable): Boolean =
        err is Unreachable || err is SocketException || err is InterruptedIOException || err is UnknownHostException
}
