package ac.mvr.phone.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun Label(text: String, modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.outline) {
    Text(text.uppercase(), style = MaterialTheme.typography.labelSmall, color = color, modifier = modifier, maxLines = 1, overflow = TextOverflow.Ellipsis)
}

@Composable
fun StatusDot(ok: Boolean, modifier: Modifier = Modifier) {
    Box(modifier = modifier.size(8.dp).clip(CircleShape).background(if (ok) Color(0xFF4EC17D) else MaterialTheme.colorScheme.error))
}

@Composable
fun Notice(store: Store, modifier: Modifier = Modifier) {
    val text by store.notice.collectAsStateWithLifecycle()
    var shown by remember { mutableStateOf("") }
    if (text != null) shown = text!!
    val alpha by animateFloatAsState(if (text != null) 1f else 0f, tween(600), label = "notice")
    Text(
        shown,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.error,
        textAlign = TextAlign.Center,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier.fillMaxWidth().heightIn(min = 18.dp).alpha(alpha),
    )
}

val LocalChecking = compositionLocalOf { false }
val LocalVpnOff = compositionLocalOf { false }
val LocalOpenTailscale = compositionLocalOf<() -> Unit> { {} }

@Composable
fun Banner(reachable: Boolean) {
    if (reachable || LocalChecking.current) return
    val scheme = MaterialTheme.colorScheme
    val vpnOff = LocalVpnOff.current
    val open = LocalOpenTailscale.current
    Text(
        if (vpnOff) "Tailscale is off on this phone · tap to turn it on" else "desktop unreachable · the phone keeps playing",
        style = MaterialTheme.typography.bodyMedium,
        color = scheme.onSurface,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp)
            .padding(bottom = 8.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(scheme.error.copy(alpha = 0.15f))
            .border(1.dp, scheme.error, RoundedCornerShape(12.dp))
            .clickable(enabled = vpnOff, onClick = open)
            .padding(horizontal = 12.dp, vertical = 10.dp),
    )
}

@Composable
fun Reachability(reachable: Boolean) {
    val checking = !reachable && LocalChecking.current
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        if (checking) Box(modifier = Modifier.size(8.dp).clip(CircleShape).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape)) else StatusDot(reachable)
        Label(if (reachable) "desktop reachable" else if (checking) "reaching the desktop" else if (LocalVpnOff.current) "tailscale off" else "desktop unreachable")
    }
}

@Composable
fun ScreenHeader(title: String, reachable: Boolean, onCollapse: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier.clip(RoundedCornerShape(12.dp)).clickable(onClick = onCollapse).padding(horizontal = 6.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.ExpandMore, "home", modifier = Modifier.size(24.dp))
            Text(title, style = MaterialTheme.typography.titleLarge)
        }
        Reachability(reachable)
    }
}

@Composable
fun CardHeader(name: String, subtitle: String?, onOpen: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable(onClick = onOpen).padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(name, style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.width(12.dp))
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            if (subtitle != null) Label(subtitle)
        }
        Icon(Icons.Filled.ChevronRight, null, tint = scheme.outline, modifier = Modifier.size(20.dp))
    }
}

@Composable
fun HomeCard(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerLow)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

@Composable
fun UpdateCard(store: Store) {
    val build by store.update.available.collectAsStateWithLifecycle()
    val progress by store.update.progress.collectAsStateWithLifecycle()
    val downloaded by store.update.ready.collectAsStateWithLifecycle()
    val ready = build ?: return
    val scheme = MaterialTheme.colorScheme
    val tint = scheme.onTertiaryContainer
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(scheme.tertiaryContainer)
            .clickable(enabled = progress == null) { store.update.install() }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Download, null, tint = tint, modifier = Modifier.size(22.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                when {
                    progress != null -> "downloading"
                    downloaded -> "install update"
                    else -> "update ready"
                },
                style = MaterialTheme.typography.titleSmall,
                color = tint,
            )
            Text(if (downloaded) "${ready.versionName} · downloaded" else "${ready.versionName} · ${(ready.size + 524_288) / 1_048_576} MB", style = MaterialTheme.typography.labelSmall, color = tint.copy(alpha = 0.7f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        val value = progress
        if (value == null) Icon(Icons.Filled.ChevronRight, null, tint = tint, modifier = Modifier.size(20.dp))
        else CircularProgressIndicator(progress = { value }, color = tint, trackColor = tint.copy(alpha = 0.2f), strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
    }
}
