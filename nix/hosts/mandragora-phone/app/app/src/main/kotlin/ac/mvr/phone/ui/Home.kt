package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.HubService
import ac.mvr.phone.net.MpdSong
import ac.mvr.phone.state.Store
import ac.mvr.phone.state.fmtTime
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay

enum class Sheet { Get, Volume, Lyrics, Sync, Hub, Queue }

@Composable
fun VerbCard(title: String, caption: String, enabled: Boolean, hot: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = modifier
            .heightIn(min = 92.dp)
            .clip(RoundedCornerShape(9.dp))
            .background(if (hot) scheme.surfaceContainer else scheme.surfaceContainerLow)
            .border(1.dp, if (hot) scheme.primary else scheme.outlineVariant, RoundedCornerShape(9.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(14.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, color = if (enabled) scheme.onSurface else scheme.outline)
        Spacer(Modifier.height(6.dp))
        Text(caption, style = MaterialTheme.typography.labelMedium, color = scheme.outline, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun HomeScreen(store: Store, onOpenSheet: (Sheet) -> Unit, onOpenStage: () -> Unit, onShare: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val now by store.now.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val mpdReachable by store.mpdReachable.collectAsStateWithLifecycle()
    val volume by store.volume.collectAsStateWithLifecycle()
    val lyrics by store.lyrics.collectAsStateWithLifecycle()
    val folders by store.folders.collectAsStateWithLifecycle()
    val config by store.config.collectAsStateWithLifecycle()
    val busy by store.busy.collectAsStateWithLifecycle()
    var query by remember { mutableStateOf("") }
    var songs by remember { mutableStateOf<List<MpdSong>>(emptyList()) }
    var hosts by remember { mutableStateOf<List<HubService>>(emptyList()) }

    LaunchedEffect(query) {
        val term = query.trim()
        if (term.length < 2 || term.startsWith("http")) { songs = emptyList(); hosts = emptyList(); return@LaunchedEffect }
        delay(250)
        val (s, h) = store.search(term)
        songs = s
        hosts = h
    }

    Column(modifier = Modifier.fillMaxWidth()) {
        TailnetBanner(reachable, now) { store.takeOver("phone") }
        Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("song, host, or paste a link", style = MaterialTheme.typography.labelLarge) },
                leadingIcon = { Icon(Icons.Filled.Search, null, tint = scheme.outline) },
                singleLine = true,
                textStyle = MaterialTheme.typography.labelLarge,
                shape = RoundedCornerShape(9.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = scheme.primary,
                    unfocusedBorderColor = scheme.outlineVariant,
                    focusedContainerColor = scheme.surfaceContainerLow,
                    unfocusedContainerColor = scheme.surfaceContainerLow,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
            val link = query.trim().takeIf { it.startsWith("http://") || it.startsWith("https://") }
            if (link != null) {
                ResultRow(kind = "link", text = link, meta = "→ ytdl") { onShare(link); query = "" }
            }
            if (songs.isNotEmpty() || hosts.isNotEmpty()) {
                LazyColumn(modifier = Modifier.heightIn(max = 220.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    items(songs) { song ->
                        ResultRow(kind = "song", text = song.display, meta = song.pos?.let { "#$it" } ?: "") { store.jumpTo(song); query = "" }
                    }
                    items(hosts) { host ->
                        ResultRow(kind = "host", text = host.host, meta = host.where) { onOpenSheet(Sheet.Hub) }
                    }
                }
            }
        }

        val other = if (now.phoneOwns) "desktop" else "phone"
        val sinkCaption = volume.sink?.let { "${it.name.take(28)} · ${it.volume}%" } ?: "desktop sink"
        val lyricsCaption = when {
            lyrics?.synced != null -> "synced · ${lyrics?.synced?.size} lines"
            lyrics?.plain != null -> "plain text"
            else -> "none for this track"
        }
        Column(modifier = Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                VerbCard("play here", "phone takes the lease", enabled = reachable && !now.phoneOwns && !busy, hot = now.phoneOwns, modifier = Modifier.weight(1f)) {
                    store.takeOver("phone")
                }
                VerbCard("play on desktop", "desktop takes the lease", enabled = reachable && now.phoneOwns && !busy, hot = !now.phoneOwns, modifier = Modifier.weight(1f)) {
                    store.takeOver("desk")
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                VerbCard("take over", "$other resumes at ${fmtTime(now.elapsed)}", enabled = reachable && !busy, hot = true, modifier = Modifier.weight(1f)) {
                    store.takeOver(if (now.phoneOwns) "desk" else "phone")
                }
                VerbCard("get", "ytdl · mp3 or mp4", enabled = reachable, hot = false, modifier = Modifier.weight(1f)) { onOpenSheet(Sheet.Get) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                VerbCard("desktop volume", sinkCaption, enabled = reachable, hot = false, modifier = Modifier.weight(1f)) { onOpenSheet(Sheet.Volume) }
                VerbCard("lyrics", lyricsCaption, enabled = true, hot = false, modifier = Modifier.weight(1f)) { onOpenSheet(Sheet.Lyrics) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                VerbCard("sync", if (folders.isEmpty()) "sync-fork · set the api key" else "${folders.size} folders", enabled = true, hot = false, modifier = Modifier.weight(1f)) { onOpenSheet(Sheet.Sync) }
                VerbCard("hub", "${config?.hub?.services?.size ?: 0} hosts", enabled = config != null, hot = false, modifier = Modifier.weight(1f)) { onOpenSheet(Sheet.Hub) }
            }
        }

        Spacer(Modifier.weight(1f))
        Box(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
            OwnerSwitch(now, deskAvailable = reachable, busy = busy, big = false) { store.takeOver(it) }
        }
        NowStrip(now, enabled = now.phoneOwns || mpdReachable, onOpen = onOpenStage) { store.togglePlay() }
    }
}

@Composable
private fun ResultRow(kind: String, text: String, meta: String, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(5.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            kind.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = scheme.outline,
            modifier = Modifier.border(1.dp, scheme.outlineVariant, RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 1.dp),
        )
        Text(text, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(meta, style = MaterialTheme.typography.labelMedium, color = scheme.outline)
    }
}
