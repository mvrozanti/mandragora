package ac.mvr.phone.ui

import ac.mvr.phone.R
import ac.mvr.phone.logic.Maker
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

private class Mark(val icon: Int, val brand: Color?)

private val MARKS = mapOf(
    Maker.CLAUDE to Mark(R.drawable.mark_claude, Color(0xFFD97757)),
    Maker.DEEPSEEK to Mark(R.drawable.mark_deepseek, Color(0xFF4D6BFE)),
    Maker.QWEN to Mark(R.drawable.mark_qwen, Color(0xFF615CED)),
    Maker.OPENAI to Mark(R.drawable.mark_openai, null),
    Maker.OLLAMA to Mark(R.drawable.mark_ollama, null),
    Maker.OPENCODE to Mark(R.drawable.mark_opencode, null),
)

fun brandOf(maker: Maker?): Color? = maker?.let { MARKS[it]?.brand }

@Composable
fun MakerMark(maker: Maker?, size: Dp = 18.dp, tint: Color? = null) {
    val mark = maker?.let { MARKS[it] }
    if (mark == null) {
        Spacer(Modifier.size(size))
        return
    }
    Icon(
        painterResource(mark.icon),
        contentDescription = maker.name.lowercase(),
        tint = tint ?: mark.brand ?: MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.size(size),
    )
}
