package ac.mvr.phone.media

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import ac.mvr.phone.store
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

private const val JOB_ID = 4102
private const val PERIOD_MS = 60 * 60 * 1000L
private const val FLEX_MS = 15 * 60 * 1000L
const val MIRROR_BUDGET_MS = 8 * 60 * 1000L

class MusicMirrorJob : JobService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var running: Job? = null

    override fun onStartJob(params: JobParameters): Boolean {
        running = scope.launch {
            runCatching { applicationContext.store.music.sync(System.currentTimeMillis() + MIRROR_BUDGET_MS) }
            jobFinished(params, false)
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        running?.cancel()
        return true
    }

    companion object {
        fun schedule(context: Context) {
            val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
            if (scheduler.getPendingJob(JOB_ID) != null) return
            val info = JobInfo.Builder(JOB_ID, ComponentName(context, MusicMirrorJob::class.java))
                .setPeriodic(PERIOD_MS, FLEX_MS)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_UNMETERED)
                .setRequiresStorageNotLow(true)
                .setPersisted(true)
                .build()
            runCatching { scheduler.schedule(info) }
        }
    }
}
