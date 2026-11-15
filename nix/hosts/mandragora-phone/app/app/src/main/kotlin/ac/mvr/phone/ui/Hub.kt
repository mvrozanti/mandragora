package ac.mvr.phone.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ac.mvr.phone.state.HubAlert
import ac.mvr.phone.state.HubLevel
import ac.mvr.phone.state.HubLine
import ac.mvr.phone.state.HubMachineView
import ac.mvr.phone.state.HubMeter
import ac.mvr.phone.state.HubRow
import ac.mvr.phone.state.HubView
import ac.mvr.phone.state.Store
import ac.mvr.phone.state.hubView
import androidx.lifecycle.compose.collectAsStateWithLifecycle

private val HubOk = Color(0xFF4EC17D)
private val HubWarn = Color(0xFFE0A458)

@Composable
private fun rememberHubView(store: Store): HubView? {
    val feed by store.hub.feed.collectAsStateWithLifecycle()
    val fresh by store.hub.fresh.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    return remember(feed, reachable, fresh) { feed?.let { hubView(it, reachable, fresh) } }
}

@Composable
fun HubCard(store: Store, onOpen: (String) -> Unit) {
    val view = rememberHubView(store)
    HomeCard {
        CardHeader("hub", view?.let { "${it.count} services" }) { onOpen("hub") }
        Column(
            modifier = Modifier.fillMaxWidth().clickable { onOpen("hub") },
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (view == null) Label("waiting for the desktop") else view.glance.forEach { HubGlanceLine(it) }
        }
    }
}

@Composable
fun HubScreen(store: Store, onCollapse: () -> Unit) {
    val context = LocalContext.current
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val view = rememberHubView(store)
    val clicks = remember { store.prefs.hubClicks.value }
    var expanded by rememberSaveable { mutableStateOf(false) }
    val rows = remember(view, clicks) { view?.sortedRows(clicks) ?: emptyList() }

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("hub", reachable, onCollapse)
        if (view == null) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth().padding(18.dp), contentAlignment = Alignment.TopStart) {
                Label("waiting for the desktop")
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(start = 14.dp, end = 14.dp, top = 2.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                item {
                    Label(
                        "${view.count} services" + if (view.live) "" else " · last known",
                        modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
                    )
                }
                item {
                    HubStatusBlock(view, expanded, Modifier.padding(bottom = 10.dp)) { expanded = !expanded }
                }
                items(rows) { row ->
                    HubServiceRow(row) { openService(context, store, row) }
                }
            }
        }
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}

private fun openService(context: Context, store: Store, row: HubRow) {
    store.prefs.bumpClick(row.entry.host)
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(row.link)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (err: ActivityNotFoundException) {
        store.report(IllegalStateException("no browser on this phone"))
    }
}

@Composable
private fun HubDot(level: HubLevel, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val down = scheme.error
    val unknown = scheme.outlineVariant
    Canvas(modifier = modifier.size(8.dp)) {
        val radius = size.minDimension / 2
        when (level) {
            HubLevel.Ok -> drawCircle(HubOk, radius)
            HubLevel.Warn -> drawCircle(HubWarn, radius - 1.dp.toPx(), style = Stroke(width = 2.dp.toPx()))
            HubLevel.Down -> {
                drawCircle(down.copy(alpha = 0.25f), radius + 3.dp.toPx())
                drawCircle(down, radius)
            }
            HubLevel.Unknown -> drawCircle(unknown, radius)
        }
    }
}

@Composable
private fun HubGlanceLine(line: HubLine) {
    val scheme = MaterialTheme.colorScheme
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        HubDot(line.level, Modifier.padding(top = 4.dp))
        if (line.name.isNotEmpty()) Text(line.name, style = MaterialTheme.typography.labelMedium, color = scheme.onSurface, maxLines = 1)
        Text(line.text, style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun HubStatusBlock(view: HubView, expanded: Boolean, modifier: Modifier = Modifier, onToggle: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(16.dp)
    val turn by animateFloatAsState(if (expanded) 180f else 0f, label = "chevron")
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(scheme.surfaceContainerLow)
            .border(1.dp, scheme.outlineVariant, shape),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClickLabel = if (expanded) "collapse" else "expand", onClick = onToggle)
                .heightIn(min = 48.dp)
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                view.glance.forEach { HubGlanceLine(it) }
            }
            Icon(Icons.Filled.ExpandMore, null, tint = scheme.outline, modifier = Modifier.size(20.dp).rotate(turn))
        }
        AnimatedVisibility(visible = expanded) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                HubMachineCard(view.desk)
                HubMachineCard(view.vps)
                HubAlertCard(view.alerts)
            }
        }
    }
}

@Composable
private fun HubInnerCard(content: @Composable () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(12.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(scheme.surfaceContainer)
            .border(1.dp, scheme.outlineVariant, shape)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        content()
    }
}

@Composable
private fun HubPill(text: String, level: HubLevel) {
    val scheme = MaterialTheme.colorScheme
    val (fg, line) = when (level) {
        HubLevel.Ok -> HubOk to HubOk
        HubLevel.Warn -> HubWarn to HubWarn
        HubLevel.Down -> scheme.error to scheme.error
        HubLevel.Unknown -> scheme.onSurfaceVariant to scheme.outline
    }
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        color = fg,
        maxLines = 1,
        modifier = Modifier.border(1.dp, line, RoundedCornerShape(5.dp)).padding(horizontal = 6.dp, vertical = 1.dp),
    )
}

@Composable
private fun HubMeterRow(meter: HubMeter) {
    val scheme = MaterialTheme.colorScheme
    val fill = when (meter.level) {
        HubLevel.Down -> scheme.error
        HubLevel.Warn -> HubWarn
        else -> scheme.primary
    }
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Label(meter.label, modifier = Modifier.width(44.dp))
        Box(modifier = Modifier.weight(1f).height(4.dp).clip(RoundedCornerShape(2.dp)).background(scheme.outlineVariant)) {
            Box(modifier = Modifier.fillMaxWidth(meter.percent / 100f).fillMaxHeight().background(fill))
        }
        Text(
            meter.value,
            style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.3.sp),
            color = scheme.onSurfaceVariant,
            textAlign = TextAlign.End,
            maxLines = 1,
            modifier = Modifier.width(76.dp),
        )
    }
}

@Composable
private fun HubMachineCard(machine: HubMachineView) {
    val scheme = MaterialTheme.colorScheme
    HubInnerCard {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(machine.name, style = MaterialTheme.typography.titleMedium.copy(fontSize = 15.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
            HubPill(machine.pill, machine.pillLevel)
        }
        Label(machine.meta, modifier = Modifier.padding(bottom = 6.dp))
        machine.meters.forEach { HubMeterRow(it) }
        Text(
            buildAnnotatedString {
                machine.note.strong?.let { withStyle(SpanStyle(color = scheme.onSurface)) { append(it) } }
                append(machine.note.rest)
            },
            style = MaterialTheme.typography.labelMedium,
            color = scheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 6.dp),
        )
    }
}

@Composable
private fun HubAlertCard(alerts: List<HubAlert>) {
    val shown = alerts.ifEmpty { listOf(HubAlert(HubLevel.Ok, "all clear", "no thresholds crossed")) }
    HubInnerCard {
        Label("needs attention", modifier = Modifier.padding(bottom = 6.dp))
        shown.forEachIndexed { index, alert ->
            if (index > 0) HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.outlineVariant)
            HubAlertRow(alert)
        }
    }
}

@Composable
private fun HubAlertRow(alert: HubAlert) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        HubDot(alert.level, Modifier.padding(top = 6.dp))
        Column {
            Text(alert.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = scheme.onSurface)
            Text(alert.detail, style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.3.sp), color = scheme.outline)
        }
    }
}

@Composable
private fun HubLockBadge(open: Boolean) {
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(5.dp)
    val surface = if (open) {
        Modifier.clip(shape).background(scheme.primary)
    } else {
        Modifier.alpha(0.45f).border(1.dp, scheme.outlineVariant, shape)
    }
    Box(modifier = Modifier.size(22.dp).then(surface), contentAlignment = Alignment.Center) {
        Icon(
            if (open) Icons.Outlined.LockOpen else Icons.Outlined.Lock,
            null,
            tint = if (open) scheme.onPrimary else scheme.outline,
            modifier = Modifier.size(14.dp),
        )
    }
}

@Composable
private fun HubNoTile() {
    val scheme = MaterialTheme.colorScheme
    Text(
        "NO TILE",
        style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.7.sp),
        color = scheme.outline,
        maxLines = 1,
        modifier = Modifier.border(1.dp, scheme.outlineVariant, RoundedCornerShape(5.dp)).padding(horizontal = 4.dp),
    )
}

@Composable
private fun HubServiceRow(row: HubRow, onOpen: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(6.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(46.dp)
            .clip(shape)
            .background(if (row.level == HubLevel.Down) scheme.error.copy(alpha = 0.07f) else Color.Transparent)
            .clickable(onClickLabel = "open", role = Role.Button, onClick = onOpen)
            .clearAndSetSemantics { contentDescription = row.description }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        HubDot(row.level)
        HubLockBadge(row.entry.access == "open")
        Text(
            row.entry.host,
            style = MaterialTheme.typography.bodyLarge.copy(fontFamily = Mono, fontSize = 15.sp, letterSpacing = (-0.15).sp),
            color = scheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        if (row.entry.untiled) HubNoTile()
    }
}
