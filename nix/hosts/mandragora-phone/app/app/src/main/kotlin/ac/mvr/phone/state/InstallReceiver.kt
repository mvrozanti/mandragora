package ac.mvr.phone.state

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import ac.mvr.phone.store
import androidx.core.content.IntentCompat

class InstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != UpdateStore.ACTION_STATUS) return
        context.store.update.settle(
            intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE),
            IntentCompat.getParcelableExtra(intent, Intent.EXTRA_INTENT, Intent::class.java),
            intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE),
        )
    }
}
