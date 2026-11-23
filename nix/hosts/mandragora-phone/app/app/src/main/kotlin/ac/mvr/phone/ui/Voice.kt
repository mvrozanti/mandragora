package ac.mvr.phone.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import ac.mvr.phone.net.SttStatus
import ac.mvr.phone.state.Store
import ac.mvr.phone.state.Transcript
import ac.mvr.phone.state.VoicePhase
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import java.util.Locale

private fun statusLine(status: SttStatus?): String {
    if (status == null) return "stt unreachable"
    val holder = status.holder?.name
    val model = if (status.loaded) "model warm" else "model cold"
    return if (holder != null) "$model · gpu held by $holder" else model
}

private fun Transcript.caption(): String {
    val parts = ArrayList<String>()
    if (task == "translate") parts.add("$language → en") else if (language.isNotEmpty()) parts.add("$language ${(probability * 100).toInt()}%")
    if (duration > 0) parts.add("%.1f s in %.1f s".format(Locale.ROOT, duration, elapsed))
    parts.add(origin)
    return parts.joinToString(" · ")
}

@Composable
private fun Toggle(text: String, selected: Boolean, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (selected) scheme.primaryContainer else scheme.surfaceContainerHigh)
            .clickable(onClick = onTap)
            .padding(horizontal = 12.dp, vertical = 7.dp),
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge, color = if (selected) scheme.onPrimaryContainer else scheme.onSurfaceVariant)
    }
}

@Composable
private fun SmallChip(text: String, tone: Color, onTone: Color, onTap: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(tone)
            .clickable(onClick = onTap)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge, color = onTone)
    }
}

@Composable
private fun MicButton(phase: VoicePhase, size: Int, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val recording = phase == VoicePhase.RECORDING
    Box(
        modifier = Modifier
            .size(size.dp)
            .clip(CircleShape)
            .background(if (recording) scheme.error else scheme.primary)
            .clickable(enabled = phase != VoicePhase.SENDING, onClick = onTap),
        contentAlignment = Alignment.Center,
    ) {
        when (phase) {
            VoicePhase.SENDING -> CircularProgressIndicator(color = scheme.onPrimary, strokeWidth = 2.dp, modifier = Modifier.size((size / 3).dp))
            VoicePhase.RECORDING -> Icon(Icons.Filled.Stop, "stop and transcribe", tint = scheme.onError, modifier = Modifier.size((size / 2.5).dp))
            VoicePhase.IDLE -> Icon(Icons.Filled.Mic, "record", tint = scheme.onPrimary, modifier = Modifier.size((size / 2.5).dp))
        }
    }
}

@Composable
private fun rememberMicTap(store: Store): () -> Unit {
    val context = LocalContext.current
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) store.voice.record() else store.report(IllegalStateException("the microphone permission was refused"))
    }
    return {
        when (store.voice.phase.value) {
            VoicePhase.RECORDING -> store.voice.stop()
            VoicePhase.SENDING -> Unit
            VoicePhase.IDLE ->
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) store.voice.record()
                else ask.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
}

@Composable
private fun Elapsed(phase: VoicePhase, startedAt: Long) {
    var now by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    LaunchedEffect(phase) {
        while (phase == VoicePhase.RECORDING) {
            now = SystemClock.elapsedRealtime()
            delay(250)
        }
    }
    val text = when (phase) {
        VoicePhase.RECORDING -> {
            val seconds = ((now - startedAt) / 1000).coerceAtLeast(0)
            "recording · %d:%02d · tap to send".format(Locale.ROOT, seconds / 60, seconds % 60)
        }
        VoicePhase.SENDING -> "transcribing on the desktop"
        VoicePhase.IDLE -> "tap to record"
    }
    Label(text, color = if (phase == VoicePhase.RECORDING) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.outline)
}

@Composable
fun VoiceCard(store: Store, onOpen: (String) -> Unit) {
    val phase by store.voice.phase.collectAsStateWithLifecycle()
    val startedAt by store.voice.startedAt.collectAsStateWithLifecycle()
    val status by store.voice.status.collectAsStateWithLifecycle()
    val history by store.voice.history.collectAsStateWithLifecycle()
    val tap = rememberMicTap(store)
    HomeCard {
        CardHeader("voice", statusLine(status)) { onOpen("voice") }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            MicButton(phase, 52, tap)
            Column(modifier = Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).clickable { onOpen("voice") }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Elapsed(phase, startedAt)
                val last = history.firstOrNull()
                if (last != null) Text(last.text, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun TranscriptRow(entry: Transcript, onForget: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(scheme.surfaceContainerLow).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Label(entry.caption())
        SelectionContainer { Text(entry.text, style = ReplyBody, color = scheme.onSurface) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SmallChip("copy", scheme.secondaryContainer, scheme.onSecondaryContainer) {
                clipboard.setText(AnnotatedString(entry.text))
            }
            SmallChip("share", scheme.surfaceContainerHigh, scheme.onSurface) {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, entry.text)
                runCatching { context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            }
            SmallChip("forget", scheme.surfaceContainerHigh, scheme.onSurfaceVariant, onForget)
        }
    }
}

@Composable
fun VoiceScreen(store: Store, onCollapse: () -> Unit) {
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val phase by store.voice.phase.collectAsStateWithLifecycle()
    val startedAt by store.voice.startedAt.collectAsStateWithLifecycle()
    val status by store.voice.status.collectAsStateWithLifecycle()
    val history by store.voice.history.collectAsStateWithLifecycle()
    val task by store.prefs.voiceTask.collectAsStateWithLifecycle()
    val lang by store.prefs.voiceLang.collectAsStateWithLifecycle()
    val tap = rememberMicTap(store)
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> uri?.let { store.voice.transcribeShared(it) } }
    LaunchedEffect(Unit) {
        while (true) {
            store.foreground.first { it }
            runCatching { store.voice.refresh() }
            delay(10_000)
        }
    }
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("voice", reachable, onCollapse)
        Banner(reachable)
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(start = 14.dp, end = 14.dp, top = 2.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(MaterialTheme.colorScheme.surfaceContainerLow).padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Label(statusLine(status))
                        if (status?.loaded == false) {
                            SmallChip("warm up", MaterialTheme.colorScheme.surfaceContainerHigh, MaterialTheme.colorScheme.onSurface) { store.voice.warmup() }
                        }
                    }
                    MicButton(phase, 96, tap)
                    Elapsed(phase, startedAt)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Toggle("as said", task == "transcribe") { store.prefs.setVoiceTask("transcribe") }
                        Toggle("to english", task == "translate") { store.prefs.setVoiceTask("translate") }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Toggle("auto", lang.isBlank()) { store.prefs.setVoiceLang("") }
                        Toggle("pt", lang == "pt") { store.prefs.setVoiceLang("pt") }
                        Toggle("en", lang == "en") { store.prefs.setVoiceLang("en") }
                        Toggle("a file", false) { if (phase == VoicePhase.IDLE) pick.launch("audio/*") }
                    }
                }
            }
            if (history.isEmpty()) item { Label("record, pick a file, or share audio to mandragora", modifier = Modifier.padding(start = 6.dp, top = 6.dp)) }
            items(history, key = { it.id }) { entry -> TranscriptRow(entry) { store.voice.forget(entry.id) } }
        }
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}
