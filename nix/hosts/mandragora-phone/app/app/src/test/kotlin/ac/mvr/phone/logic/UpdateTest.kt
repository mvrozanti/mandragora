package ac.mvr.phone.logic

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateTest {

    @Test
    fun aNewerPublishedBuildIsCheckedOnce() {
        assertTrue(newBuild(published = 6, installed = 5, checked = 0))
        assertFalse(newBuild(published = 6, installed = 5, checked = 6))
    }

    @Test
    fun theInstalledOrAnOlderBuildIsNothingNew() {
        assertFalse(newBuild(published = 5, installed = 5, checked = 0))
        assertFalse(newBuild(published = 0, installed = 5, checked = 0))
    }
}
