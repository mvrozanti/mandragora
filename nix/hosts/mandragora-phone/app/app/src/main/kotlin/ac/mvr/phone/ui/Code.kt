package ac.mvr.phone.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import ac.mvr.phone.state.CodeStore
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.border
import ac.mvr.phone.net.CodeEntry
import ac.mvr.phone.net.CodePart
import ac.mvr.phone.net.CodeProject
import ac.mvr.phone.net.CodeSession
import ac.mvr.phone.net.CodeStatus
import ac.mvr.phone.net.PermissionAsk
import ac.mvr.phone.net.QuestionAsk
import ac.mvr.phone.state.CodeModel
import ac.mvr.phone.state.Store
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

private fun JsonObject.str(key: String): String? = runCatching { this[key]?.jsonPrimitive?.contentOrNull }.getOrNull()

private fun folderOf(path: String?): String = path?.trimEnd('/')?.substringAfterLast('/')?.ifEmpty { path } ?: "home"

private fun ago(ms: Long): String {
    val seconds = (System.currentTimeMillis() - ms) / 1000
    return when {
        ms <= 0 -> ""
        seconds < 60 -> "now"
        seconds < 3600 -> "${seconds / 60} m"
        seconds < 86400 -> "${seconds / 3600} h"
        else -> "${seconds / 86400} d"
    }
}

@Composable
private fun Chip(text: String, tone: Color, onTone: Color, enabled: Boolean = true, onTap: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (enabled) tone else tone.copy(alpha = 0.4f))
            .clickable(enabled = enabled, onClick = onTap)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge, color = onTone, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun SessionDot(open: Boolean, busy: Boolean) {
    val scheme = MaterialTheme.colorScheme
    val pulse by rememberInfiniteTransition(label = "dot").animateFloat(
        initialValue = 1f,
        targetValue = 0.35f,
        animationSpec = infiniteRepeatable(tween(700), RepeatMode.Reverse),
        label = "dot",
    )
    val color = when {
        busy -> scheme.primary.copy(alpha = pulse)
        open -> Color(0xFF4EC17D)
        else -> Color.Transparent
    }
    Box(
        modifier = Modifier
            .size(8.dp)
            .clip(CircleShape)
            .background(color)
            .border(1.dp, if (busy || open) Color.Transparent else scheme.outlineVariant, CircleShape),
    )
}

@Composable
private fun SessionRow(session: CodeSession, status: CodeStatus?, selected: Boolean = false, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val busy = status?.type == "busy"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (selected) scheme.surfaceContainerHigh else Color.Transparent)
            .clickable(onClick = onTap)
            .padding(horizontal = 8.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SessionDot(open = session.live != null, busy = busy)
        Column(modifier = Modifier.weight(1f)) {
            Text(session.title.ifBlank { "untitled" }, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val live = session.live
            val state = listOfNotNull(
                if (live != null) "on the desktop · ${live.status ?: "open"}" else if (busy) "working" else null,
                ago(session.time.updated).ifEmpty { null },
            ).joinToString(" · ")
            Label("${session.backend} · ${session.folder} · $state", color = if (live != null) scheme.tertiary else scheme.outline)
            session.snippet?.takeIf { it.isNotBlank() }?.let { snip ->
                Text(Meaning.annotate(snip, scheme), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
fun CodeCard(store: Store, onOpen: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val sessions by store.code.sessions.collectAsStateWithLifecycle()
    val statuses by store.code.statuses.collectAsStateWithLifecycle()
    val fresh by store.code.fresh.collectAsStateWithLifecycle()
    val count by store.prefs.codeCardCount.collectAsStateWithLifecycle()
    val busy = sessions.count { statuses[it.id]?.type == "busy" }
    val subtitle = when {
        !fresh && sessions.isEmpty() -> "waiting for the desktop"
        busy > 0 -> "$busy working"
        else -> "idle"
    }
    HomeCard {
        CardHeader("code", subtitle) { onOpen("sessions") }
        sessions.take(count).forEach { session ->
            SessionRow(session, statuses[session.id]) {
                store.code.open(session)
                onOpen("code")
            }
        }
        Row {
            Chip("new session", scheme.surfaceContainerHigh, scheme.onSurface) {
                store.code.startNew()
                onOpen("code")
            }
        }
    }
}

@Composable
private fun SessionBar(current: CodeSession?, newIn: String?, model: CodeModel?, live: Boolean, onPick: () -> Unit, onModel: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).clickable(onClick = onPick).padding(horizontal = 6.dp, vertical = 4.dp),
        ) {
            Text(current?.title?.ifBlank { null } ?: "new session", style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val where = current?.live
            val note = when {
                where != null -> " · on the desktop as ${where.name ?: "an open session"}"
                live -> ""
                else -> " · not live"
            }
            Label((current?.folder ?: folderOf(newIn)) + note, color = if (live && where == null) scheme.outline else scheme.tertiary)
        }
        Chip(model?.label ?: "model", scheme.surfaceContainerHigh, scheme.onSurface) { onModel() }
    }
}

@Composable
private fun ToolLine(part: CodePart) {
    val scheme = MaterialTheme.colorScheme
    var open by remember(part.id) { mutableStateOf(false) }
    val state = part.state
    val status = state?.status ?: "pending"
    val input = state?.input
    val title = state?.title ?: input?.str("command") ?: input?.str("filePath") ?: input?.str("pattern") ?: input?.str("description") ?: ""
    val tint = when (status) {
        "error" -> scheme.error
        "completed" -> scheme.outline
        else -> scheme.primary
    }
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { open = !open }.padding(horizontal = 4.dp, vertical = 2.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (status == "completed" || status == "error") "▪" else "▸", style = MaterialTheme.typography.labelLarge, color = tint)
            Text(part.tool ?: "tool", style = MaterialTheme.typography.labelLarge, color = tint)
            Text(title, style = MaterialTheme.typography.labelMedium, color = scheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        }
        if (open) {
            val body = state?.error ?: state?.output ?: input?.toString() ?: ""
            Text(body.take(4000), style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ReasoningLine(part: CodePart) {
    val scheme = MaterialTheme.colorScheme
    var open by remember(part.id) { mutableStateOf(false) }
    val text = part.text ?: return
    if (text.isBlank()) return
    Column(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { open = !open }.padding(horizontal = 4.dp, vertical = 2.dp)) {
        Label(if (open) "thinking" else "thinking · ${text.lines().size} lines", color = scheme.outline)
        if (open) Text(text, style = MaterialTheme.typography.bodyMedium, color = scheme.onSurface.copy(alpha = 0.6f))
    }
}

@Composable
private fun EntryView(entry: CodeEntry, scheme: ColorScheme) {
    if (entry.info.role == "user") {
        val text = entry.parts.filter { it.type == "text" && !it.synthetic && !it.ignored }.mapNotNull { it.text }.joinToString("\n")
        if (text.isBlank()) return
        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
            Box(modifier = Modifier.clip(RoundedCornerShape(18.dp)).background(scheme.surfaceContainerHigh).padding(horizontal = 14.dp, vertical = 10.dp)) {
                Text(text, style = MaterialTheme.typography.bodyLarge, color = scheme.onSurface)
            }
        }
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        entry.parts.forEach { part ->
            when (part.type) {
                "text" -> {
                    val text = part.text
                    if (!part.ignored && !text.isNullOrBlank()) MarkdownText(text, scheme)
                }
                "reasoning" -> ReasoningLine(part)
                "tool" -> ToolLine(part)
            }
        }
        entry.info.error?.let { Label(it.text, color = scheme.error) }
    }
}

@Composable
private fun PendingBubble(text: String, busy: Boolean) {
    val scheme = MaterialTheme.colorScheme
    Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(modifier = Modifier.alpha(0.6f).clip(RoundedCornerShape(18.dp)).background(scheme.surfaceContainerHigh).padding(horizontal = 14.dp, vertical = 10.dp)) {
            Text(text, style = MaterialTheme.typography.bodyLarge, color = scheme.onSurface)
        }
        Label(if (busy) "queued · goes in when the current turn ends" else "sent · waiting for the session", color = scheme.tertiary)
    }
}

@Composable
private fun PermissionCard(ask: PermissionAsk, onReply: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val lines = ask.metadata?.str("command")?.let { listOf(it) } ?: ask.patterns.take(3)
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(scheme.surfaceContainerHigh).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("wants to ${ask.permission}", style = MaterialTheme.typography.titleMedium, color = scheme.tertiary)
        lines.forEach { Text(it, style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant, maxLines = 3, overflow = TextOverflow.Ellipsis) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip("once", scheme.primary, scheme.onPrimary) { onReply("once") }
            Chip("always", scheme.surfaceContainer, scheme.onSurface) { onReply("always") }
            Chip("reject", scheme.error, scheme.onError) { onReply("reject") }
        }
    }
}

@Composable
private fun QuestionCard(ask: QuestionAsk, onAnswer: (List<List<String>>) -> Unit, onReject: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var picks by remember(ask.id) { mutableStateOf<Map<Int, List<String>>>(emptyMap()) }
    val single = ask.questions.size == 1 && !ask.questions[0].multiple
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(scheme.surfaceContainerHigh).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        ask.questions.forEachIndexed { index, question ->
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (question.header.isNotBlank()) Label(question.header, color = scheme.tertiary)
                Text(question.question, style = MaterialTheme.typography.bodyMedium)
                question.options.forEach { option ->
                    val chosen = picks[index]?.contains(option.label) == true
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (chosen) scheme.primary else scheme.surfaceContainer)
                            .clickable {
                                if (single) {
                                    onAnswer(listOf(listOf(option.label)))
                                } else {
                                    val now = picks[index] ?: emptyList()
                                    val next = when {
                                        !question.multiple -> listOf(option.label)
                                        chosen -> now - option.label
                                        else -> now + option.label
                                    }
                                    picks = picks + (index to next)
                                }
                            }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    ) {
                        Text(option.label, style = MaterialTheme.typography.bodyMedium, color = if (chosen) scheme.onPrimary else scheme.onSurface)
                        if (option.description.isNotBlank()) Label(option.description, color = if (chosen) scheme.onPrimary else scheme.outline)
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!single) {
                val complete = ask.questions.indices.all { !picks[it].isNullOrEmpty() }
                Chip("answer", scheme.primary, scheme.onPrimary, enabled = complete) { onAnswer(ask.questions.indices.map { picks[it] ?: emptyList() }) }
            }
            Chip("skip", scheme.surfaceContainer, scheme.onSurface) { onReject() }
        }
    }
}

@Composable
private fun Composer(
    draft: String,
    busy: Boolean,
    enabled: Boolean,
    attachments: List<CodeStore.Attachment>,
    uploading: Boolean,
    onChange: (String) -> Unit,
    onSend: () -> Unit,
    onStop: () -> Unit,
    onAttach: () -> Unit,
    onDetach: (String) -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val stopping = busy && draft.isBlank() && attachments.isEmpty()
    if (attachments.isNotEmpty() || uploading) {
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(start = 14.dp, end = 14.dp, top = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            attachments.forEach { file ->
                Box {
                    Image(file.thumb.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.size(64.dp).clip(RoundedCornerShape(12.dp)))
                    Box(
                        modifier = Modifier.align(Alignment.TopEnd).padding(3.dp).size(22.dp).clip(CircleShape).background(scheme.surface.copy(alpha = 0.8f)).clickable { onDetach(file.path) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Filled.Close, "remove", tint = scheme.onSurface, modifier = Modifier.size(14.dp))
                    }
                }
            }
            if (uploading) Box(modifier = Modifier.size(64.dp).clip(RoundedCornerShape(12.dp)).background(scheme.surfaceContainerHigh), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
            }
        }
    }
    Row(
        modifier = Modifier.fillMaxWidth().padding(start = 4.dp, end = 6.dp, top = 6.dp, bottom = 8.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        IconButton(onClick = onAttach, enabled = enabled && !uploading) {
            Icon(Icons.Filled.AddPhotoAlternate, "attach a picture", tint = scheme.onSurfaceVariant)
        }
        OutlinedTextField(
            value = draft,
            onValueChange = onChange,
            modifier = Modifier.weight(1f),
            enabled = enabled,
            placeholder = { Text("say what to do") },
            maxLines = 6,
            shape = RoundedCornerShape(18.dp),
            textStyle = MaterialTheme.typography.bodyMedium,
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = scheme.primary, unfocusedBorderColor = scheme.outlineVariant),
        )
        IconButton(onClick = { if (stopping) onStop() else onSend() }, enabled = enabled && !uploading && (stopping || draft.isNotBlank() || attachments.isNotEmpty())) {
            Icon(
                if (stopping) Icons.Filled.Stop else Icons.AutoMirrored.Filled.Send,
                if (stopping) "stop" else "send",
                tint = if (stopping) scheme.error else scheme.primary,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SessionSheet(
    sessions: List<CodeSession>,
    projects: List<CodeProject>,
    statuses: Map<String, CodeStatus>,
    currentId: String?,
    onPick: (CodeSession) -> Unit,
    onNew: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = scheme.surfaceContainer) {
        LazyColumn(contentPadding = PaddingValues(start = 10.dp, end = 10.dp, bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            item { Label("new session in", modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) }
            items(projects, key = { "p" + it.id }) { project ->
                Column(
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { onNew(project.worktree) }.padding(horizontal = 8.dp, vertical = 8.dp),
                ) {
                    Text(project.folder, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Label(project.worktree)
                }
            }
            item { Label("sessions", modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) }
            items(sessions, key = { it.id }) { session -> SessionRow(session, statuses[session.id], session.id == currentId) { onPick(session) } }
        }
    }
}

@Composable
fun CodeScreen(store: Store, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val code = store.code
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val current by code.current.collectAsStateWithLifecycle()
    val newIn by code.newIn.collectAsStateWithLifecycle()
    val entries by code.entries.collectAsStateWithLifecycle()
    val statuses by code.statuses.collectAsStateWithLifecycle()
    val asks by code.asks.collectAsStateWithLifecycle()
    val questions by code.questions.collectAsStateWithLifecycle()
    val model by code.model.collectAsStateWithLifecycle()
    val live by code.live.collectAsStateWithLifecycle()
    val draft by code.draft.collectAsStateWithLifecycle()
    val sessions by code.sessions.collectAsStateWithLifecycle()
    val projects by code.projects.collectAsStateWithLifecycle()
    var picking by remember { mutableStateOf(false) }
    val directory = current?.directory ?: newIn
    val backend = current?.backend?.ifEmpty { null } ?: model?.backend ?: "claude"
    LaunchedEffect(Unit) { code.enter() }
    LaunchedEffect(backend, directory) { code.watch(backend, directory) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(10_000)
            runCatching { code.refresh() }
        }
    }
    val busy = current?.let { statuses[it.id]?.type == "busy" } ?: false
    val attachments by code.attachments.collectAsStateWithLifecycle()
    val uploading by code.uploading.collectAsStateWithLifecycle()
    val pendingAll by code.pending.collectAsStateWithLifecycle()
    val pendingHere = pendingAll.filter { it.sessionId == current?.id }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) code.attach(uri) }
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("code", reachable, onCollapse)
        Banner(reachable)
        SessionBar(current, newIn, model, live, onPick = { picking = true }, onModel = { code.cycleModel() })
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            reverseLayout = true,
            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(questions, key = { "q" + it.id }) { ask -> QuestionCard(ask, onAnswer = { code.answer(ask, it) }, onReject = { code.rejectQuestion(ask) }) }
            items(asks, key = { "p" + it.id }) { ask -> PermissionCard(ask) { code.allow(ask, it) } }
            items(pendingHere.asReversed(), key = { "s" + it.id }) { PendingBubble(it.text, busy) }
            if (busy) item(key = "busy") { Label("working…", color = scheme.primary) }
            items(entries.asReversed(), key = { it.info.id }) { EntryView(it, scheme) }
            if (entries.isEmpty()) {
                item(key = "empty") {
                    Label(if (current == null) "new session in ${folderOf(newIn)}" else "nothing here yet")
                }
            }
        }
        Notice(store, Modifier.padding(horizontal = 14.dp))
        Composer(
            draft, busy, reachable, attachments, uploading,
            onChange = { code.draft.value = it },
            onSend = { code.send(draft) },
            onStop = { code.stop() },
            onAttach = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
            onDetach = { code.detach(it) },
        )
    }
    if (picking) {
        SessionSheet(
            sessions, projects, statuses, current?.id,
            onPick = { code.open(it); picking = false },
            onNew = { code.startNew(it); picking = false },
            onDismiss = { picking = false },
        )
    }
}

@Composable
fun SessionsScreen(store: Store, onOpenSession: () -> Unit, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val statuses by store.code.statuses.collectAsStateWithLifecycle()
    var query by rememberSaveable { mutableStateOf("") }
    var found by remember { mutableStateOf<List<CodeSession>?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(query) {
        if (query.isNotBlank()) delay(350)
        runCatching { store.code.find(query.trim()) }
            .onSuccess { found = it; failed = false }
            .onFailure { failed = true }
    }
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("sessions", reachable, onCollapse)
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text("a phrase or subject, across every session") },
            singleLine = true,
            shape = RoundedCornerShape(24.dp),
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = scheme.primary, unfocusedBorderColor = scheme.outlineVariant),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp),
        )
        val list = found
        Label(
            when {
                failed -> "the desktop did not answer"
                list == null -> "searching"
                query.isBlank() -> "${list.size} sessions · latest activity first"
                else -> "${list.size} sessions mention it · latest activity first"
            },
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        )
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(start = 10.dp, end = 10.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            items(list ?: emptyList(), key = { it.id }) { session ->
                SessionRow(session, statuses[session.id]) {
                    store.code.open(session)
                    onOpenSession()
                }
            }
        }
    }
}
