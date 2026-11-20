package ac.mvr.phone.state

import android.os.SystemClock
import ac.mvr.phone.net.MpdSong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class Match(val song: MpdSong, val why: String)

data class Facet(val name: String, val count: Int, val sample: MpdSong, val within: String = "")

object Finder {
    val sorts = listOf("newest" to "newest", "title" to "title", "artist" to "artist", "album" to "album", "year" to "year", "length" to "longest")

    fun year(song: MpdSong): String = song.date?.take(4) ?: ""

    fun hit(song: MpdSong, term: String): String? {
        val t = term.lowercase()
        return when {
            song.name.lowercase().contains(t) -> "title"
            (song.artist ?: "").lowercase().contains(t) -> "artist"
            (song.album ?: "").lowercase().contains(t) -> "album"
            (song.genre ?: "").lowercase().contains(t) -> "genre"
            year(song).contains(t) -> "year"
            song.file.lowercase().contains(t) -> "path"
            else -> null
        }
    }

    fun search(songs: List<MpdSong>, query: String, sort: String): List<Match> {
        val terms = query.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        val matches = ArrayList<Match>(songs.size)
        for (song in songs) {
            var why = "all"
            var ok = true
            for ((i, term) in terms.withIndex()) {
                val h = hit(song, term)
                if (h == null) { ok = false; break }
                if (i == 0) why = h
            }
            if (ok) matches.add(Match(song, why))
        }
        return sorted(matches, sort)
    }

    fun sorted(list: List<Match>, sort: String): List<Match> {
        val n = { s: String? -> (s ?: "").lowercase() }
        return when (sort) {
            "title" -> list.sortedWith(compareBy { n(it.song.name) })
            "artist" -> list.sortedWith(compareBy<Match> { n(it.song.artist) }.thenBy { n(it.song.album) }.thenBy { it.song.track ?: 0 }.thenBy { n(it.song.name) })
            "album" -> list.sortedWith(compareBy<Match> { n(it.song.album) }.thenBy { it.song.track ?: 0 }.thenBy { n(it.song.name) })
            "year" -> list.sortedWith(compareByDescending<Match> { year(it.song) }.thenBy { n(it.song.artist) })
            "length" -> list.sortedByDescending { it.song.duration ?: 0.0 }
            else -> list.sortedByDescending { it.song.lastModified ?: "" }
        }
    }

    fun facets(list: List<Match>, within: (MpdSong) -> String = { "" }, key: (MpdSong) -> String?): List<Facet> {
        val counts = LinkedHashMap<Pair<String, String>, Pair<Int, MpdSong>>()
        for (m in list) {
            val k = key(m.song)?.takeIf { it.isNotEmpty() } ?: continue
            val id = within(m.song) to k
            val prev = counts[id]
            counts[id] = (prev?.first ?: 0) + 1 to (prev?.second ?: m.song)
        }
        return counts.map { (id, v) -> Facet(id.second, v.first, v.second, id.first) }
            .sortedWith(compareByDescending<Facet> { it.count }.thenBy { it.name.lowercase() }.thenBy { it.within.lowercase() })
    }
}

class FindStore(private val store: Store) {
    private val libraryFlow = MutableStateFlow<List<MpdSong>>(emptyList())
    val library: StateFlow<List<MpdSong>> = libraryFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    private var fetchedAtMs = 0L
    private val lock = Mutex()

    suspend fun refresh(force: Boolean = false) {
        if (!force && libraryFlow.value.isNotEmpty() && SystemClock.elapsedRealtime() - fetchedAtMs < 60_000) return
        lock.withLock {
            try {
                libraryFlow.value = store.mpd.library().filter { !it.file.startsWith(".") && !it.file.contains("/.") }
                fetchedAtMs = SystemClock.elapsedRealtime()
                freshFlow.value = true
            } catch (err: CancellationException) {
                throw err
            } catch (err: Exception) {
                freshFlow.value = false
                throw err
            }
        }
    }
}
