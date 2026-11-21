package ac.mvr.phone.play

import android.net.Uri
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.DeviceInfo
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import ac.mvr.phone.net.DesktopMedia
import ac.mvr.phone.state.Store
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import kotlinx.coroutines.launch

@OptIn(UnstableApi::class)
class DeskPlayer(looper: Looper, private val store: Store) : SimpleBasePlayer(looper) {

    var bound: String? = null
        private set

    private val baseCommands = Player.Commands.Builder().addAll(
        Player.COMMAND_PLAY_PAUSE,
        Player.COMMAND_PREPARE,
        Player.COMMAND_STOP,
        Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
        Player.COMMAND_SEEK_TO_PREVIOUS,
        Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
        Player.COMMAND_SEEK_TO_NEXT,
        Player.COMMAND_GET_CURRENT_MEDIA_ITEM,
        Player.COMMAND_GET_TIMELINE,
        Player.COMMAND_GET_METADATA,
        Player.COMMAND_GET_DEVICE_VOLUME,
        Player.COMMAND_SET_DEVICE_VOLUME_WITH_FLAGS,
        Player.COMMAND_ADJUST_DEVICE_VOLUME_WITH_FLAGS,
        Player.COMMAND_RELEASE,
    ).build()

    private val deviceInfo = DeviceInfo.Builder(DeviceInfo.PLAYBACK_TYPE_REMOTE).setMinVolume(0).setMaxVolume(100).build()

    fun bind(player: String) {
        if (bound == player) return
        bound = player
        invalidateState()
    }

    fun refresh() = invalidateState()

    private fun current(): DesktopMedia? = bound?.let { name -> store.media.value.firstOrNull { it.player == name } }

    override fun getState(): State {
        val media = current()
        val sink = store.volume.value.sink
        val seekable = media != null && media.length > 0
        val commands = if (seekable) baseCommands.buildUpon().add(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM).build() else baseCommands
        val builder = State.Builder()
            .setAvailableCommands(commands)
            .setPlayWhenReady(media?.playing == true, Player.PLAY_WHEN_READY_CHANGE_REASON_REMOTE)
            .setPlaybackState(if (media == null) Player.STATE_IDLE else Player.STATE_READY)
            .setDeviceInfo(deviceInfo)
            .setDeviceVolume(sink?.volume ?: 0)
            .setIsDeviceMuted(sink?.muted == true)
        if (media != null) {
            val metadata = MediaMetadata.Builder()
                .setTitle(media.label)
                .setArtist(media.byline)
                .setMediaType(MediaMetadata.MEDIA_TYPE_VIDEO)
                .apply { if (media.art.isNotEmpty()) setArtworkUri(Uri.parse(store.bridge.mediaArtUrl(media.player, media.art))) }
                .build()
            val item = MediaItemData.Builder("desk:${media.player}")
                .setMediaItem(MediaItem.Builder().setMediaId(media.player).setMediaMetadata(metadata).build())
                .setMediaMetadata(metadata)
                .setDurationUs(if (seekable) (media.length * 1_000_000).toLong() else C.TIME_UNSET)
                .setIsSeekable(seekable)
                .build()
            val previous = MediaItemData.Builder("previous").setIsPlaceholder(true).setMediaItem(MediaItem.Builder().setMediaId("previous").build()).build()
            val next = MediaItemData.Builder("next").setIsPlaceholder(true).setMediaItem(MediaItem.Builder().setMediaId("next").build()).build()
            builder.setPlaylist(listOf(previous, item, next))
                .setCurrentMediaItemIndex(1)
                .setContentPositionMs(PositionSupplier.getExtrapolating(store.mediaPositionMs(media), if (media.playing) 1f else 0f))
        }
        return builder.build()
    }

    private fun run(block: suspend () -> Unit): ListenableFuture<*> {
        val done = SettableFuture.create<Unit>()
        store.scope.launch {
            runCatching { block() }.onFailure { store.report(it) }
            done.set(Unit)
        }
        return done
    }

    private fun command(action: String, position: Double? = null): ListenableFuture<*> {
        val player = bound ?: return SettableFuture.create<Unit>().apply { set(Unit) }
        return run { store.deskCommand(player, action, position) }
    }

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> = command(if (playWhenReady) "play" else "pause")

    override fun handlePrepare(): ListenableFuture<*> = SettableFuture.create<Unit>().apply { set(Unit) }

    override fun handleStop(): ListenableFuture<*> = command("pause")

    override fun handleRelease(): ListenableFuture<*> = SettableFuture.create<Unit>().apply { set(Unit) }

    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> = when {
        mediaItemIndex == 0 -> command("previous")
        mediaItemIndex == 2 -> command("next")
        else -> command("seek", positionMs.coerceAtLeast(0) / 1000.0)
    }

    override fun handleSetDeviceVolume(deviceVolume: Int, flags: Int): ListenableFuture<*> = run { store.setSinkVolume(deviceVolume) }

    override fun handleIncreaseDeviceVolume(flags: Int): ListenableFuture<*> = run { store.stepSinkVolume(4) }

    override fun handleDecreaseDeviceVolume(flags: Int): ListenableFuture<*> = run { store.stepSinkVolume(-4) }

    override fun handleSetDeviceMuted(muted: Boolean, flags: Int): ListenableFuture<*> = run { store.setSinkMuted(muted) }
}
