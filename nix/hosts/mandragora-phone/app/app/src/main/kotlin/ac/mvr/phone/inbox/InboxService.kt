package ac.mvr.phone.inbox

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import ac.mvr.phone.store
import kotlinx.coroutines.launch

class InboxService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Alerts.channels(this)
        val type = if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        ServiceCompat.startForeground(this, Alerts.LISTENER_ID, Alerts.listener(this), type)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    companion object {
        fun sync(context: Context) {
            val intent = Intent(context, InboxService::class.java)
            if (context.store.prefs.inboxListen.value) runCatching { ContextCompat.startForegroundService(context, intent) }
            else context.stopService(intent)
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> InboxService.sync(context)
        }
    }
}

class InboxActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Alerts.ACTION_ACCEPT) return
        val event = intent.getLongExtra(Alerts.EXTRA_EVENT, -1L)
        val item = intent.getLongExtra(Alerts.EXTRA_ITEM, -1L)
        if (event < 0) return
        Alerts.cancel(context, item)
        val pending = goAsync()
        val store = context.store
        store.scope.launch {
            try {
                store.watch.ack(event)
            } finally {
                pending.finish()
            }
        }
    }
}
