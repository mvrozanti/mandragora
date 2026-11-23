package ac.mvr.phone.logic

import ac.mvr.phone.net.CodeCommand
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SlashTest {

    private val commands = listOf(
        CodeCommand("devil", "Attack the design"),
        CodeCommand("code-review", "Review the current diff"),
        CodeCommand("compact", "Free up context by summarizing"),
        CodeCommand("hookify:writing-hookify-rules", "Write a hook rule"),
        CodeCommand("huggingface-skills:hf-cli", "Hugging Face Hub CLI"),
        CodeCommand("context", "Show current context usage"),
        CodeCommand("co", "an exact name"),
    )

    private fun names(query: String) = slashMatches(query, commands).map { it.name }

    @Test
    fun onlyALoneSlashWordAsksForCompletion() {
        assertEquals("", slashQuery("/"))
        assertEquals("dev", slashQuery("/Dev"))
        assertNull(slashQuery("/devil the bridge"))
        assertNull(slashQuery("say /devil"))
        assertNull(slashQuery(""))
    }

    @Test
    fun aLoneSlashOffersEverythingInTheDesktopsOrder() {
        assertEquals(commands.map { it.name }, names(""))
    }

    @Test
    fun anExactNameLeadsThenPrefixesThenWordStartsThenAnywhere() {
        assertEquals(listOf("co", "code-review", "compact", "context"), names("co"))
        assertEquals(listOf("code-review", "compact", "context", "co", "huggingface-skills:hf-cli"), names("c"))
        assertEquals(listOf("hookify:writing-hookify-rules"), names("ok"))
    }

    @Test
    fun aPluginSkillMatchesFromAnyWordInItsName() {
        assertEquals(listOf("hookify:writing-hookify-rules"), names("rules"))
        assertEquals(listOf("huggingface-skills:hf-cli"), names("hf-cli"))
    }

    @Test
    fun descriptionsCountOnlyFromThreeLetters() {
        assertEquals(listOf("compact"), names("summ"))
        assertEquals(emptyList<String>(), names("zz"))
    }

    @Test
    fun pickingLeavesRoomForArguments() {
        assertEquals("/devil ", slashPicked(commands.first()))
        assertNull(slashQuery(slashPicked(commands.first())))
    }
}
