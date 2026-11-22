package ac.mvr.phone.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MusicMirrorPlanTest {
    private val song = MirrorFile("a/one.mp3", 10, 100)
    private val lyrics = MirrorFile("a/one.lrc", 2, 100)
    private val newer = MirrorFile("b/two.flac", 20, 300)

    @Test
    fun onlySongsAndLyricsOutsideHiddenFoldersAreMirrored() {
        assertTrue(mirroredPath("a/one.MP3"))
        assertTrue(mirroredPath("one.lrc"))
        assertFalse(mirroredPath("a/cover.jpg"))
        assertFalse(mirroredPath(".viz/stem.mp3"))
        assertFalse(mirroredPath("a/.one.mp3.part"))
        assertFalse(mirroredPath("../etc/x.mp3"))
        assertFalse(mirroredPath("/abs.mp3"))
        assertFalse(mirroredPath("a//b.mp3"))
    }

    @Test
    fun copiesAlreadyHereAreAdoptedAndMissingOnesFetchedNewestFirst() {
        val plan = mirrorPlan(listOf(song, lyrics, newer), mapOf(song.path to 10L), emptyMap())
        assertEquals(listOf(song), plan.adopt)
        assertEquals(listOf(newer, lyrics), plan.fetch)
        assertEquals(emptyList<String>(), plan.drop)
    }

    @Test
    fun aChangedSongIsFetchedAgainEvenAtTheSameSize() {
        val edited = song.copy(mtime = 200)
        val plan = mirrorPlan(listOf(edited), mapOf(song.path to 10L), mapOf(song.path to song))
        assertEquals(listOf(edited), plan.fetch)
        val resized = mirrorPlan(listOf(song), mapOf(song.path to 9L), mapOf(song.path to song))
        assertEquals(listOf(song), resized.fetch)
    }

    @Test
    fun onlyWhatTheMirrorPutHereIsDeletedAndStrangersAreLeftAlone() {
        val owned = mapOf(song.path to song, "gone/old.mp3" to MirrorFile("gone/old.mp3", 5, 1), "gone/missing.mp3" to MirrorFile("gone/missing.mp3", 5, 1))
        val local = mapOf(song.path to 10L, "gone/old.mp3" to 5L, "mine/recorded.mp3" to 7L)
        val plan = mirrorPlan(listOf(song), local, owned)
        assertEquals(listOf("gone/old.mp3"), plan.drop)
        assertEquals(1, plan.strangers)
        assertEquals(listOf(song), plan.kept)
    }

    @Test
    fun whatFailedKeepsItsOldRecordSoTheNextPassRetries() {
        val edited = song.copy(mtime = 200)
        val owned = mapOf(song.path to song, "gone/old.mp3" to MirrorFile("gone/old.mp3", 5, 1))
        val plan = mirrorPlan(listOf(edited, newer), mapOf(song.path to 10L, "gone/old.mp3" to 5L), owned)
        val after = ownedAfter(plan, owned, fetched = setOf(newer.path), dropped = emptySet())
        assertEquals(mapOf(song.path to song, newer.path to newer, "gone/old.mp3" to owned.getValue("gone/old.mp3")), after)
        val done = ownedAfter(plan, owned, fetched = setOf(newer.path, edited.path), dropped = setOf("gone/old.mp3"))
        assertEquals(mapOf(edited.path to edited, newer.path to newer), done)
    }
}
