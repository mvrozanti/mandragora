package ac.mvr.phone.play

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
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
    private lateinit var localSession: Player
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
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()
        local.addListener(object : Player.Listener {
            override fun onEvents(player: Player, events: Player.Events) {
                if (events.containsAny(Player.EVENT_PLAY_WHEN_READY_CHANGED, Player.EVENT_PLAYBACK_STATE_CHANGED)) appStore.localPlaying.value = localIsPlaying()
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) { if (isPlaying) appStore.localStarted() }
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) appStore.localEnded()
            }
            override fun onPlayerError(error: PlaybackException) { appStore.localFailed(describe(error), local.playWhenReady) }
        })
        localSession = PhoneQueuePlayer(local)
        remote = RemotePlayer(mainLooper, appStore)
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).putExtra("screen", "music"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val initial: Player = if (appStore.lease.value.owner == "phone") localSession else remote
        session = MediaSession.Builder(this, initial).setSessionActivity(launch).build()
        remoteWatch = scope.launch {
            launch { appStore.mpdSnapshot.collectLatest { remote.refresh() } }
            launch { appStore.volume.collectLatest { remote.refresh() } }
        }
        appStore.host = this
        appStore.act { appStore.refreshVolume() }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) = Unit

    override fun onUpdateNotification(session: MediaSession, startInForegroundRequired: Boolean) {
        super.onUpdateNotification(session, true)
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
            .setArtist(listOfNotNull(artist, "on the phone").joinToString(" · "))
            .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
            .build()
        local.setMediaItem(MediaItem.Builder().setUri(uri).setMediaMetadata(metadata).build(), positionMs.coerceAtLeast(0))
        local.prepare()
        local.playWhenReady = play
        session?.setPlayer(localSession)
    }

    override fun localArtwork(uri: Uri, artwork: ByteArray) {
        val item = local.currentMediaItem ?: return
        if (item.localConfiguration?.uri != uri) return
        val metadata = item.mediaMetadata.buildUpon().setArtworkData(artwork, MediaMetadata.PICTURE_TYPE_FRONT_COVER).build()
        local.replaceMediaItem(local.currentMediaItemIndex, item.buildUpon().setMediaMetadata(metadata).build())
    }

    override fun localPositionMs(): Long = local.currentPosition

    override fun localDurationMs(): Long = local.duration.takeIf { it != C.TIME_UNSET } ?: 0L

    override fun localIsPlaying(): Boolean =
        local.playWhenReady && (local.playbackState == Player.STATE_READY || local.playbackState == Player.STATE_BUFFERING)

    override fun localPlay() {
        if (local.mediaItemCount == 0) return
        when (local.playbackState) {
            Player.STATE_IDLE -> local.prepare()
            Player.STATE_ENDED -> local.seekTo(local.currentMediaItemIndex, 0)
        }
        local.play()
    }

    private fun describe(error: PlaybackException): String {
        val http = generateSequence<Throwable>(error) { it.cause }.filterIsInstance<HttpDataSource.InvalidResponseCodeException>().firstOrNull()
        return when {
            http != null -> "the desktop answered ${http.responseCode}"
            error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
                error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT -> "the connection dropped"
            error.errorCode == PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND -> "the file is gone"
            error.errorCode in PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED..PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED -> "it does not decode"
            else -> error.errorCodeName.removePrefix("ERROR_CODE_").lowercase().replace('_', ' ')
        }
    }

    override fun localPause() { local.pause() }

    override fun localSeek(positionMs: Long) { local.seekTo(positionMs.coerceAtLeast(0)) }

    override fun localHasMedia(): Boolean = local.mediaItemCount > 0

    private inner class PhoneQueuePlayer(player: Player) : ForwardingPlayer(player) {
        private val skips = Player.Commands.Builder().addAll(
            Player.COMMAND_SEEK_TO_PREVIOUS,
            Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_NEXT,
            Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
        ).build()

        override fun getAvailableCommands(): Player.Commands = super.getAvailableCommands().buildUpon().addAll(skips).build()

        override fun isCommandAvailable(command: Int): Boolean = skips.contains(command) || super.isCommandAvailable(command)

        override fun seekToNext() { appStore.next() }

        override fun seekToNextMediaItem() { appStore.next() }

        override fun seekToPrevious() { appStore.previous() }

        override fun seekToPreviousMediaItem() { appStore.previous() }
    }
}
