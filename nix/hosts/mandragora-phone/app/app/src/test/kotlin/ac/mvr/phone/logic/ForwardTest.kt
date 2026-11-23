package ac.mvr.phone.logic

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ForwardTest {
    private val plain = NoteFacts(pkg = "com.whatsapp", self = "ac.mvr.phone", ongoing = false, summary = false, alerting = true)

    @Test
    fun onlyWhatWouldPingThePhoneTravels() {
        assertTrue(forwardable(plain))
        assertFalse(forwardable(plain.copy(pkg = "ac.mvr.phone")))
        assertFalse(forwardable(plain.copy(ongoing = true)))
        assertFalse(forwardable(plain.copy(summary = true)))
        assertFalse(forwardable(plain.copy(alerting = false)))
    }

    @Test
    fun aRepostWithTheSameWordsIsSentOnce() {
        val seen = NoteSeen()
        val note = PhoneNote("k", "com.whatsapp", "WhatsApp", "ana", "oi")
        assertTrue(seen.fresh(note, alertsOnce = false))
        assertFalse(seen.fresh(note, alertsOnce = false))
        assertTrue(seen.fresh(note.copy(text = "tudo bem?"), alertsOnce = false))
    }

    @Test
    fun anUpdateThatDoesNotAlertTheFirstTimeStaysQuiet() {
        val seen = NoteSeen()
        val note = PhoneNote("k", "org.example", "Example", "upload", "10%")
        assertTrue(seen.fresh(note, alertsOnce = true))
        assertFalse(seen.fresh(note.copy(text = "50%"), alertsOnce = true))
    }

    @Test
    fun aNoteWithoutWordsNeverTravels() {
        assertFalse(NoteSeen().fresh(PhoneNote("k", "org.example", "Example", "", ""), alertsOnce = false))
    }

    @Test
    fun theMemoryKeepsOnlyTheNewestKeys() {
        val seen = NoteSeen(keep = 2)
        val note = PhoneNote("a", "p", "P", "t", "x")
        assertTrue(seen.fresh(note, alertsOnce = false))
        assertTrue(seen.fresh(note.copy(key = "b"), alertsOnce = false))
        assertTrue(seen.fresh(note.copy(key = "c"), alertsOnce = false))
        assertTrue(seen.fresh(note, alertsOnce = false))
    }
}
