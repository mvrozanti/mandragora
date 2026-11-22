package ac.mvr.phone.state

import ac.mvr.phone.net.PowerState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.IOException

class PowerStore(private val store: Store) {
    private val stateFlow = MutableStateFlow<PowerState?>(null)
    val state: StateFlow<PowerState?> = stateFlow

    private val armedFlow = MutableStateFlow<String?>(null)
    val armed: StateFlow<String?> = armedFlow

    private val sentFlow = MutableStateFlow<String?>(null)
    val sent: StateFlow<String?> = sentFlow

    private var armJob: Job? = null

    suspend fun refresh() {
        try {
            val next = store.bridge.powerState()
            val before = stateFlow.value?.uptime
            val now = next.uptime
            if (before != null && now != null && now < before) sentFlow.value = null
            stateFlow.value = next
        } catch (err: CancellationException) {
            throw err
        } catch (err: IOException) {
            stateFlow.value = null
            throw err
        }
    }

    fun tap(action: String) {
        if (armedFlow.value == action) {
            armJob?.cancel()
            armedFlow.value = null
            send(action)
            return
        }
        armedFlow.value = action
        armJob?.cancel()
        armJob = store.scope.launch {
            delay(4_000)
            if (armedFlow.value == action) armedFlow.value = null
        }
    }

    private fun send(action: String) = store.act {
        val result = try {
            store.bridge.power(action)
        } catch (err: IOException) {
            throw IllegalStateException(Regex("\"error\":\\s*\"([^\"]+)\"").find(err.message ?: "")?.groupValues?.get(1) ?: err.message, err)
        }
        val error = result.error
        if (error != null) throw IllegalStateException(error)
        sentFlow.value = action
    }
}
