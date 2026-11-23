package ac.mvr.phone.logic

data class PhoneNote(val key: String, val pkg: String, val app: String, val title: String, val text: String)

data class NoteFacts(
    val pkg: String,
    val self: String,
    val ongoing: Boolean,
    val summary: Boolean,
    val alerting: Boolean,
)

fun forwardable(facts: NoteFacts): Boolean =
    facts.pkg != facts.self && !facts.ongoing && !facts.summary && facts.alerting

class NoteSeen(private val keep: Int = 200) {
    private val said = LinkedHashMap<String, String>()

    fun fresh(note: PhoneNote, alertsOnce: Boolean): Boolean {
        val words = "${note.title}\u0000${note.text}"
        val before = said.remove(note.key)
        said[note.key] = words
        while (said.size > keep) said.remove(said.keys.first())
        if (note.title.isEmpty() && note.text.isEmpty()) return false
        return before == null || (before != words && !alertsOnce)
    }
}
