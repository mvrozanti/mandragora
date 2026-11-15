package ac.mvr.phone.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import ac.mvr.phone.state.Store
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun HomeScreen(store: Store, onOpen: (String) -> Unit) {
    val reachable by store.reachable.collectAsStateWithLifecycle()
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("mandragora", style = MaterialTheme.typography.titleLarge)
            Reachability(reachable)
        }
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            UpdateCard(store)
            MusicCard(store, onOpen)
            MoneyCard(store, onOpen)
            HubCard(store, onOpen)
            CodeCard(store, onOpen)
            PanicCard(store, onOpen)
        }
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}
