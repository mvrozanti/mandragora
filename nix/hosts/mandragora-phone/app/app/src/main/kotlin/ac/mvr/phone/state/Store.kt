package ac.mvr.phone.state

import android.app.Application
import android.content.ComponentName
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.SystemClock
import ac.mvr.phone.BuildConfig
import ac.mvr.phone.net.BridgeClient
import ac.mvr.phone.net.BridgeConfig
import ac.mvr.phone.net.Http
import ac.mvr.phone.net.Lease
import ac.mvr.phone.net.Lyrics
import ac.mvr.phone.net.MpdClient
import ac.mvr.phone.net.MpdSnapshot
import ac.mvr.phone.net.MpdSong
import ac.mvr.phone.net.Palette
import ac.mvr.phone.net.Ports
import ac.mvr.phone.net.ThemeClient
import ac.mvr.phone.net.Unreachable
import ac.mvr.phone.net.VolumeState
import ac.mvr.phone.play.Artwork
import ac.mvr.phone.play.LocalLibrary
import ac.mvr.phone.play.LocalTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

interface PlayerHost {
    fun useRemote()
    fun useLocal(uri: Uri, title: String, artist: String?, positionMs: Long, play: Boolean, artwork: ByteArray?)
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
    val next: String? = null,
) {
    val phoneOwns: Boolean get() = owner == "phone"
}

private data class PhoneSide(val queue: List<MpdSong>, val index: Int, val playing: Boolean, val positionMs: Long, val durationMs: Long)

class Store(private val app: Application) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val library = LocalLibrary(app)
    val prefs = Prefs(app)
    val requestedScreen = MutableStateFlow<String?>(null)
    val desktopIp: String = BuildConfig.DESKTOP_IP

    val config = MutableStateFlow<BridgeConfig?>(null)
    private fun port(get: (Ports) -> Int, fallback: Int): Int = config.value?.ports?.let(get) ?: fallback

    val bridge = BridgeClient { "http://$desktopIp:${port({ it.bridge }, BuildConfig.BRIDGE_PORT)}" }
    val mpd = MpdClient({ desktopIp }, { port({ it.mpd }, 6600) })
    val theme = ThemeClient { "http://$desktopIp:${port({ it.theme }, 6684)}" }
    val money = MoneyStore(this)
    val hub = HubStore(this)
    val update = UpdateStore(this, app)
    val load = LoadStore(this)

    val reachable = MutableStateFlow(false)
    val mpdReachable = MutableStateFlow(false)
    val mpdSnapshot = MutableStateFlow<MpdSnapshot?>(null)
    private var snapshotAtMs = 0L
    val lease = MutableStateFlow(Lease())
    val volume = MutableStateFlow(VolumeState())
    val lyrics = MutableStateFlow<Lyrics?>(null)
    val lyricsFile = MutableStateFlow<String?>(null)
    val lyricsBusy = MutableStateFlow(false)
    val palette = MutableStateFlow(Palette())
    val localPlaying = MutableStateFlow(false)
    val localPositionMs = MutableStateFlow(0L)
    val localDurationMs = MutableStateFlow(0L)
    val phoneQueue = MutableStateFlow<List<MpdSong>>(emptyList())
    val phoneIndex = MutableStateFlow(-1)
    val localNames = MutableStateFlow<Set<String>>(emptySet())
    val notice = MutableStateFlow<String?>(null)
    val cover = MutableStateFlow<Bitmap?>(null)
    private var coverKey: String? = null
    private var noticeJob: Job? = null
    val foreground = MutableStateFlow(false)
    val busy = MutableStateFlow(false)
    private val tick = MutableStateFlow(0L)
    private val handoff = Mutex()
    private var heartbeatJob: Job? = null
    private var volumeTarget: Int? = null
    private var volumeJob: Job? = null

    var host: PlayerHost? = null
        set(value) {
            field = value
            if (value != null && lease.value.owner == "phone" && !busy.value && !value.localHasMedia()) restoreLocal(lease.value)
        }

    fun remoteElapsedMs(): Long {
        val snap = mpdSnapshot.value ?: return 0L
        val base = (snap.status.elapsed * 1000).toLong()
        return if (snap.status.playing) base + (SystemClock.elapsedRealtime() - snapshotAtMs) else base
    }

    private val phoneSide = combine(phoneQueue, phoneIndex, localPlaying, localPositionMs, localDurationMs) { queue, index, playing, position, duration ->
        PhoneSide(queue, index, playing, position, duration)
    }

    val now: StateFlow<NowState> = combine(mpdSnapshot, lease, phoneSide, tick) { snap, lease, phone, _ ->
        if (lease.owner == "phone") {
            val song = phone.queue.getOrNull(phone.index)
            val file = song?.file ?: lease.file
            NowState(
                owner = "phone",
                file = file,
                title = song?.name ?: lease.title ?: file?.substringAfterLast('/')?.substringBeforeLast('.') ?: "nothing playing",
                artist = song?.artist ?: lease.artist,
                elapsed = phone.positionMs / 1000.0,
                duration = phone.durationMs.takeIf { it > 0 }?.let { it / 1000.0 } ?: song?.duration ?: lease.duration ?: 0.0,
                playing = phone.playing,
                next = phoneNext(phone.queue, phone.index)?.name,
            )
        } else {
            val status = snap?.status
            val song = snap?.song
            NowState(
                owner = "desk",
                file = song?.file,
                title = song?.name ?: "nothing playing",
                artist = song?.artist,
                elapsed = remoteElapsedMs() / 1000.0,
                duration = status?.duration ?: song?.duration ?: 0.0,
                playing = status?.playing ?: false,
                next = snap?.next?.name,
            )
        }
    }.stateIn(scope, SharingStarted.Eagerly, NowState())

    private fun phoneNext(queue: List<MpdSong>, index: Int): MpdSong? {
        if (queue.isEmpty() || index < 0) return null
        return queue.getOrNull(index + 1) ?: if (mpdSnapshot.value?.status?.repeat == true) queue.first() else null
    }

    private fun nowSong(): MpdSong? = phoneQueue.value.getOrNull(phoneIndex.value)
        ?: lease.value.let { current -> current.file?.let { MpdSong(it, current.artist, current.title, null, current.duration) } }

    private fun nowFile(): String? = nowSong()?.file

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
        scope.launch { loopWhileForeground(5_000) { refreshPalette() } }
        scope.launch { loopWhileForeground(60_000) { refreshLocalNames() } }
        scope.launch { loopWhileForeground(60_000) { money.refresh() } }
        scope.launch { loopWhileForeground(30_000) { hub.refresh() } }
        scope.launch { loopWhileForeground(300_000) { update.refresh() } }
        scope.launch { loopWhileForeground(10_000) { load.refresh() } }
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
            now.map { it.owner to it.file }.distinctUntilChanged().collectLatest { (owner, file) -> loadCover(owner, file) }
        }
        scope.launch {
            var previous = lease.value.owner
            lease.collect { current ->
                if (current.owner == "phone" && heartbeatJob?.isActive != true) heartbeatJob = launch { loopHeartbeat() }
                if (current.owner != "phone") { heartbeatJob?.cancel(); heartbeatJob = null }
                val h = host
                if (h != null && !busy.value) {
                    if (previous == "phone" && current.owner == "desk") {
                        h.localPause()
                        h.useRemote()
                        phoneQueue.value = emptyList()
                        phoneIndex.value = -1
                    }
                    if (current.owner == "phone" && !h.localHasMedia()) restoreLocal(current)
                }
                if (previous == "phone" && current.owner == "desk" && !busy.value) {
                    mpdSnapshot.value?.song?.file?.let { if (it != lyricsFile.value) loadLyrics(it) }
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
            if (h != null && !busy.value) runCatching {
                adopt(bridge.heartbeat(nowSong(), phonePositionMs(h) / 1000.0, h.localIsPlaying()))
            }
            delay(5_000)
        }
    }

    private suspend fun adopt(remote: Lease) {
        if (busy.value) return
        val h = host
        val lapsed = remote.owner == "desk" && lease.value.owner == "phone" && !remote.playing && h != null && h.localHasMedia()
        lease.value = if (lapsed) bridge.takeLease("phone", nowFile(), h!!.localPositionMs() / 1000.0, h.localIsPlaying()) else remote
    }

    private fun phonePositionMs(h: PlayerHost): Long = if (h.localHasMedia()) h.localPositionMs() else (lease.value.elapsed * 1000).toLong()

    suspend fun refreshMpd() {
        val snap = mpd.snapshot()
        snapshotAtMs = SystemClock.elapsedRealtime()
        mpdSnapshot.value = snap
        mpdReachable.value = true
        val file = snap.song?.file
        if (lease.value.owner == "desk" && file != null && file != lyricsFile.value) loadLyrics(file)
        if (lease.value.owner == "phone" && snap.status.playing && !busy.value) scope.launch { refreshLease() }
    }

    private fun refreshAll() = scope.launch {
        runCatching { refreshVolume() }
        runCatching { refreshLease() }
        runCatching { refreshPalette() }
        runCatching { refreshLocalNames() }
        runCatching { money.refresh() }
        runCatching { hub.refresh() }
        runCatching { update.refresh() }
        runCatching { load.refresh() }
        val file = now.value.file
        if (file != null && file != lyricsFile.value && !lyricsBusy.value) loadLyrics(file)
    }

    suspend fun refreshVolume() { runCatching { volume.value = bridge.volume() } }
    suspend fun refreshLease() { runCatching { adopt(bridge.lease()) } }
    suspend fun refreshPalette() { runCatching { palette.value = theme.palette() } }

    suspend fun refreshLocalNames(): Set<String> {
        val names = runCatching { library.names() }.getOrDefault(localNames.value)
        localNames.value = names
        return names
    }

    fun refreshLocalNamesAsync() = scope.launch { refreshLocalNames() }

    fun applyIconBucket() {
        val hsv = FloatArray(3)
        runCatching { android.graphics.Color.colorToHSV(android.graphics.Color.parseColor(palette.value.primary), hsv) }.getOrElse { return }
        val bucket = ((Math.round(hsv[0] / 30f) % 12) + 12) % 12
        val current = prefs.iconBucket
        if (bucket == current) return
        val pm = app.packageManager
        runCatching {
            pm.setComponentEnabledSetting(ComponentName(app, "ac.mvr.phone.Icon$bucket"), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            pm.setComponentEnabledSetting(ComponentName(app, "ac.mvr.phone.Icon$current"), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            prefs.iconBucket = bucket
        }
    }

    fun report(err: Throwable) {
        val text = when (err) {
            is Unreachable -> "desktop unreachable"
            else -> err.message ?: err.toString()
        }
        noticeJob?.cancel()
        notice.value = text
        noticeJob = scope.launch {
            delay(5_000)
            notice.value = null
        }
    }

    private suspend fun loadCover(owner: String, file: String?) {
        val key = "$owner:$file"
        if (key == coverKey && cover.value != null) return
        coverKey = key
        cover.value = null
        if (file == null) return
        val bytes = runCatching {
            if (owner == "phone") library.find(file)?.let { library.artwork(it.uri) } else bridge.cover(file)
        }.getOrNull() ?: return
        val bitmap = withContext(Dispatchers.IO) { Artwork.decode(bytes) } ?: return
        if (coverKey == key) cover.value = bitmap
    }

    private fun restoreLocal(current: Lease) = scope.launch {
        val file = current.file ?: return@launch
        val track = runCatching { library.find(file) }.getOrNull() ?: return@launch
        val seed = listOf(MpdSong(file, current.artist, current.title, null, current.duration))
        val fresh = phoneQueue.value.isEmpty()
        if (fresh) {
            phoneQueue.value = seed
            phoneIndex.value = 0
        }
        host?.useLocal(track.uri, current.title ?: track.displayName, current.artist, (current.elapsed * 1000).toLong(), false, library.artwork(track.uri))
        if (fresh) {
            if (mpdSnapshot.value == null) runCatching { refreshMpd() }
            extendQueue(seed, file)
        }
    }

    fun act(block: suspend () -> Unit): Job = scope.launch {
        try { block() } catch (err: Exception) { report(err) }
    }

    fun togglePlay() = act {
        val h = host
        if (now.value.phoneOwns && h != null) {
            if (!h.localHasMedia()) restoreLocal(lease.value).join()
            if (h.localIsPlaying()) h.localPause() else h.localPlay()
        } else {
            val status = mpdSnapshot.value?.status
            when {
                status?.playing == true -> mpd.pause(true)
                status?.state == "pause" -> mpd.pause(false)
                else -> mpd.play()
            }
            refreshMpd()
        }
    }

    fun next() = act {
        if (now.value.phoneOwns) localAdvance(1) else { mpd.next(); refreshMpd() }
    }

    fun previous() = act {
        if (now.value.phoneOwns) localAdvance(-1) else { mpd.previous(); refreshMpd() }
    }

    fun seek(seconds: Double) = act {
        val h = host
        if (now.value.phoneOwns && h != null) h.localSeek((seconds * 1000).toLong())
        else { mpd.seek(seconds); refreshMpd() }
    }

    suspend fun setSinkVolume(level: Int) { volume.value = bridge.setVolume(level = level.coerceIn(0, 100)) }
    suspend fun setSinkMuted(muted: Boolean) { volume.value = bridge.setVolume(muted = muted) }
    suspend fun stepSinkVolume(step: Int) { volume.value = bridge.stepVolume(step) }
    fun setSinkMutedAsync(muted: Boolean) = act { setSinkMuted(muted) }
    fun stepSinkVolumeAsync(step: Int) = act { stepSinkVolume(step) }

    fun dragSinkVolume(level: Int) {
        volumeTarget = level
        if (volumeJob?.isActive == true) return
        volumeJob = scope.launch {
            while (true) {
                val target = volumeTarget ?: break
                volumeTarget = null
                try { setSinkVolume(target) } catch (err: Exception) { report(err); break }
                delay(120)
            }
        }
    }

    fun takeOver(target: String) = act {
        handoff.withLock {
            busy.value = true
            try {
                val h = host ?: throw IllegalStateException("player not ready yet")
                if (target == "phone") moveToPhone(h) else moveToDesk(h)
            } finally {
                busy.value = false
            }
        }
    }

    private suspend fun moveToPhone(h: PlayerHost) {
        val online = reachable.value
        if (online) runCatching { refreshMpd() }
        val snap = mpdSnapshot.value
        val expected = snap?.song?.file
        if (online && snap != null && expected == null) throw IllegalStateException("desktop has nothing to hand over")
        val known = expected?.let { library.find(it) ?: throw IllegalStateException("not on the phone yet · ${it.substringAfterLast('/')}") }
        val granted = if (online) bridge.takeLease("phone", null, null, null) else {
            runCatching { if (snap?.status?.playing == true) mpd.pause(true) }
            Lease(
                owner = "phone",
                file = snap?.song?.file,
                elapsed = remoteElapsedMs() / 1000.0,
                playing = snap?.status?.playing ?: false,
                artist = snap?.song?.artist,
                title = snap?.song?.title,
                duration = snap?.status?.duration ?: snap?.song?.duration,
            )
        }
        val file = granted.file ?: throw IllegalStateException("desktop has nothing to hand over")
        val track = if (file == expected) known else library.find(file)
        if (track == null) {
            if (online) bridge.takeLease("desk", granted.file, granted.elapsed, granted.playing)
            throw IllegalStateException("not on the phone yet · ${file.substringAfterLast('/')}")
        }
        val current = MpdSong(file, granted.artist, granted.title, null, granted.duration)
        val seed = listOf(current)
        phoneQueue.value = seed
        phoneIndex.value = 0
        lease.value = granted
        h.useLocal(track.uri, granted.title ?: track.displayName, granted.artist, (granted.elapsed * 1000).toLong(), granted.playing, library.artwork(track.uri))
        loadLyrics(file)
        extendQueue(seed, file, snap)
    }

    private suspend fun extendQueue(seed: List<MpdSong>, file: String, snap: MpdSnapshot? = mpdSnapshot.value) {
        val names = refreshLocalNames()
        val copied = runCatching { copyQueue(snap, file, names) }.getOrDefault(emptyList())
        if (phoneQueue.value !== seed || phoneIndex.value != 0) return
        val queue = if (copied.any { it.file == file }) copied else seed + copied
        val at = queue.indexOfFirst { it.file == file && it.pos == snap?.status?.song }
        phoneQueue.value = queue
        phoneIndex.value = if (at >= 0) at else queue.indexOfFirst { it.file == file }
    }

    private suspend fun copyQueue(snap: MpdSnapshot?, file: String, names: Set<String>): List<MpdSong> {
        val status = snap?.status ?: return emptyList()
        val local = mpd.queueWindow(0, status.playlistLength).filter { it.file.substringAfterLast('/') in names }
        if (!status.random) return local
        return listOfNotNull(local.firstOrNull { it.file == file }) + local.filter { it.file != file }.shuffled()
    }

    private suspend fun moveToDesk(h: PlayerHost) {
        if (!reachable.value) throw Unreachable("desktop unreachable")
        val positionMs = phonePositionMs(h)
        val playing = h.localIsPlaying()
        h.localPause()
        val granted = try {
            bridge.takeLease("desk", nowFile(), positionMs / 1000.0, playing)
        } catch (err: Exception) {
            if (playing) h.localPlay()
            throw err
        }
        lease.value = granted
        phoneQueue.value = emptyList()
        phoneIndex.value = -1
        h.useRemote()
        refreshMpd()
    }

    private suspend fun startLocal(h: PlayerHost, song: MpdSong, track: LocalTrack, positionMs: Long, play: Boolean) {
        lease.value = lease.value.copy(file = song.file, title = song.title, artist = song.artist, duration = song.duration, elapsed = positionMs / 1000.0)
        h.useLocal(track.uri, song.name, song.artist, positionMs, play, library.artwork(track.uri))
        runCatching { bridge.heartbeat(song, positionMs / 1000.0, play) }
        loadLyrics(song.file)
    }

    private suspend fun localAdvance(step: Int) {
        val h = host ?: return
        val queue = phoneQueue.value
        if (queue.isEmpty()) return
        var index = phoneIndex.value + step
        if (index < 0 || index >= queue.size) {
            if (mpdSnapshot.value?.status?.repeat != true) return
            index = (index + queue.size) % queue.size
        }
        val song = queue[index]
        val track = library.find(song.file) ?: throw IllegalStateException("not on the phone yet · ${song.name}")
        phoneIndex.value = index
        startLocal(h, song, track, 0, true)
    }

    fun localEnded() = act {
        val status = mpdSnapshot.value?.status
        if (status?.single == true) {
            if (status.repeat) host?.let { it.localSeek(0); it.localPlay() }
            return@act
        }
        localAdvance(1)
    }

    fun playSong(song: MpdSong) = act {
        val h = host
        if (now.value.phoneOwns && h != null) {
            val track = library.find(song.file) ?: throw IllegalStateException("not on the phone yet · ${song.name}")
            val queue = phoneQueue.value.toMutableList()
            val at = (phoneIndex.value + 1).coerceIn(0, queue.size)
            queue.add(at, song)
            phoneQueue.value = queue
            phoneIndex.value = at
            startLocal(h, song, track, 0, true)
        } else {
            val id = mpd.addId(song.file, afterCurrent = mpdSnapshot.value?.status?.song != null)
            mpd.playId(id)
            refreshMpd()
        }
    }

    private fun visible(songs: List<MpdSong>) = songs.filter { !it.file.startsWith(".") && !it.file.contains("/.") }

    suspend fun recent(): List<MpdSong> = visible(mpd.recent(200))

    suspend fun find(term: String): List<MpdSong> = visible(mpd.find(term, 120))

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
}

fun fmtTime(seconds: Double): String {
    val total = seconds.coerceAtLeast(0.0).toInt()
    return "%d:%02d".format(java.util.Locale.ROOT, total / 60, total % 60)
}
