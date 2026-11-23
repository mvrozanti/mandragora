package ac.mvr.phone.state

import ac.mvr.phone.BuildConfig
import ac.mvr.phone.inbox.Alerts
import ac.mvr.phone.logic.newBuild
import ac.mvr.phone.net.InboxItem
import ac.mvr.phone.net.InboxView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class InboxStore(private val store: Store) {
    private val itemsFlow = MutableStateFlow<List<InboxItem>>(emptyList())
    val items: StateFlow<List<InboxItem>> = itemsFlow

    private val readFlow = MutableStateFlow(0L)
    val read: StateFlow<Long> = readFlow

    private val liveFlow = MutableStateFlow(false)
    val live: StateFlow<Boolean> = liveFlow

    val viewing = MutableStateFlow(false)

    val unread: StateFlow<Int> = combine(itemsFlow, readFlow) { items, read -> items.count { it.id > read } }
        .stateIn(store.scope, SharingStarted.Eagerly, 0)

    private var last = 0L
    private var published: Long? = null
    private var checked = 0L

    suspend fun listen() {
        var backoff = MIN_BACKOFF
        var synced = false
        while (currentCoroutineContext().isActive) {
            val view = runCatching { store.bridge.inbox(if (synced) last else 0L, if (synced) WAIT_SECONDS else 0, published.takeIf { synced }) }.getOrNull()
            when {
                view == null -> {
                    liveFlow.value = false
                    synced = false
                    delay(backoff)
                    backoff = (backoff * 2).coerceAtMost(MAX_BACKOFF)
                }
                synced && view.last < last -> synced = false
                else -> {
                    absorb(view, replace = !synced)
                    synced = true
                    liveFlow.value = true
                    backoff = MIN_BACKOFF
                }
            }
        }
    }

    private fun absorb(view: InboxView, replace: Boolean) {
        published = view.app
        if (newBuild(view.app, BuildConfig.VERSION_CODE.toLong(), checked)) {
            checked = view.app
            store.scope.launch { runCatching { store.update.refresh() } }
        }
        itemsFlow.value = if (replace) view.items else (itemsFlow.value + view.items).distinctBy { it.id }.takeLast(KEEP)
        readFlow.value = view.read
        last = view.last
        val notified = store.prefs.inboxNotified
        if (notified < 0 || notified > view.last) {
            store.prefs.inboxNotified = view.last
            return
        }
        val fresh = view.items.filter { it.id > notified && it.id > view.read }
        if (!(viewing.value && store.foreground.value)) fresh.forEach { Alerts.post(store.appContext, it) }
        if (view.last > notified) store.prefs.inboxNotified = view.last
        itemsFlow.value.filter { it.id <= view.read }.forEach { Alerts.cancel(store.appContext, it.id) }
    }

    fun markRead() {
        val upTo = itemsFlow.value.maxOfOrNull { it.id } ?: return
        Alerts.clear(store.appContext)
        if (upTo <= readFlow.value) return
        readFlow.value = upTo
        store.act { store.bridge.inboxRead(upTo) }
    }

    fun dismiss(id: Long) {
        itemsFlow.value = itemsFlow.value.filterNot { it.id == id }
        Alerts.cancel(store.appContext, id)
        store.act { store.bridge.inboxDrop(id = id) }
    }

    fun clear() {
        val upTo = itemsFlow.value.maxOfOrNull { it.id } ?: return
        itemsFlow.value = emptyList()
        Alerts.clear(store.appContext)
        store.act { store.bridge.inboxDrop(upTo = upTo) }
    }

    private companion object {
        const val WAIT_SECONDS = 45
        const val KEEP = 300
        const val MIN_BACKOFF = 2_000L
        const val MAX_BACKOFF = 60_000L
    }
}
