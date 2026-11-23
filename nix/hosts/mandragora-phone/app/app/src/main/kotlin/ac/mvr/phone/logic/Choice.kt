package ac.mvr.phone.logic

data class Choice(val label: String, val recommended: Boolean)

private val RECOMMENDED = Regex("""\s*\(recommended\)""", RegexOption.IGNORE_CASE)
private val ESCAPE_HINT = Regex("""\s*\(esc\)\s*$""", RegexOption.IGNORE_CASE)
private val TYPE_SOMETHING = Regex("""^type something\.?$""", RegexOption.IGNORE_CASE)

const val OWN_ANSWER = "write my own answer"

fun choiceOf(raw: String): Choice {
    val plain = raw.replace(RECOMMENDED, "").replace(ESCAPE_HINT, "").trim()
    return Choice(if (TYPE_SOMETHING.matches(plain)) OWN_ANSWER else plain, RECOMMENDED.containsMatchIn(raw))
}

fun stepLabel(label: String, index: Int, count: Int): String = if (index == count - 1) "review" else label

fun nextLabel(step: Int, count: Int): String? = when {
    step == count - 1 -> null
    step == count - 2 -> "review"
    else -> "next"
}

fun submitKey(options: List<Pair<String, String>>): String? =
    options.firstOrNull { (_, label) -> label.startsWith("submit", ignoreCase = true) }?.first ?: options.firstOrNull()?.first

fun ownAnswerSeed(shown: String, typed: String): String = shown.ifEmpty { typed }

fun toggled(now: List<String>, label: String, multiple: Boolean): List<String> = when {
    !multiple -> listOf(label)
    label in now -> now - label
    else -> now + label
}
