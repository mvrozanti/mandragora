package ac.mvr.phone.logic

import ac.mvr.phone.net.CodeEntry
import ac.mvr.phone.net.CodeMessage
import ac.mvr.phone.net.CodePart
import ac.mvr.phone.net.MessageError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TurnsTest {

    private var counter = 0

    private fun part(type: String, text: String? = null, tool: String? = null, ignored: Boolean = false, synthetic: Boolean = false) =
        CodePart(id = "p${counter++}", messageID = "m", type = type, text = text, tool = tool, ignored = ignored, synthetic = synthetic)

    private fun user(id: String, text: String) = CodeEntry(CodeMessage(id = id, role = "user"), listOf(part("text", text)))

    private fun assistant(id: String, vararg parts: CodePart, error: String? = null) =
        CodeEntry(CodeMessage(id = id, role = "assistant", error = error?.let { MessageError(name = it) }), parts.toList())

    private fun tool(name: String = "Bash") = part("tool", tool = name)

    private fun thinking() = part("reasoning", text = "hmm")

    private fun words(text: String) = part("text", text)

    @Test
    fun saidKeepsOnlyVisibleText() {
        val entry = CodeEntry(
            CodeMessage(id = "u", role = "user"),
            listOf(words("hello"), part("text", "hidden", ignored = true), part("text", "machine", synthetic = true), tool()),
        )
        assertEquals("hello", said(entry))
    }

    @Test
    fun chainOfCallsAcrossEntriesFoldsIntoOne() {
        val shown = squashCalls(
            listOf(
                user("u1", "do it"),
                assistant("a1", thinking(), tool()),
                assistant("a2", tool("Edit")),
                assistant("a3", thinking(), tool("Read")),
                assistant("a4", words("done")),
            ),
        )
        assertEquals(listOf("u1", "calls", "a4:0"), shown.map { it.key.substringBefore(':').takeIf { k -> k == "calls" } ?: it.key })
        val calls = shown[1] as ShownCalls
        assertTrue(calls.squashed)
        assertEquals(5, calls.parts.size)
        assertEquals(3, calls.parts.count { it.type == "tool" })
    }

    @Test
    fun textBreaksAChainAndASingleCallStaysLoose() {
        val shown = squashCalls(
            listOf(
                assistant("a1", words("checking"), tool()),
                assistant("a2", words("now this"), tool(), tool()),
            ),
        )
        val kinds = shown.map { if (it is ShownCalls) "calls:${it.squashed}" else "text" }
        assertEquals(listOf("text", "calls:false", "text", "calls:true"), kinds)
    }

    @Test
    fun blankAndIgnoredTextDoNotBreakAChain() {
        val shown = squashCalls(
            listOf(
                assistant("a1", tool(), part("text", "   ")),
                assistant("a2", part("text", "skip", ignored = true), tool()),
            ),
        )
        assertEquals(1, shown.size)
        assertTrue((shown.single() as ShownCalls).squashed)
    }

    @Test
    fun anErrorEndsTheChainAndGetsItsOwnTail() {
        val shown = squashCalls(listOf(assistant("a1", tool(), tool(), error = ABORTED)))
        assertEquals(2, shown.size)
        val tail = shown[1] as ShownEntry
        assertTrue(tail.tail)
        assertEquals("a1:end", tail.key)
        assertTrue(tail.parts.isEmpty())
    }

    @Test
    fun keysStayStableWhileARunGrows() {
        val first = tool()
        val before = squashCalls(listOf(assistant("a1", first, tool())))
        val after = squashCalls(listOf(assistant("a1", first, tool()), assistant("a2", tool())))
        assertEquals(before.single().key, after.single().key)
    }

    @Test
    fun abortedTurnOffersItsPromptAgain() {
        val stops = stoppedTurns(listOf(user("u1", "build it"), assistant("a1", words("on it"), error = ABORTED)), settled = true)
        assertEquals("build it", stops.resend["u1"])
        assertEquals("build it", stops.chips["a1"])
    }

    @Test
    fun unansweredPromptCanBeResentOnceSettled() {
        val entries = listOf(user("u1", "first"), assistant("a1", words("ok")), user("u2", "second"))
        assertEquals("second", stoppedTurns(entries, settled = true).chips["u2"])
        assertFalse(stoppedTurns(entries, settled = false).chips.containsKey("u2"))
    }

    @Test
    fun answeredPromptOffersNothing() {
        val stops = stoppedTurns(listOf(user("u1", "hi"), assistant("a1", words("hello"))), settled = true)
        assertTrue(stops.resend.isEmpty())
        assertTrue(stops.chips.isEmpty())
    }
}
