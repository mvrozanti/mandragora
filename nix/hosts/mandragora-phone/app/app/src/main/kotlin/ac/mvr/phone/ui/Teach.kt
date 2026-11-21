package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
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
import ac.mvr.phone.net.TeachStats
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlin.math.roundToInt

private val TEACH_ACTIONS = listOf("warmup" to "warm up", "long" to "long session", "answer" to "show the answer", "done" to "done for today")

private fun TeachStats.headline(): String {
    val accuracy = reviews.accuracy?.let { " · ${(it * 100).roundToInt()}% right" } ?: ""
    return "streak ${streak.current} d · ${due.size + backlog} due$accuracy"
}

@Composable
fun TeachCard(store: Store, onOpen: (String) -> Unit) {
    val state by store.teach.state.collectAsStateWithLifecycle()
    val turns by store.teach.turns.collectAsStateWithLifecycle()
    val stats by store.teach.stats.collectAsStateWithLifecycle()
    val fresh by store.teach.fresh.collectAsStateWithLifecycle()
    val subtitle = when {
        !fresh -> "waiting for the desktop"
        state.busy -> "the tutor is writing"
        state.pending > 0 -> "${state.pending} waiting for claude"
        else -> stats?.headline() ?: "idle"
    }
    HomeCard {
        CardHeader("teach", subtitle) { onOpen("teach") }
        val said = turns.lastOrNull { it.role == "assistant" }
        Text(
            said?.content?.lineSequence()?.firstOrNull { it.isNotBlank() } ?: "start a warm-up or ask the tutor anything",
            style = MaterialTheme.typography.bodyMedium,
            color = if (said == null) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun TeachProgress(store: Store, stats: TeachStats?) {
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
        if (stats == null) {
            Label("reading progress…")
            return@Column
        }
        Text(stats.headline(), style = MaterialTheme.typography.titleSmall)
        Label(stats.mastery.joinToString(" · ") { "${it.n} ${it.status}" }.ifBlank { "no concepts yet" })
        stats.due.take(5).forEach { concept ->
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${concept.topic} · ${concept.name}",
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                ChatChip("explain it back", scheme.surfaceContainerHigh, scheme.onSurface) { store.teach.act("explain", concept.id) }
            }
        }
        if (stats.queue.pending > 0) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Label("${stats.queue.pending} queued" + (stats.queue.lastError?.let { " · $it" } ?: ""), Modifier.weight(1f))
                ChatChip("retry now", scheme.secondaryContainer, scheme.onSecondaryContainer) { store.teach.retry() }
            }
        }
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("nudge me after ${stats.nudges.idleHours} h idle", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Switch(checked = stats.nudges.enabled, onCheckedChange = { store.teach.nudges(it) })
        }
    }
}

@Composable
fun TeachScreen(store: Store, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val state by store.teach.state.collectAsStateWithLifecycle()
    val turns by store.teach.turns.collectAsStateWithLifecycle()
    val stats by store.teach.stats.collectAsStateWithLifecycle()
    val fresh by store.teach.fresh.collectAsStateWithLifecycle()
    val draft by store.teach.draft.collectAsStateWithLifecycle()
    var progress by rememberSaveable { mutableStateOf(false) }
    val list = rememberLazyListState()
    LaunchedEffect(Unit) { store.teach.follow() }
    LaunchedEffect(progress) { if (progress) runCatching { store.teach.loadStats() } }
    FollowBottom(list, turns.size)
    Column(modifier = Modifier.fillMaxSize().imePadding()) {
        ScreenHeader("teach", reachable, onCollapse)
        Banner(reachable)
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val tone = if (progress) scheme.primary else scheme.surfaceContainerHigh
            ChatChip(if (progress) "hide progress" else "progress", tone, if (progress) scheme.onPrimary else scheme.onSurface) { progress = !progress }
            TEACH_ACTIONS.forEach { (action, name) ->
                ChatChip(name, scheme.surfaceContainerHigh, scheme.onSurface, fresh && !state.busy) { store.teach.act(action) }
            }
        }
        if (progress) TeachProgress(store, stats)
        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            if (turns.isEmpty()) {
                Label(if (fresh) "no lesson yet · warm up, or say what you want to learn" else "waiting for the desktop", Modifier.padding(18.dp))
            }
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
        when {
            state.busy -> Label("the tutor is writing…", Modifier.padding(horizontal = 18.dp))
            state.pending > 0 -> Label("${state.pending} waiting for claude to come back", Modifier.padding(horizontal = 18.dp))
        }
        Notice(store, Modifier.padding(horizontal = 14.dp))
        PromptBar(
            value = draft,
            onChange = { store.teach.draft.value = it },
            onSend = { store.teach.submit() },
            placeholder = "answer, or ask the tutor",
            enabled = fresh,
        )
    }
}
