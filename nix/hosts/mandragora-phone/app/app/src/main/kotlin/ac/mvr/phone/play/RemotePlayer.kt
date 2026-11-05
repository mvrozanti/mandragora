package ac.mvr.phone.play

import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.DeviceInfo
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import ac.mvr.phone.state.Store
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.launch

@OptIn(UnstableApi::class)
class RemotePlayer(looper: Looper, private val store: Store) : SimpleBasePlayer(looper) {

    private val commands = Player.Commands.Builder().addAll(
        Player.COMMAND_PLAY_PAUSE,
        Player.COMMAND_PREPARE,
        Player.COMMAND_STOP,
        Player.COMMAND_SEEK_TO_DEFAULT_POSITION,
        Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
        Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
        Player.COMMAND_SEEK_TO_PREVIOUS,
        Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
        Player.COMMAND_SEEK_TO_NEXT,
        Player.COMMAND_SEEK_TO_MEDIA_ITEM,
        Player.COMMAND_SEEK_BACK,
        Player.COMMAND_SEEK_FORWARD,
        Player.COMMAND_SET_SHUFFLE_MODE,
        Player.COMMAND_SET_REPEAT_MODE,
        Player.COMMAND_GET_CURRENT_MEDIA_ITEM,
        Player.COMMAND_GET_TIMELINE,
        Player.COMMAND_GET_METADATA,
        Player.COMMAND_GET_DEVICE_VOLUME,
        Player.COMMAND_SET_DEVICE_VOLUME_WITH_FLAGS,
        Player.COMMAND_ADJUST_DEVICE_VOLUME_WITH_FLAGS,
        Player.COMMAND_GET_AUDIO_ATTRIBUTES,
        Player.COMMAND_RELEASE,
    ).build()

    private val deviceInfo = DeviceInfo.Builder(DeviceInfo.PLAYBACK_TYPE_REMOTE).setMinVolume(0).setMaxVolume(100).build()

    override fun getState(): State {
        val snap = store.mpdSnapshot.value
        val status = snap?.status
        val song = snap?.song
        val sink = store.volume.value.sink
        val builder = State.Builder()
            .setAvailableCommands(commands)
            .setPlayWhenReady(status?.playing == true, Player.PLAY_WHEN_READY_CHANGE_REASON_REMOTE)
            .setPlaybackState(if (song == null) Player.STATE_IDLE else Player.STATE_READY)
            .setRepeatMode(if (status?.repeat == true) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF)
            .setShuffleModeEnabled(status?.random == true)
            .setDeviceInfo(deviceInfo)
            .setDeviceVolume(sink?.volume ?: 0)
            .setIsDeviceMuted(sink?.muted == true)
            .setMaxSeekToPreviousPositionMs(3000)
            .setSeekBackIncrementMs(10_000)
            .setSeekForwardIncrementMs(10_000)
        if (song != null && status != null) {
            val metadata = MediaMetadata.Builder()
                .setTitle(song.title ?: song.file.substringAfterLast('/').substringBeforeLast('.'))
                .setArtist(listOfNotNull(song.artist, "on desktop").joinToString(" · "))
                .setAlbumTitle(song.album)
                .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
                .build()
            val durationUs = ((status.duration ?: song.duration ?: 0.0) * 1_000_000).toLong()
            val current = MediaItemData.Builder("current:${song.file}")
                .setMediaItem(MediaItem.Builder().setMediaId(song.file).setMediaMetadata(metadata).build())
                .setMediaMetadata(metadata)
                .setDurationUs(if (durationUs > 0) durationUs else androidx.media3.common.C.TIME_UNSET)
                .setIsSeekable(true)
                .build()
            val previous = MediaItemData.Builder("previous").setIsPlaceholder(true).setMediaItem(MediaItem.Builder().setMediaId("previous").build()).build()
            val next = MediaItemData.Builder("next").setIsPlaceholder(true).setMediaItem(MediaItem.Builder().setMediaId("next").build()).build()
            builder.setPlaylist(listOf(previous, current, next))
                .setCurrentMediaItemIndex(1)
                .setContentPositionMs(PositionSupplier.getExtrapolating(store.remoteElapsedMs(), if (status.playing) 1f else 0f))
        }
        return builder.build()
    }

    private fun run(block: suspend () -> Unit): ListenableFuture<*> {
        store.scope.launch { runCatching { block() }.onFailure { store.report(it) } }
        return Futures.immediateVoidFuture()
    }

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> = run {
        if (playWhenReady) store.mpd.play() else store.mpd.pause(true)
        store.refreshMpd()
    }

    override fun handlePrepare(): ListenableFuture<*> = Futures.immediateVoidFuture()

    override fun handleStop(): ListenableFuture<*> = run { store.mpd.pause(true); store.refreshMpd() }

    override fun handleRelease(): ListenableFuture<*> = Futures.immediateVoidFuture()

    override fun handleSetRepeatMode(repeatMode: Int): ListenableFuture<*> = run {
        store.mpd.setFlag("repeat", repeatMode != Player.REPEAT_MODE_OFF)
        store.refreshMpd()
    }

    override fun handleSetShuffleModeEnabled(shuffleModeEnabled: Boolean): ListenableFuture<*> = run {
        store.mpd.setFlag("random", shuffleModeEnabled)
        store.refreshMpd()
    }

    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> = run {
        when (mediaItemIndex) {
            0 -> store.mpd.previous()
            2 -> store.mpd.next()
            else -> store.mpd.seek(positionMs.coerceAtLeast(0) / 1000.0)
        }
        store.refreshMpd()
    }

    override fun handleSetDeviceVolume(deviceVolume: Int, flags: Int): ListenableFuture<*> = run {
        store.setSinkVolume(deviceVolume)
    }

    override fun handleIncreaseDeviceVolume(flags: Int): ListenableFuture<*> = run {
        store.stepSinkVolume(4)
    }

    override fun handleDecreaseDeviceVolume(flags: Int): ListenableFuture<*> = run {
        store.stepSinkVolume(-4)
    }

    override fun handleSetDeviceMuted(muted: Boolean, flags: Int): ListenableFuture<*> = run {
        store.setSinkMuted(muted)
    }

    fun refresh() = invalidateState()
}
