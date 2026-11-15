package ac.mvr.phone.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import ac.mvr.phone.net.MpdSong
import ac.mvr.phone.state.Facet
import ac.mvr.phone.state.Finder
import ac.mvr.phone.state.Match
import ac.mvr.phone.state.Store
import ac.mvr.phone.state.fmtTime
import androidx.lifecycle.compose.collectAsStateWithLifecycle

private fun highlight(text: String, term: String, color: Color): AnnotatedString {
    val at = if (term.isEmpty()) -1 else text.lowercase().indexOf(term.lowercase())
    if (at < 0) return AnnotatedString(text)
    return buildAnnotatedString {
        append(text.substring(0, at))
        withStyle(SpanStyle(color = color, fontWeight = FontWeight.Medium)) { append(text.substring(at, at + term.length)) }
        append(text.substring(at + term.length))
    }
}

@Composable
fun FindScreen(store: Store, onCollapse: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val now by store.now.collectAsStateWithLifecycle()
    val reachable by store.reachable.collectAsStateWithLifecycle()
    val names by store.localNames.collectAsStateWithLifecycle()
    val library by store.find.library.collectAsStateWithLifecycle()
    val fresh by store.find.fresh.collectAsStateWithLifecycle()
    var query by rememberSaveable { mutableStateOf("") }
    var sort by rememberSaveable { mutableStateOf("newest") }
    var drillKey by rememberSaveable { mutableStateOf("") }
    var drillValue by rememberSaveable { mutableStateOf("") }
    var allArtists by rememberSaveable { mutableStateOf(false) }
    var allAlbums by rememberSaveable { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        store.refreshLocalNamesAsync()
        runCatching { focus.requestFocus() }
        loading = true
        runCatching { store.find.refresh() }
        loading = false
    }

    val term = query.trim().split(Regex("\\s+")).firstOrNull { it.isNotEmpty() } ?: ""
    val matched = remember(library, query, sort) { Finder.search(library, query, sort) }
    val drilled = remember(matched, drillKey, drillValue) {
        when (drillKey) {
            "artist" -> matched.filter { it.song.artist == drillValue }
            "album" -> matched.filter { it.song.album == drillValue }
            else -> matched
        }
    }
    val artists = remember(drilled, term, drillKey) {
        if (drillKey.isNotEmpty()) emptyList() else Finder.facets(if (term.isEmpty()) drilled else drilled.filter { (it.song.artist ?: "").contains(term, ignoreCase = true) }) { it.artist }
    }
    val albums = remember(drilled, term, drillKey) {
        if (drillKey == "album") emptyList() else Finder.facets(if (term.isEmpty()) drilled else drilled.filter { (it.song.album ?: "").contains(term, ignoreCase = true) || (it.song.artist ?: "").contains(term, ignoreCase = true) }) { it.album }
    }
    val artistsShown = if (allArtists) artists else artists.take(if (term.isEmpty()) 4 else 3)
    val albumsShown = if (allAlbums) albums else albums.take(if (term.isEmpty()) 4 else 3)

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader("find", reachable, onCollapse)
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text("artist, album, song, genre, year…", style = MaterialTheme.typography.bodyLarge) },
            leadingIcon = { Icon(Icons.Filled.Search, null, tint = scheme.outline) },
            trailingIcon = {
                if (query.isNotEmpty()) Icon(Icons.Filled.Close, "clear", tint = scheme.outline, modifier = Modifier.clickable { query = ""; drillKey = ""; drillValue = "" })
            },
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
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp).focusRequester(focus),
        )
        if (drillKey.isNotEmpty()) {
            Row(modifier = Modifier.padding(horizontal = 18.dp, vertical = 6.dp)) {
                Row(
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(scheme.surfaceContainerHigh).clickable { drillKey = ""; drillValue = "" }.padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("$drillKey: $drillValue", style = MaterialTheme.typography.labelLarge, color = scheme.tertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Icon(Icons.Filled.Close, "widen", tint = scheme.outline, modifier = Modifier.padding(0.dp))
                }
            }
        }
        if (library.isEmpty()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth().padding(18.dp), contentAlignment = Alignment.TopStart) {
                Label(if (loading) "reading the library…" else "desktop unreachable")
            }
        } else {
            LazyColumn(modifier = Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(bottom = 12.dp)) {
                if (artistsShown.isNotEmpty()) {
                    item { SectionHead("artists", if (artists.size > artistsShown.size) "${artists.size} in all" else if (allArtists && artists.size > 4) "fewer" else null) { allArtists = !allArtists } }
                    items(artistsShown, key = { "a:" + it.name }) { facet ->
                        FacetRow(highlight(facet.name, term, scheme.primary), "${facet.count} song${if (facet.count == 1) "" else "s"}") {
                            drillKey = "artist"; drillValue = facet.name; query = ""; allArtists = false; allAlbums = false
                        }
                    }
                }
                if (albumsShown.isNotEmpty()) {
                    item { SectionHead("albums", if (albums.size > albumsShown.size) "${albums.size} in all" else if (allAlbums && albums.size > 4) "fewer" else null) { allAlbums = !allAlbums } }
                    items(albumsShown, key = { "b:" + it.name }) { facet ->
                        FacetRow(
                            highlight(facet.name, term, scheme.primary),
                            listOfNotNull(facet.sample.artist, "${facet.count} song${if (facet.count == 1) "" else "s"}", Finder.year(facet.sample).takeIf { it.isNotEmpty() }).joinToString(" · "),
                        ) { drillKey = "album"; drillValue = facet.name; allAlbums = false }
                    }
                }
                item {
                    SectionHead("songs · ${drilled.size}" + if (fresh) "" else " · last known", null) {}
                    Row(modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Finder.sorts.forEach { (key, label) ->
                            val selected = key == sort
                            Text(
                                label,
                                style = MaterialTheme.typography.labelLarge,
                                color = if (selected) scheme.onPrimary else scheme.onSurfaceVariant,
                                modifier = Modifier.clip(RoundedCornerShape(999.dp)).background(if (selected) scheme.primary else scheme.surfaceContainerHigh).clickable { sort = key }.padding(horizontal = 12.dp, vertical = 6.dp),
                            )
                        }
                    }
                }
                items(drilled, key = { it.song.file }) { match ->
                    val song = match.song
                    val dim = now.phoneOwns && song.file.substringAfterLast('/') !in names
                    SongRow(song, match, term, dim, scheme.primary) { store.playSong(song); onCollapse() }
                }
            }
        }
        Notice(store, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}

@Composable
private fun SectionHead(title: String, action: String?, onAction: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(modifier = Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 12.dp, bottom = 2.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Label(title, color = scheme.onSurfaceVariant)
        if (action != null) Text(action, style = MaterialTheme.typography.labelMedium, color = scheme.primary, modifier = Modifier.clickable(onClick = onAction).padding(4.dp))
    }
}

@Composable
private fun FacetRow(title: AnnotatedString, subtitle: String, onOpen: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(horizontal = 18.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = scheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Icon(Icons.Filled.ChevronRight, null, tint = scheme.outline)
    }
}

@Composable
private fun SongRow(song: MpdSong, match: Match, term: String, dim: Boolean, mark: Color, onPlay: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val parts = ArrayList<AnnotatedString>()
    parts.add(highlight(song.artist ?: "unknown artist", term, mark))
    song.album?.takeIf { it.isNotEmpty() }?.let { parts.add(highlight(it, term, mark)) }
    if (match.why !in setOf("all", "title", "artist", "album")) parts.add(AnnotatedString("matched ${match.why}"))
    if (dim) parts.add(AnnotatedString("not on the phone yet"))
    val subtitle = buildAnnotatedString { parts.forEachIndexed { i, p -> if (i > 0) append(" · "); append(p) } }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !dim, onClick = onPlay)
            .padding(horizontal = 18.dp, vertical = 9.dp)
            .alpha(if (dim) 0.35f else 1f),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(highlight(song.name, term, mark), style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = scheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(song.duration?.let(::fmtTime) ?: "", style = MaterialTheme.typography.labelMedium, color = scheme.outline)
    }
}
