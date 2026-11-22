package ac.mvr.phone.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
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
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
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
        if (cache != null && cache.hasCache && (total ?: 0.0) == 0.0) {
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

@Composable
fun MoneyScreen(store: Store, onCollapse: () -> Unit) {
    val data by store.money.cache.collectAsStateWithLifecycle()
    val refreshing by store.money.refreshing.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val unitPref by store.prefs.unit.collectAsStateWithLifecycle()
    val hidden by store.prefs.hiddenAmounts.collectAsStateWithLifecycle()
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
            TotalBlock(
                cache = cache,
                unit = unit,
                hidden = hidden,
                busy = busy,
                canRefresh = reachable,
                onUnit = store.prefs::setUnit,
                onHidden = { store.prefs.setHiddenAmounts(!hidden) },
                onRefresh = store.money::refreshNow,
            )
            FetchedLine(cache, reachable, busy, nowMs)
            cache?.basis?.let { BasisBlock(it, fx, unit, hidden) }
            if (cache != null && cache.venues.isNotEmpty()) {
                val statement = remember(cache) { statementOf(cache) }
                val columns = rememberColumns(statement)
                val readout = Readout(unit, fx, cache.totalUsd, hidden)
                WhatItIs(statement, columns, readout)
                WhereItSits(statement, columns, readout)
            }
            val error = cache?.error
            if (cache != null && cache.hasCache && error != null) {
                Text(error, style = NoteText, color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(horizontal = 4.dp))
            }
        }
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}

private const val SMALL_SHARE = 0.01

private val GridGap = 10.dp

private val TotalLarge = TextStyle(fontWeight = FontWeight.Medium, fontSize = 32.sp, letterSpacing = (-0.5).sp, fontFeatureSettings = "tnum")

private val HeadingText = TextStyle(fontWeight = FontWeight.Medium, fontSize = 11.sp, letterSpacing = 1.sp)

private val BodyText = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontFeatureSettings = "tnum")

private val StrongText = TextStyle(fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 21.sp, fontFeatureSettings = "tnum")

private val ShareText = TextStyle(fontSize = 12.5.sp, fontFeatureSettings = "tnum")

private val NoteText = TextStyle(fontSize = 12.sp, lineHeight = 16.sp)

private val TagText = TextStyle(fontSize = 11.sp, lineHeight = 16.sp)

private data class Line(
    val asset: String,
    val name: String,
    val amount: Double?,
    val usd: Double?,
    val dust: Boolean,
    val count: Int,
    val detail: String?,
    val note: String?,
)

private data class Place(val name: String, val usd: Double?, val missing: Boolean, val stale: Boolean, val note: String?, val lines: List<Line>)

private data class AssetTotal(val asset: String, val name: String, val dust: Boolean, val amount: Double?, val usd: Double, val count: Int)

private data class Statement(val places: List<Place>, val assets: List<AssetTotal>, val small: List<AssetTotal>)

private data class Readout(val unit: String, val fx: MoneyFx, val total: Double?, val hidden: Boolean) {
    fun money(usd: Double?): String = shown(MoneyFormat.unit(usd, unit, fx), hidden)

    fun share(usd: Double?): String = MoneyFormat.share(usd, total) ?: ""

    fun quantity(amount: Double?, asset: String): String =
        if (amount == null || asset.lowercase() == unit) "" else shown(MoneyFormat.qty(amount), hidden)
}

private fun lineOf(holding: MoneyHolding, venue: MoneyVenue): Line {
    val label = holding.label
    val plain = label.isEmpty() || label.equals(venue.label, ignoreCase = true) || label == holding.asset
    val bare = label.none(Char::isWhitespace) && venue.holdings.count { it.asset == holding.asset } < 2
    return Line(
        asset = holding.asset,
        name = if (holding.isDust) "Dust" else holding.asset,
        amount = holding.amount,
        usd = holding.usd,
        dust = holding.isDust,
        count = if (holding.isDust) label.takeWhile(Char::isDigit).toIntOrNull() ?: 0 else 0,
        detail = if (holding.isDust || plain || bare) null else label,
        note = holding.note,
    )
}

private fun placeOf(venue: MoneyVenue): Place = Place(
    name = venue.label,
    usd = if (venue.missing) null else venue.usd,
    missing = venue.missing,
    stale = venue.staleSince != null,
    note = venue.note.takeIf { venue.noteOnly },
    lines = if (venue.missing) emptyList() else venue.holdings.map { lineOf(it, venue) }.sortedByDescending { it.usd ?: -1.0 },
)

private fun totalsOf(places: List<Place>): List<AssetTotal> =
    places.flatMap { it.lines }
        .filter { it.asset.isNotEmpty() && (it.amount != null || it.usd != null) }
        .groupBy { it.asset }
        .map { (asset, lines) ->
            val amounts = lines.mapNotNull { it.amount }
            AssetTotal(
                asset = asset,
                name = lines.first().name,
                dust = lines.first().dust,
                amount = if (amounts.size == lines.size) amounts.sum() else null,
                usd = lines.sumOf { it.usd ?: 0.0 },
                count = lines.sumOf { it.count },
            )
        }
        .sortedByDescending { it.usd }

private fun statementOf(cache: MoneyCache): Statement {
    val places = cache.venues.map(::placeOf).sortedByDescending { it.usd ?: -1.0 }
    val totals = totalsOf(places)
    val whole = cache.totalUsd?.takeIf { it > 0 } ?: return Statement(places, totals, emptyList())
    val (big, small) = totals.partition { it.usd / whole >= SMALL_SHARE }
    return if (small.size > 1) Statement(places, big, small) else Statement(places, totals, emptyList())
}

private fun Modifier.dashedUnderline(color: Color): Modifier = drawBehind {
    val y = size.height - 0.5.dp.toPx()
    val dash = 3.dp.toPx()
    drawLine(color, Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(dash, dash)))
}

private fun Modifier.topRule(color: Color): Modifier = drawBehind {
    drawLine(color, Offset(0f, 0f), Offset(size.width, 0f), strokeWidth = 1.dp.toPx())
}

@Composable
private fun Heading(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(), style = HeadingText, color = MaterialTheme.colorScheme.outline, maxLines = 1, modifier = modifier)
}

@Composable
private fun Panel(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerLow)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Heading(title)
        content()
    }
}

@Composable
private fun TotalBlock(
    cache: MoneyCache?,
    unit: String,
    hidden: Boolean,
    busy: Boolean,
    canRefresh: Boolean,
    onUnit: (String) -> Unit,
    onHidden: () -> Unit,
    onRefresh: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val fx = cache?.fx ?: MoneyFx()
    val total = cache?.totalUsd
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(scheme.surfaceContainerLow)
            .padding(start = 16.dp, end = 6.dp, top = 4.dp, bottom = 14.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Heading("total", Modifier.weight(1f))
            IconButton(onClick = onHidden, modifier = Modifier.size(42.dp)) {
                Icon(
                    if (hidden) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                    if (hidden) "show amounts" else "hide amounts",
                    tint = scheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onRefresh, enabled = canRefresh && !busy, modifier = Modifier.size(42.dp)) {
                if (busy) {
                    Spinning { angle -> Icon(Icons.Outlined.Refresh, "refreshing", tint = scheme.tertiary, modifier = Modifier.rotate(angle)) }
                } else {
                    Icon(Icons.Outlined.Refresh, "refresh", tint = scheme.onSurfaceVariant, modifier = Modifier.alpha(if (canRefresh) 1f else 0.4f))
                }
            }
        }
        Text(
            shown(MoneyFormat.unit(total, unit, fx), hidden),
            style = TotalLarge,
            color = if (total == null) scheme.outline else scheme.onSurface,
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .padding(end = 10.dp)
                .clip(RoundedCornerShape(8.dp))
                .clickable { onUnit(MoneyFormat.nextUnit(unit)) },
        )
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.Bottom) {
            MoneyFormat.units.filter { it != unit }.forEach { other ->
                Text(
                    shown(MoneyFormat.unit(total, other, fx), hidden),
                    style = BodyText,
                    color = scheme.onSurfaceVariant,
                    maxLines = 1,
                    modifier = Modifier
                        .clickable { onUnit(other) }
                        .dashedUnderline(scheme.outlineVariant)
                        .padding(vertical = 2.dp),
                )
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
    val timer = "refreshes every 15 min"
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
        Text(text, style = NoteText, color = color)
    }
}

@Composable
private fun BasisBlock(basis: MoneyBasis, fx: MoneyFx, unit: String, hidden: Boolean) {
    val scheme = MaterialTheme.colorScheme
    val brl = unit == "brl"
    val symbol = if (brl) "R$ " else "$ "
    val paid = if (brl) basis.avgBrl else basis.avgUsd
    val today = if (brl) MoneyFormat.nowBrl(fx) else fx.btcUsd
    val ratio = MoneyFormat.gainRatio(today, paid)
    Panel("bitcoin bought") {
        Text(
            "${shown(MoneyFormat.btc(basis.btc), hidden)} BTC in ${basis.buys} buys since ${MoneyFormat.since(basis.first)}",
            style = BodyText,
            color = scheme.onSurfaceVariant,
        )
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("paid on average", style = BodyText, color = scheme.outline, maxLines = 1)
                Text("price today", style = BodyText, color = scheme.outline, maxLines = 1)
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(shown(symbol + MoneyFormat.grouped(paid, 2), hidden), style = BodyText, color = scheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(today?.let { symbol + MoneyFormat.grouped(it, 2) } ?: "--", style = BodyText, color = scheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("", style = BodyText)
                Text(
                    MoneyFormat.gain(ratio),
                    style = BodyText.copy(fontWeight = FontWeight.Medium),
                    color = when {
                        ratio == null -> scheme.outline
                        ratio >= 0 -> GainUp
                        else -> scheme.error
                    },
                    maxLines = 1,
                )
            }
        }
    }
}

private class Columns(val name: Dp, val share: Dp)

@Composable
private fun rememberColumns(statement: Statement): Columns {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    return remember(statement, density) {
        val names = statement.assets.map { it.name } + statement.places.flatMap { place -> place.lines.map { it.name } } + "${statement.small.size} small"
        val widest = names.maxOf { measurer.measure(it, BodyText, maxLines = 1, softWrap = false).size.width }
        val share = measurer.measure("100%", ShareText, maxLines = 1, softWrap = false).size.width
        with(density) { Columns(name = maxOf(widest.toDp(), 56.sp.toDp()), share = share.toDp()) }
    }
}

@Composable
private fun GridRow(columns: Columns, name: String, quantity: String, value: String, share: String, quiet: Boolean) {
    val scheme = MaterialTheme.colorScheme
    val main = if (quiet) scheme.onSurfaceVariant else scheme.onSurface
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(GridGap)) {
        Text(name, style = BodyText, color = main, maxLines = 1, softWrap = false, modifier = Modifier.widthIn(min = columns.name).alignByBaseline())
        Text(quantity, style = BodyText, color = scheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).alignByBaseline())
        Text(value, style = BodyText, color = main, maxLines = 1, softWrap = false, textAlign = TextAlign.End, modifier = Modifier.alignByBaseline())
        Text(
            share,
            style = ShareText,
            color = scheme.outline,
            maxLines = 1,
            softWrap = false,
            textAlign = TextAlign.End,
            modifier = Modifier.width(columns.share).alignByBaseline(),
        )
    }
}

@Composable
private fun GridNote(columns: Columns, text: String) {
    Text(text, style = NoteText, color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(start = columns.name + GridGap))
}

@Composable
private fun StaleTag() {
    val color = MaterialTheme.colorScheme.tertiary
    Text(
        "stale",
        style = TagText,
        color = color,
        maxLines = 1,
        modifier = Modifier
            .padding(start = 6.dp)
            .border(1.dp, color.copy(alpha = 0.5f), RoundedCornerShape(5.dp))
            .padding(horizontal = 5.dp),
    )
}

@Composable
private fun WhatItIs(statement: Statement, columns: Columns, readout: Readout) {
    Panel("what it is") {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            statement.assets.forEach { asset ->
                val quantity = if (asset.dust) "${asset.count} small" else readout.quantity(asset.amount, asset.asset)
                GridRow(columns, asset.name, quantity, readout.money(asset.usd), readout.share(asset.usd), quiet = false)
            }
            if (statement.small.isNotEmpty()) {
                val sum = statement.small.sumOf { it.usd }
                Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    GridRow(columns, "${statement.small.size} small", "", readout.money(sum), readout.share(sum), quiet = false)
                    GridNote(columns, statement.small.joinToString(", ") { it.name })
                }
            }
        }
    }
}

@Composable
private fun WhereItSits(statement: Statement, columns: Columns, readout: Readout) {
    val rule = MaterialTheme.colorScheme.outlineVariant
    Panel("where it sits") {
        statement.places.forEach { place ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp)
                    .topRule(rule)
                    .padding(top = 10.dp),
                verticalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                PlaceRow(columns, place, readout)
                place.note?.let { GridNote(columns, it) }
                place.lines.forEach { LineEntry(columns, it, readout) }
            }
        }
    }
}

@Composable
private fun PlaceRow(columns: Columns, place: Place, readout: Readout) {
    val scheme = MaterialTheme.colorScheme
    val known = !place.missing && place.note == null
    val color = if (known) scheme.onSurface else scheme.outline
    val value = when {
        place.missing -> "unavailable"
        place.note != null -> ""
        else -> readout.money(place.usd)
    }
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(GridGap)) {
        Row(modifier = Modifier.weight(1f).alignByBaseline(), verticalAlignment = Alignment.CenterVertically) {
            Text(place.name, style = StrongText, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            if (place.stale) StaleTag()
        }
        Text(value, style = StrongText, color = color, maxLines = 1, softWrap = false, textAlign = TextAlign.End, modifier = Modifier.alignByBaseline())
        Text(
            if (known) readout.share(place.usd) else "",
            style = ShareText,
            color = scheme.outline,
            maxLines = 1,
            softWrap = false,
            textAlign = TextAlign.End,
            modifier = Modifier.width(columns.share).alignByBaseline(),
        )
    }
}

@Composable
private fun LineEntry(columns: Columns, line: Line, readout: Readout) {
    val quantity = if (line.dust) "${line.count} small balances" else readout.quantity(line.amount, line.asset)
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        GridRow(columns, line.name, quantity, readout.money(line.usd), "", quiet = true)
        line.detail?.let { GridNote(columns, it) }
        line.note?.let { GridNote(columns, it) }
    }
}
