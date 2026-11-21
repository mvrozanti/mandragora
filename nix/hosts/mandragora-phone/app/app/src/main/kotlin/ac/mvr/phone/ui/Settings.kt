package ac.mvr.phone.ui

import android.text.format.DateUtils
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LifecycleResumeEffect
import ac.mvr.phone.inbox.InboxService
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle

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
)

@SuppressLint("BatteryLife")
private fun askBatteryExemption(context: Context) {
    runCatching { context.startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}"))) }
}

private fun batteryExempt(context: Context): Boolean =
    context.getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(context.packageName) ?: true

@Composable
fun SettingsScreen(store: Store, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val order by store.prefs.cardOrder.collectAsStateWithLifecycle()
    val autoplay by store.prefs.autoplaySkip.collectAsStateWithLifecycle()
    val squash by store.prefs.squashCalls.collectAsStateWithLifecycle()
    val listen by store.prefs.inboxListen.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var exempt by remember { mutableStateOf(batteryExempt(context)) }
    LifecycleResumeEffect(Unit) {
        exempt = batteryExempt(context)
        onPauseOrDispose { }
    }
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
                Label("alerts")
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("listen in the background", style = MaterialTheme.typography.bodyLarge)
                        Label(if (listen) "desktop alerts arrive as notifications" else "alerts wait in the inbox until the app opens")
                    }
                    Switch(checked = listen, onCheckedChange = {
                        store.prefs.setInboxListen(it)
                        InboxService.sync(context)
                    })
                }
                if (listen && !exempt) {
                    Row(
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { askBatteryExemption(context) }.padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("battery is restricted", style = MaterialTheme.typography.bodyLarge, color = scheme.error)
                            Label("tap to let the listener run while the phone sleeps")
                        }
                    }
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
