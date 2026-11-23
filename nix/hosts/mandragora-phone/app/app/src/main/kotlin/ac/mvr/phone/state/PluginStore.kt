package ac.mvr.phone.state

import ac.mvr.phone.net.PluginClient
import ac.mvr.phone.net.PluginManifest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class PluginStore(private val store: Store) {
    private val client = PluginClient { store.desktopUrl({ it.plugin }, 6691) }

    private val manifestFlow = MutableStateFlow<PluginManifest?>(null)
    val manifest: StateFlow<PluginManifest?> = manifestFlow

    suspend fun refresh() = loadManifest()

    suspend fun loadManifest(): PluginManifest = readable { client.manifest() }.also { manifestFlow.value = it }

    suspend fun enter(): Boolean {
        val chat = loadManifest().chat ?: return false
        store.code.openIn(chat.backend, chat.directory)
        return true
    }
}
