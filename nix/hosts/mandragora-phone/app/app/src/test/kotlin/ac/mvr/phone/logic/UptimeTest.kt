package ac.mvr.phone.logic

import org.junit.Assert.assertEquals
import org.junit.Test

class UptimeTest {
    @Test
    fun namesTheLargestUnitsOnly() {
        assertEquals("up 1 d 2 h", uptimeLabel(93_784.52))
        assertEquals("up 3 h 5 min", uptimeLabel(11_100.0))
        assertEquals("up 0 min", uptimeLabel(12.0))
    }
}
