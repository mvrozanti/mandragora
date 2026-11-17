package ac.mvr.phone.ui

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

sealed interface MdBlock
data class MdPara(val text: String) : MdBlock
data class MdHeading(val level: Int, val text: String) : MdBlock
data class MdList(val ordered: Boolean, val items: List<String>) : MdBlock
data class MdQuote(val text: String) : MdBlock
data class MdFence(val body: String) : MdBlock
data class MdTable(val head: List<String>, val rows: List<List<String>>) : MdBlock

object Markdown {
    private val fence = Regex("^\\s*```")
    private val tableRow = Regex("^\\s*\\|")
    private val tableRule = Regex("^\\s*\\|\\s*:?-{2,}")
    private val heading = Regex("^(#{1,4})\\s+(.*)")
    private val item = Regex("^\\s*([-*]|\\d+\\.)\\s+")
    private val ordered = Regex("^\\s*\\d+\\.")
    private val quote = Regex("^>\\s?")
    private val paraStop = Regex("^\\s*(```|\\||#{1,4}\\s|[-*]\\s|\\d+\\.\\s|>)")
    private val continuation = Regex("^\\s{2,}\\S")
    private val inlineToken = Regex("(⟦([nracdwu]):([\\s\\S]*?)⟧)|(`([^`]+)`)|(\\*\\*([^*]+)\\*\\*)|(\\*([^*\\s][^*]*)\\*)|(\\[([^\\]]+)\\]\\(([^)]+)\\))")
    private val number = Regex("^[\\s−+\\-~]*[\\d.,]+\\s*(%|°|s|k|ms|MB|GB|GiB|MiB|x|×)?$")

    fun blocks(text: String): List<MdBlock> {
        val lines = text.split('\n')
        val out = ArrayList<MdBlock>()
        var i = 0
        while (i < lines.size) {
            val line = lines[i]
            if (fence.containsMatchIn(line)) {
                val body = ArrayList<String>()
                i++
                while (i < lines.size && !fence.containsMatchIn(lines[i])) body.add(lines[i++])
                i++
                out.add(MdFence(body.joinToString("\n")))
                continue
            }
            if (tableRow.containsMatchIn(line) && i + 1 < lines.size && tableRule.containsMatchIn(lines[i + 1])) {
                val rows = ArrayList<String>()
                while (i < lines.size && tableRow.containsMatchIn(lines[i])) rows.add(lines[i++])
                val cells = { r: String -> r.trim().removePrefix("|").removeSuffix("|").split('|').map { it.trim() } }
                out.add(MdTable(cells(rows[0]), rows.drop(2).map(cells)))
                continue
            }
            val h = heading.find(line)
            if (h != null) {
                out.add(MdHeading(h.groupValues[1].length, h.groupValues[2]))
                i++
                continue
            }
            if (item.containsMatchIn(line)) {
                val isOrdered = ordered.containsMatchIn(line)
                val items = ArrayList<String>()
                while (i < lines.size && item.containsMatchIn(lines[i])) {
                    var entry = lines[i].replace(item, "")
                    i++
                    while (i < lines.size && continuation.containsMatchIn(lines[i]) && !item.containsMatchIn(lines[i])) entry += " " + lines[i++].trim()
                    items.add(entry)
                }
                out.add(MdList(isOrdered, items))
                continue
            }
            if (quote.containsMatchIn(line)) {
                val parts = ArrayList<String>()
                while (i < lines.size && quote.containsMatchIn(lines[i])) parts.add(lines[i++].replace(quote, ""))
                out.add(MdQuote(parts.joinToString(" ")))
                continue
            }
            if (line.isBlank()) {
                i++
                continue
            }
            val para = ArrayList<String>()
            while (i < lines.size && lines[i].isNotBlank() && !paraStop.containsMatchIn(lines[i])) para.add(lines[i++])
            if (para.isEmpty()) para.add(lines[i++])
            out.add(MdPara(para.joinToString(" ")))
        }
        return out
    }

    private class Built(val text: StringBuilder = StringBuilder(), val spans: MutableList<Triple<Int, Int, SpanStyle>> = ArrayList())

    private fun walk(src: String, into: Built, scheme: ColorScheme) {
        var last = 0
        for (m in inlineToken.findAll(src)) {
            into.text.append(src, last, m.range.first)
            val start = into.text.length
            val g = m.groupValues
            when {
                g[1].isNotEmpty() -> {
                    walk(g[3], into, scheme)
                    into.spans.add(Triple(start, into.text.length, Meaning.markStyle(g[2][0], scheme)))
                }
                g[4].isNotEmpty() -> {
                    into.text.append(g[5])
                    into.spans.add(Triple(start, into.text.length, SpanStyle(fontFamily = Mono, color = scheme.primary, background = scheme.surfaceContainerHigh)))
                }
                g[6].isNotEmpty() -> {
                    walk(g[7], into, scheme)
                    into.spans.add(Triple(start, into.text.length, SpanStyle(fontWeight = FontWeight.Bold)))
                }
                g[8].isNotEmpty() -> {
                    walk(g[9], into, scheme)
                    into.spans.add(Triple(start, into.text.length, SpanStyle(fontStyle = FontStyle.Italic)))
                }
                else -> {
                    walk(g[11], into, scheme)
                    into.spans.add(Triple(start, into.text.length, SpanStyle(color = scheme.primary, textDecoration = TextDecoration.Underline)))
                }
            }
            last = m.range.last + 1
        }
        into.text.append(src, last, src.length)
    }

    fun inline(src: String, scheme: ColorScheme): AnnotatedString {
        val built = Built()
        walk(src, built, scheme)
        val text = built.text.toString()
        return buildAnnotatedString {
            append(text)
            var offset = 0
            for (line in text.split('\n')) {
                for (span in Meaning.scoreLine(line)) addStyle(Meaning.style(span.facet, scheme), offset + span.start, offset + span.end)
                offset += line.length + 1
            }
            for ((start, end, style) in built.spans) addStyle(style, start, end)
        }
    }

    private val plainScheme = androidx.compose.material3.darkColorScheme()

    fun plain(src: String): String {
        val built = Built()
        walk(src, built, plainScheme)
        return built.text.toString()
    }

    fun numeric(cell: String): Boolean = cell.isBlank() || cell == "—" || number.matches(plain(cell))
}

@Composable
fun MarkdownText(text: String, scheme: ColorScheme) {
    val blocks = remember(text) { Markdown.blocks(text) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        blocks.forEach { block ->
            when (block) {
                is MdPara -> Text(remember(block, scheme) { Markdown.inline(block.text, scheme) }, style = MaterialTheme.typography.bodyMedium)
                is MdHeading -> Text(
                    remember(block, scheme) { Markdown.inline(block.text, scheme) },
                    style = if (block.level <= 2) MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                )
                is MdList -> Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    block.items.forEachIndexed { index, entry ->
                        Row {
                            Text(if (block.ordered) "${index + 1}." else "•", style = MaterialTheme.typography.bodyMedium, color = scheme.outline, modifier = Modifier.width(20.dp))
                            Text(remember(entry, scheme) { Markdown.inline(entry, scheme) }, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
                is MdQuote -> Row(
                    modifier = Modifier.drawBehind { drawLine(scheme.outlineVariant, Offset(0f, 0f), Offset(0f, size.height), strokeWidth = 3.dp.toPx()) }.padding(start = 12.dp),
                ) {
                    Text(remember(block, scheme) { Markdown.inline(block.text, scheme) }, style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
                }
                is MdFence -> Box(
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(scheme.surfaceContainerLow).horizontalScroll(rememberScrollState()).padding(horizontal = 10.dp, vertical = 8.dp),
                ) {
                    Text(block.body, style = TextStyle(fontFamily = Mono, fontSize = 12.sp), color = scheme.primary, softWrap = false)
                }
                is MdTable -> MarkdownTable(block, scheme)
            }
        }
    }
}

@Composable
private fun MarkdownTable(table: MdTable, scheme: ColorScheme) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val cellStyle = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp)
    val headStyle = cellStyle.copy(fontWeight = FontWeight.Medium, fontSize = 12.sp)
    val columns = table.head.size
    val rows = remember(table) { table.rows.map { r -> List(columns) { c -> r.getOrElse(c) { "" } } } }
    val numericCols = remember(table) { List(columns) { c -> rows.all { Markdown.numeric(it[c]) } } }
    val longest = remember(table) { List(columns) { c -> maxOf(Markdown.plain(table.head[c]).length, rows.maxOfOrNull { Markdown.plain(it[c]).length } ?: 0) } }
    val widths: List<Dp> = remember(table, density) {
        List(columns) { c ->
            val widest = (listOf(table.head[c]) + rows.map { it[c] }).maxOf { cell ->
                measurer.measure(Markdown.plain(cell), if (cell == table.head[c]) headStyle else cellStyle, softWrap = false).size.width
            }
            val natural = with(density) { widest.toDp() } + 20.dp
            val width = when {
                longest[c] <= 16 -> natural
                longest[c] > 30 -> natural.coerceIn(168.dp, 220.dp)
                else -> natural.coerceIn(96.dp, 220.dp)
            }
            if (c == 0 && columns > 2) width.coerceAtMost(140.dp) else width
        }
    }
    val pinned = columns > 2
    val scroll = rememberScrollState()
    Column(modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(scheme.surfaceContainerLow)) {
        TableRow(table.head, widths, numericCols, pinned, scroll, scheme, header = true, headStyle)
        rows.forEach { row -> TableRow(row, widths, numericCols, pinned, scroll, scheme, header = false, cellStyle) }
    }
}

@Composable
private fun TableRow(
    cells: List<String>,
    widths: List<Dp>,
    numericCols: List<Boolean>,
    pinned: Boolean,
    scroll: ScrollState,
    scheme: ColorScheme,
    header: Boolean,
    style: TextStyle,
) {
    val line = scheme.outlineVariant
    val firstWidth = widths.first()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(if (header) scheme.surfaceContainerHigh else scheme.surfaceContainerLow)
            .drawBehind {
                drawLine(line, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 1.dp.toPx())
                if (pinned) drawLine(line, Offset(firstWidth.toPx(), 0f), Offset(firstWidth.toPx(), size.height), strokeWidth = 1.dp.toPx())
            },
    ) {
        val start = if (pinned) 1 else 0
        if (pinned) Cell(cells[0], widths[0], numericCols[0], scheme, header, style)
        Row(modifier = Modifier.horizontalScroll(scroll)) {
            for (c in start until cells.size) Cell(cells[c], widths[c], numericCols[c], scheme, header, style)
        }
    }
}

@Composable
private fun Cell(text: String, width: Dp, numeric: Boolean, scheme: ColorScheme, header: Boolean, style: TextStyle) {
    Text(
        remember(text, scheme) { Markdown.inline(text, scheme) },
        style = style,
        color = if (header) scheme.onSurfaceVariant else scheme.onSurface,
        textAlign = if (numeric) TextAlign.End else TextAlign.Start,
        softWrap = !numeric,
        modifier = Modifier.width(width).padding(horizontal = 10.dp, vertical = 7.dp),
    )
}
