package ac.mvr.phone.play

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import ac.mvr.phone.MainActivity
import ac.mvr.phone.state.PlayerHost
import ac.mvr.phone.state.Store
import ac.mvr.phone.store
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

@OptIn(UnstableApi::class)
class PlaybackService : MediaSessionService(), PlayerHost {
    private lateinit var appStore: Store
    private lateinit var local: ExoPlayer
    private lateinit var remote: RemotePlayer
    private var session: MediaSession? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var remoteWatch: Job? = null

    override fun onCreate() {
        super.onCreate()
        appStore = store
        local = ExoPlayer.Builder(this)
            .setAudioAttributes(AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).setUsage(C.USAGE_MEDIA).build(), true)
            .setHandleAudioBecomingNoisy(true)
            .build()
        local.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) { appStore.localPlaying.value = isPlaying }
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) appStore.localEnded()
            }
        })
        remote = RemotePlayer(mainLooper, appStore)
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val initial: Player = if (appStore.lease.value.owner == "phone") local else remote
        session = MediaSession.Builder(this, initial).setSessionActivity(launch).build()
        remoteWatch = scope.launch {
            launch { appStore.mpdSnapshot.collectLatest { remote.refresh() } }
            launch { appStore.volume.collectLatest { remote.refresh() } }
        }
        appStore.host = this
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (!local.isPlaying) stopSelf()
    }

    override fun onDestroy() {
        appStore.host = null
        remoteWatch?.cancel()
        scope.cancel()
        session?.release()
        session = null
        local.release()
        remote.release()
        super.onDestroy()
    }

    override fun useRemote() {
        local.pause()
        session?.setPlayer(remote)
        remote.refresh()
    }

    override fun useLocal(uri: Uri, title: String, artist: String?, positionMs: Long, play: Boolean) {
        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(listOfNotNull(artist, "on this phone").joinToString(" · "))
            .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
            .build()
        local.setMediaItem(MediaItem.Builder().setUri(uri).setMediaMetadata(metadata).build(), positionMs.coerceAtLeast(0))
        local.prepare()
        local.playWhenReady = play
        session?.setPlayer(local)
    }

    override fun localPositionMs(): Long = local.currentPosition

    override fun localDurationMs(): Long = local.duration.takeIf { it != C.TIME_UNSET } ?: 0L

    override fun localIsPlaying(): Boolean = local.playWhenReady && local.playbackState != Player.STATE_ENDED

    override fun localPlay() { local.play() }

    override fun localPause() { local.pause() }

    override fun localSeek(positionMs: Long) { local.seekTo(positionMs.coerceAtLeast(0)) }
}
