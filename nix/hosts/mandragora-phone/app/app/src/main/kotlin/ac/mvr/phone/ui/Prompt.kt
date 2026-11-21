package ac.mvr.phone.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun PromptBar(
    value: String,
    onChange: (String) -> Unit,
    onSend: () -> Unit,
    placeholder: String,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onStop: (() -> Unit)? = null,
    leading: (@Composable () -> Unit)? = null,
) {
    val scheme = MaterialTheme.colorScheme
    val stopping = onStop != null && value.isBlank()
    Row(
        modifier = modifier.fillMaxWidth().padding(start = 4.dp, end = 6.dp, top = 6.dp, bottom = 8.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        if (leading != null) leading() else Row(modifier = Modifier.padding(start = 10.dp)) {}
        OutlinedTextField(
            value = value,
            onValueChange = onChange,
            modifier = Modifier.weight(1f),
            enabled = enabled,
            placeholder = { Text(placeholder) },
            maxLines = 6,
            shape = RoundedCornerShape(18.dp),
            textStyle = MaterialTheme.typography.bodyMedium,
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = scheme.primary, unfocusedBorderColor = scheme.outlineVariant),
        )
        IconButton(onClick = { if (stopping) onStop?.invoke() else onSend() }, enabled = enabled && (stopping || value.isNotBlank())) {
            Icon(
                if (stopping) Icons.Filled.Stop else Icons.AutoMirrored.Filled.Send,
                if (stopping) "stop" else "send",
                tint = if (stopping) scheme.error else scheme.primary,
            )
        }
    }
}
