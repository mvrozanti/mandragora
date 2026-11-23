package ac.mvr.phone.logic

import ac.mvr.phone.net.Lease
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LeaseHolderTest {
    @Test
    fun aPhoneLeaseTakenByAnotherInstallIsHeldElsewhere() {
        assertTrue(heldElsewhere(Lease(owner = "phone", device = "emulator"), "phone-a"))
    }

    @Test
    fun ourOwnLeaseALegacyLeaseAndTheDesksAreNot() {
        assertFalse(heldElsewhere(Lease(owner = "phone", device = "phone-a"), "phone-a"))
        assertFalse(heldElsewhere(Lease(owner = "phone"), "phone-a"))
        assertFalse(heldElsewhere(Lease(owner = "desk", device = "emulator"), "phone-a"))
    }
}
