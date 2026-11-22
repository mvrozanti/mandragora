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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.logic.freeLabel
import ac.mvr.phone.logic.gib
import ac.mvr.phone.logic.gpuSubtitle
import ac.mvr.phone.logic.lockLabel
import ac.mvr.phone.logic.residentName
import ac.mvr.phone.logic.vramLabel
import ac.mvr.phone.logic.vramShare
import ac.mvr.phone.net.GpuInfo
import ac.mvr.phone.net.GpuProc
import ac.mvr.phone.net.GpuResident
import ac.mvr.phone.net.GpuState
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import java.util.Locale

@Composable
private fun Meter(name: String, value: String, share: Float, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val tone = when {
        share >= 0.9f -> scheme.error
        share >= 0.7f -> scheme.tertiary
        else -> scheme.primary
    }
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Label(name)
            Label(value)
        }
        Box(modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(scheme.outlineVariant)) {
            Box(modifier = Modifier.fillMaxWidth(share.coerceIn(0.02f, 1f)).fillMaxHeight().background(tone))
        }
    }
}

@Composable
private fun FreeButton(residents: List<GpuResident>, freeing: Boolean, enabled: Boolean, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val text = if (freeing) "asking them to let go…" else freeLabel(residents) ?: return
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(scheme.secondaryContainer)
            .clickable(enabled = enabled && !freeing, onClick = onTap)
            .padding(vertical = 14.dp, horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = MaterialTheme.typography.titleMedium, color = scheme.onSecondaryContainer, textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

private fun nowSeconds(): Double = System.currentTimeMillis() / 1000.0

@Composable
fun GpuCard(store: Store, onOpen: (String) -> Unit) {
    val state by store.gpu.state.collectAsStateWithLifecycle()
    val fresh by store.gpu.fresh.collectAsStateWithLifecycle()
    val freeing by store.gpu.freeing.collectAsStateWithLifecycle()
    val current = state
    val info = current?.gpu
    HomeCard {
        CardHeader("gpu", gpuSubtitle(info)?.let { it + if (fresh) "" else " · last known" }) { onOpen("gpu") }
        when {
            current == null -> Label("waiting for the desktop")
            info == null -> Label("nvidia-smi did not answer")
            else -> {
                Meter("vram", vramLabel(info), vramShare(info), Modifier.clip(RoundedCornerShape(10.dp)).clickable { onOpen("gpu") })
                Label(lockLabel(current.lock, nowSeconds()))
            }
        }
        if (current != null) FreeButton(current.residents, freeing.isNotEmpty(), fresh) { store.gpu.free(current.residents) }
    }
}

@Composable
private fun ResidentRow(resident: GpuResident, freeing: Boolean, enabled: Boolean, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(residentName(resident), style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Label(listOf(if (resident.kind == "stt") resident.name else "ollama", gib(resident.mem)).joinToString(" · "))
        }
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(999.dp))
                .background(scheme.secondaryContainer)
                .clickable(enabled = enabled && !freeing, onClick = onTap)
                .padding(horizontal = 14.dp, vertical = 8.dp),
        ) {
            Text(if (freeing) "freeing…" else "free", style = MaterialTheme.typography.labelLarge, color = scheme.onSecondaryContainer)
        }
    }
}

private fun GpuProc.detail(): String = listOfNotNull(
    kind,
    unit.takeIf { it.endsWith(".service") }?.removeSuffix(".service"),
    "holds the lock".takeIf { holder },
    "outside the lock".takeIf { outside },
).joinToString(" · ")

@Composable
private fun ProcRow(proc: GpuProc) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(proc.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Label(proc.detail(), color = if (proc.holder || proc.outside) scheme.tertiary else scheme.outline)
        }
        Text(gib(proc.mem), style = MaterialTheme.typography.labelLarge, color = scheme.onSurface)
    }
}

@Composable
private fun GpuGauges(current: GpuState, info: GpuInfo, fresh: Boolean) {
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(scheme.surfaceContainerLow).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Meter("vram", vramLabel(info), vramShare(info))
        Meter("busy", "${info.util.toInt()}%", (info.util / 100.0).toFloat())
        val card = info.name.removePrefix("NVIDIA ").removePrefix("GeForce ")
        Label("%s · %d°C · %.0f W".format(Locale.ROOT, card, info.temp.toInt(), info.power) + if (fresh) "" else " · last known")
        Text(lockLabel(current.lock, nowSeconds()), style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
fun GpuScreen(store: Store, onCollapse: () -> Unit) {
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val state by store.gpu.state.collectAsStateWithLifecycle()
    val fresh by store.gpu.fresh.collectAsStateWithLifecycle()
    val freeing by store.gpu.freeing.collectAsStateWithLifecycle()
    val freed by store.gpu.freed.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) {
        store.foreground.collectLatest { foreground ->
            while (foreground) {
                runCatching { store.gpu.refresh() }
                delay(3_000)
            }
        }
    }
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("gpu", reachable, onCollapse)
        Banner(reachable)
        val current = state
        val info = current?.gpu
        if (current == null || info == null) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth().padding(18.dp), contentAlignment = Alignment.TopStart) {
                Label(if (current == null) "waiting for the desktop" else "nvidia-smi did not answer")
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(start = 14.dp, end = 14.dp, top = 2.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                item { GpuGauges(current, info, fresh) }
                item { FreeButton(current.residents, freeing.isNotEmpty(), fresh) { store.gpu.free(current.residents) } }
                if (current.residents.isNotEmpty()) {
                    item { Label("kept loaded, freed on request", modifier = Modifier.padding(start = 6.dp, top = 6.dp)) }
                    items(current.residents, key = { "r:" + it.name }) { resident ->
                        ResidentRow(resident, resident.name in freeing, fresh) { store.gpu.free(listOf(resident)) }
                    }
                }
                item { Label("using the gpu, by vram", modifier = Modifier.padding(start = 6.dp, top = 6.dp)) }
                items(current.procs, key = { "p:" + it.name }) { ProcRow(it) }
                val last = freed
                if (last != null) item { Label("freed $last", modifier = Modifier.padding(start = 6.dp, top = 6.dp)) }
                item { Label("free asks a model to unload; nothing here kills a process", modifier = Modifier.padding(start = 6.dp, top = 6.dp)) }
            }
        }
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}
