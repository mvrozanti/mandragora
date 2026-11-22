package ac.mvr.phone.ui

import ac.mvr.phone.logic.Pin
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
fun ChatChip(text: String, tone: Color, onTone: Color, enabled: Boolean = true, onTap: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (enabled) tone else tone.copy(alpha = 0.4f))
            .clickable(enabled = enabled, onClick = onTap)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge, color = onTone, maxLines = 1)
    }
}

@Composable
fun ChatUser(text: String) {
    val scheme = MaterialTheme.colorScheme
    Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End) {
        Box(modifier = Modifier.clip(RoundedCornerShape(18.dp)).background(scheme.surfaceContainerHigh).padding(horizontal = 14.dp, vertical = 10.dp)) {
            Text(text, style = MaterialTheme.typography.bodyLarge, color = scheme.onSurface)
        }
    }
}

@Composable
fun ChatReply(text: String, thinking: String? = null) {
    val scheme = MaterialTheme.colorScheme
    var open by rememberSaveable(text.hashCode()) { mutableStateOf(false) }
    Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (!thinking.isNullOrBlank()) {
            Text(
                if (open) thinking else "thought · tap to read",
                style = MaterialTheme.typography.bodySmall,
                color = scheme.outline,
                maxLines = if (open) Int.MAX_VALUE else 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.clickable { open = !open },
            )
        }
        MarkdownText(text, scheme)
    }
}

@Composable
fun ChatNote(text: String, error: Boolean = false, mono: Boolean = false) {
    val scheme = MaterialTheme.colorScheme
    var open by rememberSaveable(text.hashCode()) { mutableStateOf(false) }
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        fontFamily = if (mono) FontFamily.Monospace else null,
        color = if (error) scheme.error else scheme.onSurfaceVariant,
        maxLines = if (open) Int.MAX_VALUE else 6,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(scheme.surfaceContainerLow)
            .clickable { open = !open }
            .padding(horizontal = 12.dp, vertical = 8.dp),
    )
}

@Composable
fun ChatSystem(text: String) {
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(scheme.surfaceContainerLow)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        MarkdownText(text, scheme)
    }
}

@Composable
fun FollowBottom(list: LazyListState, count: Int) {
    LaunchedEffect(count) {
        if (count > 0) list.animateScrollToItem(count - 1)
    }
}

private val LazyListState.roof: Int get() = layoutInfo.viewportEndOffset - layoutInfo.afterContentPadding

fun LazyListState.showsWhole(key: Any): Boolean {
    val item = layoutInfo.visibleItemsInfo.firstOrNull { it.key == key } ?: return false
    return item.offset + item.size <= roof
}

suspend fun LazyListState.pinTop(pin: Pin) {
    scrollToItem(0)
    if (showsWhole(pin.key)) return
    scrollToItem(pin.index)
    val item = layoutInfo.visibleItemsInfo.firstOrNull { it.key == pin.key } ?: return
    scrollBy((item.offset + item.size - roof).toFloat())
}
