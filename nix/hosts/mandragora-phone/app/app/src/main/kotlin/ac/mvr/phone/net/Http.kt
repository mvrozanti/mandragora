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
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

val json = Json { ignoreUnknownKeys = true; isLenient = true; explicitNulls = false }

class Unreachable(message: String, cause: Throwable? = null) : IOException(message, cause)

object Http {
    val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(2500, TimeUnit.MILLISECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .writeTimeout(5, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false)
        .build()

    private val jsonType = "application/json; charset=utf-8".toMediaType()

    suspend fun get(url: String, headers: Map<String, String> = emptyMap()): String = withContext(Dispatchers.IO) {
        val builder = Request.Builder().url(url)
        headers.forEach { (k, v) -> builder.header(k, v) }
        execute(builder.build())
    }

    suspend fun post(url: String, body: JsonElement?, headers: Map<String, String> = emptyMap()): String = withContext(Dispatchers.IO) {
        val payload = (body?.toString() ?: "").toRequestBody(jsonType)
        val builder = Request.Builder().url(url).post(payload)
        headers.forEach { (k, v) -> builder.header(k, v) }
        execute(builder.build())
    }

    suspend fun delete(url: String, headers: Map<String, String> = emptyMap()): String = withContext(Dispatchers.IO) {
        val builder = Request.Builder().url(url).delete()
        headers.forEach { (k, v) -> builder.header(k, v) }
        execute(builder.build())
    }

    private fun execute(request: Request): String {
        try {
            client.newCall(request).execute().use { response ->
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
