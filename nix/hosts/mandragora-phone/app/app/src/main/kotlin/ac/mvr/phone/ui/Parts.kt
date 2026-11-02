package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.VolumeState
import ac.mvr.phone.state.NowState
import ac.mvr.phone.state.fmtTime

@Composable
fun Label(text: String, modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.outline) {
    Text(text.uppercase(), style = MaterialTheme.typography.labelSmall, color = color, modifier = modifier)
}

@Composable
fun Chip(text: String, selected: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (selected) scheme.primary else Color.Transparent)
            .border(1.dp, if (selected) scheme.primary else scheme.outlineVariant, RoundedCornerShape(999.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 8.dp),
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelLarge,
            color = when {
                !enabled -> scheme.outline
                selected -> scheme.onPrimary
                else -> scheme.onSurfaceVariant
            },
        )
    }
}

@Composable
fun Transport(now: NowState, enabled: Boolean, flagsEnabled: Boolean, onToggle: () -> Unit, onNext: () -> Unit, onPrevious: () -> Unit, onRepeat: () -> Unit, onRandom: () -> Unit, compact: Boolean = false) {
    val scheme = MaterialTheme.colorScheme
    val playSize = if (compact) 56.dp else 72.dp
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), modifier = Modifier.fillMaxWidth()) {
        IconButton(onClick = onRepeat, enabled = flagsEnabled) {
            Icon(Icons.Filled.Repeat, "repeat", tint = if (now.repeat) scheme.primary else scheme.onSurface)
        }
        IconButton(onClick = onPrevious, enabled = enabled) { Icon(Icons.Filled.SkipPrevious, "previous", tint = scheme.onSurface) }
        Box(
            modifier = Modifier
                .size(playSize)
                .clip(CircleShape)
                .background(if (enabled) scheme.primary else scheme.surfaceContainerHigh)
                .clickable(enabled = enabled, onClick = onToggle),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (now.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                if (now.playing) "pause" else "play",
                tint = if (enabled) scheme.onPrimary else scheme.outline,
                modifier = Modifier.size(if (compact) 28.dp else 34.dp),
            )
        }
        IconButton(onClick = onNext, enabled = enabled) { Icon(Icons.Filled.SkipNext, "next", tint = scheme.onSurface) }
        IconButton(onClick = onRandom, enabled = flagsEnabled) {
            Icon(Icons.Filled.Shuffle, "random", tint = if (now.random) scheme.primary else scheme.onSurface)
        }
    }
}

@Composable
fun ProgressRow(now: NowState, enabled: Boolean, onSeek: (Double) -> Unit) {
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
            enabled = enabled,
            colors = SliderDefaults.colors(thumbColor = scheme.onSurface, activeTrackColor = scheme.primary, inactiveTrackColor = scheme.outlineVariant),
        )
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(fmtTime(value * duration), style = MaterialTheme.typography.labelMedium, color = scheme.outline)
            Text("-" + fmtTime(duration - value * duration), style = MaterialTheme.typography.labelMedium, color = scheme.outline)
        }
    }
}

@Composable
fun OwnerSwitch(now: NowState, deskAvailable: Boolean, busy: Boolean, big: Boolean, onTake: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val height = if (big) 64.dp else 48.dp
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(999.dp))
            .border(1.dp, scheme.outline, RoundedCornerShape(999.dp)),
    ) {
        listOf("desk" to "desktop", "phone" to "this phone").forEach { (key, label) ->
            val selected = now.owner == key
            val enabled = !busy && (key == "phone" || deskAvailable || selected)
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .background(if (selected) scheme.primary else Color.Transparent)
                    .clickable(enabled = enabled && !selected) { onTake(key) },
                contentAlignment = Alignment.Center,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(if (selected && now.playing) Color(0xFF4EC17D) else if (selected) scheme.onPrimary else scheme.outline),
                    )
                    Text(
                        label.uppercase(),
                        style = MaterialTheme.typography.labelMedium,
                        color = if (selected) scheme.onPrimary else if (enabled) scheme.onSurfaceVariant else scheme.outline,
                    )
                }
            }
        }
    }
}

@Composable
fun NowStrip(now: NowState, enabled: Boolean, onOpen: () -> Unit, onToggle: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(scheme.surfaceContainerLow)
            .clickable(onClick = onOpen)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Cover(now, Modifier.size(48.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(listOfNotNull(now.artist, now.title).joinToString(" · "), style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                "${now.whereLabel} · ${fmtTime(now.elapsed)} / ${fmtTime(now.duration)}" + if (now.playing) "" else " · paused",
                style = MaterialTheme.typography.labelMedium,
                color = scheme.outline,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(onClick = onToggle, enabled = enabled) {
            Icon(if (now.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, "toggle", tint = scheme.onSurface)
        }
    }
}

@Composable
fun Cover(now: NowState, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val seed = (now.file ?: now.title).hashCode()
    val tones = listOf(scheme.primary, scheme.secondary, scheme.tertiary)
    Box(modifier = modifier.clip(RoundedCornerShape(6.dp)).background(scheme.surfaceContainerHigh)) {
        Box(
            modifier = Modifier
                .padding(start = ((seed ushr 1) % 40).dp / 2, top = ((seed ushr 7) % 40).dp / 2)
                .size(((seed ushr 3) % 30 + 20).dp)
                .clip(CircleShape)
                .background(tones[(seed ushr 11) % 3].copy(alpha = 0.7f)),
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth(((seed ushr 5) % 60 + 20) / 100f)
                .height(5.dp)
                .background(scheme.primary),
        )
    }
}

@Composable
fun SinkRail(volume: VolumeState, enabled: Boolean, onChange: (Int) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var dragging by remember { mutableStateOf<Float?>(null) }
    val level = volume.sink?.volume ?: 0
    val value = dragging ?: (level / 100f)
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(44.dp).fillMaxHeight()) {
        Label("desk")
        Spacer(Modifier.height(4.dp))
        Box(modifier = Modifier.weight(1f).width(44.dp), contentAlignment = Alignment.Center) {
            Slider(
                value = value,
                onValueChange = { dragging = it },
                onValueChangeFinished = {
                    dragging?.let { onChange((it * 100).toInt()) }
                    dragging = null
                },
                enabled = enabled,
                colors = SliderDefaults.colors(thumbColor = scheme.onSurface, activeTrackColor = scheme.primary, inactiveTrackColor = scheme.outlineVariant),
                modifier = Modifier
                    .layout { measurable, constraints ->
                        val placeable = measurable.measure(
                            androidx.compose.ui.unit.Constraints(
                                minWidth = constraints.minHeight,
                                maxWidth = constraints.maxHeight,
                                minHeight = constraints.minWidth,
                                maxHeight = constraints.maxWidth,
                            ),
                        )
                        layout(placeable.height, placeable.width) {
                            placeable.place(-(placeable.width - placeable.height) / 2, (placeable.width - placeable.height) / 2)
                        }
                    }
                    .rotate(-90f),
            )
        }
        Spacer(Modifier.height(4.dp))
        Text("${(value * 100).toInt()}%", style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant)
    }
}

@Composable
fun TailnetBanner(reachable: Boolean, now: NowState, onPlayHere: () -> Unit) {
    if (reachable) return
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .clip(RoundedCornerShape(9.dp))
            .background(scheme.error.copy(alpha = 0.18f))
            .border(1.dp, scheme.error, RoundedCornerShape(9.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Label("tailnet down · fails closed", color = scheme.error)
        Text(
            if (now.phoneOwns) "playing locally · desktop volume, queue and get are unavailable"
            else "desktop last known at ${fmtTime(now.elapsed)} · controls frozen, nothing falls back to mvr.ac",
            style = MaterialTheme.typography.bodyMedium,
            color = scheme.onSurface,
        )
        if (!now.phoneOwns && now.file != null) {
            TextButton(onClick = onPlayHere) { Text("play here from ${fmtTime(now.elapsed)}", style = MaterialTheme.typography.labelLarge) }
        }
    }
}

@Composable
fun StatusDot(ok: Boolean?, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = modifier
            .size(8.dp)
            .clip(CircleShape)
            .background(when (ok) { true -> Color(0xFF4EC17D); false -> scheme.error; null -> scheme.outlineVariant }),
    )
}
