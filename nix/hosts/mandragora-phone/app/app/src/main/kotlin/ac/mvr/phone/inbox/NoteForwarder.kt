package ac.mvr.phone.inbox

import android.app.Notification
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import ac.mvr.phone.logic.NoteFacts
import ac.mvr.phone.logic.NoteSeen
import ac.mvr.phone.logic.PhoneNote
import ac.mvr.phone.logic.forwardable
import ac.mvr.phone.store
import kotlinx.coroutines.launch

class NoteForwarder : NotificationListenerService() {
    private val seen = NoteSeen()

    override fun onNotificationPosted(sbn: StatusBarNotification, rankingMap: RankingMap?) {
        val note = note(sbn, rankingMap) ?: return
        if (seen.fresh(note, alertsOnce = sbn.notification.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0)) {
            val store = applicationContext.store
            store.scope.launch { runCatching { store.bridge.phoneNote(note.pkg, note.app, note.title, note.text) } }
        }
    }

    private fun note(sbn: StatusBarNotification, rankingMap: RankingMap?): PhoneNote? {
        val flags = sbn.notification.flags
        val facts = NoteFacts(
            pkg = sbn.packageName,
            self = packageName,
            ongoing = sbn.isOngoing || flags and Notification.FLAG_FOREGROUND_SERVICE != 0,
            summary = flags and Notification.FLAG_GROUP_SUMMARY != 0,
            alerting = alerting(sbn, rankingMap),
        )
        if (!forwardable(facts)) return null
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val body = extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT)
        return PhoneNote(sbn.key, sbn.packageName, label(sbn.packageName), title, body?.toString()?.trim().orEmpty())
    }

    private fun alerting(sbn: StatusBarNotification, rankingMap: RankingMap?): Boolean {
        val ranking = Ranking()
        if (rankingMap?.getRanking(sbn.key, ranking) != true) return true
        return ranking.importance >= NotificationManager.IMPORTANCE_DEFAULT
    }

    private fun label(pkg: String): String = runCatching {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION") packageManager.getApplicationInfo(pkg, 0)
        }
        packageManager.getApplicationLabel(info).toString()
    }.getOrDefault(pkg.substringAfterLast('.'))
}
