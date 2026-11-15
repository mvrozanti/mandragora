package ac.mvr.phone.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

@Serializable
data class MoneyFx(
    @SerialName("btc_usd") val btcUsd: Double? = null,
    @SerialName("usd_brl") val usdBrl: Double? = null,
)

@Serializable
data class MoneyBasis(
    val btc: Double = 0.0,
    val usd: Double = 0.0,
    val brl: Double = 0.0,
    @SerialName("avg_usd") val avgUsd: Double = 0.0,
    @SerialName("avg_brl") val avgBrl: Double = 0.0,
    val buys: Int = 0,
    val first: Double = 0.0,
    val last: Double = 0.0,
)

@Serializable
data class MoneyHolding(
    val label: String = "",
    val asset: String = "",
    val amount: Double? = null,
    val usd: Double? = null,
    val note: String? = null,
) {
    val isDust: Boolean get() = asset == "dust" && amount == null
}

@Serializable
data class MoneyVenue(
    val id: String = "",
    val label: String = "",
    val usd: Double? = null,
    val holdings: List<MoneyHolding> = emptyList(),
    val error: String? = null,
    val note: String? = null,
    @SerialName("stale_since") val staleSince: Double? = null,
    val missing: Boolean = false,
) {
    val noteOnly: Boolean get() = note != null && holdings.isEmpty()
}

@Serializable
data class MoneyCache(
    val version: Int = 0,
    val fx: MoneyFx = MoneyFx(),
    val prices: Map<String, Double?> = emptyMap(),
    val basis: MoneyBasis? = null,
    val venues: List<MoneyVenue> = emptyList(),
    @SerialName("total_usd") val totalUsd: Double? = null,
    val error: String? = null,
    @SerialName("fetched_at") val fetchedAt: Double = 0.0,
    val stale: Boolean = false,
    val refreshing: Boolean = false,
) {
    val hasCache: Boolean get() = fetchedAt > 0.0
}

private val moneyJson = Json(from = json) { coerceInputValues = true }

fun parseMoney(text: String): MoneyCache = moneyJson.decodeFromString(text)

object MoneyFormat {
    const val ICON = "₿"
    const val STALE_AFTER = 20 * 60
    val units = listOf("btc", "usd", "brl")

    fun unitOf(value: String): String = if (value in units) value else "btc"

    fun nextUnit(value: String): String = units[(units.indexOf(unitOf(value)) + 1) % units.size]

    fun mask(text: String): String = text.replace(Regex("\\d"), "•")

    private fun special(value: Double): String? = when {
        value.isNaN() -> "nan"
        value.isInfinite() -> if (value > 0) "inf" else "-inf"
        else -> null
    }

    private fun fixed(value: Double, decimals: Int): BigDecimal = BigDecimal(value).setScale(decimals, RoundingMode.HALF_EVEN)

    private fun strip(text: String): String = text.trimEnd('0').trimEnd('.')

    fun grouped(value: Double, decimals: Int): String {
        special(value)?.let { return it }
        val pattern = if (decimals > 0) "#,##0." + "0".repeat(decimals) else "#,##0"
        val format = DecimalFormat(pattern, DecimalFormatSymbols(Locale.US))
        format.roundingMode = RoundingMode.HALF_EVEN
        return format.format(fixed(value, decimals))
    }

    fun btc(value: Double): String = special(value) ?: strip(fixed(value, 8).toPlainString())

    fun qty(amount: Double): String = when {
        amount >= 1000 -> grouped(amount, 2)
        amount >= 1 -> strip(grouped(amount, 4))
        else -> general(amount, 4)
    }

    private fun general(value: Double, digits: Int): String {
        special(value)?.let { return it }
        if (value == 0.0) return if (1.0 / value < 0) "-0" else "0"
        val rounded = BigDecimal(value).round(MathContext(digits, RoundingMode.HALF_EVEN))
        val exponent = rounded.precision() - rounded.scale() - 1
        if (exponent < -4 || exponent >= digits) {
            val mantissa = rounded.movePointLeft(exponent).stripTrailingZeros().toPlainString()
            val sign = if (exponent < 0) "-" else "+"
            return "${mantissa}e$sign${abs(exponent).toString().padStart(2, '0')}"
        }
        return rounded.stripTrailingZeros().toPlainString()
    }

    private fun truthy(value: Double?): Double? = value?.takeIf { it != 0.0 && !it.isNaN() }

    fun convert(usd: Double?, unit: String, fx: MoneyFx): Double? {
        if (usd == null) return null
        return when (unit) {
            "usd" -> usd
            "brl" -> truthy(fx.usdBrl)?.let { usd * it }
            else -> truthy(fx.btcUsd)?.let { usd / it }
        }
    }

    fun unit(usd: Double?, unit: String, fx: MoneyFx): String {
        val value = convert(usd, unit, fx) ?: return "--"
        return when (unit) {
            "usd" -> "$ ${grouped(value, 2)}"
            "brl" -> "R$ ${grouped(value, 2)}"
            else -> "$ICON ${btc(value)}"
        }
    }

    fun gainRatio(now: Double?, avg: Double?): Double? {
        val n = truthy(now) ?: return null
        val a = truthy(avg) ?: return null
        return n / a - 1
    }

    fun gain(ratio: Double?): String {
        ratio ?: return "--"
        val percent = ratio * 100
        special(percent)?.let { return it }
        val sign = if (percent < 0 || (percent == 0.0 && 1.0 / percent < 0)) "-" else "+"
        return "$sign${fixed(abs(percent), 1).toPlainString()}%"
    }

    fun share(usd: Double?, total: Double?): String? {
        val t = truthy(total) ?: return null
        val u = usd ?: return null
        val percent = u / t * 100
        special(percent)?.let { return "$it%" }
        return "${fixed(percent, 0).toPlainString()}%"
    }

    fun nowBrl(fx: MoneyFx): Double? {
        val usd = truthy(fx.btcUsd) ?: return null
        val rate = truthy(fx.usdBrl) ?: return null
        return usd * rate
    }

    fun since(epoch: Double): String =
        DateTimeFormatter.ofPattern("MMM yyyy", Locale.US).withZone(ZoneId.systemDefault()).format(Instant.ofEpochMilli((epoch * 1000).toLong()))

    fun ago(epoch: Double, nowMs: Long): String {
        val seconds = (nowMs / 1000.0 - epoch).toLong().coerceAtLeast(0)
        return when {
            seconds < 60 -> "just now"
            seconds < 3600 -> "${seconds / 60} min ago"
            seconds < 48 * 3600 -> "${seconds / 3600} h ago"
            else -> "${seconds / 86400} d ago"
        }
    }

    fun isStale(cache: MoneyCache, nowMs: Long): Boolean =
        cache.stale || nowMs / 1000.0 - cache.fetchedAt > STALE_AFTER
}
