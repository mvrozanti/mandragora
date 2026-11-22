package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ac.mvr.phone.logic.auditLine
import ac.mvr.phone.logic.failing
import ac.mvr.phone.net.HostCheck
import ac.mvr.phone.state.Store
import kotlinx.coroutines.launch

@Composable
fun AuditLine(store: Store, onOpen: (String) -> Unit) {
    val checks by store.audit.checks.collectAsStateWithLifecycle()
    val line = auditLine(checks) ?: return
    val only = failing(checks).singleOrNull()?.takeIf { it.fix != null }
    val context = LocalContext.current
    val scheme = MaterialTheme.colorScheme
    val tint = scheme.onErrorContainer
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(scheme.errorContainer)
            .clickable { if (only != null) store.audit.fix(context, only) else onOpen("settings") }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Warning, null, tint = tint, modifier = Modifier.size(22.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text("this phone", style = MaterialTheme.typography.titleSmall, color = tint)
            Text(line, style = MaterialTheme.typography.labelSmall, color = tint.copy(alpha = 0.8f), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Icon(Icons.Filled.ChevronRight, null, tint = tint, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun CheckDot(ok: Boolean?) {
    val scheme = MaterialTheme.colorScheme
    val tone = when (ok) {
        true -> Color(0xFF4EC17D)
        false -> scheme.error
        null -> scheme.outlineVariant
    }
    Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(tone))
}

@Composable
private fun CheckRow(check: HostCheck, onFix: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val fixable = check.ok != true && check.fix != null
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable(enabled = fixable, onClick = onFix).padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CheckDot(check.ok)
        Column(modifier = Modifier.weight(1f)) {
            Text(check.label, style = MaterialTheme.typography.bodyLarge, color = if (check.ok == false) scheme.error else scheme.onSurface)
            if (check.ok != true && check.detail.isNotEmpty()) Text(check.detail, style = MaterialTheme.typography.bodySmall, color = scheme.outline)
        }
        if (fixable) Icon(Icons.Filled.ChevronRight, null, tint = scheme.outline, modifier = Modifier.size(20.dp))
    }
}

@Composable
fun AuditSection(store: Store) {
    val checks by store.audit.checks.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scheme = MaterialTheme.colorScheme
    LifecycleResumeEffect(Unit) {
        store.scope.launch { runCatching { store.audit.refresh() } }
        onPauseOrDispose { }
    }
    val off = failing(checks).size
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(scheme.surfaceContainerLow).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Label(
            when {
                checks.isEmpty() -> "this phone · checking"
                off == 0 -> "this phone · everything in place"
                else -> "this phone · $off off"
            },
            color = if (off > 0) scheme.error else scheme.outline,
        )
        checks.forEach { check -> CheckRow(check) { store.audit.fix(context, check) } }
        Label("the desktop reads this too: mandragora-audit, phone-host")
    }
}
