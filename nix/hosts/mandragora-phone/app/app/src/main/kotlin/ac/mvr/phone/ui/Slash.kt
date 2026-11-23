package ac.mvr.phone.ui

import ac.mvr.phone.net.CodeCommand
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
fun SlashMenu(matches: List<CodeCommand>, looking: Boolean, onPick: (CodeCommand) -> Unit) {
    if (matches.isEmpty() && !looking) return
    val scheme = MaterialTheme.colorScheme
    val frame = Modifier
        .fillMaxWidth()
        .padding(start = 10.dp, end = 10.dp, top = 6.dp)
        .clip(RoundedCornerShape(20.dp))
        .background(scheme.surfaceContainer)
    if (matches.isEmpty()) {
        Text(
            "looking up commands and skills…",
            style = MaterialTheme.typography.bodySmall,
            color = scheme.onSurfaceVariant,
            modifier = frame.padding(horizontal = 16.dp, vertical = 12.dp),
        )
        return
    }
    LazyColumn(modifier = frame.heightIn(max = 264.dp), reverseLayout = true) {
        items(matches, key = { it.name }) { command -> SlashRow(command) { onPick(command) } }
    }
}

@Composable
private fun SlashRow(command: CodeCommand, onTap: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Column(modifier = Modifier.fillMaxWidth().clickable(onClick = onTap).padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "/" + command.name,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = scheme.primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            if (command.argumentHint.isNotEmpty()) {
                Text(
                    command.argumentHint,
                    style = MaterialTheme.typography.labelSmall,
                    color = scheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
        }
        if (command.description.isNotEmpty()) {
            Text(
                command.description,
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
