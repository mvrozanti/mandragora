package ac.mvr.phone.logic

import ac.mvr.phone.net.CodeSession
import ac.mvr.phone.net.CodeStatus
import ac.mvr.phone.net.DesktopMedia
import ac.mvr.phone.net.LiveInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeskTest {

    private val youtube = DesktopMedia(player = "firefox.1", status = "Playing", title = "a video", source = "YouTube")
    private val pausedTab = youtube.copy(status = "Paused")
    private val mpv = DesktopMedia(player = "mpv", status = "Playing", source = "mpv")

    @Test
    fun onlyTheVideoPlayingTakesTheLockScreen() {
        val shown = lockScreen(musicOn = false, players = listOf(youtube), showingDesk = false, bound = null)
        assertEquals(LockScreen(showDesk = true, bind = "firefox.1", beside = null), shown)
    }

    @Test
    fun musicPlayingKeepsTheLockScreenAndTheVideoGoesBeside() {
        val shown = lockScreen(musicOn = true, players = listOf(youtube), showingDesk = true, bound = "firefox.1")
        assertEquals(LockScreen(showDesk = false, bind = null, beside = youtube), shown)
    }

    @Test
    fun aPausedVideoStaysOnlyIfItWasAlreadyShown() {
        assertTrue(lockScreen(false, listOf(pausedTab), showingDesk = true, bound = "firefox.1").showDesk)
        assertFalse(lockScreen(false, listOf(pausedTab), showingDesk = false, bound = "firefox.1").showDesk)
    }

    @Test
    fun aClosedTabGivesTheLockScreenBackToMusic() {
        assertFalse(lockScreen(false, emptyList(), showingDesk = true, bound = "firefox.1").showDesk)
        assertFalse(lockScreen(false, listOf(mpv.copy(status = "Paused")), showingDesk = true, bound = "firefox.1").showDesk)
    }

    @Test
    fun nothingPlayingAndNothingShownBindsNothing() {
        val shown = lockScreen(false, listOf(pausedTab), showingDesk = false, bound = null)
        assertNull(shown.bind)
        assertNull(shown.beside)
    }

    @Test
    fun theFirstPlayingPlayerWins() {
        assertEquals("mpv", lockScreen(false, listOf(pausedTab, mpv, youtube), false, null).bind)
    }

    @Test
    fun playAndResumingPausedPlayersPauseTheMusic() {
        assertTrue(resumes("play", "firefox.1", listOf(youtube)))
        assertTrue(resumes("play-pause", "firefox.1", listOf(pausedTab)))
        assertTrue(resumes("play-pause", "gone", listOf(youtube)))
    }

    @Test
    fun pausingOrSkippingNeverPausesTheMusic() {
        assertFalse(resumes("play-pause", "firefox.1", listOf(youtube)))
        assertFalse(resumes("pause", "firefox.1", listOf(pausedTab)))
        assertFalse(resumes("next", "firefox.1", listOf(pausedTab)))
        assertFalse(resumes("seek", "firefox.1", listOf(pausedTab)))
    }

    @Test
    fun aSessionIsActiveWhenOpenWorkingOrWaiting() {
        val closed = CodeSession(id = "s")
        assertTrue(active(closed.copy(live = LiveInfo(status = "idle")), null))
        assertTrue(active(closed, CodeStatus(type = "busy")))
        assertTrue(active(closed, CodeStatus(message = "waiting")))
        assertFalse(active(closed, CodeStatus()))
        assertFalse(active(closed, null))
    }

    @Test
    fun backgroundTasksReadAsOneLineOnlyWhenSomethingRuns() {
        val open = CodeSession(id = "s", live = LiveInfo(status = "idle", background = listOf("2 shells", "1 monitor")))
        assertEquals("2 shells, 1 monitor", inBackground(open))
        assertNull(inBackground(open.copy(live = LiveInfo(background = listOf(" ")))))
        assertNull(inBackground(open.copy(live = LiveInfo())))
        assertNull(inBackground(CodeSession(id = "s")))
        assertNull(inBackground(null))
    }

    @Test
    fun backgroundTasksLandOnlyOnOpenSessions() {
        val open = CodeSession(id = "s", live = LiveInfo(status = "busy")).also { it.backend = "claude" }
        val moved = withBackground(open, listOf("1 shell"))
        assertEquals(listOf("1 shell"), moved.live?.background)
        assertEquals("busy", moved.live?.status)
        assertEquals("claude", moved.backend)
        val closed = CodeSession(id = "s")
        assertEquals(closed, withBackground(closed, listOf("1 shell")))
    }

    @Test
    fun desktopMediaReadsAsTitleAndByline() {
        assertEquals("a video", youtube.label)
        assertEquals("YouTube on the desktop", youtube.byline)
        assertEquals("mpv", mpv.label)
        assertEquals("chan · YouTube on the desktop", youtube.copy(artist = "chan").byline)
    }
}
