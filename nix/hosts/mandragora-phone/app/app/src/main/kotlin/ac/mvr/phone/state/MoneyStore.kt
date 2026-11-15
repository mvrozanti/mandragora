package ac.mvr.phone.state

import ac.mvr.phone.net.MoneyCache
import ac.mvr.phone.net.parseMoney
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class MoneyStore(private val store: Store) {
    private val rawFlow = MutableStateFlow(store.prefs.lastMoney)
    val raw: StateFlow<String?> = rawFlow

    private val cacheFlow = MutableStateFlow(rawFlow.value?.let { text -> runCatching { parseMoney(text).copy(refreshing = false) }.getOrNull() })
    val cache: StateFlow<MoneyCache?> = cacheFlow

    private val refreshingFlow = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = refreshingFlow

    suspend fun refresh() {
        adopt(store.bridge.money())
    }

    private fun adopt(text: String): MoneyCache {
        val next = parseMoney(text)
        val current = cacheFlow.value
        if (!next.hasCache && current != null && current.hasCache) {
            val kept = current.copy(refreshing = next.refreshing)
            cacheFlow.value = kept
            return kept
        }
        cacheFlow.value = next
        rawFlow.value = text
        store.prefs.lastMoney = text
        return next
    }

    fun refreshNow() {
        if (refreshingFlow.value) return
        refreshingFlow.value = true
        store.act {
            try {
                val before = cacheFlow.value?.fetchedAt ?: 0.0
                store.bridge.refreshMoney()
                var sawRunning = false
                val deadline = System.currentTimeMillis() + 60_000
                while (System.currentTimeMillis() < deadline) {
                    delay(2_000)
                    val next = runCatching { adopt(store.bridge.money()) }.getOrNull() ?: continue
                    if (next.fetchedAt != before) break
                    if (next.refreshing) sawRunning = true
                    else if (sawRunning) throw IllegalStateException("refresh failed on the desktop")
                }
            } finally {
                refreshingFlow.value = false
            }
        }
    }
}
