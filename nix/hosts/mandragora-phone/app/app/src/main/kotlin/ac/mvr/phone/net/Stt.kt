package ac.mvr.phone.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.File

@Serializable
data class SttResult(
    val text: String = "",
    val language: String = "",
    @SerialName("language_probability") val probability: Double = 0.0,
    val duration: Double = 0.0,
    val task: String = "transcribe",
    @SerialName("elapsed_seconds") val elapsed: Double = 0.0,
)

@Serializable
data class SttHolder(val name: String? = null, @SerialName("held_seconds") val held: Double = 0.0)

@Serializable
data class SttStatus(
    @SerialName("model_loaded") val loaded: Boolean = false,
    @SerialName("gpu_lock_holder") val holder: SttHolder? = null,
)

class SttClient(private val baseUrl: () -> String) {
    suspend fun status(): SttStatus = json.decodeFromString(Http.get("${baseUrl()}/api/stt/status"))

    suspend fun warmup() { Http.post("${baseUrl()}/api/stt/warmup", null, long = true) }

    suspend fun transcribe(file: File, type: String, task: String, language: String?): SttResult {
        val spoken = language?.takeIf { it.isNotBlank() }?.let { "&language=$it" } ?: ""
        return json.decodeFromString(Http.postFile("${baseUrl()}/api/transcribe?task=$task$spoken", file, type))
    }
}
