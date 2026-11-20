package ac.mvr.phone.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.job
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.Credentials
import okhttp3.Request
import java.io.IOException
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

@Serializable
data class CodeAccess(val id: String = "opencode", val name: String = id, val port: Int = 4096, val user: String = "opencode", val password: String? = null)

@Serializable
data class CodeBackends(val backends: List<CodeAccess> = emptyList())

@Serializable
data class LiveInfo(val name: String? = null, val status: String? = null, val waiting: String? = null, val tmux: String? = null)

@Serializable
data class CodeTime(val created: Long = 0, val updated: Long = 0)

@Serializable
data class CodeSession(
    val id: String,
    val title: String = "",
    val directory: String = "",
    val parentID: String? = null,
    val time: CodeTime = CodeTime(),
    val live: LiveInfo? = null,
    val snippet: String? = null,
) {
    @Transient var backend: String = ""
    val folder: String get() = directory.trimEnd('/').substringAfterLast('/').ifEmpty { directory }
}

@Serializable
data class CodeProject(val id: String, val worktree: String, val name: String? = null, val time: CodeTime = CodeTime()) {
    @Transient var backend: String = ""
    val folder: String get() = name ?: worktree.trimEnd('/').substringAfterLast('/').ifEmpty { worktree }
}

@Serializable
data class CodeStatus(val type: String = "idle", val message: String? = null)

@Serializable
data class ToolState(
    val status: String = "pending",
    val title: String? = null,
    val output: String? = null,
    val error: String? = null,
    val input: JsonObject? = null,
)

@Serializable
data class CodePart(
    val id: String,
    val messageID: String,
    val sessionID: String = "",
    val type: String,
    val text: String? = null,
    val tool: String? = null,
    val callID: String? = null,
    val state: ToolState? = null,
    val synthetic: Boolean = false,
    val ignored: Boolean = false,
)

@Serializable
data class MessageTime(val created: Double = 0.0, val completed: Double? = null)

@Serializable
data class MessageError(val name: String = "", val data: JsonObject? = null) {
    val text: String get() = data?.get("message")?.jsonPrimitive?.contentOrNull ?: name
}

@Serializable
data class CodeMessage(
    val id: String,
    val sessionID: String = "",
    val role: String,
    val time: MessageTime = MessageTime(),
    val modelID: String? = null,
    val providerID: String? = null,
    val agent: String? = null,
    val error: MessageError? = null,
    val finish: String? = null,
)

@Serializable
data class CodeEntry(val info: CodeMessage, val parts: List<CodePart> = emptyList())

@Serializable
data class PermissionAsk(
    val id: String,
    val sessionID: String,
    val permission: String = "",
    val patterns: List<String> = emptyList(),
    val always: List<String> = emptyList(),
    val metadata: JsonObject? = null,
)

@Serializable
data class QuestionOption(val label: String, val description: String = "")

@Serializable
data class QuestionInfo(
    val question: String,
    val header: String = "",
    val options: List<QuestionOption> = emptyList(),
    val multiple: Boolean = false,
    val custom: Boolean = false,
)

@Serializable
data class QuestionAsk(val id: String, val sessionID: String, val questions: List<QuestionInfo> = emptyList())

@Serializable
data class Uploaded(val path: String)

@Serializable
data class ScreenOption(val key: String, val label: String, val detail: String = "", val text: Boolean = false, val current: Boolean = false)

@Serializable
data class ScreenAsk(
    val id: String,
    val sessionID: String,
    val waiting: String = "",
    val body: String = "",
    val plan: String? = null,
    val options: List<ScreenOption> = emptyList(),
    val tabs: Boolean = false,
)

@Serializable
data class Pressed(val screen: ScreenAsk? = null)

@Serializable
data class CodeProvider(val id: String, val name: String = id, val models: Map<String, JsonObject> = emptyMap())

@Serializable
data class SessionSettings(val providerID: String? = null, val modelID: String? = null, val mode: String = "auto", val effort: String? = null)

@Serializable
data class CodeProviders(
    val all: List<CodeProvider> = emptyList(),
    val connected: List<String> = emptyList(),
    val default: Map<String, String> = emptyMap(),
)

data class CodeEvent(val type: String, val properties: JsonObject)

class CodeClient(val id: String, private val baseUrl: () -> String, private val access: () -> CodeAccess?) {
    private fun headers(): Map<String, String> {
        val password = access()?.password ?: return emptyMap()
        return mapOf("Authorization" to Credentials.basic(access()?.user ?: "opencode", password))
    }

    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    private fun url(path: String, directory: String? = null): String {
        val base = baseUrl() + path
        if (directory == null) return base
        return base + (if ('?' in path) "&" else "?") + "directory=" + enc(directory)
    }

    suspend fun projects(): List<CodeProject> =
        json.decodeFromString<List<CodeProject>>(Http.get(url("/project"), headers())).onEach { it.backend = id }

    suspend fun upload(bytes: ByteArray, type: String = "image/jpeg", name: String? = null): String =
        json.decodeFromString<Uploaded>(Http.postBytes(url("/upload" + (name?.let { "?name=" + enc(it) } ?: "")), bytes, type, headers())).path

    suspend fun find(query: String, limit: Int): List<CodeSession> =
        json.decodeFromString<List<CodeSession>>(Http.get(url("/find?limit=$limit&q=" + enc(query)), headers())).onEach { it.backend = id }

    suspend fun sessions(directory: String, limit: Int): List<CodeSession> =
        json.decodeFromString<List<CodeSession>>(Http.get(url("/session?limit=$limit", directory), headers())).onEach { it.backend = id }

    suspend fun status(directory: String): Map<String, CodeStatus> =
        json.decodeFromString(Http.get(url("/session/status", directory), headers()))

    suspend fun providers(): CodeProviders = json.decodeFromString(Http.get(url("/provider"), headers()))

    suspend fun configuredModel(): String? =
        Http.obj(Http.get(url("/config"), headers()))["model"]?.jsonPrimitive?.contentOrNull

    suspend fun create(directory: String, providerID: String?, modelID: String?, settings: SessionSettings? = null): CodeSession {
        val body = buildJsonObject {
            if (providerID != null && modelID != null) put("model", buildJsonObject { put("providerID", providerID); put("id", modelID) })
            if (settings != null) {
                put("mode", settings.mode)
                settings.effort?.let { put("effort", it) }
            }
        }
        return json.decodeFromString<CodeSession>(Http.post(url("/session", directory), body, headers())).also { it.backend = id }
    }

    suspend fun settings(id: String, directory: String): SessionSettings =
        json.decodeFromString(Http.get(url("/session/$id/settings", directory), headers()))

    suspend fun setSettings(id: String, directory: String, body: JsonObject): SessionSettings =
        json.decodeFromString(Http.post(url("/session/$id/settings", directory), body, headers()))

    suspend fun messages(id: String, directory: String, limit: Int): List<CodeEntry> =
        json.decodeFromString(Http.get(url("/session/$id/message?limit=$limit", directory), headers()))

    suspend fun prompt(id: String, directory: String, text: String, providerID: String?, modelID: String?) {
        val body = buildJsonObject {
            if (providerID != null && modelID != null) put("model", buildJsonObject { put("providerID", providerID); put("modelID", modelID) })
            put("parts", buildJsonArray { add(buildJsonObject { put("type", "text"); put("text", text) }) })
        }
        Http.post(url("/session/$id/prompt_async", directory), body, headers())
    }

    suspend fun abort(id: String, directory: String) {
        Http.post(url("/session/$id/abort", directory), buildJsonObject { }, headers())
    }

    suspend fun close(id: String, directory: String) {
        Http.post(url("/session/$id/close", directory), buildJsonObject { }, headers())
    }

    suspend fun permissions(directory: String): List<PermissionAsk> =
        json.decodeFromString(Http.get(url("/permission", directory), headers()))

    suspend fun questions(directory: String): List<QuestionAsk> =
        json.decodeFromString(Http.get(url("/question", directory), headers()))

    suspend fun permission(sessionID: String, permissionID: String, directory: String, response: String) {
        Http.post(url("/session/$sessionID/permissions/$permissionID", directory), buildJsonObject { put("response", response) }, headers())
    }

    suspend fun answer(requestID: String, directory: String, answers: List<List<String>>) {
        val body = buildJsonObject {
            put("answers", buildJsonArray { answers.forEach { one -> add(buildJsonArray { one.forEach { add(it) } }) } })
        }
        Http.post(url("/question/$requestID/reply", directory), body, headers())
    }

    suspend fun screens(directory: String): List<ScreenAsk> =
        json.decodeFromString(Http.get(url("/screen", directory), headers()))

    suspend fun press(sessionID: String, directory: String, id: String, key: String, text: String?): ScreenAsk? {
        val body = buildJsonObject {
            put("id", id)
            put("key", key)
            if (text != null) put("text", text)
        }
        return json.decodeFromString<Pressed>(Http.post(url("/session/$sessionID/screen", directory), body, headers())).screen
    }

    suspend fun reject(requestID: String, directory: String) {
        Http.post(url("/question/$requestID/reject", directory), buildJsonObject { }, headers())
    }

    fun events(directory: String?): Flow<CodeEvent> = flow {
        val client = Http.client.newBuilder().readTimeout(45, TimeUnit.SECONDS).build()
        val builder = Request.Builder().url(url("/event", directory)).header("Accept", "text/event-stream")
        headers().forEach { (k, v) -> builder.header(k, v) }
        val call = client.newCall(builder.build())
        currentCoroutineContext().job.invokeOnCompletion { call.cancel() }
        call.execute().use { response ->
            if (!response.isSuccessful) throw IOException("${response.code} /event")
            val source = response.body?.source() ?: throw IOException("empty event stream")
            val data = StringBuilder()
            while (true) {
                val line = source.readUtf8Line() ?: break
                if (line.isEmpty()) {
                    if (data.isNotEmpty()) {
                        val payload = data.toString()
                        data.setLength(0)
                        val obj = runCatching { json.parseToJsonElement(payload).jsonObject }.getOrNull()
                        val type = obj?.get("type")?.jsonPrimitive?.contentOrNull
                        if (obj != null && type != null) emit(CodeEvent(type, obj["properties"]?.jsonObject ?: JsonObject(emptyMap())))
                    }
                } else if (line.startsWith("data:")) {
                    if (data.isNotEmpty()) data.append('\n')
                    data.append(line.substring(5).trimStart())
                }
            }
        }
    }.flowOn(Dispatchers.IO)
}
