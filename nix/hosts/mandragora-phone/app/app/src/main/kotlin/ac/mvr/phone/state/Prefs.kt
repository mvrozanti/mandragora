package ac.mvr.phone.state

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject
import java.util.UUID

val CARDS = listOf("music", "inbox", "money", "hub", "code", "ask", "voice", "plugin", "watch", "panic", "gpu", "power")

class Prefs(context: Context) {
    private val sp: SharedPreferences = context.getSharedPreferences("mandragora", Context.MODE_PRIVATE)

    private val unitFlow = MutableStateFlow(sp.getString("unit", "brl") ?: "brl")
    val unit: StateFlow<String> = unitFlow

    private val hiddenFlow = MutableStateFlow(sp.getBoolean("hiddenAmounts", false))
    val hiddenAmounts: StateFlow<Boolean> = hiddenFlow

    private val orderFlow = MutableStateFlow(readOrder())
    val cardOrder: StateFlow<List<String>> = orderFlow

    private val autoplayFlow = MutableStateFlow(sp.getBoolean("autoplaySkip", true))
    val autoplaySkip: StateFlow<Boolean> = autoplayFlow

    private val squashFlow = MutableStateFlow(sp.getBoolean("squashCalls", true))
    val squashCalls: StateFlow<Boolean> = squashFlow

    private val clicksFlow = MutableStateFlow(readClicks())
    val hubClicks: StateFlow<Map<String, Int>> = clicksFlow

    private val listenFlow = MutableStateFlow(sp.getBoolean("inboxListen", true))
    val inboxListen: StateFlow<Boolean> = listenFlow

    private val voiceTaskFlow = MutableStateFlow(sp.getString("voiceTask", "transcribe") ?: "transcribe")
    val voiceTask: StateFlow<String> = voiceTaskFlow

    private val voiceLangFlow = MutableStateFlow(sp.getString("voiceLang", "") ?: "")
    val voiceLang: StateFlow<String> = voiceLangFlow

    fun setInboxListen(value: Boolean) {
        listenFlow.value = value
        sp.edit().putBoolean("inboxListen", value).apply()
    }

    fun setVoiceTask(value: String) {
        voiceTaskFlow.value = value
        sp.edit().putString("voiceTask", value).apply()
    }

    fun setVoiceLang(value: String) {
        voiceLangFlow.value = value
        sp.edit().putString("voiceLang", value).apply()
    }

    var inboxNotified: Long
        get() = sp.getLong("inboxNotified", -1L)
        set(value) = sp.edit().putLong("inboxNotified", value).apply()

    var voiceHistory: String?
        get() = sp.getString("voiceHistory", null)
        set(value) = putIfChanged("voiceHistory", value)

    fun setUnit(value: String) {
        unitFlow.value = value
        sp.edit().putString("unit", value).apply()
    }

    fun setAutoplaySkip(value: Boolean) {
        autoplayFlow.value = value
        sp.edit().putBoolean("autoplaySkip", value).apply()
    }

    fun setSquashCalls(value: Boolean) {
        squashFlow.value = value
        sp.edit().putBoolean("squashCalls", value).apply()
    }

    fun setCardOrder(value: List<String>) {
        val next = normalizeOrder(value)
        orderFlow.value = next
        sp.edit().putString("cardOrder", next.joinToString(",")).apply()
    }

    private fun readOrder(): List<String> = normalizeOrder(sp.getString("cardOrder", null)?.split(',') ?: emptyList())

    private fun normalizeOrder(value: List<String>): List<String> {
        val known = value.filter { it in CARDS }.distinct()
        return known + CARDS.filter { it !in known }
    }

    fun setHiddenAmounts(value: Boolean) {
        hiddenFlow.value = value
        sp.edit().putBoolean("hiddenAmounts", value).apply()
    }

    fun bumpClick(host: String) {
        val next = clicksFlow.value.toMutableMap()
        next[host] = (next[host] ?: 0) + 1
        clicksFlow.value = next
        val obj = JSONObject()
        next.forEach { (k, v) -> obj.put(k, v) }
        sp.edit().putString("hubClicks", obj.toString()).apply()
    }

    val deviceId: String by lazy {
        sp.getString("deviceId", null) ?: UUID.randomUUID().toString().also { sp.edit().putString("deviceId", it).apply() }
    }

    var iconBucket: Int
        get() = sp.getInt("iconBucket", 8)
        set(value) = sp.edit().putInt("iconBucket", value).apply()

    var lastMoney: String?
        get() = sp.getString("lastMoney", null)
        set(value) = putIfChanged("lastMoney", value)

    var lastHub: String?
        get() = sp.getString("lastHub", null)
        set(value) = putIfChanged("lastHub", value)

    var lastCodeSession: String?
        get() = sp.getString("lastCodeSession", null)
        set(value) = putIfChanged("lastCodeSession", value)

    var lastCodeDir: String?
        get() = sp.getString("lastCodeDir", null)
        set(value) = putIfChanged("lastCodeDir", value)

    var codeModel: String?
        get() = sp.getString("codeModel", null)
        set(value) = putIfChanged("codeModel", value)

    private fun putIfChanged(key: String, value: String?) {
        if (sp.getString(key, null) == value) return
        sp.edit().putString(key, value).apply()
    }

    private fun readClicks(): Map<String, Int> {
        val raw = sp.getString("hubClicks", null) ?: return emptyMap()
        return runCatching {
            val obj = JSONObject(raw)
            obj.keys().asSequence().associateWith { obj.getInt(it) }
        }.getOrDefault(emptyMap())
    }
}
