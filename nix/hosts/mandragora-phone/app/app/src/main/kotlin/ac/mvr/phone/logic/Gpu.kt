package ac.mvr.phone.logic

import ac.mvr.phone.net.GpuInfo
import ac.mvr.phone.net.GpuLock
import ac.mvr.phone.net.GpuResident
import java.util.Locale

private const val GIB = 1073741824.0

fun gib(bytes: Long): String = "%.1f G".format(Locale.ROOT, bytes / GIB)

fun vramLabel(info: GpuInfo): String = "%.1f of %s".format(Locale.ROOT, info.memUsed / GIB, gib(info.memTotal))

fun vramShare(info: GpuInfo): Float = if (info.memTotal <= 0) 0f else (info.memUsed.toDouble() / info.memTotal).toFloat().coerceIn(0f, 1f)

fun gpuSubtitle(info: GpuInfo?): String? = info?.let { "${it.util.toInt()}% busy · ${it.temp.toInt()}°C" }

private fun span(seconds: Double): String = if (seconds < 120) "${seconds.toInt()} s" else "${(seconds / 60).toInt()} min"

fun lockLabel(lock: GpuLock, now: Double): String {
    val holder = lock.holder
    val outside = lock.unmanaged
    return when {
        holder != null -> {
            val held = (now - holder.since).coerceAtLeast(0.0)
            val left = holder.expected?.let { (it - held).takeIf { rest -> rest > 0 } }
            "held by ${holder.name} for ${span(held)}" + (left?.let { " · about ${span(it)} left" } ?: "")
        }
        outside != null -> "${outside.name} uses it outside the lock"
        lock.error != null -> "gpu-lock did not answer"
        else -> "the lock is free"
    }
}

fun residentName(resident: GpuResident): String = if (resident.kind == "stt") "whisper" else resident.name

fun freeLabel(residents: List<GpuResident>): String? =
    if (residents.isEmpty()) null else "free ${residents.joinToString(" + ") { residentName(it) }} · ${gib(residents.sumOf { it.mem })}"
