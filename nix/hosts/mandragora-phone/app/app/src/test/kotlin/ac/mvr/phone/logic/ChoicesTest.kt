package ac.mvr.phone.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ChoicesTest {

    @Test
    fun recommendedBecomesAFlag() {
        assertEquals(Choice("Short summary", true), choiceOf("Short summary (Recommended)"))
        assertEquals(Choice("Detailed report", false), choiceOf("Detailed report"))
    }

    @Test
    fun terminalHintsAreDropped() {
        assertEquals(Choice("No, and tell Claude what to do differently", false), choiceOf("No, and tell Claude what to do differently (esc)"))
        assertEquals(OWN_ANSWER, choiceOf("Type something.").label)
        assertEquals(OWN_ANSWER, choiceOf("Type something").label)
    }

    @Test
    fun theLastStepIsTheReview() {
        assertEquals("Format", stepLabel("Format", 0, 3))
        assertEquals("review", stepLabel("Submit", 2, 3))
    }

    @Test
    fun theForwardButtonNamesWhereItGoes() {
        assertEquals("next", nextLabel(0, 4))
        assertEquals("next", nextLabel(-1, 4))
        assertEquals("review", nextLabel(2, 4))
        assertNull(nextLabel(3, 4))
    }

    @Test
    fun aPickTogglesOnlyWhereSeveralAreAllowed() {
        assertEquals(listOf("b"), toggled(listOf("a"), "b", multiple = false))
        assertEquals(listOf("a", "b"), toggled(listOf("a"), "b", multiple = true))
        assertEquals(listOf("a"), toggled(listOf("a", "b"), "b", multiple = true))
    }

    @Test
    fun theReviewSubmitsWithItsSubmitOption() {
        assertEquals("1", submitKey(listOf("1" to "Submit answers", "2" to "Cancel")))
        assertEquals("2", submitKey(listOf("1" to "Cancel", "2" to "submit")))
        assertEquals("1", submitKey(listOf("1" to "Send", "2" to "Cancel")))
        assertNull(submitKey(emptyList()))
    }

    @Test
    fun reopeningAnOwnAnswerShowsWhatTheDesktopHoldsElseWhatWasTyped() {
        assertEquals("rats", ownAnswerSeed("rats", "mice"))
        assertEquals("mice", ownAnswerSeed("", "mice"))
    }
}
