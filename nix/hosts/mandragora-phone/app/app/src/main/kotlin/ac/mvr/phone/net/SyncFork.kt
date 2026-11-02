package ac.mvr.phone.net

import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull

data class SyncFolder(
    val id: String,
    val label: String,
    val path: String,
    val type: String,
    val paused: Boolean,
    val state: String = "",
    val localFiles: Long = 0,
    val needFiles: Long = 0,
    val needBytes: Long = 0,
) {
    val direction: String get() = when (type) {
        "receiveonly" -> "→"
        "sendonly" -> "←"
        else -> "⇄"
    }
}

class SyncForkClient(private val apiKey: () -> String?) {
    private val base = "http://127.0.0.1:8384"

    private fun headers(): Map<String, String> {
        val key = apiKey() ?: throw IllegalStateException("no api key")
        return mapOf("X-API-Key" to key)
    }

    suspend fun folders(): List<SyncFolder> {
        val config = json.parseToJsonElement(Http.get("$base/rest/config/folders", headers())).jsonArray
        return config.map { element ->
            val obj = element.jsonObject
            val id = obj["id"]!!.jsonPrimitive.content
            val status = runCatching { Http.obj(Http.get("$base/rest/db/status?folder=$id", headers())) }.getOrNull()
            SyncFolder(
                id = id,
                label = obj["label"]?.jsonPrimitive?.contentOrNull?.ifBlank { null } ?: id,
                path = obj["path"]?.jsonPrimitive?.contentOrNull ?: "",
                type = obj["type"]?.jsonPrimitive?.contentOrNull ?: "sendreceive",
                paused = obj["paused"]?.jsonPrimitive?.booleanOrNull ?: false,
                state = status?.get("state")?.jsonPrimitive?.contentOrNull ?: "",
                localFiles = status?.get("localFiles")?.jsonPrimitive?.longOrNull ?: 0,
                needFiles = status?.get("needFiles")?.jsonPrimitive?.longOrNull ?: 0,
                needBytes = status?.get("needBytes")?.jsonPrimitive?.longOrNull ?: 0,
            )
        }
    }

    suspend fun rescan(folderId: String? = null) {
        val url = if (folderId == null) "$base/rest/db/scan" else "$base/rest/db/scan?folder=$folderId"
        Http.post(url, null, headers())
    }

    suspend fun connected(): Boolean = runCatching {
        Http.obj(Http.get("$base/rest/system/status", headers()))
        true
    }.getOrDefault(false)
}
