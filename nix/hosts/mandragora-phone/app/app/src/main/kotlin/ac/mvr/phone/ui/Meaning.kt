package ac.mvr.phone.ui

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight

enum class Facet { Risk, Command, Action, Uncertainty, Dim }

data class Span(val start: Int, val end: Int, val facet: Facet, val weight: Float)

object Meaning {
    private const val MAX_SPANS_PER_LINE = 3
    private const val RISK_COMMAND_WEIGHT = 0.95f
    private const val RISK_PROSE_WEIGHT = 0.85f
    private const val COMMAND_WEIGHT = 0.75f
    private const val ACTION_WEIGHT = 0.7f
    private const val UNCERTAINTY_WEIGHT = 0.4f
    private const val DIM_WEIGHT = 0.5f

    private val riskCommands = listOf("rm -rf", "rm -fr", "sudo rm", "git reset --hard", "git push -f", "git push --force", "git clean -fd", "--force", "dd of=", "mkfs", "chmod -R 777", ":>")
    private val riskSql = listOf("DROP TABLE", "DROP DATABASE", "TRUNCATE")
    private val riskProse = listOf("irreversible", "cannot be undone", "can't be undone", "permanently delete", "truncate")
    private val hedges = listOf("probably", "might", "may not", "I believe", "I think", "should work", "untested", "not sure", "unverified", "approximately", "roughly")
    private val binaries = setOf(
        "git", "cargo", "npm", "pnpm", "yarn", "pip", "pip3", "python", "python3", "docker",
        "kubectl", "make", "rm", "mv", "cp", "mkdir", "ssh", "scp", "rsync", "curl", "wget",
        "systemctl", "journalctl", "nix", "nixos-rebuild", "apt", "brew", "chmod", "chown", "dd",
        "mkfs", "tar", "sed", "awk", "grep", "cat",
    )
    private val vetoWords = setOf("is", "are", "was", "were", "will", "has", "have", "can", "and", "or", "the", "a")
    private val backtick = Regex("`([^`\\n]+)`")
    private val dollarLine = Regex("^\\s{0,8}\\$\\s+(\\S.*)$")
    private val indentedCommand = Regex("^(\\s{2,})((?:sudo\\s+)?[a-z][a-z0-9_.-]*)(\\s+)(\\S+)")
    private val action = Regex("(you need to|you'll need to|you should now|run the following|make sure to|don't forget to|before you \\w[^,]{0,60},|manually)", RegexOption.IGNORE_CASE)
    private val shellShape = Regex("^(\\$\\s+)?(sudo\\s+)?([a-z][a-z0-9_.-]*)(\\s|$)")
    private val dimOpener = Regex("^\\s*(Let me\\b|I'll\\b|I'm going to\\b|Now I\\b|First,|Next,|Great!|Perfect!|Sure\\b|Certainly\\b)")
    private val toolNarration = Regex("^\\s*(?:[⏺●○]\\s|⎿\\s|Tool call:|Calling tool\\b|Running tool\\b)")

    fun scoreLine(line: String): List<Span> {
        val spans = ArrayList<Span>()
        risk(line, spans)
        command(line, spans)
        actions(line, spans)
        hedge(line, spans)
        dim(line, spans)
        return spans.sortedWith(compareByDescending<Span> { it.weight }.thenBy { it.start }).take(MAX_SPANS_PER_LINE).sortedBy { it.start }
    }

    fun annotate(text: String, scheme: ColorScheme): AnnotatedString = buildAnnotatedString {
        append(text)
        var offset = 0
        var fenced = false
        for (line in text.split('\n')) {
            val end = offset + line.length
            when {
                line.trimStart().startsWith("```") -> {
                    fenced = !fenced
                    addStyle(SpanStyle(color = scheme.outline), offset, end)
                }
                fenced -> addStyle(SpanStyle(fontFamily = Mono, color = scheme.primary), offset, end)
                else -> for (span in scoreLine(line)) addStyle(style(span.facet, scheme), offset + span.start, offset + span.end)
            }
            offset = end + 1
        }
    }

    fun style(facet: Facet, scheme: ColorScheme): SpanStyle = when (facet) {
        Facet.Risk -> SpanStyle(color = scheme.error, fontWeight = FontWeight.Bold)
        Facet.Command -> SpanStyle(fontFamily = Mono, color = scheme.primary, background = scheme.surfaceContainerHigh)
        Facet.Action -> SpanStyle(color = scheme.tertiary, fontWeight = FontWeight.SemiBold)
        Facet.Uncertainty -> SpanStyle(color = scheme.onSurface.copy(alpha = 0.6f), fontStyle = FontStyle.Italic)
        Facet.Dim -> SpanStyle(color = scheme.onSurface.copy(alpha = 0.5f))
    }

    private fun push(spans: MutableList<Span>, start: Int, end: Int, facet: Facet, weight: Float) {
        if (start < end) spans.add(Span(start, end, facet, weight))
    }

    private fun occurrences(text: String, pattern: String, ignoreCase: Boolean): List<Int> {
        val found = ArrayList<Int>()
        var from = 0
        while (true) {
            val at = text.indexOf(pattern, from, ignoreCase)
            if (at < 0) break
            found.add(at)
            from = at + pattern.length
        }
        return found
    }

    private fun wordBounded(text: String, start: Int, end: Int): Boolean =
        (start == 0 || !text[start - 1].isLetterOrDigit()) && (end >= text.length || !text[end].isLetterOrDigit())

    private fun risk(line: String, spans: MutableList<Span>) {
        for (pattern in riskCommands) for (at in occurrences(line, pattern, false)) {
            val end = at + pattern.length
            if (pattern == "--force" && end < line.length && line[end] == '-') continue
            if (pattern == "mkfs" && at > 0 && line[at - 1].isLetterOrDigit()) continue
            push(spans, at, end, Facet.Risk, RISK_COMMAND_WEIGHT)
        }
        for (pattern in riskSql) for (at in occurrences(line, pattern, false)) {
            if (wordBounded(line, at, at + pattern.length)) push(spans, at, at + pattern.length, Facet.Risk, RISK_COMMAND_WEIGHT)
        }
        for (pattern in riskProse) for (at in occurrences(line, pattern, true)) {
            if (wordBounded(line, at, at + pattern.length)) push(spans, at, at + pattern.length, Facet.Risk, RISK_PROSE_WEIGHT)
        }
    }

    private fun command(line: String, spans: MutableList<Span>) {
        for (match in backtick.findAll(line)) {
            val group = match.groups[1] ?: continue
            if (shellShaped(group.value)) push(spans, group.range.first, group.range.last + 1, Facet.Command, COMMAND_WEIGHT)
        }
        val dollar = dollarLine.find(line)?.groups?.get(1)
        if (dollar != null) {
            push(spans, dollar.range.first, dollar.range.last + 1, Facet.Command, COMMAND_WEIGHT)
            return
        }
        val indented = indentedCommand.find(line) ?: return
        val binary = indented.groups[2] ?: return
        val arg = indented.groups[4] ?: return
        val bare = binary.value.removePrefix("sudo").trim()
        if (bare in binaries && arg.value !in vetoWords && !arg.value.first().isUpperCase()) {
            push(spans, binary.range.first, line.trimEnd().length, Facet.Command, COMMAND_WEIGHT)
        }
    }

    private fun shellShaped(content: String): Boolean {
        val match = shellShape.find(content) ?: return false
        if (match.groups[1] != null || match.groups[2] != null) return true
        val binary = match.groups[3]?.value ?: return false
        val rest = content.substring(match.range.last + 1).trimStart()
        val arg = rest.split(Regex("\\s+")).firstOrNull() ?: ""
        return binary in binaries && (rest.isEmpty() || arg !in vetoWords)
    }

    private fun actions(line: String, spans: MutableList<Span>) {
        for (match in action.findAll(line)) {
            val head = line.substring(0, match.range.first).trimEnd()
            if (!(head.isEmpty() || head.last() in ".!?:;")) continue
            val tail = line.substring(match.range.last + 1)
            val stop = tail.indexOfFirst { it == '.' || it == '!' || it == '?' }
            val end = if (stop < 0) line.trimEnd().length else match.range.last + 1 + stop
            push(spans, match.range.first, end, Facet.Action, ACTION_WEIGHT)
        }
    }

    private fun hedge(line: String, spans: MutableList<Span>) {
        for (pattern in hedges) for (at in occurrences(line, pattern, true)) {
            val end = at + pattern.length
            if (!wordBounded(line, at, end)) continue
            val clauseStart = line.substring(0, at).indexOfLast { it in ",;.:" } + 1
            val after = line.substring(end)
            val stop = after.indexOfFirst { it in ",;.:" }
            val clauseEnd = if (stop < 0) line.trimEnd().length else end + stop
            val lead = line.substring(clauseStart)
            val start = clauseStart + (lead.length - lead.trimStart().length)
            push(spans, start, clauseEnd, Facet.Uncertainty, UNCERTAINTY_WEIGHT)
        }
    }

    private fun dim(line: String, spans: MutableList<Span>) {
        if (dimOpener.containsMatchIn(line) || toolNarration.containsMatchIn(line)) {
            val start = line.length - line.trimStart().length
            push(spans, start, line.trimEnd().length, Facet.Dim, DIM_WEIGHT)
        }
    }
}
