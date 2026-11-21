package ac.mvr.phone.ui

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.inbox.Alerts
import ac.mvr.phone.net.InboxItem
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay

private fun since(ts: Double): String {
    val seconds = (System.currentTimeMillis() / 1000.0 - ts).toLong().coerceAtLeast(0)
    return when {
        seconds < 60 -> "now"
        seconds < 3600 -> "${seconds / 60} min"
        seconds < 86_400 -> "${seconds / 3600} h"
        else -> "${seconds / 86_400} d"
    }
}

@Composable
private fun ActionChip(text: String, tone: Color, onTone: Color, onTap: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(tone)
            .clickable(onClick = onTap)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge, color = onTone)
    }
}

@Composable
private fun InboxLine(item: InboxItem, fresh: Boolean) {
    val scheme = MaterialTheme.colorScheme
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (fresh) Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(if (item.alert) scheme.error else scheme.primary))
            Label("${item.title} · ${since(item.ts)}", color = if (item.alert) scheme.error else scheme.outline)
        }
        Text(item.text.lineSequence().firstOrNull() ?: "", style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun InboxCard(store: Store, onOpen: (String) -> Unit) {
    val items by store.inbox.items.collectAsStateWithLifecycle()
    val unread by store.inbox.unread.collectAsStateWithLifecycle()
    val read by store.inbox.read.collectAsStateWithLifecycle()
    val live by store.inbox.live.collectAsStateWithLifecycle()
    val subtitle = when {
        unread > 0 -> "$unread new"
        live -> "listening"
        else -> "not listening"
    }
    HomeCard {
        CardHeader("inbox", subtitle) { onOpen("inbox") }
        val newest = items.takeLast(2).reversed()
        if (newest.isEmpty()) Label("nothing from the desktop yet")
        newest.forEach { item ->
            Box(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { onOpen("inbox") }) {
                InboxLine(item, item.id > read)
            }
        }
    }
}

@Composable
private fun InboxRow(item: InboxItem, fresh: Boolean, onOpen: (String) -> Unit, onAccept: (Long) -> Unit, onDismiss: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val uri = LocalUriHandler.current
    var expanded by rememberSaveable(item.id) { mutableStateOf(false) }
    val event = Alerts.watchEvent(item)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(if (item.alert && fresh) scheme.error.copy(alpha = 0.10f) else scheme.surfaceContainerLow)
            .clickable { expanded = !expanded }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (fresh) Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(if (item.alert) scheme.error else scheme.primary))
            Label("${item.source} · ${since(item.ts)}", color = if (item.alert) scheme.error else scheme.outline)
        }
        Text(item.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(
            item.text,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = if (expanded) Int.MAX_VALUE else 4,
            overflow = TextOverflow.Ellipsis,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val target = item.open
            if (target != null && target != "inbox") ActionChip("open $target", scheme.primaryContainer, scheme.onPrimaryContainer) { onOpen(target) }
            if (event != null) ActionChip("accept", scheme.secondaryContainer, scheme.onSecondaryContainer) { onAccept(event) }
            item.link?.let { link -> ActionChip("link", scheme.surfaceContainerHigh, scheme.onSurface) { runCatching { uri.openUri(link) } } }
            ActionChip("dismiss", scheme.surfaceContainerHigh, scheme.onSurfaceVariant, onDismiss)
        }
    }
}

@Composable
fun InboxScreen(store: Store, onCollapse: () -> Unit, onOpen: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val items by store.inbox.items.collectAsStateWithLifecycle()
    val live by store.inbox.live.collectAsStateWithLifecycle()
    val readAtOpen = remember { store.inbox.read.value }
    var armed by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        store.inbox.viewing.value = true
        onDispose { store.inbox.viewing.value = false }
    }
    LaunchedEffect(items.lastOrNull()?.id) { store.inbox.markRead() }
    LaunchedEffect(armed) {
        if (armed) {
            delay(4_000)
            armed = false
        }
    }
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("inbox", reachable, onCollapse)
        Banner(reachable)
        if (items.isEmpty()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth().padding(18.dp), contentAlignment = Alignment.TopStart) {
                Label(if (live) "nothing from the desktop yet" else "waiting for the desktop")
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(start = 14.dp, end = 14.dp, top = 2.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Label(if (live) "listening · newest first" else "not listening · last known")
                        ActionChip(
                            if (armed) "tap again" else "clear all",
                            if (armed) scheme.error else scheme.surfaceContainerHigh,
                            if (armed) scheme.onError else scheme.onSurface,
                        ) {
                            if (armed) {
                                armed = false
                                store.inbox.clear()
                            } else {
                                armed = true
                            }
                        }
                    }
                }
                items(items.asReversed(), key = { it.id }) { item ->
                    InboxRow(
                        item,
                        fresh = item.id > readAtOpen,
                        onOpen = onOpen,
                        onAccept = { event ->
                            store.watch.ack(event)
                            store.inbox.dismiss(item.id)
                        },
                        onDismiss = { store.inbox.dismiss(item.id) },
                    )
                }
            }
        }
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}
