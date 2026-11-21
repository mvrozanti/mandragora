package ac.mvr.phone.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

val json = Json { ignoreUnknownKeys = true; isLenient = true; explicitNulls = false }

class Unreachable(message: String, cause: Throwable? = null) : IOException(message, cause)

object Http {
    val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(2500, TimeUnit.MILLISECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .writeTimeout(5, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private val jsonType = "application/json; charset=utf-8".toMediaType()

    private val patient: OkHttpClient by lazy { client.newBuilder().readTimeout(180, TimeUnit.SECONDS).build() }

    suspend fun postFile(url: String, file: File, type: String): String = withContext(Dispatchers.IO) {
        execute(Request.Builder().url(url).post(file.asRequestBody(type.toMediaType())).build(), patient)
    }

    suspend fun get(url: String, headers: Map<String, String> = emptyMap(), long: Boolean = false): String = withContext(Dispatchers.IO) {
        val builder = Request.Builder().url(url)
        headers.forEach { (k, v) -> builder.header(k, v) }
        execute(builder.build(), if (long) patient else client)
    }

    suspend fun post(url: String, body: JsonElement?, headers: Map<String, String> = emptyMap(), long: Boolean = false): String = withContext(Dispatchers.IO) {
        val payload = (body?.toString() ?: "").toRequestBody(jsonType)
        val builder = Request.Builder().url(url).post(payload)
        headers.forEach { (k, v) -> builder.header(k, v) }
        execute(builder.build(), if (long) patient else client)
    }

    suspend fun patch(url: String, body: JsonElement?, headers: Map<String, String> = emptyMap()): String = withContext(Dispatchers.IO) {
        val payload = (body?.toString() ?: "").toRequestBody(jsonType)
        val builder = Request.Builder().url(url).patch(payload)
        headers.forEach { (k, v) -> builder.header(k, v) }
        execute(builder.build())
    }

    suspend fun postBytes(url: String, bytes: ByteArray, type: String, headers: Map<String, String> = emptyMap()): String = withContext(Dispatchers.IO) {
        val builder = Request.Builder().url(url).post(bytes.toRequestBody(type.toMediaType()))
        headers.forEach { (k, v) -> builder.header(k, v) }
        execute(builder.build())
    }

    suspend fun delete(url: String, headers: Map<String, String> = emptyMap()): String = withContext(Dispatchers.IO) {
        val builder = Request.Builder().url(url).delete()
        headers.forEach { (k, v) -> builder.header(k, v) }
        execute(builder.build())
    }

    suspend fun bytes(url: String): ByteArray? = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(url).build()
        try {
            client.newCall(request).execute().use { response ->
                if (response.code == 404) return@withContext null
                if (!response.isSuccessful) throw IOException("${response.code} ${request.url.encodedPath}")
                response.body?.bytes()
            }
        } catch (err: IOException) {
            if (err.message?.startsWith("4") == true || err.message?.startsWith("5") == true) throw err
            throw Unreachable("${request.url.host} unreachable", err)
        }
    }

    suspend fun download(url: String, target: File, onProgress: (Long, Long) -> Unit) = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(url).build()
        try {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw IOException("${response.code} ${request.url.encodedPath}")
                val body = response.body ?: throw IOException("empty body")
                val total = body.contentLength()
                var done = 0L
                target.outputStream().use { out ->
                    body.byteStream().use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            out.write(buffer, 0, n)
                            done += n
                            onProgress(done, total)
                        }
                    }
                }
            }
        } catch (err: IOException) {
            if (err.message?.startsWith("4") == true || err.message?.startsWith("5") == true) throw err
            throw Unreachable("${request.url.host} unreachable", err)
        }
    }

    private fun execute(request: Request, using: OkHttpClient = client): String {
        try {
            using.newCall(request).execute().use { response ->
                val text = response.body?.string() ?: ""
                if (!response.isSuccessful) throw IOException("${response.code} ${request.url.encodedPath}: ${text.take(160)}")
                return text
            }
        } catch (err: IOException) {
            if (err is Unreachable) throw err
            if (err.message?.startsWith("4") == true || err.message?.startsWith("5") == true) throw err
            throw Unreachable("${request.url.host} unreachable", err)
        }
    }

    fun obj(text: String): JsonObject = json.parseToJsonElement(text).jsonObject
}
