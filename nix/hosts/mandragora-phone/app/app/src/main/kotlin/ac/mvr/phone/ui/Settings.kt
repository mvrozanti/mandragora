package ac.mvr.phone.ui

import android.text.format.DateUtils
import android.text.format.Formatter
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import ac.mvr.phone.inbox.InboxService
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import ac.mvr.phone.state.MirrorStatus
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch

private val CARD_NAMES = mapOf(
    "music" to "music",
    "inbox" to "inbox",
    "money" to "money",
    "hub" to "hub",
    "code" to "code",
    "ask" to "ask · the local model",
    "voice" to "voice · speech to text",
    "teach" to "teach · the tutor",
    "watch" to "watch",
    "panic" to "panic",
    "gpu" to "gpu · vram and who holds it",
    "power" to "power · reboot or power off the desktop",
)

@Composable
fun SettingsScreen(store: Store, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val order by store.prefs.cardOrder.collectAsStateWithLifecycle()
    val autoplay by store.prefs.autoplaySkip.collectAsStateWithLifecycle()
    val squash by store.prefs.squashCalls.collectAsStateWithLifecycle()
    val listen by store.prefs.inboxListen.collectAsStateWithLifecycle()
    val context = LocalContext.current
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("settings", reachable, onCollapse)
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 14.dp).padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            AuditSection(store)
            Column(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(scheme.surfaceContainerLow).padding(horizontal = 16.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Label("home cards · in this order")
                order.forEachIndexed { index, card ->
                    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(CARD_NAMES[card] ?: card, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                        IconButton(onClick = { store.prefs.setCardOrder(moved(order, index, -1)) }, enabled = index > 0, modifier = Modifier.size(40.dp)) {
                            Icon(Icons.Filled.KeyboardArrowUp, "move $card up", tint = if (index > 0) scheme.onSurface else scheme.outlineVariant)
                        }
                        IconButton(onClick = { store.prefs.setCardOrder(moved(order, index, 1)) }, enabled = index < order.lastIndex, modifier = Modifier.size(40.dp)) {
                            Icon(Icons.Filled.KeyboardArrowDown, "move $card down", tint = if (index < order.lastIndex) scheme.onSurface else scheme.outlineVariant)
                        }
                    }
                }
                Label("the update line always comes first")
            }
            Column(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(scheme.surfaceContainerLow).padding(horizontal = 16.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Label("alerts")
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("listen in the background", style = MaterialTheme.typography.bodyLarge)
                        Label(if (listen) "desktop alerts arrive as notifications" else "alerts wait in the inbox until the app opens")
                    }
                    Switch(checked = listen, onCheckedChange = {
                        store.prefs.setInboxListen(it)
                        InboxService.sync(context)
                        store.scope.launch { runCatching { store.audit.refresh() } }
                    })
                }
            }
            Column(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(scheme.surfaceContainerLow).padding(horizontal = 16.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Label("music")
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("next and prev start playback", style = MaterialTheme.typography.bodyLarge)
                        Label(if (autoplay) "a skip while paused plays the new song" else "a skip while paused stays paused")
                    }
                    Switch(checked = autoplay, onCheckedChange = { store.prefs.setAutoplaySkip(it) })
                }
            }
            Column(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(scheme.surfaceContainerLow).padding(horizontal = 16.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Label("code")
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("squash call chains", style = MaterialTheme.typography.bodyLarge)
                        Label(if (squash) "two or more calls in a row show as one line; tap it to open" else "every command, skill and edit gets its own line")
                    }
                    Switch(checked = squash, onCheckedChange = { store.prefs.setSquashCalls(it) })
                }
            }
            PhotosSection(store)
            MusicSection(store)
        }
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}

@Composable
private fun PhotosSection(store: Store) {
    val scheme = MaterialTheme.colorScheme
    val context = LocalContext.current
    val allowed by store.photos.allowed.collectAsStateWithLifecycle()
    val contact by store.photos.lastContactMs.collectAsStateWithLifecycle()
    val moved by store.photos.moved.collectAsStateWithLifecycle()
    val detail = when {
        !allowed -> "off · the switch opens Android's all files access for this app"
        contact == 0L -> "on · not in touch with the desktop yet"
        else -> "on · last in touch ${DateUtils.getRelativeTimeSpanString(contact)}" + if (moved > 0) " · $moved moved off the phone" else ""
    }
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(scheme.surfaceContainerLow).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Label("photos")
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text("the desktop reaches photos and videos", style = MaterialTheme.typography.bodyLarge)
                Label(detail)
            }
            Switch(checked = allowed, onCheckedChange = { context.startActivity(store.photos.accessSettings()) })
        }
        Label("it copies what it asks for, checks the copy, and only then deletes it here")
    }
}

@Composable
private fun MusicSection(store: Store) {
    val scheme = MaterialTheme.colorScheme
    val context = LocalContext.current
    val allowed by store.photos.allowed.collectAsStateWithLifecycle()
    val status by store.music.status.collectAsStateWithLifecycle()
    val detail = musicDetail(allowed, status, Formatter.formatShortFileSize(context, status.leftBytes))
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(scheme.surfaceContainerLow).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Label("music")
        Text("the desktop's library, kept on this phone", style = MaterialTheme.typography.bodyLarge)
        Label(detail)
        Label("over Wi-Fi, about once an hour; a song the desktop deletes leaves the phone too, and nothing else in Music is touched")
    }
}

private fun musicDetail(allowed: Boolean, status: MirrorStatus, left: String): String {
    val checked = if (status.doneAtMs > 0) " · checked ${DateUtils.getRelativeTimeSpanString(status.doneAtMs)}" else ""
    return when {
        !allowed -> "off · it needs all files access, the switch above"
        status.error != null -> "stopped · ${status.error}"
        status.total == 0 -> if (status.running) "copying for the first time" else "waits for Wi-Fi"
        status.have < status.total -> "${status.have} of ${status.total} files · $left to go" + if (status.running) " · copying" else ""
        else -> "all ${status.total} files$checked"
    }
}

private fun moved(order: List<String>, index: Int, step: Int): List<String> {
    val target = index + step
    if (target !in order.indices) return order
    val next = order.toMutableList()
    next[index] = order[target]
    next[target] = order[index]
    return next
}
