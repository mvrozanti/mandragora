package ac.mvr.phone.state

import ac.mvr.phone.logic.residentName
import ac.mvr.phone.net.GpuResident
import ac.mvr.phone.net.GpuState
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.IOException

class GpuStore(private val store: Store) {
    private val stateFlow = MutableStateFlow<GpuState?>(null)
    val state: StateFlow<GpuState?> = stateFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    private val freeingFlow = MutableStateFlow<Set<String>>(emptySet())
    val freeing: StateFlow<Set<String>> = freeingFlow

    private val freedFlow = MutableStateFlow<String?>(null)
    val freed: StateFlow<String?> = freedFlow

    suspend fun refresh() {
        try {
            stateFlow.value = store.bridge.gpu()
            freshFlow.value = true
        } catch (err: IOException) {
            freshFlow.value = false
            throw err
        }
    }

    fun free(residents: List<GpuResident>) {
        if (residents.isEmpty() || freeingFlow.value.isNotEmpty()) return
        store.act {
            freeingFlow.value = residents.map { it.name }.toSet()
            try {
                residents.forEach { resident ->
                    val result = readable { store.bridge.freeGpu(resident) }
                    result.error?.let { throw IllegalStateException(it) }
                }
                freedFlow.value = residents.joinToString(" + ") { residentName(it) }
            } finally {
                freeingFlow.value = emptySet()
            }
            delay(800)
            refresh()
        }
    }
}
