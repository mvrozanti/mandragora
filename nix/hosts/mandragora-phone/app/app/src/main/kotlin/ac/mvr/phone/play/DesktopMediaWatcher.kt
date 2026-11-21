package ac.mvr.phone.play

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle
import ac.mvr.phone.MainActivity
import ac.mvr.phone.R
import ac.mvr.phone.net.DesktopMedia
import ac.mvr.phone.store
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class DesktopMediaWatcher : Service() {

    companion object {
        private const val CHANNEL_WATCH = "desk_watch"
        private const val CHANNEL_MEDIA = "desk_media"
        private const val NOTIF_WATCH = 1
        private const val NOTIF_MEDIA = 2
        private const val ACTION = "ac.mvr.phone.DESK_MEDIA"
        private const val EXTRA_ACTION = "action"
        private const val EXTRA_PLAYER = "player"
        private const val ACTIVE_POLL_MS = 5_000L
        private const val IDLE_POLL_MS = 15_000L

        fun ensure(context: Context) {
            runCatching { ContextCompat.startForegroundService(context, Intent(context, DesktopMediaWatcher::class.java)) }
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var poll: Job? = null
    private var session: MediaSessionCompat? = null

    private val transportActions: Long =
        PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS

    override fun onCreate() {
        super.onCreate()
        val notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel(CHANNEL_WATCH, "watching the desk", NotificationManager.IMPORTANCE_MIN))
        notifications.createNotificationChannel(NotificationChannel(CHANNEL_MEDIA, "desktop media", NotificationManager.IMPORTANCE_LOW))
        session = MediaSessionCompat(this, "mandragora-desk-media").apply {
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = command(null, "play")
                override fun onPause() = command(null, "pause")
                override fun onSkipToNext() = command(null, "next")
                override fun onSkipToPrevious() = command(null, "previous")
            })
        }
        startForeground(NOTIF_WATCH, watchNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        poll = scope.launch {
            while (isActive) {
                val players = pollMedia()
                delay(if (players.isEmpty()) IDLE_POLL_MS else ACTIVE_POLL_MS)
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION) {
            command(intent.getStringExtra(EXTRA_PLAYER), intent.getStringExtra(EXTRA_ACTION) ?: "play-pause")
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        poll?.cancel()
        session?.isActive = false
        session?.release()
        session = null
        getSystemService(NotificationManager::class.java).cancel(NOTIF_MEDIA)
        scope.cancel()
        super.onDestroy()
    }

    private suspend fun pollMedia(): List<DesktopMedia> {
        val players = runCatching { store.bridge.media().players }.getOrDefault(store.media.value)
        store.media.value = players
        update(players)
        return players
    }

    private fun command(player: String?, action: String) {
        scope.launch {
            val current = store.media.value
            val target = player ?: current.firstOrNull { it.playing }?.player ?: current.firstOrNull()?.player ?: return@launch
            runCatching { store.bridge.mediaAction(target, action) }
                .onSuccess { store.media.value = it.players; update(it.players) }
        }
    }

    private fun update(players: List<DesktopMedia>) {
        val active = players.firstOrNull { it.playing } ?: players.firstOrNull()
        val mediaSession = session ?: return
        val notifications = getSystemService(NotificationManager::class.java)
        if (active == null) {
            mediaSession.isActive = false
            notifications.cancel(NOTIF_MEDIA)
            return
        }
        mediaSession.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, active.title.ifEmpty { active.source })
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, active.artist.ifEmpty { "${active.source} on the desktop" })
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, "on the desktop")
                .build(),
        )
        mediaSession.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(transportActions)
                .setState(if (active.playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED, PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1f)
                .build(),
        )
        mediaSession.isActive = true
        notifications.notify(NOTIF_MEDIA, mediaNotification(active))
    }

    private fun mediaNotification(player: DesktopMedia): Notification {
        val playing = player.playing
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).putExtra("screen", "music"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_MEDIA)
            .setSmallIcon(R.drawable.ic_launcher_mono)
            .setContentTitle(player.title.ifEmpty { player.source })
            .setContentText(listOfNotNull(player.artist.takeIf { it.isNotEmpty() }, "${player.source} on the desktop").joinToString(" · "))
            .setContentIntent(openApp)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_media_previous, "previous", actionPending(player.player, "previous"))
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "pause" else "play",
                actionPending(player.player, if (playing) "pause" else "play"),
            )
            .addAction(android.R.drawable.ic_media_next, "next", actionPending(player.player, "next"))
            .setStyle(MediaStyle().setMediaSession(session?.sessionToken).setShowActionsInCompactView(0, 1, 2))
            .build()
    }

    private fun actionPending(player: String, action: String): PendingIntent {
        val intent = Intent(this, DesktopMediaWatcher::class.java)
            .setAction(ACTION)
            .putExtra(EXTRA_PLAYER, player)
            .putExtra(EXTRA_ACTION, action)
        return PendingIntent.getService(this, (player + action).hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun watchNotification(): Notification = NotificationCompat.Builder(this, CHANNEL_WATCH)
        .setSmallIcon(R.drawable.ic_launcher_mono)
        .setContentTitle("mandragora")
        .setContentText("watching the desk")
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setPriority(NotificationCompat.PRIORITY_MIN)
        .build()
}
