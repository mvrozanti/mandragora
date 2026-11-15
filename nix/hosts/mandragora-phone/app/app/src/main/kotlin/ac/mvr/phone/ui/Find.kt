package ac.mvr.phone.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.MpdSong
import ac.mvr.phone.state.Store
import ac.mvr.phone.state.fmtTime
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FindSheet(store: Store, onDismiss: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val now by store.now.collectAsStateWithLifecycle()
    val names by store.localNames.collectAsStateWithLifecycle()
    var query by remember { mutableStateOf("") }
    var songs by remember { mutableStateOf<List<MpdSong>>(emptyList()) }
    var hint by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }

    LaunchedEffect(Unit) { store.refreshLocalNamesAsync() }
    LaunchedEffect(query) {
        val term = query.trim()
        if (term.isNotEmpty()) delay(250)
        runCatching { if (term.isEmpty()) store.recent() else store.find(term) }
            .onSuccess { songs = it; hint = if (term.isEmpty()) "newest first · ${it.size} songs" else "${it.size} songs" }
            .onFailure { songs = emptyList(); hint = "desktop unreachable" }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = scheme.surfaceContainerLow,
        contentColor = scheme.onSurface,
    ) {
        LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
        Column(modifier = Modifier.fillMaxHeight(0.92f)) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("play something…", style = MaterialTheme.typography.bodyLarge) },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge,
                shape = RoundedCornerShape(24.dp),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = scheme.primary,
                    unfocusedBorderColor = scheme.outlineVariant,
                    focusedContainerColor = scheme.surface,
                    unfocusedContainerColor = scheme.surface,
                ),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).focusRequester(focus),
            )
            Label(hint, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
            LazyColumn(modifier = Modifier.fillMaxWidth()) {
                items(songs, key = { it.file }) { song ->
                    val dim = now.phoneOwns && song.file.substringAfterLast('/') !in names
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = !dim) { store.playSong(song); onDismiss() }
                            .padding(horizontal = 20.dp, vertical = 10.dp)
                            .alpha(if (dim) 0.35f else 1f),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(song.name, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(listOfNotNull(song.artist ?: "unknown artist", "not on the phone yet".takeIf { dim }).joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = scheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Text(song.duration?.let(::fmtTime) ?: "", style = MaterialTheme.typography.labelMedium, color = scheme.outline)
                    }
                }
            }
        }
    }
}
