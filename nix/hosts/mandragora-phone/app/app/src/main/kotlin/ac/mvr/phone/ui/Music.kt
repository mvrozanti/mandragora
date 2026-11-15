package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun MusicScreen(store: Store, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val now by store.now.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val volume by store.volume.collectAsStateWithLifecycle()
    val lyrics by store.lyrics.collectAsStateWithLifecycle()
    val lyricsBusy by store.lyricsBusy.collectAsStateWithLifecycle()
    val busy by store.busy.collectAsStateWithLifecycle()
    var showLyrics by remember { mutableStateOf(false) }
    var find by rememberSaveable { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("music", reachable, onCollapse)
        Banner(reachable)
        Box(modifier = Modifier.padding(horizontal = 14.dp)) {
            VolumeBar(volume, enabled = reachable, onDrag = store::dragSinkVolume) {
                store.setSinkMutedAsync(volume.sink?.muted != true)
            }
        }
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = 22.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth().padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                if (showLyrics) {
                    LyricsPane(lyrics, now.elapsed, lyricsBusy, Modifier.fillMaxSize().clickable { showLyrics = false })
                } else {
                    Cover(
                        now,
                        Modifier
                            .fillMaxHeight()
                            .aspectRatio(1f, matchHeightConstraintsFirst = true)
                            .widthIn(max = 300.dp)
                            .clip(RoundedCornerShape(20.dp))
                            .clickable { showLyrics = true },
                    )
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(now.title, style = MaterialTheme.typography.headlineMedium, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(now.artist ?: "", style = MaterialTheme.typography.bodyLarge, color = scheme.onSurfaceVariant, textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            ProgressRow(now) { store.seek(it) }
            Transport(now, onToggle = store::togglePlay, onNext = store::next, onPrevious = store::previous)
            Label(now.next?.let { "next · $it" } ?: "")
            OwnerSwitch(now, deskReachable = reachable, busy = busy) { store.takeOver(it) }
            Notice(store)
        }
        FindBar { find = true }
    }
    if (find) FindSheet(store) { find = false }
}

@Composable
private fun FindBar(onFind: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = Modifier.fillMaxWidth().background(scheme.surfaceContainerLow).padding(top = 8.dp, bottom = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(999.dp))
                .background(scheme.surfaceContainerHigh)
                .clickable(onClick = onFind)
                .padding(horizontal = 22.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Search, null, tint = scheme.onSurface, modifier = Modifier.size(18.dp))
            Text("play something", style = MaterialTheme.typography.bodyLarge)
        }
    }
}

@Composable
fun MusicCard(store: Store, onOpen: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val now by store.now.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val volume by store.volume.collectAsStateWithLifecycle()
    val place = if (now.phoneOwns) "on the phone" else "on the desktop"
    val state = if (now.playing) "playing" else "paused"
    HomeCard {
        CardHeader("music", now.next?.let { "next · $it" }) { onOpen("music") }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).clickable { onOpen("music") },
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Cover(now, Modifier.size(56.dp), corner = 12.dp)
                Column(modifier = Modifier.weight(1f)) {
                    Text(now.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(now.artist ?: "", style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Label("$state $place" + if (reachable) "" else " · desktop unreachable")
                }
            }
            Box(
                modifier = Modifier.size(52.dp).clip(CircleShape).background(scheme.primary).clickable(onClick = store::togglePlay),
                contentAlignment = Alignment.Center,
            ) {
                Icon(if (now.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (now.playing) "pause" else "play", tint = scheme.onPrimary, modifier = Modifier.size(28.dp))
            }
        }
        VolumeBar(volume, enabled = reachable, onDrag = store::dragSinkVolume) {
            store.setSinkMutedAsync(volume.sink?.muted != true)
        }
    }
}
