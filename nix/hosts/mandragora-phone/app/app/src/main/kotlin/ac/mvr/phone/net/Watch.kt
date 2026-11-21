package ac.mvr.phone.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class Watcher(
    val id: Long,
    val kind: String = "",
    val target: String = "",
    val name: String = "",
    val enabled: Boolean = true,
    @SerialName("last_polled_at") val lastPolledAt: String? = null,
    @SerialName("last_error") val lastError: String? = null,
    @SerialName("requires_ack") val requiresAck: Boolean = false,
    val condition: String? = null,
    @SerialName("watch_id") val watchId: Long? = null,
    val push: Boolean = true,
    @SerialName("trigger_count") val triggerCount: Int = 0,
    @SerialName("open_trigger_count") val openTriggerCount: Int = 0,
    val state: String = "waiting",
) {
    val title: String get() = name.ifBlank { condition ?: "$kind · $target" }
}

@Serializable
data class WatchTrigger(
    val id: Long,
    @SerialName("watcher_id") val watcherId: Long = 0,
    @SerialName("watcher_name") val watcherName: String? = null,
    val condition: String? = null,
    val title: String? = null,
    val summary: String? = null,
    val link: String? = null,
    @SerialName("occurred_at") val occurredAt: String? = null,
    @SerialName("received_at") val receivedAt: String? = null,
    @SerialName("acked_at") val ackedAt: String? = null,
    @SerialName("ai_verdict") val aiVerdict: String? = null,
    @SerialName("ai_reason") val aiReason: String? = null,
)

@Serializable
data class WatchSpec(val id: Long = 0, val name: String? = null, val kind: String? = null)

@Serializable
data class WatchHealth(
    val ok: Boolean = true,
    val degraded: List<String> = emptyList(),
    @SerialName("undecidable_specs") val undecidable: List<WatchSpec> = emptyList(),
    @SerialName("last_poll_at") val lastPollAt: String? = null,
    @SerialName("last_push_at") val lastPushAt: String? = null,
)

@Serializable
data class WatchToggled(val ok: Boolean = false, val enabled: Boolean = true)

@Serializable
data class WatchPolled(val ok: Boolean = false, val inserted: Int = 0, val fetched: Int = 0)

@Serializable
data class WatchAcked(val ok: Boolean = false, val acked: JsonElement? = null)

@Serializable
data class WatchDropped(val ok: Boolean = false, val condition: String? = null, val places: Int = 1)

@Serializable
data class WatchCreated(val ok: Boolean = false, val created: List<JsonObject> = emptyList(), val warnings: List<JsonElement> = emptyList())

class WatchClient(private val base: () -> String) {
    private fun api(path: String) = "${base()}/api/$path"

    suspend fun watchers(): List<Watcher> = json.decodeFromString(Http.get(api("watchers")))

    suspend fun health(): WatchHealth = json.decodeFromString(Http.get("${base()}/healthz"))

    suspend fun open(limit: Int = 10): List<WatchTrigger> = json.decodeFromString(Http.get(api("triggers?limit=$limit")))

    suspend fun triggers(watcher: Long, limit: Int = 30): List<WatchTrigger> =
        json.decodeFromString(Http.get(api("watchers/$watcher/triggers?limit=$limit")))

    suspend fun ack(event: Long): WatchAcked = json.decodeFromString(Http.post(api("events/$event/ack"), null))

    suspend fun ackAll(watcher: Long): WatchAcked = json.decodeFromString(Http.post(api("watchers/$watcher/ack-all"), null))

    suspend fun toggle(watcher: Long): WatchToggled = json.decodeFromString(Http.post(api("watchers/$watcher/toggle"), null))

    suspend fun poll(watcher: Long): WatchPolled = json.decodeFromString(Http.post(api("watchers/$watcher/poll"), null, long = true))

    suspend fun dropWatcher(watcher: Long): WatchDropped = json.decodeFromString(Http.delete(api("watchers/$watcher")))

    suspend fun dropWatch(watch: Long): WatchDropped = json.decodeFromString(Http.delete(api("watches/$watch")))

    suspend fun compose(text: String): WatchCreated =
        json.decodeFromString(Http.post(api("compose/quick"), buildJsonObject { put("text", text) }, long = true))
}
