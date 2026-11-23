package ac.mvr.phone.logic

import ac.mvr.phone.net.CodeCommand

private val WORD_BREAKS = setOf(':', '-', '_')
private const val DESCRIPTION_REACH = 3

fun slashQuery(text: String): String? =
    if (text.startsWith("/") && text.none { it.isWhitespace() }) text.drop(1).lowercase() else null

private fun startsAtWord(name: String, query: String): Boolean =
    name.indices.any { at -> (at == 0 || name[at - 1] in WORD_BREAKS) && name.startsWith(query, at) }

fun slashMatches(query: String, commands: List<CodeCommand>): List<CodeCommand> {
    if (query.isEmpty()) return commands
    return commands.mapNotNull { command ->
        val name = command.name.lowercase()
        val rank = when {
            name == query -> 0
            name.startsWith(query) -> 1
            startsAtWord(name, query) -> 2
            query in name -> 3
            query.length >= DESCRIPTION_REACH && query in command.description.lowercase() -> 4
            else -> return@mapNotNull null
        }
        rank to command
    }.sortedBy { it.first }.map { it.second }
}

fun slashPicked(command: CodeCommand): String = "/" + command.name + " "
