package ac.mvr.phone.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun StageScreen(store: Store, onHome: () -> Unit, onOpenSheet: (Sheet) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val now by store.now.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val mpdReachable by store.mpdReachable.collectAsStateWithLifecycle()
    val volume by store.volume.collectAsStateWithLifecycle()
    val lyrics by store.lyrics.collectAsStateWithLifecycle()
    val lyricsBusy by store.lyricsBusy.collectAsStateWithLifecycle()
    val busy by store.busy.collectAsStateWithLifecycle()
    val controlsEnabled = now.phoneOwns || mpdReachable
    val listState = rememberLazyListState()
    val synced = lyrics?.synced
    val currentLine = synced?.indexOfLast { it.t <= now.elapsed } ?: -1

    LaunchedEffect(currentLine) {
        if (currentLine >= 0) listState.animateScrollToItem((currentLine - 2).coerceAtLeast(0))
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            TailnetBanner(reachable, now) { store.takeOver("phone") }
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onHome) { Label("◂ verbs", color = scheme.onSurfaceVariant) }
                TextButton(onClick = { onOpenSheet(Sheet.Get) }, enabled = reachable) { Label("get", color = if (reachable) scheme.onSurfaceVariant else scheme.outline) }
                TextButton(onClick = { onOpenSheet(Sheet.Sync) }) { Label("sync", color = scheme.onSurfaceVariant) }
            }
            Box(modifier = Modifier.weight(1f).fillMaxWidth().padding(start = 20.dp, end = 64.dp)) {
                when {
                    synced != null && synced.isNotEmpty() -> LazyColumn(state = listState, verticalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.fillMaxSize()) {
                        itemsIndexed(synced) { index, line ->
                            Text(
                                line.x.ifBlank { "…" },
                                style = MaterialTheme.typography.headlineMedium.copy(fontWeight = if (index == currentLine) FontWeight.SemiBold else FontWeight.Normal),
                                color = when {
                                    index == currentLine -> scheme.onSurface
                                    index < currentLine -> scheme.onSurfaceVariant
                                    else -> scheme.outline
                                },
                            )
                        }
                        item { Spacer(Modifier.height(240.dp)) }
                    }
                    lyrics?.plain != null -> LazyColumn(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        item { Label("plain lyrics · no timing", color = scheme.outline) }
                        itemsIndexed(lyrics!!.plain!!.lines()) { _, line -> Text(line, style = MaterialTheme.typography.bodyLarge, color = scheme.onSurfaceVariant) }
                        item { Spacer(Modifier.height(240.dp)) }
                    }
                    else -> Column(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            if (lyricsBusy) "fetching lyrics…" else if (now.file == null) "nothing playing" else "no lyrics for this track yet",
                            style = MaterialTheme.typography.labelLarge,
                            color = scheme.outline,
                        )
                        if (!lyricsBusy && now.file != null && reachable) {
                            TextButton(onClick = { now.file?.let { store.loadLyrics(it) } }) { Text("ask lrclib again", style = MaterialTheme.typography.labelLarge) }
                        }
                    }
                }
            }
            Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Cover(now, Modifier.size(64.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(now.title, style = MaterialTheme.typography.headlineMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            listOfNotNull(now.artist, now.whereLabel).joinToString(" · "),
                            style = MaterialTheme.typography.labelMedium,
                            color = scheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                ProgressRow(now, enabled = controlsEnabled) { store.seek(it) }
                Notice(store)
                OwnerSwitch(now, deskAvailable = reachable, busy = busy, big = true) { store.takeOver(it) }
                Transport(
                    now,
                    enabled = controlsEnabled,
                    flagsEnabled = mpdReachable,
                    onToggle = { store.togglePlay() },
                    onNext = { store.next() },
                    onPrevious = { store.previous() },
                    onRepeat = { store.setFlag("repeat", !now.repeat) },
                    onRandom = { store.setFlag("random", !now.random) },
                )
                TextButton(onClick = { onOpenSheet(Sheet.Queue) }, enabled = mpdReachable, modifier = Modifier.fillMaxWidth()) {
                    Label("▴ queue · #${now.pos?.plus(1) ?: 0} of ${now.queueLength}", color = scheme.outline)
                }
            }
        }
        Box(modifier = Modifier.align(Alignment.CenterEnd).fillMaxHeight(0.38f).padding(end = 6.dp)) {
            SinkRail(volume, enabled = reachable) { store.setSinkVolumeAsync(it) }
        }
    }
}
