package ac.mvr.phone.ui

import android.text.format.DateUtils
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle

private val CARD_NAMES = mapOf("music" to "music", "money" to "money", "hub" to "hub", "code" to "code", "panic" to "panic")

@Composable
fun SettingsScreen(store: Store, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val order by store.prefs.cardOrder.collectAsStateWithLifecycle()
    val autoplay by store.prefs.autoplaySkip.collectAsStateWithLifecycle()
    val codeCount by store.prefs.codeCardCount.collectAsStateWithLifecycle()
    val squash by store.prefs.squashCalls.collectAsStateWithLifecycle()
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("settings", reachable, onCollapse)
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 14.dp).padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
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
                    Text("sessions on the card", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                    IconButton(onClick = { store.prefs.setCodeCardCount(codeCount - 1) }, enabled = codeCount > 1, modifier = Modifier.size(40.dp)) {
                        Icon(Icons.Filled.KeyboardArrowDown, "fewer", tint = if (codeCount > 1) scheme.onSurface else scheme.outlineVariant)
                    }
                    Text("$codeCount", style = MaterialTheme.typography.titleMedium)
                    IconButton(onClick = { store.prefs.setCodeCardCount(codeCount + 1) }, enabled = codeCount < 8, modifier = Modifier.size(40.dp)) {
                        Icon(Icons.Filled.KeyboardArrowUp, "more", tint = if (codeCount < 8) scheme.onSurface else scheme.outlineVariant)
                    }
                }
                Label("the chevron on the card opens every session")
                Row(modifier = Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("squash call chains", style = MaterialTheme.typography.bodyLarge)
                        Label(if (squash) "two or more calls in a row show as one line; tap it to open" else "every command, skill and edit gets its own line")
                    }
                    Switch(checked = squash, onCheckedChange = { store.prefs.setSquashCalls(it) })
                }
            }
            PhotosSection(store)
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

private fun moved(order: List<String>, index: Int, step: Int): List<String> {
    val target = index + step
    if (target !in order.indices) return order
    val next = order.toMutableList()
    next[index] = order[target]
    next[target] = order[index]
    return next
}
