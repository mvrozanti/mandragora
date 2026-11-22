package ac.mvr.phone.ui

import ac.mvr.phone.logic.choiceOf
import ac.mvr.phone.logic.nextLabel
import ac.mvr.phone.logic.stepLabel
import ac.mvr.phone.logic.toggled
import ac.mvr.phone.net.QuestionAsk
import ac.mvr.phone.net.ScreenAsk
import ac.mvr.phone.net.ScreenOption
import ac.mvr.phone.net.ScreenStep
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

private const val CONTEXT_LINES = 12

@Composable
private fun Steps(steps: List<ScreenStep>, at: Int) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        steps.forEachIndexed { index, step ->
            val here = index == at
            val shape = RoundedCornerShape(999.dp)
            Row(
                modifier = Modifier
                    .clip(shape)
                    .background(if (here) scheme.secondaryContainer else Color.Transparent)
                    .border(1.dp, if (here) Color.Transparent else scheme.outlineVariant, shape)
                    .padding(horizontal = 10.dp, vertical = 5.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (step.done) Icon(Icons.Filled.Check, null, tint = scheme.primary, modifier = Modifier.size(14.dp))
                Text(
                    stepLabel(step.label, index, steps.size),
                    style = MaterialTheme.typography.labelMedium,
                    color = if (here) scheme.onSecondaryContainer else scheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun Context(text: String, code: Boolean) {
    val scheme = MaterialTheme.colorScheme
    if (!code) {
        Text(text, style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
        return
    }
    var open by remember(text) { mutableStateOf(false) }
    val long = text.lines().size > CONTEXT_LINES
    Text(
        text,
        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
        color = scheme.onSurface,
        maxLines = if (open || !long) Int.MAX_VALUE else CONTEXT_LINES,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(scheme.surfaceContainer)
            .clickable(enabled = long) { open = !open }
            .padding(10.dp),
    )
}

private fun leadOf(option: ScreenOption): Lead = when {
    option.checked == true -> Lead.CHECKED
    option.text -> Lead.WRITE
    option.checked == false -> Lead.UNCHECKED
    else -> Lead.NONE
}

private fun leadOf(single: Boolean, multiple: Boolean, chosen: Boolean): Lead = when {
    single -> Lead.NONE
    multiple -> if (chosen) Lead.CHECKED else Lead.UNCHECKED
    else -> if (chosen) Lead.PICKED else Lead.UNPICKED
}

@Composable
private fun ScreenActions(ask: ScreenAsk, onPress: (String, String?) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Actions {
        ask.options.filter { it.aside }.forEach { aside -> Quiet(aside.label.lowercase()) { onPress(aside.key, null) } }
        Quiet("cancel") { onPress("escape", null) }
        if (ask.tabs) {
            val back = ask.step != 0
            IconButton(onClick = { onPress("previous", null) }, enabled = back) {
                Icon(Icons.Filled.ChevronLeft, "back", tint = if (back) scheme.onSurfaceVariant else scheme.outlineVariant)
            }
            nextLabel(ask.step, ask.steps.size)?.let { Forward(it) { onPress("next", null) } }
        }
    }
}

@Composable
private fun Heading(ask: ScreenAsk) {
    val scheme = MaterialTheme.colorScheme
    val structured = ask.title.isNotBlank()
    if (!structured && ask.waiting.isNotBlank()) Label(ask.waiting, color = scheme.tertiary)
    val context = if (structured) ask.context else ask.body
    val code = !structured || ask.steps.isEmpty()
    if (code && context.isNotBlank()) Context(context, code = true)
    if (structured) Text(ask.title, style = MaterialTheme.typography.titleMedium, color = scheme.onSurface, modifier = Modifier.padding(vertical = 4.dp))
    if (!code && context.isNotBlank()) Context(context, code = false)
}

@Composable
fun ScreenCard(ask: ScreenAsk, onPress: (String, String?) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var typing by remember(ask.id) { mutableStateOf<String?>(null) }
    ChoiceCard {
        if (ask.steps.isNotEmpty()) Steps(ask.steps, ask.step)
        ask.plan?.let { MarkdownText(it, scheme) }
        Heading(ask)
        ask.options.filterNot { it.aside }.forEach { option ->
            if (typing == option.key) {
                OwnAnswer { onPress(option.key, it) }
            } else {
                val choice = choiceOf(option.label)
                ChoiceRow(choice.label, option.detail, leadOf(option), choice.recommended) {
                    if (option.text) typing = option.key else onPress(option.key, null)
                }
            }
        }
        ScreenActions(ask, onPress)
    }
}

@Composable
fun QuestionCard(ask: QuestionAsk, onAnswer: (List<List<String>>) -> Unit, onReject: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var picks by remember(ask.id) { mutableStateOf<Map<Int, List<String>>>(emptyMap()) }
    val single = ask.questions.size == 1 && !ask.questions[0].multiple
    ChoiceCard {
        ask.questions.forEachIndexed { index, question ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (question.header.isNotBlank()) Label(question.header, color = scheme.tertiary)
                Text(question.question, style = MaterialTheme.typography.titleMedium, color = scheme.onSurface)
                question.options.forEach { option ->
                    val now = picks[index] ?: emptyList()
                    val choice = choiceOf(option.label)
                    ChoiceRow(choice.label, option.description, leadOf(single, question.multiple, option.label in now), choice.recommended) {
                        if (single) onAnswer(listOf(listOf(option.label))) else picks = picks + (index to toggled(now, option.label, question.multiple))
                    }
                }
            }
        }
        Actions {
            Quiet("skip") { onReject() }
            if (!single) {
                val complete = ask.questions.indices.all { !picks[it].isNullOrEmpty() }
                Forward("answer", enabled = complete) { onAnswer(ask.questions.indices.map { picks[it] ?: emptyList() }) }
            }
        }
    }
}
