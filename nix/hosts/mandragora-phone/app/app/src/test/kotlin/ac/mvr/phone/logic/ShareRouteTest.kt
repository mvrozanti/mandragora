package ac.mvr.phone.logic

import org.junit.Assert.assertEquals
import org.junit.Test

class ShareRouteTest {
    @Test
    fun oneClipGoesToVoiceEverythingElseToCode() {
        assertEquals(ShareRoute.VOICE, shareRoute("audio/ogg", 1, null))
        assertEquals(ShareRoute.VOICE, shareRoute("video/mp4", 1, "caption"))
        assertEquals(ShareRoute.CODE, shareRoute("video/mp4", 2, null))
        assertEquals(ShareRoute.CODE, shareRoute("image/png", 1, null))
        assertEquals(ShareRoute.CODE, shareRoute("application/pdf", 1, null))
        assertEquals(ShareRoute.CODE, shareRoute("*/*", 3, null))
        assertEquals(ShareRoute.CODE, shareRoute("text/plain", 0, "https://example.org"))
        assertEquals(ShareRoute.NONE, shareRoute("text/plain", 0, "  "))
        assertEquals(ShareRoute.NONE, shareRoute("image/png", 0, null))
    }

    @Test
    fun namesWhatWasShared() {
        assertEquals("a picture", sharedLabel(listOf("image/jpeg"), null))
        assertEquals("3 pictures", sharedLabel(listOf("image/jpeg", "image/png", "image/webp"), null))
        assertEquals("a file", sharedLabel(listOf("application/pdf"), null))
        assertEquals("2 pictures and a file", sharedLabel(listOf("image/jpeg", "application/pdf", "image/png"), ""))
        assertEquals("a link", sharedLabel(emptyList(), " https://example.org/a?b=c "))
        assertEquals("the text", sharedLabel(emptyList(), "look at https://example.org"))
        assertEquals("a picture, 2 files and a link", sharedLabel(listOf("image/png", "text/plain", "application/zip"), "http://x.y"))
        assertEquals("nothing", sharedLabel(emptyList(), null))
    }

    @Test
    fun sharedTextJoinsTheDraftOnItsOwnLine() {
        assertEquals("https://example.org", withShared("", "https://example.org"))
        assertEquals("check this\nhttps://example.org", withShared("check this  ", " https://example.org"))
        assertEquals("keep me", withShared("keep me", null))
    }
}
