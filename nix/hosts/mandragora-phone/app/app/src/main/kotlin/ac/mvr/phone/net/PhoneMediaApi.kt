package ac.mvr.phone.net

import ac.mvr.phone.logic.PhoneMediaItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody
import okio.BufferedSink
import okio.source
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.TimeUnit

@Serializable
data class RemoveJob(val id: String, val sha256: String)

@Serializable
data class PhoneMediaJobs(
    val thumbs: List<String> = emptyList(),
    val pull: List<String> = emptyList(),
    val remove: List<RemoveJob> = emptyList(),
    val reindex: Boolean = false,
) {
    val empty: Boolean get() = thumbs.isEmpty() && pull.isEmpty() && remove.isEmpty()
}

private const val UPLOAD_TIMEOUT_S = 120L

class PhoneMediaApi(private val baseUrl: () -> String) {
    private val uploads by lazy {
        Http.client.newBuilder().writeTimeout(UPLOAD_TIMEOUT_S, TimeUnit.SECONDS).readTimeout(UPLOAD_TIMEOUT_S, TimeUnit.SECONDS).build()
    }

    suspend fun postIndex(items: List<PhoneMediaItem>): PhoneMediaJobs = json.decodeFromString(
        Http.post("${baseUrl()}/api/phone/media/index", buildJsonObject {
            putJsonArray("items") {
                items.forEach { item ->
                    addJsonObject {
                        put("id", item.id.toString())
                        put("name", item.name)
                        put("path", item.path)
                        put("kind", item.kind)
                        put("mime", item.mime)
                        put("size", item.size)
                        put("taken", item.taken)
                        put("modified", item.modified)
                    }
                }
            }
        }),
    )

    suspend fun jobs(): PhoneMediaJobs = json.decodeFromString(Http.get("${baseUrl()}/api/phone/media/jobs"))

    suspend fun thumb(id: String, jpeg: ByteArray) {
        Http.postBytes("${baseUrl()}/api/phone/media/thumb?id=$id", jpeg, "image/jpeg")
    }

    suspend fun upload(id: String, sha256: String, length: Long, open: () -> InputStream) = withContext(Dispatchers.IO) {
        val body = object : RequestBody() {
            override fun contentType(): MediaType = "application/octet-stream".toMediaType()
            override fun contentLength(): Long = length
            override fun writeTo(sink: BufferedSink) {
                open().source().use { sink.writeAll(it) }
            }
        }
        val request = Request.Builder().url("${baseUrl()}/api/phone/media/file?id=$id").header("X-Sha256", sha256).post(body).build()
        uploads.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("${response.code}: ${response.body?.string()?.take(160)}")
        }
    }

    suspend fun report(id: String, job: String, error: String? = null) {
        Http.post("${baseUrl()}/api/phone/media/report", buildJsonObject {
            put("id", id)
            put("job", job)
            if (error != null) put("error", error)
        })
    }
}
