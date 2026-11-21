package ac.mvr.phone.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class TeachTurn(val id: Long, val ts: Long = 0, val role: String, val content: String = "")

@Serializable
data class TeachState(
    val turns: List<TeachTurn> = emptyList(),
    val last: Long = 0,
    val busy: Boolean = false,
    val queued: Int = 0,
    val pending: Int = 0,
    val nudges: Boolean = true,
    val micro: Int = 0,
    val version: Long = 0,
)

@Serializable
data class TeachConcept(val id: Int, val topic: String = "", val name: String = "", val status: String = "", val overdueDays: Double = 0.0)

@Serializable
data class TeachCount(val status: String, val n: Int = 0)

@Serializable
data class TeachStreak(val current: Int = 0, val longest: Int = 0, @SerialName("total_days") val totalDays: Int = 0)

@Serializable
data class TeachBucket(val bucket: Int, val n: Int = 0, val accuracy: Double? = null, val brier: Double? = null)

@Serializable
data class TeachGoal(val id: Int, val topic: String = "", val target: String = "", val deadline: String? = null)

@Serializable
data class TeachReviews(val total: Int = 0, val correct: Int = 0, val accuracy: Double? = null)

@Serializable
data class TeachMistake(val pattern: String = "", val n: Int = 0)

@Serializable
data class TeachWeak(val id: Int, val topic: String = "", val name: String = "", val reps: Int = 0, val lapses: Int = 0, val lapseRate: Double = 0.0)

@Serializable
data class TeachTopic(val name: String, val retention: Double = 0.9, val concepts: Int = 0, val mastered: Int = 0)

@Serializable
data class TeachQueue(val pending: Int = 0, val oldestWaitSec: Long = 0, val attempts: Int = 0, val lastError: String? = null, val drainEverySec: Int = 600)

@Serializable
data class TeachNudges(val enabled: Boolean = true, val idleHours: Int = 24, val cooldownHours: Int = 12)

@Serializable
data class TeachStats(
    val due: List<TeachConcept> = emptyList(),
    val backlog: Int = 0,
    val mastery: List<TeachCount> = emptyList(),
    val masteryScope: String = "all topics",
    val streak: TeachStreak = TeachStreak(),
    val calibration: List<TeachBucket> = emptyList(),
    val goals: List<TeachGoal> = emptyList(),
    val reviews: TeachReviews = TeachReviews(),
    val mistakes: List<TeachMistake> = emptyList(),
    val weakest: List<TeachWeak> = emptyList(),
    val topics: List<TeachTopic> = emptyList(),
    val queue: TeachQueue = TeachQueue(),
    val nudges: TeachNudges = TeachNudges(),
    val micro: Int = 0,
)

class TeachClient(private val baseUrl: () -> String) {
    suspend fun state(after: Long, version: Long? = null, waitSec: Int = 0): TeachState {
        val waiting = version != null && waitSec > 0
        val url = "${baseUrl()}/api/teach?after=$after" + if (waiting) "&v=$version&wait=$waitSec" else ""
        return json.decodeFromString(Http.get(url, long = waiting))
    }

    suspend fun say(text: String) {
        Http.post("${baseUrl()}/api/teach/say", buildJsonObject { put("text", text) })
    }

    suspend fun act(action: String, concept: Int? = null) {
        Http.post("${baseUrl()}/api/teach/act", buildJsonObject {
            put("action", action)
            concept?.let { put("concept", it) }
        })
    }

    suspend fun stats(topic: String? = null): TeachStats {
        val scope = topic?.let { "?topic=" + java.net.URLEncoder.encode(it, "UTF-8").replace("+", "%20") } ?: ""
        return json.decodeFromString(Http.get("${baseUrl()}/api/teach/stats$scope"))
    }

    suspend fun retention(topic: String, value: Double) {
        Http.post("${baseUrl()}/api/teach/retention", buildJsonObject {
            put("topic", topic)
            put("value", value)
        })
    }

    suspend fun nudges(enabled: Boolean) {
        Http.post("${baseUrl()}/api/teach/nudge", buildJsonObject { put("enabled", enabled) })
    }

    suspend fun retry() {
        Http.post("${baseUrl()}/api/teach/retry", buildJsonObject { })
    }
}
