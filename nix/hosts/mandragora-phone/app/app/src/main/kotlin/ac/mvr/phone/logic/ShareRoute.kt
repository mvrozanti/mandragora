package ac.mvr.phone.logic

enum class ShareRoute { VOICE, CODE, NONE }

fun shareRoute(type: String, streams: Int, text: String?): ShareRoute = when {
    streams == 1 && (type.startsWith("audio/") || type.startsWith("video/")) -> ShareRoute.VOICE
    streams > 0 || !text.isNullOrBlank() -> ShareRoute.CODE
    else -> ShareRoute.NONE
}

private val link = Regex("^https?://\\S+$")

fun sharedLabel(types: List<String>, text: String?): String {
    val pictures = types.count { it.startsWith("image/") }
    val files = types.size - pictures
    val words = text?.trim().orEmpty()
    val parts = listOfNotNull(
        counted(pictures, "a picture", "pictures"),
        counted(files, "a file", "files"),
        when {
            words.isEmpty() -> null
            link.matches(words) -> "a link"
            else -> "the text"
        },
    )
    return when (parts.size) {
        0 -> "nothing"
        1 -> parts[0]
        else -> parts.dropLast(1).joinToString(", ") + " and " + parts.last()
    }
}

private fun counted(n: Int, one: String, many: String): String? = when (n) {
    0 -> null
    1 -> one
    else -> "$n $many"
}

fun withShared(draft: String, text: String?): String =
    listOf(draft.trim(), text?.trim().orEmpty()).filter { it.isNotEmpty() }.joinToString("\n")
