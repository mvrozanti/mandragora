package ac.mvr.phone.net

import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull

data class Palette(
    val surface: String = "#13140d",
    val surfaceContainerLow: String = "#1b1c15",
    val surfaceContainer: String = "#1f2019",
    val surfaceContainerHigh: String = "#292b23",
    val onSurface: String = "#e3e3d7",
    val onSurfaceVariant: String = "#c6c8b8",
    val outline: String = "#909284",
    val outlineVariant: String = "#46483c",
    val primary: String = "#bbcf81",
    val onPrimary: String = "#283500",
    val primaryContainer: String = "#3d4c0d",
    val secondary: String = "#c3caa9",
    val tertiary: String = "#a1d0c6",
    val live: Boolean = false,
)

class ThemeClient(private val baseUrl: () -> String) {
    suspend fun palette(): Palette {
        val obj = Http.obj(Http.get("${baseUrl()}/api/theme?colors=1"))
        fun pick(key: String, fallback: String): String {
            val value = obj[key]?.jsonPrimitive?.contentOrNull ?: return fallback
            return if (Regex("^#[0-9a-fA-F]{6,8}$").matches(value)) value else fallback
        }
        val base = Palette()
        return Palette(
            surface = pick("surface", base.surface),
            surfaceContainerLow = pick("surface_container_low", base.surfaceContainerLow),
            surfaceContainer = pick("surface_container", base.surfaceContainer),
            surfaceContainerHigh = pick("surface_container_high", base.surfaceContainerHigh),
            onSurface = pick("on_surface", base.onSurface),
            onSurfaceVariant = pick("on_surface_variant", base.onSurfaceVariant),
            outline = pick("outline", base.outline),
            outlineVariant = pick("outline_variant", base.outlineVariant),
            primary = pick("primary", base.primary),
            onPrimary = pick("on_primary", base.onPrimary),
            primaryContainer = pick("primary_container", base.primaryContainer),
            secondary = pick("secondary", base.secondary),
            tertiary = pick("tertiary", base.tertiary),
            live = true,
        )
    }
}
