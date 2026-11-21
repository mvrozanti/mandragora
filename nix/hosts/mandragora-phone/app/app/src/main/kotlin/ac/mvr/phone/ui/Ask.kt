package ac.mvr.phone.ui

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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.AskEntry
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
private fun AskLine(entry: AskEntry) {
    when (entry.role) {
        "user" -> ChatUser(entry.text)
        "assistant" -> ChatReply(entry.text, entry.thinking)
        "shell", "tool" -> ChatNote(entry.text, mono = true)
        "error" -> ChatNote(entry.text, error = true)
        else -> ChatSystem(entry.text)
    }
}

@Composable
fun AskCard(store: Store, onOpen: (String) -> Unit) {
    val state by store.ask.state.collectAsStateWithLifecycle()
    val entries by store.ask.entries.collectAsStateWithLifecycle()
    val fresh by store.ask.fresh.collectAsStateWithLifecycle()
    val subtitle = when {
        !fresh -> "waiting for the desktop"
        state.busy -> state.activity ?: "working"
        else -> state.model.ifBlank { "idle" }
    }
    HomeCard {
        CardHeader("ask", subtitle) { onOpen("ask") }
        val reply = entries.lastOrNull { it.role == "assistant" }
        Text(
            reply?.text?.lineSequence()?.firstOrNull { it.isNotBlank() } ?: "ask the local model anything, or /help",
            style = MaterialTheme.typography.bodyMedium,
            color = if (reply == null) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
fun AskScreen(store: Store, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val state by store.ask.state.collectAsStateWithLifecycle()
    val entries by store.ask.entries.collectAsStateWithLifecycle()
    val fresh by store.ask.fresh.collectAsStateWithLifecycle()
    val draft by store.ask.draft.collectAsStateWithLifecycle()
    val list = rememberLazyListState()
    LaunchedEffect(Unit) { store.ask.follow() }
    FollowBottom(list, entries.size)
    Column(modifier = Modifier.fillMaxSize().imePadding()) {
        ScreenHeader("ask", reachable, onCollapse)
        Banner(reachable)
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Label(state.model.ifBlank { "model" })
            ChatChip(if (state.think) "thinking on" else "thinking off", scheme.surfaceContainerHigh, scheme.onSurface, fresh) { store.ask.toggleThink() }
            ChatChip("clear", scheme.surfaceContainerHigh, scheme.onSurface, fresh && !state.busy) { store.ask.send("/clear") }
            state.commands.forEach { command ->
                ChatChip(command.name, scheme.secondaryContainer, scheme.onSecondaryContainer, fresh) { store.ask.send("/run ${command.name}") }
            }
        }
        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            if (entries.isEmpty()) {
                Label(if (fresh) "nothing asked yet · /help lists the commands" else "waiting for the desktop", Modifier.padding(18.dp))
            }
            LazyColumn(
                state = list,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 14.dp, end = 14.dp, top = 4.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(entries, key = { it.id }) { entry -> AskLine(entry) }
            }
        }
        if (state.busy) {
            val queued = if (state.queued > 0) " · ${state.queued} queued" else ""
            Label("${state.activity ?: "working"}$queued", Modifier.padding(horizontal = 18.dp))
        }
        Notice(store, Modifier.padding(horizontal = 14.dp))
        PromptBar(
            value = draft,
            onChange = { store.ask.draft.value = it },
            onSend = { store.ask.submit() },
            placeholder = "ask, or /help",
            enabled = fresh,
            onStop = if (state.busy) ({ store.ask.stop() }) else null,
        )
    }
}
