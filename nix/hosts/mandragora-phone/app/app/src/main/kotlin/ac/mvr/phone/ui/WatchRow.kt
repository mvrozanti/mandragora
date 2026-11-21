package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.WatchTrigger
import ac.mvr.phone.net.Watcher
import ac.mvr.phone.state.Store

@Composable
private fun WatcherHead(store: Store, watcher: Watcher, working: Boolean) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { store.watch.expand(watcher.id) }.padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(watcher.title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Label(watcher.caption(), color = if (watcher.lastError != null) scheme.error else scheme.outline)
        }
        if (working) {
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
        } else if (watcher.openTriggerCount > 0) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(if (watcher.push) scheme.primary else scheme.surfaceContainerHigh)
                    .padding(horizontal = 10.dp, vertical = 4.dp),
            ) {
                Text("${watcher.openTriggerCount}", style = MaterialTheme.typography.labelLarge, color = if (watcher.push) scheme.onPrimary else scheme.onSurface)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WatcherActions(store: Store, watcher: Watcher, armed: Boolean, usable: Boolean) {
    val scheme = MaterialTheme.colorScheme
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (watcher.openTriggerCount > 0) ChatChip("accept all", scheme.primary, scheme.onPrimary, usable) { store.watch.ackAll(watcher.id) }
        ChatChip(if (watcher.enabled) "pause" else "resume", scheme.surfaceContainerHigh, scheme.onSurface, usable) { store.watch.toggle(watcher.id) }
        ChatChip("poll now", scheme.surfaceContainerHigh, scheme.onSurface, usable) { store.watch.poll(watcher.id) }
        val places = store.watch.places(watcher)
        val dropText = when {
            armed -> "tap again"
            watcher.watchId != null && places > 1 -> "delete · $places places"
            else -> "delete"
        }
        val tone = if (armed) scheme.error else scheme.errorContainer
        ChatChip(dropText, tone, if (armed) scheme.onError else scheme.onErrorContainer, usable) { store.watch.tapDelete(watcher) }
    }
}

@Composable
private fun WatcherFired(store: Store, triggers: List<WatchTrigger>?, enabled: Boolean) {
    when {
        triggers == null -> Label("loading what fired")
        triggers.isEmpty() -> Label("nothing has fired yet")
        else -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            triggers.forEach { trigger ->
                TriggerLine(trigger, showWatcher = false, onAccept = if (enabled) ({ store.watch.ack(trigger.id) }) else null)
            }
        }
    }
}

@Composable
internal fun WatcherRow(
    store: Store,
    watcher: Watcher,
    expanded: Boolean,
    triggers: List<WatchTrigger>?,
    working: Boolean,
    armed: Boolean,
    enabled: Boolean,
) {
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(if (expanded) scheme.surfaceContainerLow else Color.Transparent)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        WatcherHead(store, watcher, working)
        if (!expanded) return@Column
        val condition = watcher.condition
        if (!condition.isNullOrBlank() && condition != watcher.title) {
            Text(condition, style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
        }
        watcher.lastError?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = scheme.error, maxLines = 3, overflow = TextOverflow.Ellipsis) }
        WatcherActions(store, watcher, armed, enabled && !working)
        WatcherFired(store, triggers, enabled)
    }
}
