package ac.mvr.phone.ui

import ac.mvr.phone.logic.ABORTED
import ac.mvr.phone.logic.Shown
import ac.mvr.phone.logic.ShownCalls
import ac.mvr.phone.logic.ShownEntry
import ac.mvr.phone.logic.Stops
import ac.mvr.phone.logic.active
import ac.mvr.phone.logic.said
import ac.mvr.phone.logic.squashCalls
import ac.mvr.phone.logic.stoppedTurns
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Mic
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager
import ac.mvr.phone.play.Voice
import java.io.File
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.layout.height
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.ui.unit.IntOffset
import ac.mvr.phone.state.CLOSE_GRACE_MS
import kotlin.math.roundToInt

import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.material.icons.filled.Image
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.unit.Dp
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
import ac.mvr.phone.net.ScreenAsk
import ac.mvr.phone.net.SessionSettings
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.DpOffset
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
import androidx.compose.runtime.key
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

private fun JsonObject.str(key: String): String? = runCatching { this[key]?.jsonPrimitive?.contentOrNull }.getOrNull()

private fun folderOf(path: String?): String = path?.trimEnd('/')?.substringAfterLast('/')?.ifEmpty { path } ?: "home"

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
private fun SwipeToClose(enabled: Boolean, onClose: () -> Unit, content: @Composable () -> Unit) {
    if (!enabled) {
        content()
        return
    }
    val scheme = MaterialTheme.colorScheme
    val haptic = LocalHapticFeedback.current
    val density = LocalDensity.current
    var width by remember { mutableIntStateOf(0) }
    var drag by remember { mutableFloatStateOf(0f) }
    val reach = width * 0.4f
    val armed = reach > 0f && -drag >= reach
    LaunchedEffect(armed) { if (armed) haptic.performHapticFeedback(HapticFeedbackType.LongPress) }
    Box(modifier = Modifier.fillMaxWidth().onSizeChanged { width = it.width }) {
        if (drag < 0f) {
            val tint = if (armed) scheme.onError else scheme.onErrorContainer
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .padding(start = with(density) { (width + drag).coerceAtLeast(0f).toDp() })
                    .clip(RoundedCornerShape(12.dp))
                    .background(if (armed) scheme.error else scheme.errorContainer),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Close, null, tint = tint, modifier = Modifier.size(18.dp))
                    Text(if (armed) "let go to close" else "close", style = MaterialTheme.typography.labelLarge, color = tint, maxLines = 1)
                }
            }
        }
        Box(
            modifier = Modifier
                .offset { IntOffset(drag.roundToInt(), 0) }
                .draggable(
                    orientation = Orientation.Horizontal,
                    state = rememberDraggableState { delta -> drag = (drag + delta).coerceIn(-width.toFloat(), 0f) },
                    onDragStopped = { velocity ->
                        if (-drag >= reach || (velocity < -2400f && -drag > reach / 3)) onClose()
                        animate(drag, 0f, animationSpec = spring(dampingRatio = 0.8f, stiffness = 500f)) { value, _ -> drag = value }
                    },
                ),
        ) { content() }
    }
}

@Composable
private fun ClosingRow(session: CodeSession, busy: Boolean, until: Long, onUndo: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var left by remember(until) { mutableLongStateOf(until - System.currentTimeMillis()) }
    LaunchedEffect(until) {
        while (left > 0) {
            delay(50)
            left = until - System.currentTimeMillis()
        }
    }
    val share = (left.toFloat() / CLOSE_GRACE_MS).coerceIn(0f, 1f)
    val seconds = ((left + 999) / 1000).coerceAtLeast(0)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(scheme.errorContainer)
            .padding(start = 12.dp, end = 6.dp, top = 8.dp, bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(session.title.ifBlank { "untitled" }, style = MaterialTheme.typography.bodyLarge, color = scheme.onErrorContainer, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Label(
                if (seconds > 0) "closing on the desktop in $seconds s" + (if (busy) " · its turn stops" else "") else "closing on the desktop…",
                color = scheme.onErrorContainer.copy(alpha = 0.8f),
            )
            Box(
                modifier = Modifier
                    .padding(top = 6.dp)
                    .fillMaxWidth()
                    .height(2.dp)
                    .clip(CircleShape)
                    .background(scheme.onErrorContainer.copy(alpha = 0.2f)),
            ) {
                Box(modifier = Modifier.fillMaxWidth(share).fillMaxHeight().background(scheme.onErrorContainer))
            }
        }
        if (left > 0) Chip("undo", scheme.onErrorContainer, scheme.errorContainer, onTap = onUndo)
    }
}

@Composable
private fun SessionRow(
    session: CodeSession,
    status: CodeStatus?,
    selected: Boolean = false,
    closingUntil: Long? = null,
    onClose: (() -> Unit)? = null,
    onUndo: () -> Unit = {},
    onTap: () -> Unit,
) {
    if (closingUntil != null) {
        ClosingRow(session, status?.type == "busy", closingUntil, onUndo)
        return
    }
    SwipeToClose(enabled = onClose != null, onClose = { onClose?.invoke() }) {
        SessionLine(session, status, selected, onTap)
    }
}

@Composable
private fun SessionLine(session: CodeSession, status: CodeStatus?, selected: Boolean, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val busy = status?.type == "busy"
    val waiting = status?.message == "waiting"
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
            Text(
                session.title.ifBlank { "untitled" },
                style = MaterialTheme.typography.bodyLarge,
                color = if (waiting) scheme.error else Color.Unspecified,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
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
    val closing by store.code.closing.collectAsStateWithLifecycle()
    val busy = sessions.count { statuses[it.id]?.type == "busy" }
    val waiting = sessions.count { statuses[it.id]?.message == "waiting" }
    val subtitle = when {
        !fresh && sessions.isEmpty() -> "waiting for the desktop"
        waiting > 0 -> if (waiting == 1) "1 needs you" else "$waiting need you"
        busy > 0 -> "$busy working"
        else -> "idle"
    }
    val connected = sessions.filter { active(it, statuses[it.id]) }
    val connectedIds = connected.map { it.id }.toSet()
    val shown = connected + sessions.filter { it.id !in connectedIds }.take((count - connected.size).coerceAtLeast(0))
    HomeCard {
        CardHeader("code", subtitle) { onOpen("sessions") }
        shown.forEach { session ->
            key(session.id) {
                val status = statuses[session.id]
                SessionRow(
                    session, status,
                    closingUntil = closing[session.id],
                    onClose = if (store.code.closable(session, status)) ({ store.code.close(session) }) else null,
                    onUndo = { store.code.undoClose(session.id) },
                ) {
                    store.code.open(session)
                    onOpen("code")
                }
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

private val MODES = listOf("auto" to "auto", "default" to "ask", "acceptEdits" to "accept edits", "plan" to "plan")
private val EFFORTS = listOf(null, "low", "medium", "high", "xhigh", "max")
private val MODE_NOTES = mapOf(
    "auto" to "a classifier approves or refuses each tool call; asks only when it cannot tell",
    "default" to "asks before every edit and command",
    "acceptEdits" to "edits files without asking; asks before commands",
    "plan" to "reads and plans; changes nothing until you approve the plan",
)

private fun chipText(model: CodeModel?, settings: SessionSettings, tunable: Boolean): String {
    val base = model?.label ?: "model"
    if (!tunable) return base
    return listOfNotNull(base, settings.effort, MODES.firstOrNull { it.first == settings.mode }?.second?.substringBefore(' ')).joinToString(" · ")
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun TuneSheet(
    models: List<CodeModel>,
    model: CodeModel?,
    settings: SessionSettings,
    tunable: Boolean,
    desk: String?,
    onModel: (CodeModel) -> Unit,
    onEffort: (String?) -> Unit,
    onMode: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = scheme.surfaceContainer) {
        Column(modifier = Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (desk != null) Text("runs in a desktop terminal as $desk; changes go to that terminal, for this session only. Another kind of model restarts it with the conversation kept: claude and deepseek in a new desktop window, a local model in the background on the desktop", style = MaterialTheme.typography.bodySmall, color = scheme.outline)
            Label("model")
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                models.forEach { option ->
                    val on = option == model
                    Chip(option.label, if (on) scheme.primary else scheme.surfaceContainerHigh, if (on) scheme.onPrimary else scheme.onSurface) { onModel(option) }
                }
            }
            if (tunable) {
                Label("effort")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    EFFORTS.forEach { level ->
                        val on = level == settings.effort
                        Chip(level ?: "default", if (on) scheme.primary else scheme.surfaceContainerHigh, if (on) scheme.onPrimary else scheme.onSurface) { onEffort(level) }
                    }
                }
                Label("mode")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    MODES.forEach { (id, name) ->
                        val on = id == settings.mode
                        Chip(name, if (on) scheme.primary else scheme.surfaceContainerHigh, if (on) scheme.onPrimary else scheme.onSurface) { onMode(id) }
                    }
                }
                MODE_NOTES[settings.mode]?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = scheme.outline) }
            }
        }
    }
}

@Composable
private fun SessionBar(current: CodeSession?, chip: String, onRename: (String) -> Unit, onPick: () -> Unit, onModel: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var editing by remember(current?.id) { mutableStateOf(false) }
    if (editing && current != null) {
        TitleEditor(current.title, onSave = { editing = false; onRename(it) }, onCancel = { editing = false })
        return
    }
    Row(
        modifier = Modifier.fillMaxWidth().padding(start = 14.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            current?.title?.ifBlank { null } ?: if (current == null) "new session" else "untitled",
            style = MaterialTheme.typography.titleMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .clip(RoundedCornerShape(10.dp))
                .clickable { if (current != null) editing = true else onPick() }
                .padding(horizontal = 6.dp, vertical = 4.dp),
        )
        Chip(chip, scheme.surfaceContainerHigh, scheme.onSurface) { onModel() }
    }
}

@Composable
private fun TitleEditor(title: String, onSave: (String) -> Unit, onCancel: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var field by remember { mutableStateOf(TextFieldValue(title, TextRange(title.length))) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    BackHandler(onBack = onCancel)
    Row(
        modifier = Modifier.fillMaxWidth().padding(start = 14.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = field,
            onValueChange = { field = it.copy(text = it.text.replace('\n', ' ')) },
            textStyle = MaterialTheme.typography.titleMedium,
            placeholder = { Text("name this session") },
            maxLines = 4,
            shape = RoundedCornerShape(14.dp),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onSave(field.text) }),
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = scheme.primary, unfocusedBorderColor = scheme.outlineVariant),
            modifier = Modifier.weight(1f).focusRequester(focus),
        )
        IconButton(onClick = { onSave(field.text) }) { Icon(Icons.Filled.Check, "rename", tint = scheme.primary) }
        IconButton(onClick = onCancel) { Icon(Icons.Filled.Close, "cancel", tint = scheme.onSurfaceVariant) }
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
private fun StoppedLine(chip: String?, onResend: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Label("stopped", color = scheme.error)
        if (chip != null) Chip("resend", scheme.surfaceContainerHigh, scheme.onSurface) { onResend(chip) }
    }
}

@Composable
private fun Held(actions: List<Pair<String, () -> Unit>>, content: @Composable () -> Unit) {
    var at by remember { mutableStateOf<Offset?>(null) }
    var height by remember { mutableIntStateOf(0) }
    val haptic = LocalHapticFeedback.current
    val density = LocalDensity.current
    Box(
        modifier = Modifier
            .onSizeChanged { height = it.height }
            .pointerInput(Unit) {
                detectTapGestures(onLongPress = { point ->
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    at = point
                })
            },
    ) {
        content()
        val point = at ?: Offset.Zero
        DropdownMenu(
            expanded = at != null,
            onDismissRequest = { at = null },
            offset = with(density) { DpOffset(point.x.toDp(), (point.y - height).toDp()) },
        ) {
            actions.forEach { (label, act) ->
                DropdownMenuItem(text = { Text(label) }, onClick = { at = null; act() })
            }
        }
    }
}

@Composable
private fun CallsView(calls: ShownCalls) {
    if (!calls.squashed) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            calls.parts.forEach { if (it.type == "tool") ToolLine(it) else ReasoningLine(it) }
        }
        return
    }
    val scheme = MaterialTheme.colorScheme
    var open by remember(calls.key) { mutableStateOf(false) }
    val tools = calls.parts.filter { it.type == "tool" }
    val live = tools.last().takeIf { it.state?.status != "completed" && it.state?.status != "error" }
    val failed = tools.count { it.state?.status == "error" }
    val names = tools.groupingBy { it.tool ?: "tool" }.eachCount().entries
        .sortedByDescending { it.value }
        .joinToString(" · ") { (name, count) -> if (count > 1) "$name ×$count" else name }
    val tint = when {
        live != null -> scheme.primary
        failed > 0 -> scheme.error
        else -> scheme.outline
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { open = !open }.padding(horizontal = 4.dp, vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (open) "▾" else if (live != null) "▸" else "▪", style = MaterialTheme.typography.labelLarge, color = tint)
            Text("${tools.size} calls", style = MaterialTheme.typography.labelLarge, color = tint)
            Text(
                listOfNotNull(names, "$failed failed".takeIf { failed > 0 }).joinToString(" · "),
                style = MaterialTheme.typography.labelMedium,
                color = scheme.outline,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
        }
        if (open) {
            Column(modifier = Modifier.padding(start = 14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                calls.parts.forEach { if (it.type == "tool") ToolLine(it) else ReasoningLine(it) }
            }
        } else if (live != null) {
            Box(modifier = Modifier.padding(start = 14.dp)) { ToolLine(live) }
        }
    }
}

@Composable
private fun EntryView(
    entry: CodeEntry,
    scheme: ColorScheme,
    stops: Stops,
    onEdit: (String) -> Unit,
    onResend: (String) -> Unit,
    parts: List<CodePart> = entry.parts,
    tail: Boolean = true,
) {
    val clipboard = LocalClipboardManager.current
    val chip = stops.chips[entry.info.id]
    if (entry.info.role == "user") {
        val text = said(entry)
        if (text.isBlank()) return
        val actions = buildList<Pair<String, () -> Unit>> {
            add("copy" to { clipboard.setText(AnnotatedString(CodeStore.split(text).first.ifEmpty { text })) })
            add("edit" to { onEdit(text) })
            if (stops.resend.containsKey(entry.info.id)) add("resend" to { onResend(text) })
        }
        Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            UserBubble(text, faded = false, actions = actions)
            if (chip != null) StoppedLine(chip, onResend)
        }
        return
    }
    val words = entry.parts.filter { it.type == "text" && !it.ignored }.mapNotNull { it.text }.filter { it.isNotBlank() }.joinToString("\n\n")
    val copy = listOf<Pair<String, () -> Unit>>("copy" to { clipboard.setText(AnnotatedString(Meaning.unmark(words))) })
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        parts.forEach { part ->
            when (part.type) {
                "text" -> {
                    val text = part.text
                    if (!part.ignored && !text.isNullOrBlank()) Held(copy) { MarkdownText(text, scheme) }
                }
                "reasoning" -> ReasoningLine(part)
                "tool" -> ToolLine(part)
                "divider" -> Row(modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(modifier = Modifier.weight(1f).height(1.dp).background(scheme.outlineVariant))
                    Label(part.text.orEmpty(), modifier = Modifier.padding(horizontal = 10.dp), color = scheme.outline)
                    Box(modifier = Modifier.weight(1f).height(1.dp).background(scheme.outlineVariant))
                }
            }
        }
        entry.info.error?.takeIf { tail }?.let { error ->
            if (error.name == ABORTED) {
                StoppedLine(chip, onResend)
            } else {
                Label(error.text, color = scheme.error)
            }
        }
    }
}

@Composable
private fun UserBubble(text: String, faded: Boolean, actions: List<Pair<String, () -> Unit>> = emptyList()) {
    Column(modifier = Modifier.fillMaxWidth().alpha(if (faded) 0.6f else 1f), horizontalAlignment = Alignment.End) {
        if (actions.isEmpty()) BubbleBody(text) else Held(actions) { BubbleBody(text) }
    }
}

@Composable
private fun BubbleBody(text: String) {
    val scheme = MaterialTheme.colorScheme
    val (words, attached) = CodeStore.split(text)
    val pictures = attached.filter { it.picture }
    Column(
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        attached.filterNot { it.picture }.forEach { file -> FileChip(file.name) }
        if (pictures.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                pictures.forEach { picture ->
                    val thumb = CodeStore.sentThumbs[picture.path]
                    if (thumb != null) {
                        Image(thumb.asImageBitmap(), "picture", contentScale = ContentScale.Crop, modifier = Modifier.size(96.dp).clip(RoundedCornerShape(14.dp)))
                    } else {
                        Row(
                            modifier = Modifier.clip(RoundedCornerShape(14.dp)).background(scheme.surfaceContainerHigh).padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Icon(Icons.Filled.Image, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                            Text("picture", style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
        if (words.isNotEmpty()) {
            Box(modifier = Modifier.clip(RoundedCornerShape(18.dp)).background(scheme.surfaceContainerHigh).padding(horizontal = 14.dp, vertical = 10.dp)) {
                Text(words, style = MaterialTheme.typography.bodyLarge, color = scheme.onSurface)
            }
        }
    }
}

@Composable
private fun FileChip(name: String, modifier: Modifier = Modifier, end: Dp = 12.dp) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = modifier.clip(RoundedCornerShape(14.dp)).background(scheme.surfaceContainerHigh).padding(start = 12.dp, end = end, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(if (name.endsWith(".pdf", ignoreCase = true)) Icons.Filled.PictureAsPdf else Icons.Filled.Description, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
        Text(name, style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 220.dp))
    }
}

@Composable
private fun PendingBubble(text: String, busy: Boolean) {
    val scheme = MaterialTheme.colorScheme
    Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        UserBubble(text, faded = true)
        Label(if (busy) "queued · goes in when the current turn ends" else "sent · waiting for the session", color = scheme.tertiary)
    }
}

@Composable
private fun PermissionCard(ask: PermissionAsk, onReply: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val plan = ask.metadata?.str("plan")
    val lines = ask.metadata?.str("command")?.let { listOf(it) } ?: if (plan != null) emptyList() else ask.patterns.take(3)
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(scheme.surfaceContainerHigh).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(if (plan != null) "has a plan ready" else "wants to ${ask.permission}", style = MaterialTheme.typography.titleMedium, color = scheme.tertiary)
        plan?.let { MarkdownText(it, scheme) }
        lines.forEach { Text(it, style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant, maxLines = 3, overflow = TextOverflow.Ellipsis) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip("once", scheme.primary, scheme.onPrimary) { onReply("once") }
            Chip("always", scheme.surfaceContainer, scheme.onSurface) { onReply("always") }
            Chip("reject", scheme.error, scheme.onError) { onReply("reject") }
        }
    }
}

@Composable
private fun ScreenCard(ask: ScreenAsk, onPress: (String, String?) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var typing by remember(ask.id) { mutableStateOf<String?>(null) }
    var said by remember(ask.id) { mutableStateOf("") }
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(scheme.surfaceContainerHigh).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (ask.waiting.isNotBlank()) Label(ask.waiting, color = scheme.error)
        ask.plan?.let { MarkdownText(it, scheme) }
        if (ask.body.isNotBlank()) {
            Text(ask.body, style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace), color = scheme.onSurface)
        }
        ask.options.forEach { option ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (option.current) scheme.secondaryContainer else scheme.surfaceContainer)
                    .clickable { if (option.text) typing = option.key else onPress(option.key, null) }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                Text("${option.key}. ${option.label}", style = MaterialTheme.typography.bodyMedium, color = if (option.current) scheme.onSecondaryContainer else scheme.onSurface)
                if (option.detail.isNotBlank()) Label(option.detail, color = scheme.outline)
            }
            if (typing == option.key) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = said,
                        onValueChange = { said = it },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                        placeholder = { Text("type the answer", color = scheme.outline) },
                    )
                    IconButton(onClick = { onPress(option.key, said.trim()) }, enabled = said.isNotBlank()) {
                        Icon(Icons.AutoMirrored.Filled.Send, "send", tint = if (said.isNotBlank()) scheme.primary else scheme.outline)
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (ask.tabs) {
                Chip("‹ back", scheme.surfaceContainer, scheme.onSurface) { onPress("previous", null) }
                Chip("next ›", scheme.surfaceContainer, scheme.onSurface) { onPress("next", null) }
            }
            Chip("esc", scheme.surfaceContainer, scheme.onSurface) { onPress("escape", null) }
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
    field: TextFieldValue,
    focus: FocusRequester,
    busy: Boolean,
    enabled: Boolean,
    attachments: List<CodeStore.Attachment>,
    uploading: Boolean,
    onChange: (TextFieldValue) -> Unit,
    onSend: () -> Unit,
    onStop: () -> Unit,
    onPicture: () -> Unit,
    onFile: () -> Unit,
    onDetach: (String) -> Unit,
    hearing: Boolean,
    onSpoken: (File?) -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    var choosing by remember { mutableStateOf(false) }
    val draft = field.text
    val stopping = busy && draft.isBlank() && attachments.isEmpty()
    val context = LocalContext.current
    val voice = remember { Voice(context) }
    var recording by remember { mutableStateOf(false) }
    var since by remember { mutableLongStateOf(0L) }
    var seconds by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) { onDispose { voice.cancel() } }
    LaunchedEffect(recording) {
        while (recording) {
            seconds = ((System.currentTimeMillis() - since) / 1000).toInt()
            delay(250)
        }
    }
    fun listen() {
        if (voice.start()) {
            since = System.currentTimeMillis()
            seconds = 0
            recording = true
        } else {
            onSpoken(null)
        }
    }
    val askMic = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> if (granted) listen() }
    val speakable = !stopping && !hearing && draft.isBlank() && attachments.isEmpty() && !uploading
    if (attachments.isNotEmpty() || uploading) {
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(start = 14.dp, end = 14.dp, top = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            attachments.forEach { file ->
                Box {
                    val thumb = file.thumb
                    if (!file.picture) {
                        FileChip(file.name, Modifier.height(64.dp), end = 30.dp)
                    } else if (thumb != null) {
                        Image(thumb.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.size(64.dp).clip(RoundedCornerShape(12.dp)))
                    } else {
                        Box(modifier = Modifier.size(64.dp).clip(RoundedCornerShape(12.dp)).background(scheme.surfaceContainerHigh), contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.Image, "picture", tint = scheme.onSurfaceVariant)
                        }
                    }
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
        if (recording) {
            IconButton(onClick = { voice.cancel(); recording = false }) {
                Icon(Icons.Filled.Close, "drop the recording", tint = scheme.error)
            }
        } else Box {
            IconButton(onClick = { choosing = true }, enabled = enabled && !uploading && !hearing) {
                Icon(Icons.Filled.AttachFile, "attach", tint = scheme.onSurfaceVariant)
            }
            DropdownMenu(expanded = choosing, onDismissRequest = { choosing = false }) {
                DropdownMenuItem(
                    text = { Text("a picture") },
                    leadingIcon = { Icon(Icons.Filled.Image, null) },
                    onClick = { choosing = false; onPicture() },
                )
                DropdownMenuItem(
                    text = { Text("a file or pdf") },
                    leadingIcon = { Icon(Icons.Filled.Description, null) },
                    onClick = { choosing = false; onFile() },
                )
            }
        }
        OutlinedTextField(
            value = field,
            onValueChange = onChange,
            modifier = Modifier.weight(1f).focusRequester(focus),
            enabled = enabled && !recording && !hearing,
            placeholder = {
                Text(
                    when {
                        recording -> "listening · %d:%02d · ✓ sends it".format(seconds / 60, seconds % 60)
                        hearing -> "transcribing…"
                        else -> "say what to do"
                    },
                    color = if (recording) scheme.error else Color.Unspecified,
                )
            },
            maxLines = 6,
            shape = RoundedCornerShape(18.dp),
            textStyle = MaterialTheme.typography.bodyMedium,
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = scheme.primary, unfocusedBorderColor = scheme.outlineVariant),
        )
        when {
            recording -> IconButton(onClick = { recording = false; onSpoken(voice.finish()) }) {
                Icon(Icons.Filled.Check, "send what was said", tint = scheme.primary)
            }
            hearing -> Box(modifier = Modifier.size(48.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
            }
            speakable -> IconButton(
                onClick = {
                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) listen()
                    else askMic.launch(Manifest.permission.RECORD_AUDIO)
                },
                enabled = enabled,
            ) {
                Icon(Icons.Filled.Mic, "speak a prompt", tint = scheme.primary)
            }
            else -> IconButton(onClick = { if (stopping) onStop() else onSend() }, enabled = enabled && !uploading && (stopping || draft.isNotBlank() || attachments.isNotEmpty())) {
                Icon(
                    if (stopping) Icons.Filled.Stop else Icons.AutoMirrored.Filled.Send,
                    if (stopping) "stop" else "send",
                    tint = if (stopping) scheme.error else scheme.primary,
                )
            }
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
    closing: Map<String, Long>,
    closable: (CodeSession, CodeStatus?) -> Boolean,
    onClose: (CodeSession) -> Unit,
    onUndo: (String) -> Unit,
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
            items(sessions, key = { it.id }) { session ->
                val status = statuses[session.id]
                SessionRow(
                    session, status, session.id == currentId,
                    closingUntil = closing[session.id],
                    onClose = if (closable(session, status)) ({ onClose(session) }) else null,
                    onUndo = { onUndo(session.id) },
                ) { onPick(session) }
            }
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
    val screens by code.screens.collectAsStateWithLifecycle()
    val model by code.model.collectAsStateWithLifecycle()
    val live by code.live.collectAsStateWithLifecycle()
    var field by remember { mutableStateOf(code.draft.value.let { TextFieldValue(it, TextRange(it.length)) }) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        code.replaced.collect { text ->
            field = TextFieldValue(text, TextRange(text.length))
            if (text.isNotEmpty()) runCatching { focus.requestFocus() }
        }
    }
    val sessions by code.sessions.collectAsStateWithLifecycle()
    val projects by code.projects.collectAsStateWithLifecycle()
    val closing by code.closing.collectAsStateWithLifecycle()
    var picking by remember { mutableStateOf(false) }
    var tuning by remember { mutableStateOf(false) }
    var hearing by remember { mutableStateOf(false) }
    val settings by code.settings.collectAsStateWithLifecycle()
    val providers by code.providers.collectAsStateWithLifecycle()
    val directory = current?.directory ?: newIn
    val backend = current?.backend?.ifEmpty { null } ?: model?.backend ?: "claude"
    LaunchedEffect(Unit) { code.enter() }
    LaunchedEffect(backend, directory) {
        store.foreground.collectLatest { shown -> if (shown) code.watch(backend, directory) }
    }
    LaunchedEffect(Unit) {
        var away = false
        store.foreground.collectLatest { shown ->
            if (!shown) {
                away = true
                return@collectLatest
            }
            if (away) runCatching { code.refresh() }
            while (true) {
                delay(10_000)
                runCatching { code.refresh() }
            }
        }
    }
    val busy = current?.let { statuses[it.id]?.type == "busy" } ?: false
    val attachments by code.attachments.collectAsStateWithLifecycle()
    val uploading by code.uploading.collectAsStateWithLifecycle()
    val pendingAll by code.pending.collectAsStateWithLifecycle()
    val pendingHere = pendingAll.filter { it.sessionId == current?.id }
    val settled = current != null && !busy && pendingHere.isEmpty() && screens.isEmpty() && asks.isEmpty() && questions.isEmpty()
    val stops = remember(entries, settled) { stoppedTurns(entries, settled) }
    val squash by store.prefs.squashCalls.collectAsStateWithLifecycle()
    val shown = remember(entries, squash) { if (squash) squashCalls(entries) else null }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(8)) { uris -> code.attach(uris) }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> code.attach(uris) }
    val transcript = rememberLazyListState()
    var follow by remember(current?.id) { mutableStateOf(true) }
    LaunchedEffect(transcript) {
        snapshotFlow { Triple(transcript.isScrollInProgress, transcript.firstVisibleItemIndex, transcript.firstVisibleItemScrollOffset) }
            .collect { (scrolling, index, offset) -> if (scrolling) follow = index == 0 && offset < 120 }
    }
    val newest = listOf(entries.size, pendingHere.size, questions.size, asks.size, if (busy) 1 else 0, entries.lastOrNull()?.parts?.size ?: 0, screens.firstOrNull()?.id.hashCode(), stops.chips.keys.hashCode())
    LaunchedEffect(current?.id, newest) {
        if (follow && (transcript.firstVisibleItemIndex != 0 || transcript.firstVisibleItemScrollOffset != 0)) transcript.scrollToItem(0)
    }
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("code", reachable, onCollapse)
        Banner(reachable)
        val tunable = backend == "claude"
        SessionBar(current, chipText(model, settings, tunable), onRename = { code.rename(it) }, onPick = { picking = true }, onModel = { tuning = true })
        LazyColumn(
            state = transcript,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            reverseLayout = true,
            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(screens, key = { "x" + it.id }) { ask -> ScreenCard(ask) { key, text -> code.press(ask, key, text) } }
            items(questions, key = { "q" + it.id }) { ask -> QuestionCard(ask, onAnswer = { code.answer(ask, it) }, onReject = { code.rejectQuestion(ask) }) }
            items(asks, key = { "p" + it.id }) { ask -> PermissionCard(ask) { code.allow(ask, it) } }
            items(pendingHere.asReversed(), key = { "s" + it.id }) { PendingBubble(it.text, busy) }
            if (busy) item(key = "busy") { Label("working…", color = scheme.primary) }
            val onResend: (String) -> Unit = { follow = true; code.resend(it) }
            if (shown != null) {
                items(shown.asReversed(), key = { it.key }) { item ->
                    when (item) {
                        is ShownEntry -> EntryView(item.entry, scheme, stops, onEdit = { code.edit(it) }, onResend = onResend, parts = item.parts, tail = item.tail)
                        is ShownCalls -> CallsView(item)
                    }
                }
            } else {
                items(entries.asReversed(), key = { it.info.id }) { entry ->
                    EntryView(entry, scheme, stops, onEdit = { code.edit(it) }, onResend = onResend)
                }
            }
            if (entries.isEmpty()) {
                item(key = "empty") {
                    Label(if (current == null) "new session in ${folderOf(newIn)}" else "nothing here yet")
                }
            }
        }
        Notice(store, Modifier.padding(horizontal = 14.dp))
        Composer(
            field, focus, busy, reachable, attachments, uploading,
            onChange = { field = it; code.draft.value = it.text },
            onSend = { follow = true; code.send(field.text) },
            onStop = { code.stop() },
            onPicture = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
            onFile = { files.launch(arrayOf("*/*")) },
            onDetach = { code.detach(it) },
            hearing = hearing,
            onSpoken = { audio ->
                if (audio == null) {
                    store.report(IllegalStateException("nothing recorded; hold on a little longer"))
                } else {
                    hearing = true
                    store.act {
                        try {
                            val text = store.bridge.transcribe(audio).text
                            if (text.isBlank()) throw IllegalStateException("heard nothing")
                            follow = true
                            code.send(text)
                        } finally {
                            hearing = false
                            audio.delete()
                        }
                    }
                }
            },
        )
    }
    if (tuning) {
        val models = remember(providers, current?.backend, current?.live != null, settings.providerID) { code.modelChoices() }
        TuneSheet(
            models, model, settings, tunable = backend == "claude",
            desk = current?.live?.let { it.name ?: "an open session" },
            onModel = { code.pickModel(it) },
            onEffort = { code.pickEffort(it) },
            onMode = { code.pickMode(it) },
            onDismiss = { tuning = false },
        )
    }
    if (picking) {
        SessionSheet(
            sessions, projects, statuses, current?.id,
            closing = closing,
            closable = code::closable,
            onClose = { code.close(it) },
            onUndo = { code.undoClose(it) },
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
    val closing by store.code.closing.collectAsStateWithLifecycle()
    val closed by store.code.closed.collectAsStateWithLifecycle()
    var query by rememberSaveable { mutableStateOf("") }
    var showClosed by remember { mutableStateOf(false) }
    var found by remember { mutableStateOf<List<CodeSession>?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(query, closed) {
        if (query.isNotBlank()) delay(350)
        try {
            found = store.code.find(query.trim())
            failed = false
        } catch (err: CancellationException) {
            throw err
        } catch (err: Exception) {
            failed = true
        }
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
        val shown = if (showClosed) list else list?.filter { active(it, statuses[it.id]) }
        val hidden = (list?.size ?: 0) - (shown?.size ?: 0)
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 14.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Label(
                when {
                    failed -> "the desktop did not answer"
                    shown == null -> "searching"
                    query.isBlank() -> "${shown.size} ${if (showClosed) "sessions" else "open"} · latest activity first"
                    else -> "${shown.size} mention it · latest activity first"
                },
                modifier = Modifier.weight(1f),
            )
            if (showClosed || hidden > 0) {
                Chip(if (showClosed) "hide closed" else "+$hidden closed", scheme.surfaceContainerHigh, scheme.onSurface) { showClosed = !showClosed }
            }
        }
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(start = 10.dp, end = 10.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            items(shown ?: emptyList(), key = { it.id }) { session ->
                val status = statuses[session.id]
                SessionRow(
                    session, status,
                    closingUntil = closing[session.id],
                    onClose = if (store.code.closable(session, status)) ({ store.code.close(session) }) else null,
                    onUndo = { store.code.undoClose(session.id) },
                ) {
                    store.code.open(session)
                    onOpenSession()
                }
            }
        }
    }
}
