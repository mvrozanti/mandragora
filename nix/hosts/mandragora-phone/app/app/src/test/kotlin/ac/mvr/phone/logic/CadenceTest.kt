package ac.mvr.phone.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CadenceTest {
    @Test
    fun theConfigIsReadOftenOnlyWhileShownOrFailing() {
        assertEquals(30_000L, configWaitMs(ok = true, misses = 0, shown = true))
        assertEquals(600_000L, configWaitMs(ok = true, misses = 0, shown = false))
        assertEquals(1_000L, configWaitMs(ok = false, misses = 1, shown = false))
        assertEquals(5_000L, configWaitMs(ok = false, misses = 3, shown = true))
    }

    @Test
    fun theDesksPlayersAreAskedForOnlyWhileSomeoneCanSeeThem() {
        assertTrue(mediaPolls(shown = true, playerUp = false, screenOn = false))
        assertTrue(mediaPolls(shown = false, playerUp = true, screenOn = true))
        assertFalse(mediaPolls(shown = false, playerUp = true, screenOn = false))
        assertFalse(mediaPolls(shown = false, playerUp = false, screenOn = true))
        assertEquals(5_000L, mediaWaitMs(shown = true, polls = true))
        assertEquals(15_000L, mediaWaitMs(shown = false, polls = true))
        assertEquals(600_000L, mediaWaitMs(shown = false, polls = false))
    }

    @Test
    fun mpdIdlesLongerWhileTheAppIsAway() {
        assertEquals(50, mpdIdleSeconds(shown = true))
        assertEquals(290, mpdIdleSeconds(shown = false))
    }
}
