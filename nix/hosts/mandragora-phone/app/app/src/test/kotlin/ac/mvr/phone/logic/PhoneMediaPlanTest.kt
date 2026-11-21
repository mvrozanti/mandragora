package ac.mvr.phone.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneMediaPlanTest {

    private val car = PhoneMediaItem(7, "20261115_101500.jpg", "DCIM/Camera/", "image", "image/jpeg", 2_400_000, 1_763_200_000_000, 1_763_200_000)
    private val clip = PhoneMediaItem(9, "VID.mp4", "DCIM/Camera/", "video", "video/mp4", 80_000_000, 0, 1_763_200_100)

    @Test
    fun theSignatureIgnoresOrderButNotEdits() {
        assertEquals(indexSignature(listOf(car, clip)), indexSignature(listOf(clip, car)))
        assertNotEquals(indexSignature(listOf(car, clip)), indexSignature(listOf(car)))
        assertNotEquals(indexSignature(listOf(car)), indexSignature(listOf(car.copy(modified = car.modified + 1))))
        assertNotEquals(indexSignature(listOf(car)), indexSignature(listOf(car.copy(path = "Pictures/"))))
    }

    @Test
    fun theIndexIsPostedWhenItChangesOrGetsOld() {
        val now = 100_000_000L
        assertTrue(indexDue("a", null, 0, now))
        assertTrue(indexDue("a", "b", now, now))
        assertFalse(indexDue("a", "a", now - 1_000, now))
        assertTrue(indexDue("a", "a", now - 7 * 60 * 60 * 1000L, now))
    }

    @Test
    fun onlyTheVerifiedCopyIsDeleted() {
        val sha = "ab".repeat(32)
        assertEquals(RemoveVerdict(true, null), removeVerdict(sha, present = true, actual = sha.uppercase()))
        assertFalse(removeVerdict(sha, present = true, actual = "cd".repeat(32)).delete)
        assertFalse(removeVerdict(sha, present = true, actual = null).delete)
        assertEquals("no longer on the phone", removeVerdict(sha, present = false, actual = null).error)
    }

    @Test
    fun hexIsLowercaseAndPadded() {
        assertEquals("000fff", hex(byteArrayOf(0, 15, -1)))
    }
}
