package ac.mvr.phone.state

import ac.mvr.phone.net.HubDesk
import ac.mvr.phone.net.HubDisk
import ac.mvr.phone.net.HubEntry
import ac.mvr.phone.net.HubFeed
import ac.mvr.phone.net.HubMachine
import ac.mvr.phone.net.HubVps
import ac.mvr.phone.net.parseHubFeed
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.math.roundToInt

class HubStore(private val store: Store) {
    private val rawFlow = MutableStateFlow(store.prefs.lastHub)
    val raw: StateFlow<String?> = rawFlow

    private val feedFlow = MutableStateFlow<HubFeed?>(null)
    val feed: StateFlow<HubFeed?> = feedFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    init {
        val seed = rawFlow.value
        if (seed != null) store.scope.launch {
            val parsed = withContext(Dispatchers.Default) { runCatching { parseHubFeed(seed) }.getOrNull() }
            if (parsed != null) feedFlow.compareAndSet(null, parsed)
        }
    }

    suspend fun refresh() {
        val text = try {
            store.bridge.hub()
        } catch (err: Exception) {
            freshFlow.value = false
            throw err
        }
        val parsed = withContext(Dispatchers.Default) { runCatching { parseHubFeed(text) } }
        val next = parsed.getOrElse {
            freshFlow.value = false
            throw it
        }
        feedFlow.value = next
        rawFlow.value = text
        store.prefs.lastHub = text
        freshFlow.value = true
    }
}

enum class HubLevel { Ok, Warn, Down, Unknown }

data class HubLine(val level: HubLevel, val name: String, val text: String)

data class HubMeter(val label: String, val value: String, val percent: Float, val level: HubLevel)

data class HubAlert(val level: HubLevel, val title: String, val detail: String)

data class HubNote(val strong: String?, val rest: String)

data class HubMachineView(
    val name: String,
    val pill: String,
    val pillLevel: HubLevel,
    val meta: String,
    val meters: List<HubMeter>,
    val note: HubNote,
)

data class HubRow(val entry: HubEntry, val level: HubLevel, val link: String, val description: String)

data class HubView(
    val count: Int,
    val live: Boolean,
    val glance: List<HubLine>,
    val desk: HubMachineView,
    val vps: HubMachineView,
    val alerts: List<HubAlert>,
    val rows: List<HubRow>,
) {
    fun sortedRows(clicks: Map<String, Int>): List<HubRow> =
        rows.withIndex()
            .sortedWith(compareByDescending<IndexedValue<HubRow>> { clicks[it.value.entry.host] ?: 0 }.thenBy { it.index })
            .map { it.value }
}

private val stateWord = mapOf(HubLevel.Ok to "up", HubLevel.Warn to "degraded", HubLevel.Down to "down", HubLevel.Unknown to "not probed yet")

private fun hubNum(value: Double, decimals: Int): String = String.format(Locale.US, "%.${decimals}f", value)

private fun hubSecs(seconds: Double?): String = when {
    seconds == null -> ""
    seconds < 60 -> hubNum(seconds, 0) + "s"
    seconds < 3600 -> hubNum(seconds / 60, 1) + "m"
    else -> hubNum(seconds / 3600, 1) + "h"
}

private fun hubGb(gb: Double?): String = when {
    gb == null -> "–"
    gb < 1000 -> hubNum(gb, if (gb < 10) 1 else 0) + "G"
    else -> hubNum(gb / 1000, 1) + "T"
}

private fun hubPct(value: Double?): String = if (value == null) "–" else hubNum(value, 0) + "%"

private fun hubBand(percent: Double?, warnAt: Double, criticalAt: Double): Pair<Float, HubLevel> {
    val p = (percent ?: 0.0).takeIf { !it.isNaN() }?.coerceIn(0.0, 100.0) ?: 0.0
    val level = when {
        p >= criticalAt -> HubLevel.Down
        p >= warnAt -> HubLevel.Warn
        else -> HubLevel.Ok
    }
    return p.toFloat() to level
}

private const val VPS_DISK_WARN = 95.0
private const val VPS_DISK_CRITICAL = 98.0

private fun hubMeter(label: String, value: String, percent: Double?, warnAt: Double, criticalAt: Double): HubMeter {
    val (p, level) = hubBand(percent, warnAt, criticalAt)
    return HubMeter(label, value, p, level)
}

private fun hubDiskValue(disk: HubDisk?): String = if (disk == null) "–" else hubGb(disk.usedGb) + "/" + hubGb(disk.totalGb)

private fun hubLevelOf(state: String?): HubLevel = when (state) {
    "ok" -> HubLevel.Ok
    "warn" -> HubLevel.Warn
    "down" -> HubLevel.Down
    else -> HubLevel.Unknown
}

private val gpuVendor = Regex("^NVIDIA\\s+(GeForce\\s+)?", RegexOption.IGNORE_CASE)

fun hubView(feed: HubFeed, reachable: Boolean, fresh: Boolean): HubView {
    val live = reachable && fresh
    val healthLive = live && feed.probed
    fun machine(id: String): HubMachine = feed.machines.firstOrNull { it.id == id } ?: HubMachine(id, id, "")
    val deskMachine = machine("desk")
    val vpsMachine = machine("vps")
    val desk: HubDesk? = if (reachable) feed.gpu else null
    val vps: HubVps? = feed.vps

    fun levelOf(entry: HubEntry): HubLevel = if (healthLive) hubLevelOf(feed.health[entry.host]?.state) else HubLevel.Unknown

    val alerts = mutableListOf<HubAlert>()

    val deskView = if (desk == null) {
        alerts += HubAlert(HubLevel.Down, "${deskMachine.label} unreachable", "gpu-status is not answering — desktop asleep?")
        HubMachineView(deskMachine.label, "offline", HubLevel.Down, deskMachine.meta, emptyList(), HubNote(null, "gpu-status unreachable"))
    } else {
        val gpu = desk.gpu
        val holder = desk.holder
        val held = desk.locked
        val note = if (held) {
            val rest = listOfNotNull(
                hubSecs(holder?.heldFor).takeIf { it.isNotEmpty() }?.let { "$it held" },
                holder?.expectedRemaining?.let { "~${hubSecs(it)} left" },
            )
            HubNote(holder?.name ?: "?", rest.joinToString("") { " · $it" })
        } else {
            HubNote(null, "no holder")
        }
        if (held) alerts += HubAlert(HubLevel.Warn, "gpu-lock held", listOf(holder?.name ?: "?", hubSecs(holder?.heldFor)).filter { it.isNotEmpty() }.joinToString(" · "))
        val deskDisk = desk.disk
        val deskUsed = deskDisk?.usedPct
        if (deskDisk != null && deskUsed != null && deskUsed >= 85) {
            alerts += HubAlert(HubLevel.Warn, "desktop disk at ${hubPct(deskUsed)}", "${hubGb(deskDisk.usedGb)} of ${hubGb(deskDisk.totalGb)}")
        }
        val vramUsed = gpu?.memUsedMb
        val vramTotal = gpu?.memTotalMb
        val vram = if (vramUsed == null) "–" else hubNum(vramUsed / 1024, 1) + "/" + (if (vramTotal == null) "–" else hubNum(vramTotal / 1024, 0)) + "G"
        val temp = gpu?.tempC
        HubMachineView(
            name = deskMachine.label,
            pill = if (held) "lock held" else "lock free",
            pillLevel = if (held) HubLevel.Warn else HubLevel.Ok,
            meta = gpu?.name?.replace(gpuVendor, "") ?: "gpu",
            meters = listOf(
                hubMeter("gpu", hubPct(gpu?.utilPct), gpu?.utilPct, 50.0, 85.0),
                hubMeter("vram", vram, gpu?.memPct, 60.0, 90.0),
                hubMeter("temp", temp?.let { hubNum(it, 0) + "°C" } ?: "–", temp?.let { (it - 30) * 100 / 60 }, 50.0, 80.0),
                hubMeter("cpu", hubPct(desk.cpu?.utilPct), desk.cpu?.utilPct, 50.0, 85.0),
                hubMeter("disk", hubDiskValue(desk.disk), desk.disk?.usedPct, 70.0, 90.0),
            ),
            note = note,
        )
    }

    val vpsView = if (vps == null) {
        alerts += HubAlert(HubLevel.Down, "${vpsMachine.label} unreachable", "host-stats is not answering")
        HubMachineView(vpsMachine.label, "offline", HubLevel.Down, vpsMachine.meta, emptyList(), HubNote(null, "host-stats unreachable"))
    } else {
        val vpsDisk = vps.disk
        val vpsUsed = vpsDisk?.usedPct
        if (vpsDisk != null && vpsUsed != null && vpsUsed >= VPS_DISK_WARN) {
            alerts += HubAlert(HubLevel.Warn, "vps disk at ${hubPct(vpsUsed)}", "${hubGb(vpsDisk.usedGb)} of ${hubGb(vpsDisk.totalGb)} — seafile is the driver")
        }
        HubMachineView(
            name = vpsMachine.label,
            pill = if (live) "online" else "last known",
            pillLevel = if (live) HubLevel.Ok else HubLevel.Unknown,
            meta = vpsMachine.meta,
            meters = listOf(
                hubMeter("cpu", hubPct(vps.cpu?.utilPct), vps.cpu?.utilPct, 50.0, 85.0),
                hubMeter("disk", hubDiskValue(vps.disk), vps.disk?.usedPct, VPS_DISK_WARN, VPS_DISK_CRITICAL),
            ),
            note = HubNote(null, "${feed.services.count { it.where == "vps" }} services here"),
        )
    }

    val bad = if (healthLive) {
        feed.services.filter { levelOf(it) == HubLevel.Down || levelOf(it) == HubLevel.Warn }.sortedBy { if (levelOf(it) == HubLevel.Down) 0 else 1 }
    } else {
        emptyList()
    }
    if (healthLive) {
        bad.take(6).forEach { entry ->
            val health = feed.health[entry.host]
            val code = health?.code?.takeIf { it != 0 }?.toString() ?: "no answer"
            val ms = health?.ms?.let { " · ${it.roundToInt()}ms" } ?: ""
            alerts += HubAlert(levelOf(entry), entry.host, code + ms)
        }
        if (bad.size > 6) alerts += HubAlert(HubLevel.Warn, "${bad.size - 6} more not healthy", "see the list below")
    } else {
        alerts += HubAlert(HubLevel.Unknown, "service health unknown", "the list shows the last known services")
    }

    val deskLine = when {
        desk == null -> HubLine(HubLevel.Down, deskMachine.label, "offline")
        else -> {
            val parts = listOfNotNull(
                desk.gpu?.let { "gpu ${hubPct(it.utilPct)}" },
                desk.gpu?.memUsedMb?.let { "vram ${hubNum(it / 1024, 1)}G" },
                desk.disk?.let { "disk ${hubPct(it.usedPct)}" },
            )
            val level = when {
                !fresh -> HubLevel.Unknown
                desk.locked -> HubLevel.Warn
                else -> HubLevel.Ok
            }
            HubLine(level, deskMachine.label, parts.joinToString(" · ").ifEmpty { "up" })
        }
    }
    val vpsLine = when {
        vps == null -> HubLine(HubLevel.Down, "vps", "offline")
        else -> {
            val level = when {
                !live -> HubLevel.Unknown
                (vps.disk?.usedPct ?: 0.0) >= VPS_DISK_WARN -> HubLevel.Warn
                else -> HubLevel.Ok
            }
            HubLine(level, "vps", "cpu ${hubPct(vps.cpu?.utilPct)} · disk ${hubPct(vps.disk?.usedPct)}")
        }
    }
    val serviceLine = when {
        !healthLive -> HubLine(HubLevel.Unknown, "", "service health unknown")
        bad.size == 1 -> HubLine(HubLevel.Warn, "", "1 service needs attention")
        bad.isNotEmpty() -> HubLine(HubLevel.Warn, "", "${bad.size} services need attention")
        else -> HubLine(HubLevel.Ok, "", "all services up")
    }

    val rows = feed.services.map { entry ->
        val level = levelOf(entry)
        val open = entry.access == "open"
        val word = if (level == HubLevel.Unknown && !healthLive) "health unknown" else stateWord.getValue(level)
        val description = listOfNotNull(
            entry.host,
            entry.desc.ifEmpty { null },
            "on ${machine(entry.where).label}",
            if (open) "reachable without signing in" else "behind authelia",
            if (entry.untiled) "served by caddy, no tile" else null,
            word,
        ).distinct().joinToString(" — ")
        HubRow(entry, level, entry.url ?: "https://${entry.host}", description)
    }

    return HubView(
        count = feed.services.size,
        live = live,
        glance = listOf(deskLine, vpsLine, serviceLine),
        desk = deskView,
        vps = vpsView,
        alerts = alerts,
        rows = rows,
    )
}
