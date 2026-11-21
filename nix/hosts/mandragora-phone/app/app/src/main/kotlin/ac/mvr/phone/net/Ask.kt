package ac.mvr.phone.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class AskEntry(
    val id: Long,
    val ts: Double = 0.0,
    val role: String = "system",
    val text: String = "",
    val thinking: String? = null,
    val meta: JsonObject? = null,
)

@Serializable
data class AskPersona(val name: String, val instruction: String = "")

@Serializable
data class AskCommand(val name: String, val command: String = "")

@Serializable
data class AskState(
    val entries: List<AskEntry> = emptyList(),
    val last: Long = 0,
    val busy: Boolean = false,
    val queued: Int = 0,
    val activity: String? = null,
    val model: String = "",
    val think: Boolean = true,
    val personas: List<AskPersona> = emptyList(),
    val commands: List<AskCommand> = emptyList(),
)

class AskClient(private val baseUrl: () -> String) {
    suspend fun state(after: Long, wait: Int = 0): AskState {
        val url = "${baseUrl()}/api/ask?after=$after&wait=$wait"
        return json.decodeFromString(Http.get(url, long = wait > 0))
    }

    suspend fun send(text: String) {
        Http.post("${baseUrl()}/api/ask", buildJsonObject { put("text", text) })
    }

    suspend fun stop() {
        Http.post("${baseUrl()}/api/ask/stop", buildJsonObject { })
    }

    suspend fun think(on: Boolean) {
        Http.post("${baseUrl()}/api/ask/think", buildJsonObject { put("on", on) })
    }
}
