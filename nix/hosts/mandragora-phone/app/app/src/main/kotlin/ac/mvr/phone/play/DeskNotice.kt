package ac.mvr.phone.play

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.SystemClock
import ac.mvr.phone.MainActivity
import ac.mvr.phone.R
import ac.mvr.phone.net.DesktopMedia
import ac.mvr.phone.net.Http
import ac.mvr.phone.state.Store
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class DeskNotice(private val context: Context, private val store: Store) {

    companion object {
        const val ACTION = "ac.mvr.phone.DESK_MEDIA"
        private const val CHANNEL = "desk_media"
        private const val NOTIFICATION_ID = 2
        private const val EXTRA_PLAYER = "player"
        private const val EXTRA_ACTION = "action"
    }

    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val session = MediaSession(context, "mandragora-desk")
    private var shown: DesktopMedia? = null
    private var artKey: String? = null
    private var art: Bitmap? = null
    private var artJob: Job? = null

    init {
        notifications.createNotificationChannel(NotificationChannel(CHANNEL, "desktop media", NotificationManager.IMPORTANCE_LOW))
        session.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = send("play")
            override fun onPause() = send("pause")
            override fun onSkipToNext() = send("next")
            override fun onSkipToPrevious() = send("previous")
            override fun onSeekTo(pos: Long) = send("seek", pos / 1000.0)
        })
    }

    private fun send(action: String, position: Double? = null) {
        val player = shown?.player ?: return
        store.act { store.deskCommand(player, action, position) }
    }

    fun handle(intent: Intent) {
        val player = intent.getStringExtra(EXTRA_PLAYER) ?: return
        val action = intent.getStringExtra(EXTRA_ACTION) ?: return
        store.act { store.deskCommand(player, action) }
    }

    fun show(media: DesktopMedia) {
        val changed = media.copy(position = 0.0) != shown?.copy(position = 0.0)
        shown = media
        val seekable = media.length > 0
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        if (seekable) actions = actions or PlaybackState.ACTION_SEEK_TO
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (media.playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    store.mediaPositionMs(media),
                    if (media.playing) 1f else 0f,
                    SystemClock.elapsedRealtime(),
                )
                .build(),
        )
        if (!changed) return
        publish(media)
        if (media.art != artKey) loadArt(media)
    }

    fun hide() {
        if (shown == null) return
        shown = null
        session.isActive = false
        notifications.cancel(NOTIFICATION_ID)
    }

    fun release() {
        hide()
        artJob?.cancel()
        session.release()
    }

    private fun publish(media: DesktopMedia) {
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, media.label)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, media.byline)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, if (media.length > 0) (media.length * 1000).toLong() else -1L)
                .apply { if (artKey == media.art) art?.let { putBitmap(MediaMetadata.METADATA_KEY_ART, it) } }
                .build(),
        )
        session.isActive = true
        notifications.notify(NOTIFICATION_ID, notification(media))
    }

    private fun loadArt(media: DesktopMedia) {
        artJob?.cancel()
        artKey = media.art
        art = null
        if (media.art.isEmpty()) return
        artJob = store.scope.launch {
            val bytes = runCatching { Http.bytes(store.bridge.mediaArtUrl(media.player, media.art)) }.getOrNull() ?: return@launch
            val bitmap = withContext(Dispatchers.Default) { Artwork.decode(bytes) } ?: return@launch
            if (artKey != media.art) return@launch
            art = bitmap
            shown?.let { publish(it) }
        }
    }

    private fun notification(media: DesktopMedia): Notification {
        val open = PendingIntent.getActivity(
            context,
            1,
            Intent(context, MainActivity::class.java).putExtra("screen", "music"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val playPause = if (media.playing) "pause" else "play"
        return Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_mono)
            .setContentTitle(media.label)
            .setContentText(media.byline)
            .setLargeIcon(if (artKey == media.art) art else null)
            .setContentIntent(open)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .addAction(action(android.R.drawable.ic_media_previous, "previous", media.player))
            .addAction(action(if (media.playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play, playPause, media.player))
            .addAction(action(android.R.drawable.ic_media_next, "next", media.player))
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2))
            .build()
    }

    private fun action(icon: Int, name: String, player: String): Notification.Action {
        val intent = Intent(context, PlaybackService::class.java)
            .setAction(ACTION)
            .putExtra(EXTRA_PLAYER, player)
            .putExtra(EXTRA_ACTION, name)
        val pending = PendingIntent.getService(context, name.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Action.Builder(Icon.createWithResource(context, icon), name, pending).build()
    }
}
