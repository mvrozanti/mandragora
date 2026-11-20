package ac.mvr.phone.state

import android.os.SystemClock
import ac.mvr.phone.net.LoadState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.IOException

data class Kill(val name: String, val atMs: Long)

class LoadStore(private val store: Store) {
    private val stateFlow = MutableStateFlow<LoadState?>(null)
    val state: StateFlow<LoadState?> = stateFlow

    private val armedFlow = MutableStateFlow<String?>(null)
    val armed: StateFlow<String?> = armedFlow

    private val lastKillFlow = MutableStateFlow<Kill?>(null)
    val lastKill: StateFlow<Kill?> = lastKillFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    private var armJob: Job? = null

    suspend fun refresh() {
        try {
            stateFlow.value = store.bridge.load()
            freshFlow.value = true
        } catch (err: CancellationException) {
            throw err
        } catch (err: Exception) {
            freshFlow.value = false
            throw err
        }
    }

    fun tap(id: String) {
        if (armedFlow.value == id) {
            armJob?.cancel()
            armedFlow.value = null
            kill(id)
            return
        }
        armedFlow.value = id
        armJob?.cancel()
        armJob = store.scope.launch {
            delay(4_000)
            if (armedFlow.value == id) armedFlow.value = null
        }
    }

    fun disarm() {
        armJob?.cancel()
        armedFlow.value = null
    }

    private fun kill(id: String) = store.act {
        val result = try {
            store.bridge.kill(id)
        } catch (err: IOException) {
            throw IllegalStateException(Regex("\"error\":\\s*\"([^\"]+)\"").find(err.message ?: "")?.groupValues?.get(1) ?: err.message, err)
        }
        val error = result.error
        if (error != null) throw IllegalStateException(error)
        lastKillFlow.value = Kill(result.name ?: id, SystemClock.elapsedRealtime())
        delay(600)
        refresh()
    }
}
