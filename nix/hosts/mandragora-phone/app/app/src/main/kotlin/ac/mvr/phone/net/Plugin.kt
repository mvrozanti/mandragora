package ac.mvr.phone.net

import kotlinx.serialization.Serializable

@Serializable
data class PluginChat(val backend: String = "claude", val directory: String)

@Serializable
data class PluginManifest(val title: String = "plugin", val subtitle: String = "", val chat: PluginChat? = null)

class PluginClient(private val baseUrl: () -> String) {
    suspend fun manifest(): PluginManifest = json.decodeFromString(Http.get("${baseUrl()}/api/plugin/manifest"))
}
