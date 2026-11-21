package ac.mvr.phone.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.WatchHealth
import ac.mvr.phone.net.WatchTrigger
import ac.mvr.phone.net.Watcher
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import java.time.Instant

private val SECTIONS = listOf(
    "fired" to "fired · not accepted",
    "waiting" to "waiting",
    "done" to "done",
    "paused" to "paused",
    "feeds" to "feeds · never notify",
)

private fun Watcher.section(): String = when {
    !enabled -> "paused"
    !push -> "feeds"
    state == "triggered" -> "fired"
    state == "done" -> "done"
    else -> "waiting"
}

private fun agoIso(iso: String?): String {
    val ms = iso?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() } ?: return ""
    val seconds = (System.currentTimeMillis() - ms) / 1000
    return when {
        seconds < 60 -> "now"
        seconds < 3600 -> "${seconds / 60} m ago"
        seconds < 86400 -> "${seconds / 3600} h ago"
        else -> "${seconds / 86400} d ago"
    }
}

private fun openLink(context: Context, link: String?) {
    if (link.isNullOrBlank()) return
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

internal fun Watcher.caption(): String {
    val parts = ArrayList<String>()
    parts.add("$kind · $target")
    if (openTriggerCount > 0) parts.add("$openTriggerCount open")
    if (requiresAck) parts.add("nags until accepted")
    if (lastError != null) parts.add("a source is failing")
    return parts.joinToString(" · ")
}

private fun WatchTrigger.meta(): String {
    val parts = ArrayList<String>()
    agoIso(receivedAt ?: occurredAt).takeIf { it.isNotEmpty() }?.let { parts.add(it) }
    aiVerdict?.let { parts.add(it.lowercase()) }
    return parts.joinToString(" · ")
}

@Composable
internal fun TriggerLine(trigger: WatchTrigger, showWatcher: Boolean, onAccept: (() -> Unit)?) {
    val scheme = MaterialTheme.colorScheme
    val context = LocalContext.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).clickable(enabled = !trigger.link.isNullOrBlank()) { openLink(context, trigger.link) },
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(trigger.title ?: "(no title)", style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
            val summary = trigger.summary?.trim().orEmpty()
            val small = MaterialTheme.typography.bodySmall
            if (summary.isNotEmpty() && !showWatcher) Text(summary, style = small, color = scheme.onSurfaceVariant, maxLines = 3, overflow = TextOverflow.Ellipsis)
            val reason = trigger.aiReason
            if (!reason.isNullOrBlank() && !showWatcher) Text("why: $reason", style = small, color = scheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            val head = if (showWatcher) listOfNotNull(trigger.watcherName, trigger.meta().ifEmpty { null }).joinToString(" · ") else trigger.meta()
            if (head.isNotEmpty()) Label(head)
        }
        when {
            trigger.ackedAt != null -> Label("accepted")
            onAccept != null -> ChatChip("accept", scheme.surfaceContainerHigh, scheme.onSurface, onTap = onAccept)
        }
    }
}

@Composable
fun WatchCard(store: Store, onOpen: (String) -> Unit) {
    val watchers by store.watch.watchers.collectAsStateWithLifecycle()
    val newest by store.watch.newest.collectAsStateWithLifecycle()
    val fresh by store.watch.fresh.collectAsStateWithLifecycle()
    val list = watchers
    val open = list?.let { store.watch.openTriggerCount(it) } ?: 0
    val subtitle = when {
        list == null -> null
        open > 0 -> "$open not accepted"
        else -> "all quiet"
    }?.let { if (fresh) it else "$it · last known" }
    HomeCard {
        CardHeader("watch", subtitle) { onOpen("watch") }
        when {
            list == null -> Label("waiting for the desktop")
            newest.isEmpty() -> Label("nothing fired")
            else -> newest.take(2).forEach { trigger -> TriggerLine(trigger, showWatcher = true, onAccept = null) }
        }
    }
}

@Composable
private fun HealthLines(health: WatchHealth?) {
    val current = health ?: return
    val scheme = MaterialTheme.colorScheme
    if (current.degraded.isEmpty() && current.undecidable.isEmpty()) return
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(scheme.error.copy(alpha = 0.12f)).padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (current.degraded.isNotEmpty()) {
            val reasons = current.degraded.joinToString(", ") { it.replace('_', ' ') }
            Text("watch is degraded · $reasons", style = MaterialTheme.typography.bodyMedium, color = scheme.onSurface)
        }
        current.undecidable.forEach { spec -> Label("undecidable spec · ${spec.name ?: spec.kind ?: spec.id.toString()}", color = scheme.error) }
    }
}

@Composable
fun WatchScreen(store: Store, onCollapse: () -> Unit) {
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val watchers by store.watch.watchers.collectAsStateWithLifecycle()
    val health by store.watch.health.collectAsStateWithLifecycle()
    val fresh by store.watch.fresh.collectAsStateWithLifecycle()
    val expanded by store.watch.expanded.collectAsStateWithLifecycle()
    val triggers by store.watch.triggers.collectAsStateWithLifecycle()
    val working by store.watch.working.collectAsStateWithLifecycle()
    val armed by store.watch.armed.collectAsStateWithLifecycle()
    val composing by store.watch.composing.collectAsStateWithLifecycle()
    val said by store.watch.said.collectAsStateWithLifecycle()
    var draft by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(Unit) {
        while (true) {
            runCatching { store.watch.refresh() }
            delay(15_000)
        }
    }
    DisposableEffect(Unit) { onDispose { store.watch.disarm() } }
    val live = reachable && fresh
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("watch", reachable, onCollapse)
        Banner(reachable)
        val list = watchers
        if (list == null) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth().padding(18.dp), contentAlignment = Alignment.TopStart) {
                Label("waiting for the desktop")
            }
        } else {
            val grouped = list.groupBy { it.section() }
            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(start = 10.dp, end = 10.dp, top = 2.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                item(key = "health") { HealthLines(health) }
                val note = said
                if (note != null) item(key = "said") {
                    Row(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { store.watch.dismissSaid() }.padding(horizontal = 6.dp, vertical = 6.dp)) {
                        Text(note, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.tertiary)
                    }
                }
                if (!fresh) item(key = "stale") { Label("last known", modifier = Modifier.padding(start = 6.dp)) }
                SECTIONS.forEach { (id, title) ->
                    val rows = grouped[id].orEmpty()
                    if (rows.isEmpty()) return@forEach
                    item(key = "h-$id") { Label("$title · ${rows.size}", modifier = Modifier.padding(start = 6.dp, top = 10.dp, bottom = 2.dp)) }
                    items(rows, key = { it.id }) { watcher ->
                        WatcherRow(
                            store = store,
                            watcher = watcher,
                            expanded = expanded == watcher.id,
                            triggers = triggers[watcher.id],
                            working = watcher.id in working,
                            armed = armed == watcher.id,
                            enabled = live,
                        )
                    }
                }
            }
        }
        if (composing) Label("building the watch", modifier = Modifier.padding(horizontal = 18.dp))
        PromptBar(
            value = draft,
            onChange = { draft = it },
            onSend = {
                store.watch.compose(draft)
                draft = ""
            },
            placeholder = "what are you waiting for",
            enabled = reachable && !composing,
        )
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}
