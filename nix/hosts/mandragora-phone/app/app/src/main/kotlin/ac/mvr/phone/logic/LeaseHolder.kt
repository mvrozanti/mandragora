package ac.mvr.phone.logic

import ac.mvr.phone.net.Lease

fun heldElsewhere(lease: Lease, device: String): Boolean =
    lease.owner == "phone" && lease.device != null && lease.device != device
