package ac.mvr.phone.inbox

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import ac.mvr.phone.MainActivity
import ac.mvr.phone.R
import ac.mvr.phone.net.InboxItem
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

object Alerts {
    const val LISTENER_ID = 7001
    private const val TAG = "inbox"
    private const val CHANNEL_ALERT = "alerts"
    private const val CHANNEL_INFO = "messages"
    private const val CHANNEL_LISTENER = "listener"
    const val ACTION_ACCEPT = "ac.mvr.phone.inbox.ACCEPT"
    const val EXTRA_EVENT = "event"
    const val EXTRA_ITEM = "item"

    fun channels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannels(
            listOf(
                NotificationChannel(CHANNEL_ALERT, "alerts", NotificationManager.IMPORTANCE_HIGH).apply { description = "desktop alerts that need you" },
                NotificationChannel(CHANNEL_INFO, "messages", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "messages from the desktop" },
                NotificationChannel(CHANNEL_LISTENER, "listening", NotificationManager.IMPORTANCE_MIN).apply {
                    description = "keeps the alert listener alive"
                    setShowBadge(false)
                },
            ),
        )
    }

    private fun screen(context: Context, screen: String, request: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            request,
            Intent(context, MainActivity::class.java).putExtra("screen", screen).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    fun watchEvent(item: InboxItem): Long? =
        if (item.source == "watch") item.ref?.get("event")?.jsonPrimitive?.longOrNull else null

    fun post(context: Context, item: InboxItem) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val request = item.id.toInt()
        val builder = NotificationCompat.Builder(context, if (item.alert) CHANNEL_ALERT else CHANNEL_INFO)
            .setSmallIcon(R.drawable.ic_launcher_mono)
            .setContentTitle(item.title)
            .setContentText(item.text.lineSequence().firstOrNull() ?: item.text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(item.text))
            .setWhen((item.ts * 1000).toLong())
            .setShowWhen(true)
            .setAutoCancel(true)
            .setCategory(if (item.alert) NotificationCompat.CATEGORY_ERROR else NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(if (item.alert) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(screen(context, item.open ?: "inbox", request))
        watchEvent(item)?.let { event ->
            val accept = PendingIntent.getBroadcast(
                context,
                request,
                Intent(context, InboxActionReceiver::class.java).setAction(ACTION_ACCEPT).putExtra(EXTRA_EVENT, event).putExtra(EXTRA_ITEM, item.id),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            builder.addAction(0, "accept", accept)
        }
        item.link?.let { link ->
            val view = PendingIntent.getActivity(
                context,
                request,
                Intent(Intent.ACTION_VIEW, Uri.parse(link)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            builder.addAction(0, "open link", view)
        }
        runCatching { NotificationManagerCompat.from(context).notify(TAG, request, builder.build()) }
    }

    fun cancel(context: Context, id: Long) {
        NotificationManagerCompat.from(context).cancel(TAG, id.toInt())
    }

    fun clear(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        runCatching { manager.activeNotifications.filter { it.tag == TAG }.forEach { manager.cancel(TAG, it.id) } }
    }

    fun listener(context: Context): Notification =
        NotificationCompat.Builder(context, CHANNEL_LISTENER)
            .setSmallIcon(R.drawable.ic_launcher_mono)
            .setContentTitle("listening for desktop alerts")
            .setContentText("tap for the inbox")
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(screen(context, "inbox", LISTENER_ID))
            .build()
}
