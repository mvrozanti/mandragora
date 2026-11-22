package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.logic.uptimeLabel
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
private fun PowerButton(label: String, armed: Boolean, enabled: Boolean, modifier: Modifier, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(if (armed) scheme.error else scheme.surfaceContainerHigh)
            .clickable(enabled = enabled, onClick = onTap)
            .padding(vertical = 14.dp, horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (armed) "tap again to $label" else label,
            style = MaterialTheme.typography.titleSmall,
            color = when {
                armed -> scheme.onError
                enabled -> scheme.onSurface
                else -> scheme.outline
            },
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
fun PowerCard(store: Store) {
    val state by store.power.state.collectAsStateWithLifecycle()
    val armed by store.power.armed.collectAsStateWithLifecycle()
    val sent by store.power.sent.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val current = state
    val subtitle = when {
        sent == "reboot" -> "rebooting"
        sent == "poweroff" -> "powering off"
        current == null -> if (reachable) null else "desktop unreachable"
        current.switching -> "a switch is running"
        else -> current.uptime?.let(::uptimeLabel)
    }
    val enabled = reachable && current != null && !current.switching && sent == null
    HomeCard {
        CardHeader("power", subtitle)
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PowerButton("reboot", armed == "reboot", enabled, Modifier.weight(1f)) { store.power.tap("reboot") }
            PowerButton("power off", armed == "poweroff", enabled, Modifier.weight(1f)) { store.power.tap("poweroff") }
        }
    }
}
