package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.Hog
import ac.mvr.phone.net.LoadState
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import java.util.Locale

private fun fmtBytes(bytes: Long): String = when {
    bytes >= 1L shl 30 -> "%.1f G".format(Locale.ROOT, bytes / 1073741824.0)
    bytes >= 1L shl 20 -> "${bytes shr 20} M"
    else -> "${bytes shr 10} K"
}

private fun Hog.detail(): String {
    val parts = ArrayList<String>()
    parts.add(if (kind == "service") unit.removeSuffix(".service") else kind)
    parts.add(fmtBytes(mem) + if (swap > 0) " + ${fmtBytes(swap)} swap" else "")
    if (cpu >= 0.05) parts.add("%.1f cores".format(Locale.ROOT, cpu))
    return parts.joinToString(" · ")
}

private fun pressureSummary(state: LoadState): String =
    "mem stall ${state.pressure.memory.full10.toInt()}% · cpu wait ${state.pressure.cpu.some10.toInt()}%"

@Composable
private fun severity(value: Double): Color {
    val scheme = MaterialTheme.colorScheme
    return when {
        value >= 20 -> scheme.error
        value >= 5 -> scheme.tertiary
        else -> scheme.primary
    }
}

@Composable
private fun PressureLine(name: String, caption: String, value: Double) {
    val scheme = MaterialTheme.colorScheme
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Label("$name · $caption")
            Label("${value.toInt()}%")
        }
        Box(modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(scheme.outlineVariant)) {
            Box(modifier = Modifier.fillMaxWidth((value / 100.0).toFloat().coerceIn(0.02f, 1f)).fillMaxHeight().background(severity(value)))
        }
    }
}

@Composable
private fun KillChip(armed: Boolean, enabled: Boolean, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (armed) scheme.error else scheme.surfaceContainerHigh)
            .clickable(enabled = enabled, onClick = onTap)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        Text(
            if (armed) "tap again" else "kill",
            style = MaterialTheme.typography.labelLarge,
            color = if (armed) scheme.onError else scheme.onSurface,
        )
    }
}

@Composable
private fun HogRow(hog: Hog, armed: Boolean, enabled: Boolean, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (armed) scheme.error.copy(alpha = 0.12f) else Color.Transparent)
            .padding(horizontal = 6.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(hog.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Label(hog.detail(), color = if (armed) scheme.error else scheme.outline)
        }
        KillChip(armed, enabled, onTap)
    }
}

@Composable
private fun KillBiggest(top: Hog?, armed: Boolean, enabled: Boolean, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val text = when {
        top == null -> "nothing to kill"
        armed -> "tap again to kill ${top.name}"
        else -> "kill the biggest · ${top.name}"
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(if (armed) scheme.error else scheme.errorContainer)
            .clickable(enabled = enabled && top != null, onClick = onTap)
            .padding(vertical = 14.dp, horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.titleMedium,
            color = if (armed) scheme.onError else scheme.onErrorContainer,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
fun PanicCard(store: Store, onOpen: (String) -> Unit) {
    val state by store.load.state.collectAsStateWithLifecycle()
    val armed by store.load.armed.collectAsStateWithLifecycle()
    val fresh by store.load.fresh.collectAsStateWithLifecycle()
    val lastKill by store.load.lastKill.collectAsStateWithLifecycle()
    val current = state
    val top = current?.hogs?.firstOrNull()
    HomeCard {
        CardHeader("panic", current?.let { pressureSummary(it) + if (fresh) "" else " · last known" }) { onOpen("panic") }
        if (current == null) {
            Label("waiting for the desktop")
        } else {
            PressureLine("memory", "stalled, last 10 s", current.pressure.memory.full10)
            val killed = lastKill
            if (killed != null) Label("killed ${killed.name}")
        }
        KillBiggest(top, armed != null && armed == top?.id, fresh) { top?.let { store.load.tap(it.id) } }
    }
}

@Composable
fun PanicScreen(store: Store, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val state by store.load.state.collectAsStateWithLifecycle()
    val armed by store.load.armed.collectAsStateWithLifecycle()
    val fresh by store.load.fresh.collectAsStateWithLifecycle()
    val lastKill by store.load.lastKill.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) {
        while (true) {
            runCatching { store.load.refresh() }
            delay(3_000)
        }
    }
    DisposableEffect(Unit) { onDispose { store.load.disarm() } }
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("panic", reachable, onCollapse)
        Banner(reachable)
        val current = state
        if (current == null) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth().padding(18.dp), contentAlignment = Alignment.TopStart) {
                Label("waiting for the desktop")
            }
        } else {
            val top = current.hogs.firstOrNull()
            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(start = 14.dp, end = 14.dp, top = 2.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                item {
                    Column(
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(scheme.surfaceContainerLow).padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        PressureLine("memory", "stalled, last 10 s", current.pressure.memory.full10)
                        PressureLine("cpu", "waiting, last 10 s", current.pressure.cpu.some10)
                        PressureLine("io", "stalled, last 10 s", current.pressure.io.full10)
                        val m = current.memory
                        Label("${fmtBytes(m.available)} free of ${fmtBytes(m.total)} · swap ${fmtBytes(m.swapTotal - m.swapFree)} used of ${fmtBytes(m.swapTotal)}" + if (fresh) "" else " · last known")
                    }
                }
                item { KillBiggest(top, armed != null && armed == top?.id, fresh) { top?.let { store.load.tap(it.id) } } }
                item { Label("the heaviest, by memory and swap", modifier = Modifier.padding(start = 6.dp, top = 6.dp)) }
                items(current.hogs, key = { it.id }) { hog ->
                    HogRow(hog, armed == hog.id, fresh) { store.load.tap(hog.id) }
                }
                val killed = lastKill
                if (killed != null) item { Label("killed ${killed.name}", modifier = Modifier.padding(start = 6.dp, top = 6.dp)) }
            }
        }
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}
