package ac.mvr.phone.logic

import java.security.MessageDigest

data class PhoneMediaItem(
    val id: Long,
    val name: String,
    val path: String,
    val kind: String,
    val mime: String,
    val size: Long,
    val taken: Long,
    val modified: Long,
)

data class RemoveVerdict(val delete: Boolean, val error: String?)

private const val INDEX_REFRESH_MS = 6 * 60 * 60 * 1000L

fun indexSignature(items: List<PhoneMediaItem>): String {
    val digest = MessageDigest.getInstance("SHA-256")
    items.sortedBy { it.id }.forEach { digest.update("${it.id}:${it.size}:${it.modified}:${it.path}${it.name}\n".toByteArray()) }
    return hex(digest.digest())
}

fun indexDue(signature: String, posted: String?, postedAtMs: Long, nowMs: Long): Boolean =
    signature != posted || nowMs - postedAtMs >= INDEX_REFRESH_MS

fun removeVerdict(expected: String, present: Boolean, actual: String?): RemoveVerdict = when {
    !present -> RemoveVerdict(delete = false, error = "no longer on the phone")
    actual == null -> RemoveVerdict(delete = false, error = "could not read it on the phone")
    !actual.equals(expected, ignoreCase = true) -> RemoveVerdict(delete = false, error = "changed on the phone since the desktop copied it")
    else -> RemoveVerdict(delete = true, error = null)
}

fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
