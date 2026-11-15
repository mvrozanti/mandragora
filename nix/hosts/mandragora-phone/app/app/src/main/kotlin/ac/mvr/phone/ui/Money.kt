package ac.mvr.phone.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ac.mvr.phone.net.MoneyBasis
import ac.mvr.phone.net.MoneyCache
import ac.mvr.phone.net.MoneyFormat
import ac.mvr.phone.net.MoneyFx
import ac.mvr.phone.net.MoneyHolding
import ac.mvr.phone.net.MoneyVenue
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay

private val GainUp = Color(0xFF4EC17D)

private fun totalStyle(size: TextUnit) = TextStyle(
    fontFamily = Mono,
    fontWeight = FontWeight.SemiBold,
    fontSize = size,
    letterSpacing = (-0.5).sp,
    fontFeatureSettings = "tnum",
)

private fun shown(text: String, hidden: Boolean): String = if (hidden) MoneyFormat.mask(text) else text

@Composable
private fun rememberNowMs(): Long {
    val now by produceState(System.currentTimeMillis()) {
        while (true) {
            delay(15_000)
            value = System.currentTimeMillis()
        }
    }
    return now
}

private fun cardSubtitle(data: MoneyCache?, reachable: Boolean, nowMs: Long): String? = when {
    data == null || !data.hasCache -> if (!reachable) "desktop unreachable" else data?.error
    !reachable -> "desktop unreachable · last known"
    MoneyFormat.isStale(data, nowMs) -> "stale · fetched ${MoneyFormat.ago(data.fetchedAt, nowMs)}"
    else -> "fetched ${MoneyFormat.ago(data.fetchedAt, nowMs)}"
}

@Composable
fun MoneyCard(store: Store, onOpen: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val data by store.money.cache.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val unitPref by store.prefs.unit.collectAsStateWithLifecycle()
    val hidden by store.prefs.hiddenAmounts.collectAsStateWithLifecycle()
    val nowMs = rememberNowMs()
    val unit = MoneyFormat.unitOf(unitPref)
    val cache = data
    val total = cache?.totalUsd
    HomeCard {
        CardHeader("money", cardSubtitle(cache, reachable, nowMs)) { onOpen("money") }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .clickable { store.prefs.setUnit(MoneyFormat.nextUnit(unit)) },
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                shown(MoneyFormat.unit(total, unit, cache?.fx ?: MoneyFx()), hidden),
                style = totalStyle(28.sp),
                color = if (total == null) scheme.outline else scheme.onSurface,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            Label(unit.uppercase())
        }
        if (cache != null && cache.hasCache) {
            if (total != null && total != 0.0) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    cache.venues.forEach { ShareBar(it, total) }
                }
            } else {
                Text(
                    cache.error ?: "incomplete",
                    style = MaterialTheme.typography.labelMedium,
                    color = scheme.outline,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun ShareBar(venue: MoneyVenue, total: Double) {
    val scheme = MaterialTheme.colorScheme
    val usd = venue.usd
    val available = !venue.missing && !venue.noteOnly && usd != null
    val fraction = if (available) (usd!! / total).toFloat().coerceIn(0f, 1f) else 0f
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            venue.label,
            style = MaterialTheme.typography.labelMedium,
            color = if (available) scheme.onSurfaceVariant else scheme.outline,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.width(96.dp),
        )
        Box(
            modifier = Modifier
                .weight(1f)
                .height(6.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(scheme.surfaceContainerHigh),
        ) {
            if (fraction > 0f) {
                Box(modifier = Modifier.fillMaxHeight().fillMaxWidth(fraction).clip(RoundedCornerShape(3.dp)).background(scheme.secondary))
            }
        }
        Text(
            if (available) MoneyFormat.share(usd, total) ?: "--" else "--",
            style = MaterialTheme.typography.labelMedium,
            color = when {
                !available -> scheme.outline
                venue.staleSince != null -> scheme.tertiary
                else -> scheme.onSurfaceVariant
            },
            textAlign = TextAlign.End,
            maxLines = 1,
            modifier = Modifier.width(44.dp),
        )
    }
}

@Composable
fun MoneyScreen(store: Store, onCollapse: () -> Unit) {
    val data by store.money.cache.collectAsStateWithLifecycle()
    val refreshing by store.money.refreshing.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val unitPref by store.prefs.unit.collectAsStateWithLifecycle()
    val hidden by store.prefs.hiddenAmounts.collectAsStateWithLifecycle()
    var collapsed by rememberSaveable { mutableStateOf(listOf<String>()) }
    val nowMs = rememberNowMs()
    val unit = MoneyFormat.unitOf(unitPref)
    val cache = data
    val fx = cache?.fx ?: MoneyFx()
    val desktopRefreshing = reachable && cache?.refreshing == true
    val busy = refreshing || desktopRefreshing

    LaunchedEffect(desktopRefreshing, refreshing) {
        while (desktopRefreshing && !refreshing) {
            delay(3_000)
            runCatching { store.money.refresh() }
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("money", reachable, onCollapse)
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 14.dp)
                .padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            TotalBlock(cache, unit, hidden) { store.prefs.setUnit(MoneyFormat.nextUnit(unit)) }
            Controls(
                unit = unit,
                hidden = hidden,
                busy = busy,
                canRefresh = reachable,
                onUnit = store.prefs::setUnit,
                onHidden = { store.prefs.setHiddenAmounts(!hidden) },
                onRefresh = store.money::refreshNow,
            )
            FetchedLine(cache, reachable, busy, nowMs)
            cache?.basis?.let { BasisBlock(it, fx, hidden) }
            if (cache != null && cache.venues.isNotEmpty()) {
                Section("where it sits") {
                    cache.venues.forEach { venue ->
                        VenueRow(venue, cache.totalUsd, unit, fx, hidden, expanded = venue.id !in collapsed) {
                            collapsed = if (venue.id in collapsed) collapsed - venue.id else collapsed + venue.id
                        }
                    }
                }
            }
            val error = cache?.error
            if (cache != null && cache.hasCache && error != null) {
                Text(error, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(horizontal = 4.dp))
            }
        }
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}

@Composable
private fun TotalBlock(cache: MoneyCache?, unit: String, hidden: Boolean, onCycle: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val fx = cache?.fx ?: MoneyFx()
    val total = cache?.totalUsd
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(scheme.surfaceContainerLow)
            .clickable(onClick = onCycle)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Label("total")
        Text(
            shown(MoneyFormat.unit(total, unit, fx), hidden),
            style = totalStyle(34.sp),
            color = if (total == null) scheme.outline else scheme.onSurface,
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            MoneyFormat.units.filter { it != unit }.joinToString("   ") { shown(MoneyFormat.unit(total, it, fx), hidden) },
            style = MaterialTheme.typography.labelLarge,
            color = scheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun Controls(
    unit: String,
    hidden: Boolean,
    busy: Boolean,
    canRefresh: Boolean,
    onUnit: (String) -> Unit,
    onHidden: () -> Unit,
    onRefresh: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        MoneyFormat.units.forEach { option ->
            val selected = option == unit
            Text(
                option.uppercase(),
                style = MaterialTheme.typography.labelLarge,
                color = if (selected) scheme.onPrimary else scheme.onSurfaceVariant,
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(if (selected) scheme.primary else scheme.surfaceContainerHigh)
                    .clickable { onUnit(option) }
                    .padding(horizontal = 16.dp, vertical = 11.dp),
            )
        }
        Spacer(modifier = Modifier.weight(1f))
        IconButton(onClick = onHidden) {
            Icon(
                if (hidden) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                if (hidden) "show amounts" else "hide amounts",
                tint = scheme.onSurfaceVariant,
            )
        }
        IconButton(onClick = onRefresh, enabled = canRefresh && !busy) {
            if (busy) {
                Spinning { angle -> Icon(Icons.Outlined.Refresh, "refreshing", tint = scheme.tertiary, modifier = Modifier.rotate(angle)) }
            } else {
                Icon(Icons.Outlined.Refresh, "refresh", tint = scheme.onSurfaceVariant, modifier = Modifier.alpha(if (canRefresh) 1f else 0.4f))
            }
        }
    }
}

@Composable
private fun Spinning(content: @Composable (Float) -> Unit) {
    val angle by rememberInfiniteTransition(label = "spin").animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(1100, easing = LinearEasing)),
        label = "spin",
    )
    content(angle)
}

@Composable
private fun FetchedLine(cache: MoneyCache?, reachable: Boolean, busy: Boolean, nowMs: Long) {
    val scheme = MaterialTheme.colorScheme
    val known = cache != null && cache.hasCache
    val stale = known && MoneyFormat.isStale(cache!!, nowMs)
    val timer = "refresh timer every 15 min"
    val text = when {
        !reachable && known -> "desktop unreachable · last known values from ${MoneyFormat.ago(cache!!.fetchedAt, nowMs)}"
        !reachable -> "desktop unreachable"
        busy -> "refreshing…"
        !known -> cache?.error ?: "no cached balance yet"
        stale -> "stale · fetched ${MoneyFormat.ago(cache!!.fetchedAt, nowMs)} · $timer"
        else -> "fetched ${MoneyFormat.ago(cache!!.fetchedAt, nowMs)} · $timer"
    }
    val dot = when {
        !reachable -> scheme.error
        busy || stale || !known -> scheme.tertiary
        else -> GainUp
    }
    val color = when {
        !reachable -> scheme.onSurfaceVariant
        busy -> scheme.onSurfaceVariant
        stale || !known -> scheme.tertiary
        else -> scheme.outline
    }
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(dot))
        Text(text, style = MaterialTheme.typography.labelMedium, color = color)
    }
}

@Composable
private fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerLow)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Label(title)
        content()
    }
}

@Composable
private fun BasisBlock(basis: MoneyBasis, fx: MoneyFx, hidden: Boolean) {
    Section("cost basis") {
        BasisRow("avg buy", shown("$ ${MoneyFormat.grouped(basis.avgUsd, 2)}", hidden), MoneyFormat.gainRatio(fx.btcUsd, basis.avgUsd), null)
        BasisRow("avg buy", shown("R$ ${MoneyFormat.grouped(basis.avgBrl, 2)}", hidden), MoneyFormat.gainRatio(MoneyFormat.nowBrl(fx), basis.avgBrl), null)
        BasisRow("bought", shown("${MoneyFormat.ICON} ${MoneyFormat.btc(basis.btc)}", hidden), null, "${basis.buys} buys since ${MoneyFormat.since(basis.first)}")
    }
}

@Composable
private fun BasisRow(key: String, value: String, ratio: Double?, trailing: String?) {
    val scheme = MaterialTheme.colorScheme
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(key, style = MaterialTheme.typography.labelLarge, color = scheme.outline, modifier = Modifier.width(68.dp))
        Text(value, style = MaterialTheme.typography.labelLarge, color = scheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        if (trailing != null) {
            Text(trailing, style = MaterialTheme.typography.labelMedium, color = scheme.outline, maxLines = 1, textAlign = TextAlign.End)
        } else {
            Text(
                MoneyFormat.gain(ratio),
                style = MaterialTheme.typography.labelLarge,
                color = when {
                    ratio == null -> scheme.outline
                    ratio >= 0 -> GainUp
                    else -> scheme.error
                },
                maxLines = 1,
                textAlign = TextAlign.End,
            )
        }
    }
}

@Composable
private fun VenueRow(venue: MoneyVenue, total: Double?, unit: String, fx: MoneyFx, hidden: Boolean, expanded: Boolean, onToggle: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val plain = !venue.missing && !venue.noteOnly
    val expandable = plain && venue.holdings.isNotEmpty()
    val stale = venue.staleSince != null
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .clickable(enabled = expandable, onClick = onToggle)
                .padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                if (expanded) Icons.Filled.ExpandMore else Icons.Filled.ChevronRight,
                null,
                tint = scheme.outline,
                modifier = Modifier.size(18.dp).alpha(if (expandable) 1f else 0f),
            )
            if (!plain) {
                Text(venue.label, style = MaterialTheme.typography.bodyLarge, color = scheme.outline, maxLines = 1)
                Text(
                    if (venue.missing) "unavailable" else venue.note ?: "",
                    style = MaterialTheme.typography.labelMedium,
                    color = scheme.outline,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
            } else {
                Row(modifier = Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(venue.label, style = MaterialTheme.typography.bodyLarge, color = scheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    if (stale) Label("· stale", color = scheme.tertiary)
                }
                Text(
                    shown(MoneyFormat.unit(venue.usd, unit, fx), hidden),
                    style = MaterialTheme.typography.labelLarge,
                    color = if (stale) scheme.tertiary else scheme.onSurface,
                    maxLines = 1,
                )
                val share = MoneyFormat.share(venue.usd, total)
                if (share != null) {
                    Text(share, style = MaterialTheme.typography.labelMedium, color = scheme.outline, textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.width(40.dp))
                }
            }
        }
        if (expandable && expanded) {
            Column(modifier = Modifier.fillMaxWidth().padding(start = 26.dp, bottom = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                venue.holdings.forEach { HoldingRow(it, unit, fx, hidden) }
            }
        }
    }
}

@Composable
private fun HoldingRow(entry: MoneyHolding, unit: String, fx: MoneyFx, hidden: Boolean) {
    val scheme = MaterialTheme.colorScheme
    val mono = MaterialTheme.typography.labelLarge
    if (entry.amount == null && entry.usd == null) {
        Text("${entry.asset} ${entry.label}  ${entry.note ?: "--"}", style = mono, color = scheme.outline)
        return
    }
    val dust = entry.isDust
    val quantity = entry.amount?.let { "${shown(MoneyFormat.qty(it), hidden)} ${entry.asset}" } ?: entry.asset
    Column(modifier = Modifier.fillMaxWidth().alpha(if (dust) 0.7f else 1f)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(quantity, style = mono, color = if (dust) scheme.outline else scheme.onSurface, maxLines = 1)
            Text(entry.label, style = MaterialTheme.typography.labelMedium, color = scheme.outline, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).padding(top = 1.dp))
            Text(
                shown(MoneyFormat.unit(entry.usd, unit, fx), hidden),
                style = mono,
                color = if (dust) scheme.outline else scheme.onSurfaceVariant,
                textAlign = TextAlign.End,
                maxLines = 1,
            )
        }
        if (dust && entry.note != null) {
            Text(entry.note, style = MaterialTheme.typography.labelMedium, color = scheme.outline, modifier = Modifier.padding(top = 2.dp))
        }
    }
}
