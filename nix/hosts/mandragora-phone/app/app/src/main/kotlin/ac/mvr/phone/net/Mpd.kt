package ac.mvr.phone.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.Socket

data class MpdSong(
    val file: String,
    val artist: String? = null,
    val title: String? = null,
    val album: String? = null,
    val duration: Double? = null,
    val pos: Int? = null,
    val id: Int? = null,
) {
    val display: String get() = listOfNotNull(artist, title ?: file.substringAfterLast('/').substringBeforeLast('.')).joinToString(" · ")
}

data class MpdStatus(
    val state: String = "stop",
    val elapsed: Double = 0.0,
    val duration: Double? = null,
    val volume: Int = -1,
    val repeat: Boolean = false,
    val random: Boolean = false,
    val single: Boolean = false,
    val consume: Boolean = false,
    val song: Int? = null,
    val songId: Int? = null,
    val playlistLength: Int = 0,
) {
    val playing: Boolean get() = state == "play"
}

class MpdSnapshot(val status: MpdStatus, val song: MpdSong?, val stats: Map<String, String> = emptyMap())

class MpdClient(private val host: () -> String, private val port: () -> Int) {

    private class Connection(host: String, port: Int) : AutoCloseable {
        val socket = Socket().apply { connect(InetSocketAddress(host, port), 2500); soTimeout = 15000 }
        val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
        val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))

        init {
            val banner = reader.readLine() ?: throw IOException("no mpd banner")
            if (!banner.startsWith("OK MPD")) throw IOException("unexpected banner: $banner")
        }

        fun command(cmd: String): List<Pair<String, String>> {
            writer.write(cmd)
            writer.write("\n")
            writer.flush()
            val pairs = ArrayList<Pair<String, String>>()
            while (true) {
                val line = reader.readLine() ?: throw IOException("mpd closed the connection")
                if (line == "OK") return pairs
                if (line.startsWith("ACK ")) throw IOException(line)
                val idx = line.indexOf(": ")
                if (idx > 0) pairs.add(line.substring(0, idx) to line.substring(idx + 2))
            }
        }

        override fun close() {
            runCatching { writer.write("close\n"); writer.flush() }
            runCatching { socket.close() }
        }
    }

    private suspend fun <T> withConnection(block: (Connection) -> T): T = withContext(Dispatchers.IO) {
        try {
            Connection(host(), port()).use(block)
        } catch (err: IOException) {
            if (err.message?.startsWith("ACK") == true) throw err
            throw Unreachable("mpd unreachable", err)
        }
    }

    suspend fun command(cmd: String): List<Pair<String, String>> = withConnection { it.command(cmd) }

    suspend fun snapshot(): MpdSnapshot = withConnection { conn ->
        val status = parseStatus(conn.command("status"))
        val current = conn.command("currentsong")
        val song = if (current.isEmpty()) null else parseSong(current)
        MpdSnapshot(status, song)
    }

    suspend fun stats(): Map<String, String> = command("stats").toMap()

    suspend fun play() = command("play")
    suspend fun pause(paused: Boolean) = command(if (paused) "pause 1" else "pause 0")
    suspend fun next() = command("next")
    suspend fun previous() = command("previous")
    suspend fun seek(seconds: Double) = command("seekcur ${"%.1f".format(java.util.Locale.ROOT, seconds)}")
    suspend fun setVolume(level: Int) = command("setvol ${level.coerceIn(0, 100)}")
    suspend fun setFlag(flag: String, on: Boolean) = command("$flag ${if (on) 1 else 0}")
    suspend fun playId(id: Int) = command("playid $id")

    suspend fun queueWindow(start: Int, end: Int): List<MpdSong> {
        if (end <= start) return emptyList()
        return splitSongs(command("playlistinfo ${start.coerceAtLeast(0)}:$end"))
    }

    suspend fun search(term: String, limit: Int = 30): List<MpdSong> {
        val quoted = quote(term)
        return splitSongs(command("search any $quoted window 0:$limit"))
    }

    suspend fun idle(timeoutSeconds: Int = 60): List<String> = withContext(Dispatchers.IO) {
        try {
            Connection(host(), port()).use { conn ->
                conn.socket.soTimeout = (timeoutSeconds + 5) * 1000
                val worker = Thread {
                    try {
                        Thread.sleep(timeoutSeconds * 1000L)
                        conn.writer.write("noidle\n")
                        conn.writer.flush()
                    } catch (_: InterruptedException) {
                    } catch (_: IOException) {
                    }
                }
                worker.isDaemon = true
                worker.start()
                val changed = try {
                    conn.command("idle player mixer options playlist").map { it.second }
                } finally {
                    worker.interrupt()
                }
                changed
            }
        } catch (err: IOException) {
            throw Unreachable("mpd unreachable", err)
        }
    }

    private fun splitSongs(pairs: List<Pair<String, String>>): List<MpdSong> {
        val songs = ArrayList<MpdSong>()
        var current = ArrayList<Pair<String, String>>()
        for (pair in pairs) {
            if (pair.first == "file" && current.isNotEmpty()) {
                songs.add(parseSong(current))
                current = ArrayList()
            }
            current.add(pair)
        }
        if (current.isNotEmpty()) songs.add(parseSong(current))
        return songs
    }

    private fun parseSong(pairs: List<Pair<String, String>>): MpdSong {
        val map = pairs.toMap()
        return MpdSong(
            file = map["file"] ?: "",
            artist = map["Artist"],
            title = map["Title"],
            album = map["Album"],
            duration = map["duration"]?.toDoubleOrNull() ?: map["Time"]?.toDoubleOrNull(),
            pos = map["Pos"]?.toIntOrNull(),
            id = map["Id"]?.toIntOrNull(),
        )
    }

    private fun parseStatus(pairs: List<Pair<String, String>>): MpdStatus {
        val map = pairs.toMap()
        return MpdStatus(
            state = map["state"] ?: "stop",
            elapsed = map["elapsed"]?.toDoubleOrNull() ?: 0.0,
            duration = map["duration"]?.toDoubleOrNull(),
            volume = map["volume"]?.toIntOrNull() ?: -1,
            repeat = map["repeat"] == "1",
            random = map["random"] == "1",
            single = map["single"] == "1",
            consume = map["consume"] == "1",
            song = map["song"]?.toIntOrNull(),
            songId = map["songid"]?.toIntOrNull(),
            playlistLength = map["playlistlength"]?.toIntOrNull() ?: 0,
        )
    }

    companion object {
        fun quote(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    }
}
