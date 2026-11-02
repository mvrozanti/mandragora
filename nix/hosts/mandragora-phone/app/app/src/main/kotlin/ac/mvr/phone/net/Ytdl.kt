package ac.mvr.phone.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class YtdlJob(
    val id: String,
    val url: String = "",
    val mode: String = "audio",
    val to_client: Boolean = false,
    val status: String = "queued",
    val started: Double? = null,
    val finished: Double? = null,
    val name: String? = null,
    val filename: String? = null,
    val title: String? = null,
    val artist: String? = null,
    val exit_code: Int? = null,
    val cancelling: Boolean = false,
    val has_file: Boolean = false,
    val gone: Boolean = false,
    val progress: Double? = null,
    val stage: String? = null,
    val detail: String? = null,
) {
    val active: Boolean get() = status == "queued" || status == "running" || status == "tagging"
    val label: String get() = if (!artist.isNullOrBlank() && !title.isNullOrBlank()) "$artist · $title" else name ?: url
}

class YtdlClient(private val baseUrl: () -> String) {
    suspend fun jobs(): List<YtdlJob> = json.decodeFromString(ListSerializer(YtdlJob.serializer()), Http.get("${baseUrl()}/api/jobs"))

    suspend fun download(url: String, mode: String, toClient: Boolean): YtdlJob {
        val body = buildJsonObject {
            put("url", url)
            put("mode", mode)
            put("to_client", toClient)
        }
        return json.decodeFromString(Http.post("${baseUrl()}/api/download", body))
    }

    suspend fun cancel(id: String) = Http.post("${baseUrl()}/api/jobs/$id/cancel", null)

    suspend fun delete(id: String) = Http.delete("${baseUrl()}/api/jobs/$id")

    fun fileUrl(id: String): String = "${baseUrl()}/api/jobs/$id/file"
}
