package ac.mvr.phone.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class HubMachine(val id: String = "", val label: String = "", val meta: String = "")

@Serializable
data class HubSection(val id: String = "", val label: String = "")

@Serializable
data class HubEntry(
    val name: String = "",
    val host: String = "",
    val group: String = "",
    val desc: String = "",
    val access: String = "priv",
    val where: String = "",
    val url: String? = null,
    val probe: String? = null,
    val untiled: Boolean = false,
)

@Serializable
data class HubHealth(val code: Int? = null, val ms: Double? = null, val state: String? = null)

@Serializable
data class HubCpu(@SerialName("util_pct") val utilPct: Double? = null)

@Serializable
data class HubDisk(
    @SerialName("used_gb") val usedGb: Double? = null,
    @SerialName("total_gb") val totalGb: Double? = null,
    @SerialName("used_pct") val usedPct: Double? = null,
)

@Serializable
data class HubVps(val cpu: HubCpu? = null, val disk: HubDisk? = null, val ts: Double? = null)

@Serializable
data class HubHolder(
    val name: String? = null,
    @SerialName("held_for") val heldFor: Double? = null,
    @SerialName("expected_remaining") val expectedRemaining: Double? = null,
)

@Serializable
data class HubGpuChip(
    val name: String? = null,
    @SerialName("util_pct") val utilPct: Double? = null,
    @SerialName("mem_used_mb") val memUsedMb: Double? = null,
    @SerialName("mem_total_mb") val memTotalMb: Double? = null,
    @SerialName("mem_pct") val memPct: Double? = null,
    @SerialName("temp_c") val tempC: Double? = null,
    @SerialName("power_w") val powerW: Double? = null,
)

@Serializable
data class HubDesk(
    val locked: Boolean = false,
    val holder: HubHolder? = null,
    val gpu: HubGpuChip? = null,
    val cpu: HubCpu? = null,
    val disk: HubDisk? = null,
    val ts: Double? = null,
)

@Serializable
data class HubFeed(
    val ts: Double = 0.0,
    val machines: List<HubMachine> = emptyList(),
    val groups: List<HubSection> = emptyList(),
    val services: List<HubEntry> = emptyList(),
    val health: Map<String, HubHealth> = emptyMap(),
    val probed: Boolean = false,
    val vps: HubVps? = null,
    val gpu: HubDesk? = null,
)

fun parseHubFeed(text: String): HubFeed = json.decodeFromString(HubFeed.serializer(), text)
