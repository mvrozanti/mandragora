package ac.mvr.phone.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle

private const val UNNAMED = "plugin"

@Composable
fun PluginCard(store: Store, onOpen: (String) -> Unit) {
    val manifest by store.plugin.manifest.collectAsStateWithLifecycle()
    val sessions by store.code.sessions.collectAsStateWithLifecycle()
    val folder = manifest?.chat?.directory
    val latest = sessions.filter { it.directory == folder && it.parentID == null }.maxByOrNull { it.time.updated }
    val said = latest?.snippet?.ifBlank { null } ?: latest?.title?.ifBlank { null }
    val subtitle = manifest?.subtitle?.ifBlank { null } ?: if (manifest == null) "waiting for the desktop" else "idle"
    HomeCard {
        CardHeader(manifest?.title ?: UNNAMED, subtitle) { onOpen("plugin") }
        Text(
            said ?: "open the conversation",
            style = MaterialTheme.typography.bodyMedium,
            color = if (said == null) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
fun PluginScreen(store: Store, onReady: () -> Unit, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val manifest by store.plugin.manifest.collectAsStateWithLifecycle()
    var failure by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(attempt) {
        failure = null
        runCatching { store.plugin.enter() }
            .onSuccess { opened -> if (opened) onReady() else failure = "this plugin has no conversation" }
            .onFailure { failure = it.message ?: "the desktop did not answer" }
    }
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(manifest?.title ?: UNNAMED, reachable, onCollapse)
        Banner(reachable)
        Column(modifier = Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Label(failure ?: "opening the conversation…")
            if (failure != null) ChatChip("try again", scheme.surfaceContainerHigh, scheme.onSurface) { attempt++ }
        }
    }
}
