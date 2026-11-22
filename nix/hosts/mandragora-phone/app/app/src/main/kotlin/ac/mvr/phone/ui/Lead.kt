package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp

internal enum class Lead(val icon: ImageVector?, val on: Boolean) {
    NONE(null, false),
    CHECKED(Icons.Filled.CheckBox, true),
    UNCHECKED(Icons.Filled.CheckBoxOutlineBlank, false),
    PICKED(Icons.Filled.RadioButtonChecked, true),
    UNPICKED(Icons.Filled.RadioButtonUnchecked, false),
    WRITE(Icons.Filled.Edit, false),
}

@Composable
internal fun ChoiceCard(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) { content() }
}

@Composable
internal fun ChoiceRow(label: String, detail: String, lead: Lead, recommended: Boolean, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(14.dp)
    val edge = if (lead.on) scheme.primary else if (recommended) scheme.primary.copy(alpha = 0.35f) else Color.Transparent
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(shape)
            .background(if (lead.on) scheme.primary.copy(alpha = 0.14f) else scheme.surfaceContainer)
            .border(1.dp, edge, shape)
            .clickable(onClick = onTap)
            .padding(horizontal = 14.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        lead.icon?.let { Icon(it, null, tint = if (lead.on) scheme.primary else scheme.outline, modifier = Modifier.size(22.dp)) }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(label, style = MaterialTheme.typography.bodyLarge, color = scheme.onSurface, modifier = Modifier.weight(1f, fill = false))
                if (recommended) Pill("recommended")
            }
            if (detail.isNotBlank()) Text(detail, style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Pill(text: String) {
    val scheme = MaterialTheme.colorScheme
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = scheme.primary,
        modifier = Modifier.clip(RoundedCornerShape(999.dp)).background(scheme.primary.copy(alpha = 0.14f)).padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

@Composable
internal fun OwnAnswer(onSend: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var said by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val ready = said.isNotBlank()
    OutlinedTextField(
        value = said,
        onValueChange = { said = it },
        modifier = Modifier.fillMaxWidth().focusRequester(focus),
        placeholder = { Text("your answer", color = scheme.outline) },
        shape = RoundedCornerShape(14.dp),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
        keyboardActions = KeyboardActions(onSend = { if (ready) onSend(said.trim()) }),
        trailingIcon = {
            IconButton(onClick = { onSend(said.trim()) }, enabled = ready) {
                Icon(Icons.AutoMirrored.Filled.Send, "send", tint = if (ready) scheme.primary else scheme.outline)
            }
        },
        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = scheme.primary, unfocusedBorderColor = scheme.outlineVariant),
    )
}

@Composable
internal fun Quiet(text: String, onTap: () -> Unit) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.clip(RoundedCornerShape(999.dp)).clickable(onClick = onTap).padding(horizontal = 12.dp, vertical = 10.dp),
    )
}

@Composable
internal fun Forward(text: String, enabled: Boolean = true, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = scheme.onPrimary,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (enabled) scheme.primary else scheme.primary.copy(alpha = 0.4f))
            .clickable(enabled = enabled, onClick = onTap)
            .padding(horizontal = 18.dp, vertical = 10.dp),
    )
}

@Composable
internal fun Actions(content: @Composable () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.End),
        verticalAlignment = Alignment.CenterVertically,
    ) { content() }
}
