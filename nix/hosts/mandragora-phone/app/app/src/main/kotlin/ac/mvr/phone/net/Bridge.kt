package ac.mvr.phone.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class DesktopInfo(val ip: String, val host: String = "mandragora-desktop")

@Serializable
data class Ports(val mpd: Int = 6600, val ytdl: Int = 6685, val theme: Int = 6684, val mympd: Int = 6680, val bridge: Int = 6688, val code: Int = 4096, val claude: Int = 4097)

@Serializable
data class MusicInfo(val folderId: String = "mandragora-music", val dir: String = "")

@Serializable
data class HubGroup(val id: String, val label: String = id)

@Serializable
data class HubService(
    val name: String,
    val host: String,
    val group: String = "",
    val desc: String = "",
    val access: String = "priv",
    val where: String = "",
    val url: String? = null,
)

@Serializable
data class HubManifest(val groups: List<HubGroup> = emptyList(), val services: List<HubService> = emptyList())

@Serializable
data class BridgeConfig(
    val version: Int = 0,
    val desktop: DesktopInfo,
    val ports: Ports = Ports(),
    val music: MusicInfo = MusicInfo(),
    val hub: HubManifest = HubManifest(),
    val code: CodeBackends? = null,
    val time: Double = 0.0,
)

@Serializable
data class Sink(val id: Int, val name: String, val volume: Int, val muted: Boolean = false, val default: Boolean = false)

@Serializable
data class VolumeState(val sink: Sink? = null, val sinks: List<Sink> = emptyList())

@Serializable
data class Lease(
    val owner: String = "desk",
    val file: String? = null,
    val elapsed: Double = 0.0,
    val playing: Boolean = false,
    val artist: String? = null,
    val title: String? = null,
    val duration: Double? = null,
    val since: Double = 0.0,
    val heartbeat: Double? = null,
)

@Serializable
data class LyricLine(val t: Double, val x: String)

@Serializable
data class Lyrics(val synced: List<LyricLine>? = null, val plain: String? = null, val source: String = "")

@Serializable
data class NowPlaying(
    val file: String? = null,
    val artist: String? = null,
    val title: String? = null,
    val album: String? = null,
    val duration: Double? = null,
    val elapsed: Double = 0.0,
    val playing: Boolean = false,
    val state: String? = null,
)

@Serializable
data class AppBuild(
    val versionCode: Int = 0,
    val versionName: String = "",
    val sha256: String = "",
    val size: Long = 0,
    val variant: String = "",
    val publishedAt: Double = 0.0,
    val error: String? = null,
)

class BridgeClient(private val baseUrl: () -> String) {
    suspend fun config(): BridgeConfig = json.decodeFromString(Http.get("${baseUrl()}/api/config"))

    suspend fun volume(): VolumeState = json.decodeFromString(Http.get("${baseUrl()}/api/volume"))

    suspend fun setVolume(level: Int? = null, muted: Boolean? = null, sink: Int? = null, makeDefault: Boolean = false): VolumeState {
        val body = buildJsonObject {
            level?.let { put("volume", it) }
            muted?.let { put("muted", it) }
            sink?.let { put("sink", it) }
            if (makeDefault) put("default", true)
        }
        return json.decodeFromString(Http.post("${baseUrl()}/api/volume", body))
    }

    suspend fun stepVolume(step: Int): VolumeState =
        json.decodeFromString(Http.post("${baseUrl()}/api/volume", buildJsonObject { put("step", step) }))

    suspend fun lease(): Lease = json.decodeFromString(Http.get("${baseUrl()}/api/lease"))

    suspend fun takeLease(owner: String, file: String?, elapsed: Double?, playing: Boolean?): Lease {
        val body = buildJsonObject {
            put("owner", owner)
            file?.let { put("file", it) }
            elapsed?.let { put("elapsed", it) }
            playing?.let { put("playing", it) }
        }
        return json.decodeFromString(Http.post("${baseUrl()}/api/lease", body))
    }

    suspend fun heartbeat(song: MpdSong?, elapsed: Double, playing: Boolean): Lease {
        val body: JsonObject = buildJsonObject {
            song?.let {
                put("file", it.file)
                put("title", it.title)
                put("artist", it.artist)
                put("duration", it.duration)
            }
            put("elapsed", elapsed)
            put("playing", playing)
        }
        return json.decodeFromString(Http.post("${baseUrl()}/api/lease/position", body))
    }

    suspend fun lyrics(file: String): Lyrics {
        val encoded = java.net.URLEncoder.encode(file, "UTF-8").replace("+", "%20")
        return json.decodeFromString(Http.get("${baseUrl()}/api/lyrics?file=$encoded"))
    }

    fun fileUrl(file: String): String = "${baseUrl()}/api/file?file=" + java.net.URLEncoder.encode(file, "UTF-8").replace("+", "%20")

    fun coverUrl(file: String): String = "${baseUrl()}/api/cover?file=" + java.net.URLEncoder.encode(file, "UTF-8").replace("+", "%20")

    suspend fun cover(file: String): ByteArray? = Http.bytes(coverUrl(file))

    suspend fun now(): NowPlaying = json.decodeFromString(Http.get("${baseUrl()}/api/now"))

    suspend fun money(): String = Http.get("${baseUrl()}/api/money")

    suspend fun refreshMoney() { Http.post("${baseUrl()}/api/money/refresh", buildJsonObject { }) }

    suspend fun hub(): String = Http.get("${baseUrl()}/api/hub")

    suspend fun app(): AppBuild = json.decodeFromString(Http.get("${baseUrl()}/api/app"))

    suspend fun downloadApk(target: java.io.File, onProgress: (Long, Long) -> Unit) = Http.download("${baseUrl()}/api/app/apk", target, onProgress)

    suspend fun load(): LoadState = json.decodeFromString(Http.get("${baseUrl()}/api/load"))

    suspend fun media(): MediaState = json.decodeFromString(Http.get("${baseUrl()}/api/media"))

    suspend fun mediaAction(player: String, action: String): MediaState =
        json.decodeFromString(Http.post("${baseUrl()}/api/media", buildJsonObject { put("player", player); put("action", action) }))

    suspend fun kill(id: String): KillResult = json.decodeFromString(Http.post("${baseUrl()}/api/kill", buildJsonObject { put("id", id) }))
}

@Serializable
data class Psi(val some10: Double = 0.0, val some60: Double = 0.0, val full10: Double = 0.0, val full60: Double = 0.0)

@Serializable
data class Pressure(val memory: Psi = Psi(), val cpu: Psi = Psi(), val io: Psi = Psi())

@Serializable
data class MemInfo(val total: Long = 0, val available: Long = 0, val swapTotal: Long = 0, val swapFree: Long = 0)

@Serializable
data class Hog(val id: String, val unit: String = id, val kind: String = "", val name: String = unit, val mem: Long = 0, val swap: Long = 0, val cpu: Double = 0.0, val procs: Int = 0)

@Serializable
data class LoadState(val ts: Double = 0.0, val pressure: Pressure = Pressure(), val memory: MemInfo = MemInfo(), val hogs: List<Hog> = emptyList())

@Serializable
data class DesktopMedia(val player: String, val status: String = "", val title: String = "", val artist: String = "", val url: String = "", val source: String = "") {
    val playing: Boolean get() = status == "Playing"
}

@Serializable
data class MediaState(val players: List<DesktopMedia> = emptyList())

@Serializable
data class KillResult(val killed: String? = null, val name: String? = null, val procs: Int = 0, val error: String? = null)
