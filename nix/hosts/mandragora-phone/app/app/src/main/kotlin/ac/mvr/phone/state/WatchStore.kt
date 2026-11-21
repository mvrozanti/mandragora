package ac.mvr.phone.state

import ac.mvr.phone.net.WatchClient
import ac.mvr.phone.net.WatchHealth
import ac.mvr.phone.net.WatchTrigger
import ac.mvr.phone.net.Watcher
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.IOException
import java.time.Instant

class WatchStore(private val store: Store) {
    private val client = WatchClient { store.bridgeUrl + "/api/watch" }

    private val watchersFlow = MutableStateFlow<List<Watcher>?>(null)
    val watchers: StateFlow<List<Watcher>?> = watchersFlow

    private val newestFlow = MutableStateFlow<List<WatchTrigger>>(emptyList())
    val newest: StateFlow<List<WatchTrigger>> = newestFlow

    private val healthFlow = MutableStateFlow<WatchHealth?>(null)
    val health: StateFlow<WatchHealth?> = healthFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    private val expandedFlow = MutableStateFlow<Long?>(null)
    val expanded: StateFlow<Long?> = expandedFlow

    private val triggersFlow = MutableStateFlow<Map<Long, List<WatchTrigger>>>(emptyMap())
    val triggers: StateFlow<Map<Long, List<WatchTrigger>>> = triggersFlow

    private val armedFlow = MutableStateFlow<Long?>(null)
    val armed: StateFlow<Long?> = armedFlow

    private val workingFlow = MutableStateFlow<Set<Long>>(emptySet())
    val working: StateFlow<Set<Long>> = workingFlow

    private val composingFlow = MutableStateFlow(false)
    val composing: StateFlow<Boolean> = composingFlow

    private val saidFlow = MutableStateFlow<String?>(null)
    val said: StateFlow<String?> = saidFlow

    private var armJob: Job? = null

    suspend fun refresh() {
        runCatching {
            watchersFlow.value = client.watchers()
            newestFlow.value = client.open(5)
        }.onFailure { freshFlow.value = false }.getOrThrow()
        freshFlow.value = true
        runCatching { healthFlow.value = client.health() }
        expandedFlow.value?.let { loadTriggers(it) }
    }

    fun openTriggerCount(list: List<Watcher>): Int = list.filter { it.push && it.enabled }.sumOf { it.openTriggerCount }

    fun expand(id: Long) {
        if (expandedFlow.value == id) {
            expandedFlow.value = null
            return
        }
        expandedFlow.value = id
        store.act { loadTriggers(id) }
    }

    private suspend fun loadTriggers(id: Long) {
        triggersFlow.value = triggersFlow.value + (id to client.triggers(id))
    }

    fun ack(eventId: Long): Job = store.act {
        readable { client.ack(eventId) }
        markAcked(eventId)
        refresh()
    }

    fun ackAll(watcher: Long): Job = busy(watcher) {
        readable { client.ackAll(watcher) }
        refresh()
    }

    fun toggle(watcher: Long): Job = busy(watcher) {
        readable { client.toggle(watcher) }
        refresh()
    }

    fun poll(watcher: Long): Job = busy(watcher) {
        val polled = readable { client.poll(watcher) }
        saidFlow.value = if (polled.inserted > 0) "${polled.inserted} new of ${polled.fetched} fetched" else "nothing new · ${polled.fetched} fetched"
        refresh()
    }

    fun tapDelete(watcher: Watcher) {
        if (armedFlow.value == watcher.id) {
            armJob?.cancel()
            armedFlow.value = null
            drop(watcher)
            return
        }
        armedFlow.value = watcher.id
        armJob?.cancel()
        armJob = store.scope.launch {
            delay(4_000)
            if (armedFlow.value == watcher.id) armedFlow.value = null
        }
    }

    fun disarm() {
        armJob?.cancel()
        armedFlow.value = null
    }

    fun places(watcher: Watcher): Int {
        val watch = watcher.watchId ?: return 1
        return watchersFlow.value?.count { it.watchId == watch } ?: 1
    }

    private fun drop(watcher: Watcher) = busy(watcher.id) {
        val watch = watcher.watchId
        val dropped = readable { if (watch != null) client.dropWatch(watch) else client.dropWatcher(watcher.id) }
        if (expandedFlow.value == watcher.id) expandedFlow.value = null
        val places = "${dropped.places} place${if (dropped.places == 1) "" else "s"}"
        saidFlow.value = if (watch != null) "stopped watching ${dropped.condition ?: watcher.title} · $places" else "removed ${watcher.title}"
        refresh()
    }

    fun compose(text: String): Job {
        val sentence = text.trim()
        return store.act {
            if (sentence.isEmpty() || composingFlow.value) return@act
            composingFlow.value = true
            try {
                val created = readable { client.compose(sentence) }
                val count = created.created.size
                saidFlow.value = "watching: $sentence · $count place${if (count == 1) "" else "s"}"
                refresh()
            } finally {
                composingFlow.value = false
            }
        }
    }

    fun dismissSaid() {
        saidFlow.value = null
    }

    private fun markAcked(eventId: Long) {
        val stamp = Instant.now().toString()
        triggersFlow.value = triggersFlow.value.mapValues { (_, list) -> list.map { if (it.id == eventId) it.copy(ackedAt = stamp) else it } }
        newestFlow.value = newestFlow.value.filterNot { it.id == eventId }
    }

    private fun busy(id: Long, block: suspend () -> Unit): Job = store.act {
        workingFlow.value = workingFlow.value + id
        try {
            block()
        } finally {
            workingFlow.value = workingFlow.value - id
        }
    }

    private suspend fun <T> readable(call: suspend () -> T): T = try {
        call()
    } catch (err: IOException) {
        val text = err.message ?: ""
        val reason = Regex("\"(?:detail|error)\":\\s*\"([^\"]+)\"").find(text)?.groupValues?.get(1)
        if (reason != null) throw IllegalStateException(reason, err) else throw err
    }
}
