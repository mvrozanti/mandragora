package ac.mvr.phone.ui

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import ac.mvr.phone.net.Palette

fun hex(value: String): Color {
    val clean = value.removePrefix("#")
    val argb = when (clean.length) {
        6 -> 0xFF000000L or clean.toLong(16)
        8 -> clean.toLong(16)
        else -> 0xFF000000L
    }
    return Color(argb)
}

fun Palette.scheme(): ColorScheme = darkColorScheme(
    primary = hex(primary),
    onPrimary = hex(onPrimary),
    primaryContainer = hex(primaryContainer),
    onPrimaryContainer = hex(onSurface),
    secondary = hex(secondary),
    onSecondary = hex(onPrimary),
    tertiary = hex(tertiary),
    onTertiary = hex(onPrimary),
    background = hex(surface),
    onBackground = hex(onSurface),
    surface = hex(surface),
    onSurface = hex(onSurface),
    surfaceVariant = hex(surfaceContainer),
    onSurfaceVariant = hex(onSurfaceVariant),
    surfaceContainerLowest = hex(surface),
    surfaceContainerLow = hex(surfaceContainerLow),
    surfaceContainer = hex(surfaceContainer),
    surfaceContainerHigh = hex(surfaceContainerHigh),
    surfaceContainerHighest = hex(surfaceContainerHigh),
    outline = hex(outline),
    outlineVariant = hex(outlineVariant),
    error = Color(0xFFE06C6C),
    onError = Color(0xFF2A0000),
)

val Mono = FontFamily.Monospace

val MandragoraTypography = Typography(
    headlineMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 26.sp, letterSpacing = (-0.5).sp, lineHeight = 30.sp),
    titleLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 20.sp, letterSpacing = (-0.3).sp),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 16.sp),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
    labelLarge = TextStyle(fontFamily = Mono, fontSize = 13.sp, letterSpacing = 0.sp),
    labelMedium = TextStyle(fontFamily = Mono, fontSize = 12.sp, letterSpacing = 0.3.sp),
    labelSmall = TextStyle(fontFamily = Mono, fontSize = 11.sp, letterSpacing = 1.2.sp),
)

@Composable
fun MandragoraTheme(palette: Palette, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = palette.scheme(), typography = MandragoraTypography, content = content)
}
