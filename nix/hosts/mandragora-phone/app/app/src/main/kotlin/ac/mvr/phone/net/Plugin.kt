package ac.mvr.phone.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class PluginTurn(val id: Long, val ts: Long = 0, val role: String, val content: String = "")

@Serializable
data class PluginState(
    val turns: List<PluginTurn> = emptyList(),
    val last: Long = 0,
    val busy: Boolean = false,
    val queued: Int = 0,
    val pending: Int = 0,
    val version: Long = 0,
)

@Serializable
data class PluginAction(val id: String, val label: String = id)

@Serializable
data class PluginManifest(
    val title: String = "plugin",
    val subtitle: String = "",
    val placeholder: String = "say something",
    val empty: String = "nothing here yet",
    val actions: List<PluginAction> = emptyList(),
    val panelLabel: String = "",
)

@Serializable
data class PluginRow(val text: String, val action: String = "", val arg: Long? = null, val label: String = "")

@Serializable
data class PluginToggle(val id: String, val label: String = id, val on: Boolean = false)

@Serializable
data class PluginPanel(
    val markdown: String = "",
    val rows: List<PluginRow> = emptyList(),
    val toggles: List<PluginToggle> = emptyList(),
)

class PluginClient(private val baseUrl: () -> String) {
    suspend fun state(after: Long, version: Long? = null, waitSec: Int = 0): PluginState {
        val waiting = version != null && waitSec > 0
        val url = "${baseUrl()}/api/plugin?after=$after" + if (waiting) "&v=$version&wait=$waitSec" else ""
        return json.decodeFromString(Http.get(url, long = waiting))
    }

    suspend fun manifest(): PluginManifest = json.decodeFromString(Http.get("${baseUrl()}/api/plugin/manifest"))

    suspend fun panel(): PluginPanel = json.decodeFromString(Http.get("${baseUrl()}/api/plugin/panel"))

    suspend fun say(text: String) {
        Http.post("${baseUrl()}/api/plugin/say", buildJsonObject { put("text", text) })
    }

    suspend fun act(action: String, arg: Long? = null) {
        Http.post("${baseUrl()}/api/plugin/act", buildJsonObject {
            put("action", action)
            arg?.let { put("arg", it) }
        })
    }

    suspend fun toggle(id: String, on: Boolean) {
        Http.post("${baseUrl()}/api/plugin/toggle", buildJsonObject {
            put("id", id)
            put("on", on)
        })
    }
}
