package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.PluginManifest
import ac.mvr.phone.net.PluginPanel
import ac.mvr.phone.net.PluginTurn
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle

private const val UNNAMED = "plugin"

@Composable
fun PluginCard(store: Store, onOpen: (String) -> Unit) {
    val state by store.plugin.state.collectAsStateWithLifecycle()
    val turns by store.plugin.turns.collectAsStateWithLifecycle()
    val manifest by store.plugin.manifest.collectAsStateWithLifecycle()
    val fresh by store.plugin.fresh.collectAsStateWithLifecycle()
    val subtitle = when {
        !fresh -> "waiting for the desktop"
        state.busy -> "writing"
        state.pending > 0 -> "${state.pending} waiting for claude"
        else -> manifest?.subtitle?.ifBlank { null } ?: "idle"
    }
    HomeCard {
        CardHeader(manifest?.title ?: UNNAMED, subtitle) { onOpen("plugin") }
        val said = turns.lastOrNull { it.role == "assistant" }
        Text(
            said?.content?.lineSequence()?.firstOrNull { it.isNotBlank() } ?: (manifest?.empty ?: "nothing here yet"),
            style = MaterialTheme.typography.bodyMedium,
            color = if (said == null) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun PluginPanelView(store: Store, panel: PluginPanel?) {
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(scheme.surfaceContainerLow)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (panel == null) {
            Label("reading…")
            return@Column
        }
        if (panel.markdown.isNotBlank()) MarkdownText(panel.markdown, scheme)
        panel.rows.forEach { row ->
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(row.text, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                if (row.action.isNotBlank()) {
                    ChatChip(row.label.ifBlank { row.action }, scheme.surfaceContainerHigh, scheme.onSurface) { store.plugin.act(row.action, row.arg) }
                }
            }
        }
        panel.toggles.forEach { toggle ->
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(toggle.label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                Switch(checked = toggle.on, onCheckedChange = { store.plugin.toggle(toggle.id, it) })
            }
        }
    }
}

@Composable
private fun PluginChips(store: Store, manifest: PluginManifest?, enabled: Boolean, open: Boolean, onToggle: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val panelLabel = manifest?.panelLabel.orEmpty()
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (panelLabel.isNotBlank()) {
            val tone = if (open) scheme.primary else scheme.surfaceContainerHigh
            ChatChip(if (open) "hide $panelLabel" else panelLabel, tone, if (open) scheme.onPrimary else scheme.onSurface, onTap = onToggle)
        }
        manifest?.actions.orEmpty().forEach { action ->
            ChatChip(action.label, scheme.surfaceContainerHigh, scheme.onSurface, enabled) { store.plugin.act(action.id) }
        }
    }
}

@Composable
private fun ColumnScope.PluginTranscript(turns: List<PluginTurn>, list: LazyListState, empty: String) {
    Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
        if (turns.isEmpty()) Label(empty, Modifier.padding(18.dp))
        LazyColumn(
            state = list,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 14.dp, end = 14.dp, top = 4.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(turns, key = { it.id }) { turn ->
                if (turn.role == "user") ChatUser(turn.content) else ChatReply(turn.content)
            }
        }
    }
}

@Composable
fun PluginScreen(store: Store, onCollapse: () -> Unit) {
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val state by store.plugin.state.collectAsStateWithLifecycle()
    val turns by store.plugin.turns.collectAsStateWithLifecycle()
    val manifest by store.plugin.manifest.collectAsStateWithLifecycle()
    val panel by store.plugin.panel.collectAsStateWithLifecycle()
    val fresh by store.plugin.fresh.collectAsStateWithLifecycle()
    val draft by store.plugin.draft.collectAsStateWithLifecycle()
    var open by rememberSaveable { mutableStateOf(false) }
    val list = rememberLazyListState()
    LaunchedEffect(Unit) { runCatching { store.plugin.loadManifest() } }
    LaunchedEffect(Unit) { store.plugin.follow() }
    LaunchedEffect(open) { if (open) runCatching { store.plugin.loadPanel() } }
    FollowBottom(list, turns.size)
    val status = when {
        state.busy -> "writing…"
        state.pending > 0 -> "${state.pending} waiting for claude to come back"
        else -> null
    }
    Column(modifier = Modifier.fillMaxSize().imePadding()) {
        ScreenHeader(manifest?.title ?: UNNAMED, reachable, onCollapse)
        Banner(reachable)
        PluginChips(store, manifest, fresh && !state.busy, open) { open = !open }
        if (open) PluginPanelView(store, panel)
        PluginTranscript(turns, list, if (fresh) manifest?.empty ?: "nothing here yet" else "waiting for the desktop")
        status?.let { Label(it, Modifier.padding(horizontal = 18.dp)) }
        Notice(store, Modifier.padding(horizontal = 14.dp))
        PromptBar(
            value = draft,
            onChange = { store.plugin.draft.value = it },
            onSend = { store.plugin.submit() },
            placeholder = manifest?.placeholder ?: "say something",
            enabled = fresh,
        )
    }
}
