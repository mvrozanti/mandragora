package ac.mvr.phone

import android.app.Application
import ac.mvr.phone.inbox.Alerts
import ac.mvr.phone.state.Store

class App : Application() {
    lateinit var store: Store
        private set

    override fun onCreate() {
        super.onCreate()
        Alerts.channels(this)
        store = Store(this)
        store.start()
    }
}

val android.content.Context.store: Store
    get() = (applicationContext as App).store
