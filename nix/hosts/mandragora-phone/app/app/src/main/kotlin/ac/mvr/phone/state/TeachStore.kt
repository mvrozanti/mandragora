package ac.mvr.phone.state

import ac.mvr.phone.net.TeachClient
import ac.mvr.phone.net.TeachState
import ac.mvr.phone.net.TeachStats
import ac.mvr.phone.net.TeachTurn
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class TeachStore(private val store: Store) {
    private val client = TeachClient { store.desktopUrl({ it.teach }, 6691) }

    private val stateFlow = MutableStateFlow(TeachState())
    val state: StateFlow<TeachState> = stateFlow

    private val turnsFlow = MutableStateFlow<List<TeachTurn>>(emptyList())
    val turns: StateFlow<List<TeachTurn>> = turnsFlow

    private val statsFlow = MutableStateFlow<TeachStats?>(null)
    val stats: StateFlow<TeachStats?> = statsFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    val draft = MutableStateFlow("")

    private var last = 0L
    private var version: Long? = null

    suspend fun refresh() = pull(0)

    suspend fun follow() {
        while (currentCoroutineContext().isActive) {
            if (runCatching { pull(45) }.isFailure) delay(3_000)
        }
    }

    suspend fun loadStats() {
        statsFlow.value = readable { client.stats() }
    }

    private suspend fun pull(wait: Int) {
        val got = runCatching { client.state(last, version, wait) }.onFailure { freshFlow.value = false }.getOrThrow()
        freshFlow.value = true
        val reset = got.last < last
        val known = if (reset) emptyList() else turnsFlow.value
        val ids = known.mapTo(HashSet()) { it.id }
        val merged = (known + got.turns.filter { it.id !in ids }).sortedBy { it.id }.takeLast(KEEP)
        turnsFlow.value = merged
        last = merged.lastOrNull()?.id ?: 0L
        version = got.version
        stateFlow.value = got.copy(turns = emptyList())
    }

    fun submit() {
        val text = draft.value.trim()
        if (text.isEmpty()) return
        draft.value = ""
        store.scope.launch {
            runCatching { readable { client.say(text) } }.onFailure { err ->
                if (draft.value.isEmpty()) draft.value = text
                store.report(err)
            }
        }
    }

    fun act(action: String, concept: Int? = null) = store.act { readable { client.act(action, concept) } }

    fun nudges(enabled: Boolean) = store.act {
        readable { client.nudges(enabled) }
        loadStats()
    }

    fun retention(topic: String, value: Double) = store.act {
        readable { client.retention(topic, value) }
        loadStats()
    }

    fun retry() = store.act { readable { client.retry() } }

    private companion object {
        const val KEEP = 300
    }
}
