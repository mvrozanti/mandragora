package ac.mvr.phone.logic

import ac.mvr.phone.net.CodeEntry
import ac.mvr.phone.net.CodePart

const val ABORTED = "MessageAbortedError"

fun said(entry: CodeEntry): String =
    entry.parts.filter { it.type == "text" && !it.synthetic && !it.ignored }.mapNotNull { it.text }.joinToString("\n")

class Stops(val resend: Map<String, String>, val chips: Map<String, String>)

fun stoppedTurns(entries: List<CodeEntry>, settled: Boolean): Stops {
    val resend = HashMap<String, String>()
    val chips = HashMap<String, String>()
    var last: CodeEntry? = null
    var answered = false
    entries.forEach { entry ->
        if (entry.info.role == "user") {
            if (said(entry).isNotBlank()) {
                last = entry
                answered = false
                chips.clear()
            }
        } else {
            if (entry.parts.isNotEmpty()) answered = true
            if (entry.info.error?.name == ABORTED) last?.let { user ->
                resend[user.info.id] = said(user)
                chips[entry.info.id] = said(user)
            }
        }
    }
    val tail = last
    if (settled && tail != null && !answered && chips.isEmpty()) {
        resend[tail.info.id] = said(tail)
        chips[tail.info.id] = said(tail)
    }
    return Stops(resend, chips)
}

sealed interface Shown {
    val key: String
}

class ShownEntry(val entry: CodeEntry, val parts: List<CodePart>, val tail: Boolean, override val key: String) : Shown

class ShownCalls(val parts: List<CodePart>, val squashed: Boolean, override val key: String) : Shown

fun isCall(part: CodePart) = part.type == "tool" || part.type == "reasoning"

fun squashCalls(entries: List<CodeEntry>): List<Shown> {
    val out = ArrayList<Shown>()
    val run = ArrayList<CodePart>()
    fun flush() {
        if (run.isEmpty()) return
        out += ShownCalls(run.toList(), run.count { it.type == "tool" } >= 2, "calls:" + run.first().id)
        run.clear()
    }
    entries.forEach { entry ->
        if (entry.info.role == "user") {
            flush()
            out += ShownEntry(entry, entry.parts, true, entry.info.id)
            return@forEach
        }
        val piece = ArrayList<CodePart>()
        var pieces = 0
        fun cut() {
            if (piece.isEmpty()) return
            out += ShownEntry(entry, piece.toList(), false, entry.info.id + ":" + pieces++)
            piece.clear()
        }
        entry.parts.forEach { part ->
            when {
                isCall(part) -> { cut(); run += part }
                part.type == "text" && (part.ignored || part.text.isNullOrBlank()) -> Unit
                else -> { flush(); piece += part }
            }
        }
        cut()
        if (entry.info.error != null) {
            flush()
            out += ShownEntry(entry, emptyList(), true, entry.info.id + ":end")
        }
    }
    flush()
    return out
}
