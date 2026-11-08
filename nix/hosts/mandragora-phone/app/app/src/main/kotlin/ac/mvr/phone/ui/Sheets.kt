package ac.mvr.phone.ui

import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.MpdSong
import ac.mvr.phone.state.Store
import ac.mvr.phone.state.fmtTime
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SheetHost(store: Store, sheet: Sheet?, sharedUrl: String?, onDismiss: () -> Unit, onConsumeShare: () -> Unit) {
    if (sheet == null) return
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = state,
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) {
        Column(modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            when (sheet) {
                Sheet.Get -> GetSheet(store, sharedUrl, onConsumeShare)
                Sheet.Volume -> VolumeSheet(store)
                Sheet.Lyrics -> LyricsSheet(store)
                Sheet.Sync -> SyncSheet(store)
                Sheet.Hub -> HubSheet(store)
                Sheet.Queue -> QueueSheet(store, onDismiss)
            }
        }
    }
}

@Composable
private fun SheetTitle(title: String, trailing: String? = null) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        if (trailing != null) Text(trailing, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.outline)
    }
}

@Composable
private fun GetSheet(store: Store, sharedUrl: String?, onConsumeShare: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val jobs by store.jobs.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    var url by remember { mutableStateOf(sharedUrl ?: "") }
    var mode by remember { mutableStateOf("audio") }
    var toClient by remember { mutableStateOf(true) }
    val context = LocalContext.current
    LaunchedEffect(sharedUrl) { if (sharedUrl != null) { url = sharedUrl; onConsumeShare() } }
    LaunchedEffect(Unit) { store.refreshJobs() }

    SheetTitle("get", "ytdl · POST /api/download")
    Notice(store)
    OutlinedTextField(
        value = url,
        onValueChange = { url = it },
        placeholder = { Text("paste a link · youtube, soundcloud, anything yt-dlp eats", style = MaterialTheme.typography.labelLarge) },
        singleLine = true,
        textStyle = MaterialTheme.typography.labelLarge,
        modifier = Modifier.fillMaxWidth(),
    )
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
        Chip("mp3 · tagged by haiku", mode == "audio") { mode = "audio" }
        Chip("mp4", mode == "video") { mode = "video" }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
        Chip("to this phone", toClient) { toClient = true }
        Chip("to desktop · syncs back", !toClient) { toClient = false }
    }
    Button(
        onClick = { if (url.isNotBlank()) { store.download(url, mode, toClient); url = "" } },
        enabled = reachable && url.isNotBlank(),
        colors = ButtonDefaults.buttonColors(containerColor = scheme.primary, contentColor = scheme.onPrimary),
        shape = RoundedCornerShape(9.dp),
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) { Text("download", style = MaterialTheme.typography.labelLarge) }
    Label("history · GET /api/jobs")
    LazyColumn(modifier = Modifier.heightIn(max = 360.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items(jobs, key = { it.id }) { job ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(5.dp))
                    .background(scheme.surfaceContainer)
                    .border(1.dp, scheme.outlineVariant, RoundedCornerShape(5.dp))
                    .padding(horizontal = 10.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                StatusDot(when (job.status) { "done" -> true; "failed", "cancelled", "interrupted" -> false; else -> null })
                Column(modifier = Modifier.weight(1f)) {
                    Text(job.label, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val progress = job.progress?.let { " · ${it.toInt()}%" } ?: ""
                    Text(
                        "${job.mode} · ${if (job.to_client) "to phone" else "to desktop"} · ${job.stage ?: job.status}$progress",
                        style = MaterialTheme.typography.labelSmall,
                        color = scheme.outline,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                when {
                    job.active -> TextButton(onClick = { store.cancelJob(job.id) }) { Text(if (job.cancelling) "cancelling" else "cancel", style = MaterialTheme.typography.labelMedium) }
                    job.has_file -> TextButton(onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(store.ytdl.fileUrl(job.id))))
                    }) { Text("open file", style = MaterialTheme.typography.labelMedium) }
                    else -> Text(if (job.to_client) "expired" else "on desktop", style = MaterialTheme.typography.labelMedium, color = scheme.outline)
                }
            }
        }
    }
}

@Composable
private fun VolumeSheet(store: Store) {
    val scheme = MaterialTheme.colorScheme
    val volume by store.volume.collectAsStateWithLifecycle()
    val now by store.now.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { store.refreshVolume() }
    SheetTitle("desktop volume", volume.sink?.name?.take(30) ?: "")
    VolumeRow(label = "desktop", sub = volume.sink?.name ?: "no sink", value = volume.sink?.volume ?: 0, enabled = reachable && volume.sink != null) { store.setSinkVolumeAsync(it) }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
        volume.sinks.forEach { sink -> Chip(sink.name.take(26), sink.default, enabled = reachable) { store.setDefaultSink(sink.id) } }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Chip(if (volume.sink?.muted == true) "muted" else "mute", volume.sink?.muted == true, enabled = reachable) { store.setSinkMutedAsync(volume.sink?.muted != true) }
    }
    Spacer(Modifier.height(4.dp))
    VolumeRow(label = "mpd", sub = "software mixer", value = now.mpdVolume.coerceAtLeast(0), enabled = store.mpdReachable.value && now.mpdVolume >= 0) { store.setMpdVolume(it) }
    Text("the lock screen's volume keys follow the owner: the desktop sink while the desktop plays, the phone's own volume while the phone plays", style = MaterialTheme.typography.labelSmall, color = scheme.outline)
}

@Composable
private fun VolumeRow(label: String, sub: String, value: Int, enabled: Boolean, onChange: (Int) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var dragging by remember { mutableStateOf<Float?>(null) }
    val shown = dragging ?: (value / 100f)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(modifier = Modifier.width(96.dp)) {
            Label(label)
            Text(sub, style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Slider(
            value = shown,
            onValueChange = { dragging = it },
            onValueChangeFinished = { dragging?.let { onChange((it * 100).toInt()) }; dragging = null },
            enabled = enabled,
            colors = SliderDefaults.colors(thumbColor = scheme.onSurface, activeTrackColor = scheme.primary, inactiveTrackColor = scheme.outlineVariant),
            modifier = Modifier.weight(1f),
        )
        Text("${(shown * 100).toInt()}%", style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant, modifier = Modifier.width(44.dp))
    }
}

@Composable
private fun LyricsSheet(store: Store) {
    val scheme = MaterialTheme.colorScheme
    val lyrics by store.lyrics.collectAsStateWithLifecycle()
    val now by store.now.collectAsStateWithLifecycle()
    val busy by store.lyricsBusy.collectAsStateWithLifecycle()
    SheetTitle("lyrics", lyrics?.source ?: "")
    Text(listOfNotNull(now.artist, now.title).joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
    val synced = lyrics?.synced
    when {
        synced != null && synced.isNotEmpty() -> LazyColumn(modifier = Modifier.heightIn(max = 420.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val current = synced.indexOfLast { it.t <= now.elapsed }
            itemsIndexed(synced) { index, line ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(fmtTime(line.t), style = MaterialTheme.typography.labelSmall, color = scheme.outline, modifier = Modifier.width(40.dp))
                    Text(line.x, style = MaterialTheme.typography.bodyLarge, color = if (index == current) scheme.onSurface else scheme.onSurfaceVariant)
                }
            }
        }
        lyrics?.plain != null -> LazyColumn(modifier = Modifier.heightIn(max = 420.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(lyrics!!.plain!!.lines()) { line -> Text(line, style = MaterialTheme.typography.bodyLarge, color = scheme.onSurfaceVariant) }
        }
        else -> Text(if (busy) "fetching…" else "no lyrics stored for this track; the bridge asks lrclib when a track plays and keeps the .lrc beside the file", style = MaterialTheme.typography.bodyMedium, color = scheme.outline)
    }
    if (now.file != null) {
        OutlinedButton(onClick = { now.file?.let { store.loadLyrics(it) } }, enabled = !busy) { Text("fetch again", style = MaterialTheme.typography.labelLarge) }
    }
}

@Composable
private fun SyncSheet(store: Store) {
    val scheme = MaterialTheme.colorScheme
    val folders by store.folders.collectAsStateWithLifecycle()
    val hasKey by store.hasApiKey.collectAsStateWithLifecycle()
    val busy by store.syncBusy.collectAsStateWithLifecycle()
    val error by store.syncError.collectAsStateWithLifecycle()
    val localCount by store.localCount.collectAsStateWithLifecycle()
    var key by remember { mutableStateOf("") }
    LaunchedEffect(hasKey) { if (hasKey) store.refreshFolders() }
    SheetTitle("sync", "sync-fork · 127.0.0.1:8384")
    Text("$localCount tracks on this phone", style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant)
    if (!hasKey) {
        Text("paste Sync-Fork's api key once (Settings → GUI → API Key). it stays on this phone.", style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
        OutlinedTextField(value = key, onValueChange = { key = it }, singleLine = true, placeholder = { Text("api key") }, textStyle = MaterialTheme.typography.labelLarge, modifier = Modifier.fillMaxWidth())
        Button(onClick = { store.setApiKey(key); key = "" }, enabled = key.isNotBlank(), shape = RoundedCornerShape(9.dp)) { Text("save", style = MaterialTheme.typography.labelLarge) }
        return
    }
    if (error != null) Text(error!!, style = MaterialTheme.typography.labelMedium, color = scheme.error)
    LazyColumn(modifier = Modifier.heightIn(max = 380.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        items(folders, key = { it.id }) { folder ->
            Row(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatusDot(when { folder.paused -> null; folder.state == "idle" -> true; folder.state.isEmpty() -> null; else -> true })
                Text(folder.direction, style = MaterialTheme.typography.labelMedium, color = scheme.outline, modifier = Modifier.width(18.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(folder.label, style = MaterialTheme.typography.bodyMedium)
                    Text("${folder.type} · ${folder.state.ifBlank { "unknown" }}${if (folder.needFiles > 0) " · ${folder.needFiles} to go" else ""}", style = MaterialTheme.typography.labelSmall, color = scheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text(folder.localFiles.toString(), style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant)
            }
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = { store.rescan() }, enabled = !busy) { Text(if (busy) "scanning…" else "rescan", style = MaterialTheme.typography.labelLarge) }
        TextButton(onClick = { store.setApiKey("") }) { Text("forget key", style = MaterialTheme.typography.labelMedium) }
    }
}

@Composable
private fun HubSheet(store: Store) {
    val scheme = MaterialTheme.colorScheme
    val config by store.config.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val manifest = config?.hub
    SheetTitle("hub", "${manifest?.services?.size ?: 0} hosts")
    if (manifest == null) {
        Text("the hub manifest arrives with the bridge config", style = MaterialTheme.typography.bodyMedium, color = scheme.outline)
        return
    }
    val groups = manifest.groups.map { it.id }.ifEmpty { manifest.services.map { it.group }.distinct() }
    LazyColumn(modifier = Modifier.heightIn(max = 560.dp)) {
        groups.forEach { group ->
            val services = manifest.services.filter { it.group == group }
            if (services.isEmpty()) return@forEach
            item {
                Row(modifier = Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Label(group)
                    Box(modifier = Modifier.weight(1f).height(1.dp).background(scheme.outlineVariant))
                    Text(services.size.toString(), style = MaterialTheme.typography.labelSmall, color = scheme.outline)
                }
            }
            items(services, key = { it.host + it.name }) { service ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(5.dp))
                        .clickable {
                            val url = service.url ?: "https://${service.host}"
                            runCatching { CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url)) }
                                .onFailure { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                        }
                        .padding(horizontal = 8.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    StatusDot(if (service.where == "desk") reachable else true)
                    Box(
                        modifier = Modifier
                            .size(22.dp)
                            .clip(RoundedCornerShape(5.dp))
                            .background(if (service.access == "open") scheme.primary else scheme.surfaceContainerHigh)
                            .border(1.dp, if (service.access == "open") scheme.primary else scheme.outlineVariant, RoundedCornerShape(5.dp)),
                        contentAlignment = Alignment.Center,
                    ) { Text(if (service.access == "open") "○" else "●", style = MaterialTheme.typography.labelSmall, color = if (service.access == "open") scheme.onPrimary else scheme.outline) }
                    Column(modifier = Modifier.weight(1f)) {
                        Text(service.host, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("${service.name} · ${service.desc} · ${service.where}", style = MaterialTheme.typography.labelSmall, color = scheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

@Composable
private fun QueueSheet(store: Store, onDismiss: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val now by store.now.collectAsStateWithLifecycle()
    var songs by remember { mutableStateOf<List<MpdSong>>(emptyList()) }
    val listState = rememberLazyListState()
    LaunchedEffect(now.pos) {
        songs = runCatching { store.queueWindow() }.getOrDefault(emptyList())
        val index = songs.indexOfFirst { it.pos == now.pos }
        if (index > 2) listState.scrollToItem(index - 2)
    }
    SheetTitle("queue", "${now.queueLength} · window around #${now.pos?.plus(1) ?: 0}")
    LazyColumn(state = listState, modifier = Modifier.heightIn(max = 560.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        items(songs, key = { it.id ?: it.pos ?: it.file.hashCode() }) { song ->
            val current = song.pos == now.pos
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(5.dp))
                    .background(if (current) scheme.primaryContainer else scheme.surfaceContainerLow)
                    .clickable { store.jumpTo(song); onDismiss() }
                    .padding(horizontal = 8.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(((song.pos ?: 0) + 1).toString(), style = MaterialTheme.typography.labelSmall, color = if (current) scheme.primary else scheme.outline, modifier = Modifier.width(40.dp))
                Text(song.display, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(song.duration?.let { fmtTime(it) } ?: "", style = MaterialTheme.typography.labelSmall, color = scheme.outline)
            }
        }
    }
}
