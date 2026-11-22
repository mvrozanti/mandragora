package ac.mvr.phone.state

import ac.mvr.phone.net.PluginClient
import ac.mvr.phone.net.PluginManifest
import ac.mvr.phone.net.PluginPanel
import ac.mvr.phone.net.PluginState
import ac.mvr.phone.net.PluginTurn
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class PluginStore(private val store: Store) {
    private val client = PluginClient { store.desktopUrl({ it.plugin }, 6691) }

    private val stateFlow = MutableStateFlow(PluginState())
    val state: StateFlow<PluginState> = stateFlow

    private val turnsFlow = MutableStateFlow<List<PluginTurn>>(emptyList())
    val turns: StateFlow<List<PluginTurn>> = turnsFlow

    private val manifestFlow = MutableStateFlow<PluginManifest?>(null)
    val manifest: StateFlow<PluginManifest?> = manifestFlow

    private val panelFlow = MutableStateFlow<PluginPanel?>(null)
    val panel: StateFlow<PluginPanel?> = panelFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    val draft = MutableStateFlow("")

    private var last = 0L
    private var version: Long? = null

    suspend fun refresh() {
        pull(0)
        loadManifest()
    }

    suspend fun follow() {
        while (currentCoroutineContext().isActive) {
            if (runCatching { pull(45) }.isFailure) delay(3_000)
        }
    }

    suspend fun loadManifest() {
        manifestFlow.value = readable { client.manifest() }
    }

    suspend fun loadPanel() {
        panelFlow.value = readable { client.panel() }
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

    fun act(action: String, arg: Long? = null) = store.act {
        readable { client.act(action, arg) }
        loadManifest()
    }

    fun toggle(id: String, on: Boolean) = store.act {
        readable { client.toggle(id, on) }
        loadPanel()
    }

    private companion object {
        const val KEEP = 300
    }
}
