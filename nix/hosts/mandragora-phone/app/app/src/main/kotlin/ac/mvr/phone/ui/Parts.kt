package ac.mvr.phone.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.Smartphone
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.Lyrics
import ac.mvr.phone.net.VolumeState
import ac.mvr.phone.state.NowState
import ac.mvr.phone.state.Store
import ac.mvr.phone.state.fmtTime
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlin.math.roundToInt

private fun shortSink(name: String): String {
    val tag = Regex("\\[(.*?)\\]").find(name)?.groupValues?.get(1)
    val kind = when {
        name.contains("HDMI") -> "hdmi"
        name.contains("IEC958") -> "spdif"
        else -> null
    }
    return listOfNotNull(kind, tag).joinToString(" · ").ifEmpty { name.take(24) }
}

@Composable
fun VolumeBar(volume: VolumeState, enabled: Boolean, onDrag: (Int) -> Unit, onMute: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val sink = volume.sink
    var dragging by remember { mutableStateOf<Float?>(null) }
    val muted = sink?.muted == true
    val value = dragging ?: if (muted) 0f else (sink?.volume ?: 0) / 100f
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(scheme.surfaceContainerLow)
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .alpha(if (enabled) 1f else 0.45f),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Label("desktop volume")
            Label(sink?.name?.let(::shortSink) ?: "")
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            IconButton(onClick = onMute, enabled = enabled) {
                Icon(if (muted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp, "mute", tint = scheme.onSurfaceVariant)
            }
            Slider(
                value = value,
                onValueChange = { dragging = it; onDrag((it * 100).roundToInt()) },
                onValueChangeFinished = { dragging?.let { onDrag((it * 100).roundToInt()) }; dragging = null },
                enabled = enabled,
                modifier = Modifier.weight(1f),
                colors = SliderDefaults.colors(thumbColor = scheme.onSurface, activeTrackColor = scheme.primary, inactiveTrackColor = scheme.outlineVariant),
            )
            Text(
                if (muted && dragging == null) "mute" else "${(value * 100).roundToInt()}",
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.End,
                modifier = Modifier.width(46.dp),
            )
        }
    }
}

@Composable
fun Transport(now: NowState, onToggle: () -> Unit, onNext: () -> Unit, onPrevious: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(22.dp, Alignment.CenterHorizontally), modifier = Modifier.fillMaxWidth()) {
        IconButton(onClick = onPrevious, modifier = Modifier.size(56.dp)) {
            Icon(Icons.Filled.SkipPrevious, "previous", tint = scheme.onSurface, modifier = Modifier.size(32.dp))
        }
        Box(
            modifier = Modifier.size(76.dp).clip(CircleShape).background(scheme.primary).clickable(onClick = onToggle),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (now.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                if (now.playing) "pause" else "play",
                tint = scheme.onPrimary,
                modifier = Modifier.size(38.dp),
            )
        }
        IconButton(onClick = onNext, modifier = Modifier.size(56.dp)) {
            Icon(Icons.Filled.SkipNext, "next", tint = scheme.onSurface, modifier = Modifier.size(32.dp))
        }
    }
}

@Composable
fun ProgressRow(now: NowState, onSeek: (Double) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var dragging by remember { mutableStateOf<Float?>(null) }
    val duration = now.duration.coerceAtLeast(1.0)
    val value = dragging ?: (now.elapsed / duration).toFloat().coerceIn(0f, 1f)
    Column {
        Slider(
            value = value,
            onValueChange = { dragging = it },
            onValueChangeFinished = {
                dragging?.let { onSeek(it * duration) }
                dragging = null
            },
            colors = SliderDefaults.colors(thumbColor = scheme.onSurface, activeTrackColor = scheme.primary, inactiveTrackColor = scheme.outlineVariant),
        )
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(fmtTime(value * duration), style = MaterialTheme.typography.labelMedium, color = scheme.outline)
            Text(fmtTime(duration), style = MaterialTheme.typography.labelMedium, color = scheme.outline)
        }
    }
}

@Composable
fun OwnerSwitch(now: NowState, deskReachable: Boolean, busy: Boolean, onTake: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val knob by animateFloatAsState(if (now.phoneOwns) 1f else 0f, label = "knob")
    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(
        initialValue = 1f,
        targetValue = 0.55f,
        animationSpec = infiniteRepeatable(tween(600), RepeatMode.Reverse),
        label = "pulse",
    )
    val state = if (now.playing) "playing" else "paused"
    val primary = scheme.primary
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(64.dp)
            .clip(RoundedCornerShape(32.dp))
            .background(scheme.surfaceContainerLow)
            .border(1.dp, scheme.outlineVariant, RoundedCornerShape(32.dp))
            .drawBehind {
                val inset = 4.dp.toPx()
                val width = size.width / 2 - 2 * inset
                drawRoundRect(
                    color = primary.copy(alpha = if (busy) pulse else 1f),
                    topLeft = Offset(inset + knob * (size.width / 2), inset),
                    size = Size(width, size.height - 2 * inset),
                    cornerRadius = CornerRadius(28.dp.toPx()),
                )
            },
    ) {
        Row(modifier = Modifier.fillMaxSize()) {
            Side(
                icon = Icons.Outlined.Computer,
                label = "desktop",
                caption = if (!now.phoneOwns) state else if (deskReachable) "tap to move here" else "unreachable",
                selected = !now.phoneOwns,
                dim = now.phoneOwns && !deskReachable,
                busy = busy,
                modifier = Modifier.weight(1f),
            ) { onTake("desk") }
            Side(
                icon = Icons.Outlined.Smartphone,
                label = "phone",
                caption = if (now.phoneOwns) state else "tap to move here",
                selected = now.phoneOwns,
                dim = false,
                busy = busy,
                modifier = Modifier.weight(1f),
            ) { onTake("phone") }
        }
    }
}

@Composable
private fun Side(icon: ImageVector, label: String, caption: String, selected: Boolean, dim: Boolean, busy: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val tint = if (selected) scheme.onPrimary else scheme.onSurfaceVariant
    Row(
        modifier = modifier
            .fillMaxHeight()
            .clickable(enabled = !selected && !busy, onClick = onClick)
            .alpha(if (dim) 0.4f else 1f)
            .padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(24.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.titleMedium, color = tint, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Label(caption, color = tint.copy(alpha = 0.75f))
        }
    }
}

@Composable
fun Cover(now: NowState, cover: Bitmap?, modifier: Modifier = Modifier, corner: Dp = 20.dp) {
    val scheme = MaterialTheme.colorScheme
    if (cover != null) {
        Image(cover.asImageBitmap(), null, modifier = modifier.clip(RoundedCornerShape(corner)), contentScale = ContentScale.Crop)
        return
    }
    val seed = (now.file ?: now.title).hashCode()
    val tones = listOf(scheme.primary, scheme.secondary, scheme.tertiary)
    Box(modifier = modifier.clip(RoundedCornerShape(corner)).background(scheme.surfaceContainerHigh)) {
        Box(
            modifier = Modifier
                .padding(start = ((seed ushr 1) % 40).dp * 2, top = ((seed ushr 7) % 40).dp * 2)
                .size(((seed ushr 3) % 30 + 60).dp)
                .clip(CircleShape)
                .background(tones[(seed ushr 11) % 3].copy(alpha = 0.7f)),
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth(((seed ushr 5) % 60 + 20) / 100f)
                .height(12.dp)
                .background(scheme.primary),
        )
    }
}

@Composable
fun LyricsPane(lyrics: Lyrics?, elapsed: Double, busy: Boolean, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val synced = lyrics?.synced
    val plain = lyrics?.plain
    Box(modifier = modifier.clip(RoundedCornerShape(20.dp)).background(scheme.surfaceContainerLow).padding(16.dp)) {
        when {
            !synced.isNullOrEmpty() -> {
                val state = rememberLazyListState()
                val current = synced.indexOfLast { it.t <= elapsed }
                LaunchedEffect(current) { if (current >= 0) state.animateScrollToItem((current - 2).coerceAtLeast(0)) }
                LazyColumn(state = state, verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxSize()) {
                    itemsIndexed(synced) { index, line ->
                        Text(
                            line.x,
                            style = if (index == current) MaterialTheme.typography.titleLarge else MaterialTheme.typography.bodyLarge,
                            color = if (index == current) scheme.onSurface else scheme.outline,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
            plain != null -> LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxSize()) {
                items(plain.lines()) { line ->
                    Text(line, style = MaterialTheme.typography.bodyLarge, color = scheme.onSurfaceVariant, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                }
            }
            else -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Label(if (busy) "fetching lyrics…" else "no lyrics for this song")
            }
        }
    }
}
