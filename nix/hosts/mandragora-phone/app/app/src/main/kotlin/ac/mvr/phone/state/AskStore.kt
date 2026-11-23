package ac.mvr.phone.state

import ac.mvr.phone.net.AskClient
import ac.mvr.phone.net.AskEntry
import ac.mvr.phone.net.AskState
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class AskStore(private val store: Store) {
    private val client = AskClient { store.desktopUrl({ it.ask }, 6689) }

    private val stateFlow = MutableStateFlow(AskState())
    val state: StateFlow<AskState> = stateFlow

    private val entriesFlow = MutableStateFlow<List<AskEntry>>(emptyList())
    val entries: StateFlow<List<AskEntry>> = entriesFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    val draft = MutableStateFlow("")

    private var last = 0L

    suspend fun refresh() = pull(0)

    suspend fun follow() {
        while (currentCoroutineContext().isActive) {
            store.foreground.first { it }
            if (runCatching { pull(45) }.isFailure) delay(3_000)
        }
    }

    private suspend fun pull(wait: Int) {
        val seen = last
        val got = runCatching { client.state(seen, wait) }.onFailure { freshFlow.value = false }.getOrThrow()
        freshFlow.value = true
        merge(seen, got)
    }

    private fun merge(seen: Long, got: AskState) {
        val reset = got.last < seen
        val known = if (reset) emptyList() else entriesFlow.value
        val ids = known.mapTo(HashSet()) { it.id }
        val merged = (known + got.entries.filter { it.id !in ids }).sortedBy { it.id }.takeLast(KEEP)
        entriesFlow.value = merged
        last = if (reset) 0L else maxOf(last, merged.lastOrNull()?.id ?: 0L)
        stateFlow.value = got.copy(entries = emptyList())
    }

    fun submit() {
        val text = draft.value.trim()
        if (text.isEmpty()) return
        draft.value = ""
        store.scope.launch {
            runCatching { readable { client.send(text) } }.onFailure { err ->
                if (draft.value.isEmpty()) draft.value = text
                store.report(err)
            }
        }
    }

    fun send(text: String) = store.act { readable { client.send(text) } }

    fun stop() = store.act { readable { client.stop() } }

    fun toggleThink() = store.act { readable { client.think(!stateFlow.value.think) } }

    companion object {
        const val KEEP = 300
    }
}
