package ac.mvr.phone.state

import android.app.Application
import android.net.Uri
import android.os.SystemClock
import ac.mvr.phone.BuildConfig
import ac.mvr.phone.net.BridgeClient
import ac.mvr.phone.net.BridgeConfig
import ac.mvr.phone.net.HubService
import ac.mvr.phone.net.Lease
import ac.mvr.phone.net.Lyrics
import ac.mvr.phone.net.MpdClient
import ac.mvr.phone.net.MpdSnapshot
import ac.mvr.phone.net.MpdSong
import ac.mvr.phone.net.Palette
import ac.mvr.phone.net.Ports
import ac.mvr.phone.net.SyncFolder
import ac.mvr.phone.net.SyncForkClient
import ac.mvr.phone.net.ThemeClient
import ac.mvr.phone.net.Unreachable
import ac.mvr.phone.net.VolumeState
import ac.mvr.phone.net.YtdlClient
import ac.mvr.phone.net.YtdlJob
import ac.mvr.phone.play.LocalLibrary
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

interface PlayerHost {
    fun useRemote()
    fun useLocal(uri: Uri, title: String, artist: String?, positionMs: Long, play: Boolean)
    fun localPositionMs(): Long
    fun localDurationMs(): Long
    fun localIsPlaying(): Boolean
    fun localPlay()
    fun localPause()
    fun localSeek(positionMs: Long)
    fun localHasMedia(): Boolean
}

data class NowState(
    val owner: String = "desk",
    val file: String? = null,
    val title: String = "nothing playing",
    val artist: String? = null,
    val elapsed: Double = 0.0,
    val duration: Double = 0.0,
    val playing: Boolean = false,
    val pos: Int? = null,
    val queueLength: Int = 0,
    val repeat: Boolean = false,
    val random: Boolean = false,
    val single: Boolean = false,
    val consume: Boolean = false,
    val mpdVolume: Int = -1,
) {
    val phoneOwns: Boolean get() = owner == "phone"
    val whereLabel: String get() = if (phoneOwns) "on this phone" else "on mandragora-desktop"
}

class Store(private val app: Application) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val prefs = Prefs(app)
    val library = LocalLibrary(app)
    val desktopIp: String = BuildConfig.DESKTOP_IP

    val config = MutableStateFlow<BridgeConfig?>(null)
    private fun port(get: (Ports) -> Int, fallback: Int): Int = config.value?.ports?.let(get) ?: fallback

    val bridge = BridgeClient { "http://$desktopIp:${port({ it.bridge }, BuildConfig.BRIDGE_PORT)}" }
    val mpd = MpdClient({ desktopIp }, { port({ it.mpd }, 6600) })
    val ytdl = YtdlClient { "http://$desktopIp:${port({ it.ytdl }, 6685)}" }
    val theme = ThemeClient { "http://$desktopIp:${port({ it.theme }, 6684)}" }
    val syncFork = SyncForkClient { prefs.syncForkApiKey }

    val reachable = MutableStateFlow(false)
    val mpdReachable = MutableStateFlow(false)
    val mpdSnapshot = MutableStateFlow<MpdSnapshot?>(null)
    private var snapshotAtMs = 0L
    val lease = MutableStateFlow(Lease())
    val volume = MutableStateFlow(VolumeState())
    val jobs = MutableStateFlow<List<YtdlJob>>(emptyList())
    val lyrics = MutableStateFlow<Lyrics?>(null)
    val lyricsFile = MutableStateFlow<String?>(null)
    val lyricsBusy = MutableStateFlow(false)
    val palette = MutableStateFlow(Palette())
    val folders = MutableStateFlow<List<SyncFolder>>(emptyList())
    val syncBusy = MutableStateFlow(false)
    val syncError = MutableStateFlow<String?>(null)
    val hasApiKey = MutableStateFlow(prefs.syncForkApiKey != null)
    val localPlaying = MutableStateFlow(false)
    val localPositionMs = MutableStateFlow(0L)
    val localDurationMs = MutableStateFlow(0L)
    val localCount = MutableStateFlow(0)
    val stats = MutableStateFlow<Map<String, String>>(emptyMap())
    val notice = MutableStateFlow<String?>(null)
    private var noticeJob: Job? = null
    val foreground = MutableStateFlow(false)
    val busy = MutableStateFlow(false)
    private val tick = MutableStateFlow(0L)
    private val handoff = Mutex()
    private var heartbeatJob: Job? = null

    var host: PlayerHost? = null

    fun remoteElapsedMs(): Long {
        val snap = mpdSnapshot.value ?: return 0L
        val base = (snap.status.elapsed * 1000).toLong()
        return if (snap.status.playing) base + (SystemClock.elapsedRealtime() - snapshotAtMs) else base
    }

    val now: StateFlow<NowState> = combine(mpdSnapshot, lease, localPlaying, localPositionMs, tick) { snap, lease, localPlaying, localPos, _ ->
        val status = snap?.status
        val song = snap?.song
        if (lease.owner == "phone") {
            NowState(
                owner = "phone",
                file = lease.file ?: song?.file,
                title = lease.title ?: song?.title ?: lease.file?.substringAfterLast('/')?.substringBeforeLast('.') ?: "nothing playing",
                artist = lease.artist ?: song?.artist,
                elapsed = localPos / 1000.0,
                duration = lease.duration ?: (localDurationMs.value / 1000.0),
                playing = localPlaying,
                pos = status?.song,
                queueLength = status?.playlistLength ?: 0,
                repeat = status?.repeat ?: false,
                random = status?.random ?: false,
                single = status?.single ?: false,
                consume = status?.consume ?: false,
                mpdVolume = status?.volume ?: -1,
            )
        } else {
            NowState(
                owner = "desk",
                file = song?.file,
                title = song?.title ?: song?.file?.substringAfterLast('/')?.substringBeforeLast('.') ?: "nothing playing",
                artist = song?.artist,
                elapsed = remoteElapsedMs() / 1000.0,
                duration = status?.duration ?: song?.duration ?: 0.0,
                playing = status?.playing ?: false,
                pos = status?.song,
                queueLength = status?.playlistLength ?: 0,
                repeat = status?.repeat ?: false,
                random = status?.random ?: false,
                single = status?.single ?: false,
                consume = status?.consume ?: false,
                mpdVolume = status?.volume ?: -1,
            )
        }
    }.stateIn(scope, SharingStarted.Eagerly, NowState())

    fun start() {
        scope.launch {
            while (isActive) {
                if (foreground.value || lease.value.owner == "phone") tick.value = SystemClock.elapsedRealtime()
                delay(500)
            }
        }
        scope.launch { loopConfig() }
        scope.launch { loopMpd() }
        scope.launch { loopWhileForeground(15_000) { refreshVolume() } }
        scope.launch { loopWhileForeground(10_000) { refreshLease() } }
        scope.launch { loopWhileForeground(8_000) { refreshJobs() } }
        scope.launch { loopWhileForeground(5_000) { refreshPalette() } }
        scope.launch { loopWhileForeground(30_000) { if (hasApiKey.value) refreshFolders() } }
        scope.launch { loopWhileForeground(60_000) { localCount.value = runCatching { library.count() }.getOrDefault(0) } }
        scope.launch {
            while (isActive) {
                if (lease.value.owner == "phone") host?.let { h ->
                    localPositionMs.value = h.localPositionMs()
                    localDurationMs.value = h.localDurationMs()
                }
                delay(500)
            }
        }
        scope.launch {
            combine(foreground, reachable) { fg, ok -> fg && ok }.collect { live -> if (live) refreshAll() }
        }
        scope.launch {
            var previous = lease.value.owner
            lease.collect { current ->
                if (current.owner == "phone" && heartbeatJob == null) heartbeatJob = launch { loopHeartbeat() }
                if (current.owner != "phone") { heartbeatJob?.cancel(); heartbeatJob = null }
                val h = host
                if (h != null && !busy.value) {
                    if (previous == "phone" && current.owner == "desk") { h.localPause(); h.useRemote() }
                    if (current.owner == "phone" && !h.localHasMedia()) restoreLocal(current)
                }
                previous = current.owner
            }
        }
    }

    private suspend fun loopWhileForeground(intervalMs: Long, block: suspend () -> Unit) {
        while (scope.isActive) {
            if (foreground.value) runCatching { block() }
            delay(intervalMs)
        }
    }

    private suspend fun loopConfig() {
        while (scope.isActive) {
            val ok = runCatching { config.value = bridge.config() }.isSuccess
            reachable.value = ok
            if (ok && stats.value.isEmpty()) runCatching { stats.value = mpd.stats() }
            delay(if (ok) 30_000 else 5_000)
        }
    }

    private suspend fun loopMpd() {
        while (scope.isActive) {
            try {
                refreshMpd()
                mpd.idle(50)
            } catch (err: Exception) {
                mpdReachable.value = false
                delay(5_000)
            }
        }
    }

    private suspend fun loopHeartbeat() {
        while (scope.isActive && lease.value.owner == "phone") {
            val h = host
            if (h != null) runCatching {
                lease.value = bridge.heartbeat(lease.value.file, h.localPositionMs() / 1000.0, h.localIsPlaying())
            }
            delay(5_000)
        }
    }

    suspend fun refreshMpd() {
        val snap = mpd.snapshot()
        snapshotAtMs = SystemClock.elapsedRealtime()
        mpdSnapshot.value = snap
        mpdReachable.value = true
        val file = snap.song?.file
        if (lease.value.owner == "desk" && file != null && file != lyricsFile.value) loadLyrics(file)
    }

    private fun refreshAll() = scope.launch {
        runCatching { refreshVolume() }
        runCatching { refreshLease() }
        runCatching { refreshJobs() }
        runCatching { refreshPalette() }
        if (hasApiKey.value) runCatching { refreshFolders() }
        val file = now.value.file
        if (file != null && lyrics.value == null && !lyricsBusy.value) loadLyrics(file)
    }

    suspend fun refreshVolume() { runCatching { volume.value = bridge.volume() } }
    suspend fun refreshLease() { runCatching { lease.value = bridge.lease() } }
    suspend fun refreshJobs() { runCatching { jobs.value = ytdl.jobs() } }
    suspend fun refreshPalette() { runCatching { palette.value = theme.palette() } }

    suspend fun refreshFolders() {
        if (!hasApiKey.value) return
        try {
            folders.value = syncFork.folders()
            syncError.value = null
        } catch (err: Exception) {
            syncError.value = "sync-fork: ${err.message ?: "unreachable"}"
        }
    }

    fun report(err: Throwable) {
        val text = when (err) {
            is Unreachable -> "tailnet down · ${err.message}"
            else -> err.message ?: err.toString()
        }
        noticeJob?.cancel()
        notice.value = text
        noticeJob = scope.launch {
            delay(5_000)
            notice.value = null
        }
    }

    private fun restoreLocal(current: Lease) = scope.launch {
        val file = current.file ?: return@launch
        val track = runCatching { library.find(file) }.getOrNull() ?: return@launch
        host?.useLocal(track.uri, current.title ?: track.displayName, current.artist, (current.elapsed * 1000).toLong(), false)
    }

    fun act(block: suspend () -> Unit): Job = scope.launch {
        try { block() } catch (err: Exception) { report(err) }
    }

    fun togglePlay() = act {
        val h = host
        if (now.value.phoneOwns && h != null) {
            if (h.localIsPlaying()) h.localPause() else h.localPlay()
        } else {
            if (mpdSnapshot.value?.status?.playing == true) mpd.pause(true) else mpd.play()
            refreshMpd()
        }
    }

    fun next() = act {
        if (now.value.phoneOwns) localAdvance(1) else { mpd.next(); refreshMpd() }
    }

    fun previous() = act {
        val h = host
        if (now.value.phoneOwns && h != null) {
            if (h.localPositionMs() > 3000) h.localSeek(0) else localAdvance(-1)
        } else { mpd.previous(); refreshMpd() }
    }

    fun seek(seconds: Double) = act {
        val h = host
        if (now.value.phoneOwns && h != null) h.localSeek((seconds * 1000).toLong())
        else { mpd.seek(seconds); refreshMpd() }
    }

    fun setMpdVolume(level: Int) = act { mpd.setVolume(level); refreshMpd() }
    fun setFlag(flag: String, on: Boolean) = act { mpd.setFlag(flag, on); refreshMpd() }

    suspend fun setSinkVolume(level: Int) { volume.value = bridge.setVolume(level = level.coerceIn(0, 100)) }
    suspend fun setSinkMuted(muted: Boolean) { volume.value = bridge.setVolume(muted = muted) }
    suspend fun stepSinkVolume(step: Int) { volume.value = bridge.stepVolume(step) }
    fun setSinkVolumeAsync(level: Int) = act { setSinkVolume(level) }
    fun setSinkMutedAsync(muted: Boolean) = act { setSinkMuted(muted) }
    fun setDefaultSink(id: Int) = act { volume.value = bridge.setVolume(sink = id, makeDefault = true) }

    fun takeOver(target: String) = act {
        handoff.withLock {
            busy.value = true
            try {
                val h = host ?: throw IllegalStateException("player not ready yet")
                if (target == "phone") {
                    val granted = bridge.takeLease("phone", null, null, null)
                    val file = granted.file ?: throw IllegalStateException("desktop has nothing to hand over")
                    val track = library.find(file)
                    if (track == null) {
                        bridge.takeLease("desk", granted.file, granted.elapsed, granted.playing)
                        throw IllegalStateException("not synced to the phone yet: ${file.substringAfterLast('/')}")
                    }
                    lease.value = granted
                    h.useLocal(track.uri, granted.title ?: track.displayName, granted.artist, (granted.elapsed * 1000).toLong(), granted.playing)
                    loadLyrics(file)
                } else {
                    val positionMs = h.localPositionMs()
                    val playing = h.localIsPlaying()
                    h.localPause()
                    val granted = bridge.takeLease("desk", lease.value.file, positionMs / 1000.0, playing)
                    lease.value = granted
                    h.useRemote()
                    refreshMpd()
                }
            } finally {
                busy.value = false
            }
        }
    }

    private suspend fun localAdvance(step: Int) {
        val h = host ?: return
        val snap = mpdSnapshot.value ?: return
        val currentPos = snap.status.song ?: return
        val targetPos = currentPos + step
        if (targetPos < 0 || targetPos >= snap.status.playlistLength) return
        val song = mpd.queueWindow(targetPos, targetPos + 1).firstOrNull() ?: return
        val track = library.find(song.file) ?: throw IllegalStateException("not synced to the phone yet: ${song.file.substringAfterLast('/')}")
        song.id?.let { mpd.playId(it); mpd.pause(true) }
        refreshMpd()
        lease.value = lease.value.copy(file = song.file, title = song.title, artist = song.artist, duration = song.duration, elapsed = 0.0)
        h.useLocal(track.uri, song.title ?: track.displayName, song.artist, 0, true)
        runCatching { bridge.heartbeat(song.file, 0.0, true) }
        loadLyrics(song.file)
    }

    fun localEnded() = act {
        val snap = mpdSnapshot.value ?: return@act
        if (snap.status.single) return@act
        localAdvance(1)
    }

    fun jumpTo(song: MpdSong) = act {
        val id = song.id ?: return@act
        if (now.value.phoneOwns) {
            val h = host ?: return@act
            val track = library.find(song.file) ?: throw IllegalStateException("not synced to the phone yet")
            mpd.playId(id); mpd.pause(true); refreshMpd()
            lease.value = lease.value.copy(file = song.file, title = song.title, artist = song.artist, duration = song.duration, elapsed = 0.0)
            h.useLocal(track.uri, song.title ?: track.displayName, song.artist, 0, true)
            runCatching { bridge.heartbeat(song.file, 0.0, true) }
        } else {
            mpd.playId(id)
            refreshMpd()
        }
    }

    suspend fun queueWindow(): List<MpdSong> {
        val snap = mpdSnapshot.value ?: return emptyList()
        val pos = snap.status.song ?: 0
        val start = (pos - 10).coerceAtLeast(0)
        return mpd.queueWindow(start, (pos + 40).coerceAtMost(snap.status.playlistLength))
    }

    suspend fun search(term: String): Pair<List<MpdSong>, List<HubService>> {
        val hosts = config.value?.hub?.services.orEmpty().filter {
            it.name.contains(term, true) || it.host.contains(term, true) || it.desc.contains(term, true)
        }.take(6)
        val songs = runCatching { mpd.search(term, 12) }.getOrDefault(emptyList())
        return songs to hosts
    }

    fun download(url: String, mode: String, toClient: Boolean) = act {
        val job = ytdl.download(url.trim(), mode, toClient)
        jobs.value = listOf(job) + jobs.value.filter { it.id != job.id }
        refreshJobs()
    }

    fun cancelJob(id: String) = act { ytdl.cancel(id); refreshJobs() }

    fun loadLyrics(file: String) = scope.launch {
        if (lyricsFile.value != file) lyrics.value = null
        lyricsFile.value = file
        lyricsBusy.value = true
        try {
            lyrics.value = bridge.lyrics(file)
        } catch (err: Exception) {
            if (lyricsFile.value == file) lyricsFile.value = null
        } finally {
            lyricsBusy.value = false
        }
    }

    fun rescan() = act {
        syncBusy.value = true
        try {
            syncFork.rescan()
            delay(1500)
            refreshFolders()
        } finally {
            syncBusy.value = false
        }
    }

    fun setApiKey(key: String) {
        prefs.syncForkApiKey = key.trim().ifBlank { null }
        hasApiKey.value = prefs.syncForkApiKey != null
        act { refreshFolders() }
    }

    suspend fun awaitHost(): PlayerHost? {
        if (host != null) return host
        return runCatching { kotlinx.coroutines.withTimeout(3000) { tick.first { host != null } }; host }.getOrNull()
    }
}

fun fmtTime(seconds: Double): String {
    val total = seconds.coerceAtLeast(0.0).toInt()
    return "%d:%02d".format(java.util.Locale.ROOT, total / 60, total % 60)
}
