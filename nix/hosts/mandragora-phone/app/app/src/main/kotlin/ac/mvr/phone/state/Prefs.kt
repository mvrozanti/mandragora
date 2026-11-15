package ac.mvr.phone.state

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject

class Prefs(context: Context) {
    private val sp: SharedPreferences = context.getSharedPreferences("mandragora", Context.MODE_PRIVATE)

    private val unitFlow = MutableStateFlow(sp.getString("unit", "brl") ?: "brl")
    val unit: StateFlow<String> = unitFlow

    private val hiddenFlow = MutableStateFlow(sp.getBoolean("hiddenAmounts", false))
    val hiddenAmounts: StateFlow<Boolean> = hiddenFlow

    private val groupFlow = MutableStateFlow(sp.getString("moneyGroup", "asset") ?: "asset")
    val moneyGroup: StateFlow<String> = groupFlow

    private val clicksFlow = MutableStateFlow(readClicks())
    val hubClicks: StateFlow<Map<String, Int>> = clicksFlow

    fun setUnit(value: String) {
        unitFlow.value = value
        sp.edit().putString("unit", value).apply()
    }

    fun setMoneyGroup(value: String) {
        groupFlow.value = value
        sp.edit().putString("moneyGroup", value).apply()
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

    var iconBucket: Int
        get() = sp.getInt("iconBucket", 8)
        set(value) = sp.edit().putInt("iconBucket", value).apply()

    var lastMoney: String?
        get() = sp.getString("lastMoney", null)
        set(value) = putIfChanged("lastMoney", value)

    var lastHub: String?
        get() = sp.getString("lastHub", null)
        set(value) = putIfChanged("lastHub", value)

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
