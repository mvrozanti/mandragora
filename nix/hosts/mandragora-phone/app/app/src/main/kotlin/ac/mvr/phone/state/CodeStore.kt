package ac.mvr.phone.state

import ac.mvr.phone.net.CodeAccess
import ac.mvr.phone.net.CodeClient
import ac.mvr.phone.net.CodeEntry
import ac.mvr.phone.net.CodeEvent
import ac.mvr.phone.net.CodeMessage
import ac.mvr.phone.net.CodePart
import ac.mvr.phone.net.CodeProject
import ac.mvr.phone.net.CodeProviders
import ac.mvr.phone.net.CodeSession
import ac.mvr.phone.net.CodeStatus
import ac.mvr.phone.net.CodeTime
import ac.mvr.phone.net.ScreenAsk
import ac.mvr.phone.net.SessionSettings
import ac.mvr.phone.logic.withBackground
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import ac.mvr.phone.net.MessageError
import ac.mvr.phone.net.PermissionAsk
import ac.mvr.phone.net.QuestionAsk
import ac.mvr.phone.net.json
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonPrimitive
import java.io.IOException

data class CodeModel(val backend: String, val providerID: String, val modelID: String) {
    val label: String
        get() = when {
            backend == "claude" && providerID == "claude" -> if (modelID == "default") "claude" else modelID
            backend == "claude" -> "$providerID ${modelID.substringAfterLast('-')}"
            else -> "$backend · ${modelID.removePrefix("$providerID-")}"
        }

    val key: String get() = "$backend/$providerID/$modelID"
}

fun parseModel(value: String?): CodeModel? {
    val parts = value?.split('/', limit = 3) ?: return null
    if (parts.size != 3 || parts.any { it.isEmpty() }) return null
    return CodeModel(parts[0], parts[1], parts[2])
}

const val CLOSE_GRACE_MS = 5_000L

private val errorText = Regex("\"error\":\\s*\"([^\"]+)\"")

class CodeStore(private val store: Store) {
    private val clients = HashMap<String, CodeClient>()

    private fun backends(): List<CodeAccess> = store.config.value?.code?.backends ?: emptyList()

    private fun client(id: String): CodeClient? {
        val access = backends().firstOrNull { it.id == id } ?: return null
        return clients.getOrPut(id) {
            CodeClient(id, { "http://${store.desktopIp}:${backends().firstOrNull { it.id == id }?.port ?: access.port}" }, { backends().firstOrNull { it.id == id } })
        }
    }

    private val sessionsFlow = MutableStateFlow<List<CodeSession>>(emptyList())
    val sessions: StateFlow<List<CodeSession>> = sessionsFlow

    private val statusFlow = MutableStateFlow<Map<String, CodeStatus>>(emptyMap())
    val statuses: StateFlow<Map<String, CodeStatus>> = statusFlow

    private val projectsFlow = MutableStateFlow<List<CodeProject>>(emptyList())
    val projects: StateFlow<List<CodeProject>> = projectsFlow

    private val currentFlow = MutableStateFlow<CodeSession?>(null)
    val current: StateFlow<CodeSession?> = currentFlow

    val newIn = MutableStateFlow<String?>(null)

    private val entriesFlow = MutableStateFlow<List<CodeEntry>>(emptyList())
    val entries: StateFlow<List<CodeEntry>> = entriesFlow

    private val asksFlow = MutableStateFlow<List<PermissionAsk>>(emptyList())
    val asks: StateFlow<List<PermissionAsk>> = asksFlow

    private val questionsFlow = MutableStateFlow<List<QuestionAsk>>(emptyList())
    val questions: StateFlow<List<QuestionAsk>> = questionsFlow

    private val screensFlow = MutableStateFlow<List<ScreenAsk>>(emptyList())
    val screens: StateFlow<List<ScreenAsk>> = screensFlow

    private val providersFlow = MutableStateFlow<Map<String, CodeProviders>>(emptyMap())
    val providers: StateFlow<Map<String, CodeProviders>> = providersFlow

    private val modelFlow = MutableStateFlow(parseModel(store.prefs.codeModel))
    val model: StateFlow<CodeModel?> = modelFlow

    private val settingsFlow = MutableStateFlow(SessionSettings())
    val settings: StateFlow<SessionSettings> = settingsFlow

    private val liveFlow = MutableStateFlow(false)
    val live: StateFlow<Boolean> = liveFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    val draft = MutableStateFlow("")
    val replaced = MutableSharedFlow<String>(extraBufferCapacity = 4)

    private fun replaceDraft(text: String) {
        draft.value = text
        replaced.tryEmit(text)
    }

    private var loadJob: Job? = null
    private var syncJob: Job? = null
    private var syncAgain = false
    private var listJob: Job? = null

    data class Attachment(val path: String, val thumb: android.graphics.Bitmap?, val picture: Boolean = true) {
        val name: String get() = path.substringAfterLast('/')
        val line: String get() = (if (picture) PICTURE_LINE else FILE_LINE) + path
    }

    companion object {
        const val PICTURE_LINE = "Attached picture: "
        const val FILE_LINE = "Attached file: "
        const val PICTURE_ONLY = "Look at the attached picture."
        const val FILE_ONLY = "Look at the attached file."
        const val FILE_LIMIT = 30 * 1024 * 1024
        val sentThumbs = androidx.compose.runtime.mutableStateMapOf<String, android.graphics.Bitmap>()

        fun split(body: String): Pair<String, List<Attachment>> {
            val lines = body.lines()
            val attached = lines.mapNotNull { line ->
                when {
                    line.startsWith(PICTURE_LINE) -> line.removePrefix(PICTURE_LINE).trim().let { Attachment(it, sentThumbs[it]) }
                    line.startsWith(FILE_LINE) -> Attachment(line.removePrefix(FILE_LINE).trim(), null, picture = false)
                    else -> null
                }
            }
            val words = lines.filterNot { it.startsWith(PICTURE_LINE) || it.startsWith(FILE_LINE) }.joinToString("\n").trim()
            return (if (attached.isNotEmpty() && (words == PICTURE_ONLY || words == FILE_ONLY)) "" else words) to attached
        }
    }

    data class Pending(val id: Long, val sessionId: String, val text: String, val at: Long, val seen: Set<String>)

    val attachments = MutableStateFlow<List<Attachment>>(emptyList())
    val uploading = MutableStateFlow(false)
    val pending = MutableStateFlow<List<Pending>>(emptyList())

    fun attach(uris: List<android.net.Uri>) = run {
        if (uris.isEmpty()) return@run
        uploading.value = true
        try {
            uris.forEach { attachOne(it) }
        } finally {
            uploading.value = false
        }
    }

    private suspend fun attachOne(uri: android.net.Uri) {
        val resolver = store.appContext.contentResolver
        val type = resolver.getType(uri) ?: "application/octet-stream"
        val name = nameOf(uri, type)
        val raw = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { readCapped(uri, name) }
        val client = client("claude") ?: throw IOException("desktop unreachable")
        val shrunk = if (type.startsWith("image/")) kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { ac.mvr.phone.play.Artwork.shrink(raw, 2048) } else null
        if (shrunk == null) {
            val path = client.upload(raw, type, name)
            attachments.value = attachments.value + Attachment(path, null, picture = false)
            return
        }
        val path = client.upload(shrunk)
        val thumb = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { ac.mvr.phone.play.Artwork.decode(shrunk, 160) }
        if (thumb != null) sentThumbs[path] = thumb
        attachments.value = attachments.value + Attachment(path, thumb)
    }

    private fun nameOf(uri: android.net.Uri, type: String): String {
        val shown = runCatching {
            store.appContext.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        }.getOrNull()?.trim()
        if (!shown.isNullOrEmpty()) return shown
        val ext = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(type)
        return if (ext != null) "file.$ext" else "file"
    }

    private fun readCapped(uri: android.net.Uri, name: String): ByteArray {
        val input = store.appContext.contentResolver.openInputStream(uri) ?: throw IOException("could not read $name")
        return input.use { stream ->
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = stream.read(buffer)
                if (n < 0) break
                if (out.size() + n > FILE_LIMIT) throw IOException("$name is over ${FILE_LIMIT / (1024 * 1024)} MB")
                out.write(buffer, 0, n)
            }
            if (out.size() == 0) throw IOException("$name is empty")
            out.toByteArray()
        }
    }

    fun detach(path: String) {
        attachments.value = attachments.value.filter { it.path != path }
    }

    private fun norm(text: String): String = text.replace(Regex("\\s+"), " ").trim()

    private fun reconcile() {
        val sid = currentFlow.value?.id ?: return
        val now = System.currentTimeMillis()
        val users = entriesFlow.value.filter { it.info.role == "user" }.map { entry ->
            entry.info.id to norm(entry.parts.filter { it.type == "text" }.mapNotNull { it.text }.joinToString(" "))
        }
        pending.value = pending.value.filter { p ->
            if (now - p.at > 15 * 60_000) return@filter false
            if (p.sessionId != sid) return@filter true
            val key = norm(p.text).take(40)
            users.none { (id, text) -> id !in p.seen && text.contains(key) }
        }
    }

    private fun ordered(list: List<CodeSession>): List<CodeSession> =
        list.sortedWith(compareByDescending<CodeSession> { it.time.updated }.thenBy { it.id })

    private fun touch(id: String, at: Long) {
        sessionsFlow.value = ordered(sessionsFlow.value.map { s ->
            if (s.id == id && at > s.time.updated) s.copy(time = s.time.copy(updated = at)).also { it.backend = s.backend } else s
        })
    }

    suspend fun find(query: String): List<CodeSession> {
        val client = client("claude") ?: throw IOException("desktop unreachable")
        return client.find(query, 80)
    }

    suspend fun watchList() {
        while (currentCoroutineContext().isActive) {
            val client = client("claude")
            if (client == null) {
                delay(3_000)
                continue
            }
            try {
                client.events(null).collect { event -> listEvent(event) }
            } catch (err: Exception) {
            }
            delay(3_000)
        }
    }

    private fun listEvent(event: CodeEvent) {
        val p = event.properties
        val sessionID = p["sessionID"]?.jsonPrimitive?.contentOrNull ?: return
        when (event.type) {
            "transcript.changed" -> {
                val updated = p["updated"]?.jsonPrimitive?.contentOrNull?.toLongOrNull()
                if (updated == null || sessionsFlow.value.none { it.id == sessionID }) refreshListSoon() else touch(sessionID, updated)
            }
            "session.status" -> {
                val status = p["status"]?.let { runCatching { json.decodeFromJsonElement<CodeStatus>(it) }.getOrNull() } ?: CodeStatus()
                statusFlow.value = if (status.type == "idle") statusFlow.value - sessionID else statusFlow.value + (sessionID to status)
            }
            "session.background" -> background(sessionID, p)
        }
    }

    private fun background(sessionID: String, p: JsonObject) {
        val raw = p["tasks"] ?: return
        val tasks = runCatching { json.decodeFromJsonElement<List<String>>(raw) }.getOrNull() ?: return
        sessionsFlow.value = sessionsFlow.value.map { if (it.id == sessionID) withBackground(it, tasks) else it }
        currentFlow.value?.takeIf { it.id == sessionID }?.let { currentFlow.value = withBackground(it, tasks) }
    }

    val directory: String? get() = currentFlow.value?.directory ?: newIn.value

    private fun currentClient(): CodeClient? {
        val backend = currentFlow.value?.backend?.ifEmpty { null } ?: modelFlow.value?.backend ?: backends().firstOrNull()?.id ?: return null
        return client(backend)
    }

    private suspend fun <T> attempt(block: suspend () -> T): Result<T> = try {
        Result.success(block())
    } catch (err: kotlinx.coroutines.CancellationException) {
        throw err
    } catch (err: Exception) {
        Result.failure(err)
    }

    private class Listing(val backend: String, val projects: List<CodeProject>, val sessions: List<CodeSession>, val statuses: Map<String, CodeStatus>)

    private val listed = HashMap<String, Set<String>>()

    private suspend fun listing(client: CodeClient): Listing = coroutineScope {
        val projects = client.projects().sortedByDescending { it.time.updated }
        val perProject = projects.take(6).map { project ->
            async {
                val key = client.id + "\n" + project.worktree
                val list = attempt { client.sessions(project.worktree, 8) }.getOrNull()
                if (list != null) listed[key] = list.map { it.id }.toSet()
                val sessions = list ?: listed[key].orEmpty().let { was -> sessionsFlow.value.filter { it.backend == client.id && it.id in was } }
                sessions to attempt { client.status(project.worktree) }.getOrNull()
            }
        }.awaitAll()
        val kept = perProject.filter { it.second == null }.flatMap { it.first }.mapNotNull { s -> statusFlow.value[s.id]?.let { s.id to it } }.toMap()
        val fresh = perProject.mapNotNull { it.second }.flatMap { it.entries }.associate { it.key to it.value }
        Listing(client.id, projects, perProject.flatMap { it.first }, kept + fresh)
    }

    suspend fun refresh() {
        val ids = backends().map { it.id }
        if (ids.isEmpty()) {
            freshFlow.value = false
            throw IOException("desktop unreachable")
        }
        try {
            val perBackend = coroutineScope {
                ids.mapNotNull { id -> client(id) }.map { client ->
                    async { attempt { listing(client) } }
                }.awaitAll()
            }
            val answered = perBackend.mapNotNull { it.getOrNull() }
            if (answered.isEmpty()) throw perBackend.firstNotNullOfOrNull { it.exceptionOrNull() } ?: IOException("desktop unreachable")
            val failed = ids.filter { id -> answered.none { it.backend == id } }
            val keptSessions = sessionsFlow.value.filter { it.backend in failed }
            val keptStatus = keptSessions.mapNotNull { s -> statusFlow.value[s.id]?.let { s.id to it } }.toMap()
            projectsFlow.value = (answered.flatMap { it.projects } + projectsFlow.value.filter { it.backend in failed }).distinctBy { it.worktree }.sortedByDescending { it.time.updated }
            sessionsFlow.value = ordered((answered.flatMap { it.sessions } + keptSessions).filter { it.parentID == null }.distinctBy { it.backend + it.id })
            statusFlow.value = keptStatus + answered.flatMap { it.statuses.entries }.associate { it.key to it.value }
            currentFlow.value?.let { cur -> sessionsFlow.value.firstOrNull { it.id == cur.id && it.backend == cur.backend }?.let { currentFlow.value = it } }
            freshFlow.value = true
        } catch (err: Exception) {
            freshFlow.value = false
            throw err
        }
    }

    suspend fun enter() {
        if (providersFlow.value.isEmpty()) runCatching { loadProviders() }
        if (currentFlow.value != null || newIn.value != null) return
        runCatching { refresh() }
        val last = store.prefs.lastCodeSession
        val found = sessionsFlow.value.firstOrNull { it.id == last }
        if (found != null) open(found) else startNew()
    }

    private suspend fun loadProviders() {
        val loaded = coroutineScope {
            backends().mapNotNull { access -> client(access.id) }.map { client ->
                async { runCatching { client.id to client.providers() }.getOrNull() }
            }.awaitAll().filterNotNull().toMap()
        }
        if (loaded.isNotEmpty()) providersFlow.value = loaded
        if (modelFlow.value == null || choices().none { it == modelFlow.value }) modelFlow.value = choices().firstOrNull()
        currentFlow.value?.let { followModel(it, entriesFlow.value) }
    }

    private fun choices(): List<CodeModel> {
        val ordered = backends().sortedBy { if (it.id == "claude") 0 else 1 }
        return ordered.flatMap { access ->
            val p = providersFlow.value[access.id] ?: return@flatMap emptyList()
            val ids = p.connected.filter { it != "opencode" }.ifEmpty { p.connected }
            ids.flatMap { id ->
                val listed = if (access.id == "claude") p.all.firstOrNull { it.id == id }?.models?.keys?.toList().orEmpty() else emptyList()
                listed.ifEmpty { listOfNotNull(p.default[id]) }.map { CodeModel(access.id, id, it) }
            }
        }
    }

    fun modelChoices(): List<CodeModel> {
        val session = currentFlow.value
        val backend = session?.backend?.ifEmpty { null }
        return choices().filter { backend == null || it.backend == backend }
    }

    private fun followModel(session: CodeSession, entries: List<CodeEntry>) {
        if (session.backend == "claude") {
            val chosen = settingsFlow.value
            val match = choices().firstOrNull { it.backend == "claude" && it.providerID == chosen.providerID && it.modelID == chosen.modelID } ?: return
            if (modelFlow.value != match) modelFlow.value = match
            return
        }
        val last = entries.lastOrNull { it.info.role == "assistant" && it.info.providerID != null }?.info ?: return
        val options = choices().filter { it.backend == session.backend }
        val match = options.firstOrNull { it.providerID == last.providerID && it.modelID == last.modelID }
            ?: options.firstOrNull { it.providerID == last.providerID }
            ?: return
        if (modelFlow.value != match) modelFlow.value = match
    }

    private fun adjustable(): CodeSession? = currentFlow.value?.takeIf { it.backend == "claude" }

    private val changes = Mutex()
    private var queuedChanges = 0

    private fun change(body: kotlinx.serialization.json.JsonObject) {
        val session = adjustable() ?: return
        queuedChanges += 1
        run {
            changes.withLock {
                queuedChanges -= 1
                val client = client(session.backend) ?: throw IOException("desktop unreachable")
                val saved = try {
                    client.setSettings(session.id, session.directory, body)
                } catch (err: Exception) {
                    attempt { client.settings(session.id, session.directory) }.getOrNull()?.let { found ->
                        if (queuedChanges == 0 && currentFlow.value?.id == session.id) {
                            settingsFlow.value = found
                            followModel(session, entriesFlow.value)
                        }
                    }
                    throw err
                }
                if (queuedChanges == 0 && currentFlow.value?.id == session.id) settingsFlow.value = saved
                if (body.containsKey("providerID")) refreshListSoon()
            }
        }
    }

    fun pickModel(choice: CodeModel) {
        modelFlow.value = choice
        store.prefs.codeModel = choice.key
        if (choice.backend != "claude") return
        settingsFlow.value = settingsFlow.value.copy(providerID = choice.providerID, modelID = choice.modelID)
        change(buildJsonObject { put("providerID", choice.providerID); put("modelID", choice.modelID) })
    }

    fun pickMode(mode: String) {
        settingsFlow.value = settingsFlow.value.copy(mode = mode)
        change(buildJsonObject { put("mode", mode) })
    }

    fun pickEffort(effort: String?) {
        settingsFlow.value = settingsFlow.value.copy(effort = effort)
        change(buildJsonObject { put("effort", effort?.let { kotlinx.serialization.json.JsonPrimitive(it) } ?: JsonNull) })
    }

    fun open(session: CodeSession) {
        currentFlow.value = session
        newIn.value = null
        store.prefs.lastCodeSession = session.id
        store.prefs.lastCodeDir = session.directory
        if (modelFlow.value?.backend != session.backend) choices().firstOrNull { it.backend == session.backend }?.let { modelFlow.value = it }
        entriesFlow.value = emptyList()
        asksFlow.value = emptyList()
        questionsFlow.value = emptyList()
        screensFlow.value = emptyList()
        settingsFlow.value = SessionSettings()
        loadJob?.cancel()
        loadJob = run { load(session) }
    }

    private suspend fun load(session: CodeSession) {
        val client = client(session.backend) ?: throw IOException("desktop unreachable")
        val list = client.messages(session.id, session.directory, 80)
        if (currentFlow.value?.id != session.id) return
        entriesFlow.value = list
        if (session.backend == "claude") runCatching { client.settings(session.id, session.directory) }.getOrNull()?.let { found ->
            if (currentFlow.value?.id == session.id) settingsFlow.value = found
        }
        followModel(session, list)
        reconcile()
        prompts(session, client)
    }

    private suspend fun prompts(session: CodeSession, client: CodeClient) {
        val pending = attempt { client.permissions(session.directory) }.getOrNull()?.filter { it.sessionID == session.id }
        val open = attempt { client.questions(session.directory) }.getOrNull()?.filter { it.sessionID == session.id }
        val shown = attempt { client.screens(session.directory) }.getOrNull()?.filter { it.sessionID == session.id }
        if (currentFlow.value?.id != session.id) return
        pending?.let { asksFlow.value = it }
        open?.let { questionsFlow.value = it }
        shown?.let { screensFlow.value = it }
    }

    private var promptJob: Job? = null

    private fun syncPrompts() {
        val session = currentFlow.value ?: return
        val client = client(session.backend) ?: return
        promptJob?.cancel()
        promptJob = store.scope.launch { prompts(session, client) }
    }

    fun startNew(directory: String? = null) {
        val dir = directory ?: store.prefs.lastCodeDir ?: projectsFlow.value.firstOrNull()?.worktree ?: "/home/m"
        currentFlow.value = null
        entriesFlow.value = emptyList()
        asksFlow.value = emptyList()
        questionsFlow.value = emptyList()
        screensFlow.value = emptyList()
        settingsFlow.value = SessionSettings()
        parseModel(store.prefs.codeModel)?.let { saved -> choices().firstOrNull { it == saved }?.let { modelFlow.value = it } }
        newIn.value = dir
        store.prefs.lastCodeDir = dir
    }

    private fun humanize(err: Throwable): Throwable {
        if (err !is IOException) return err
        val found = errorText.find(err.message ?: "")?.groupValues?.get(1) ?: return err
        return IllegalStateException(found, err)
    }

    private fun run(block: suspend () -> Unit): Job = store.scope.launch {
        try { block() } catch (err: kotlinx.coroutines.CancellationException) { throw err } catch (err: Exception) { store.report(humanize(err)) }
    }

    fun send(text: String) = run {
        val typed = text.trim()
        val files = attachments.value
        if ((typed.isEmpty() && files.isEmpty()) || sending.value) return@run
        val body = (listOf(typed.ifEmpty { if (files.all { it.picture }) PICTURE_ONLY else FILE_ONLY }) + files.map { it.line }).joinToString("\n")
        sending.value = true
        replaceDraft("")
        attachments.value = attachments.value.filter { it !in files }
        try {
            deliver(body)
        } catch (err: Exception) {
            if (draft.value.isEmpty() && attachments.value.isEmpty() && !uploading.value) {
                replaceDraft(text)
                attachments.value = files
            }
            throw err
        } finally {
            sending.value = false
        }
    }

    fun resend(body: String) = run {
        if (sending.value) return@run
        sending.value = true
        try {
            deliver(body)
        } finally {
            sending.value = false
        }
    }

    fun edit(body: String) {
        val (words, attached) = split(body)
        attachments.value = attached
        replaceDraft(words)
    }

    val sending = MutableStateFlow(false)

    private suspend fun deliver(body: String) {
        var session = currentFlow.value
        val chosen = modelFlow.value
        val backend = session?.backend?.ifEmpty { null } ?: chosen?.backend ?: choices().firstOrNull()?.backend ?: "claude"
        val client = client(backend) ?: throw IOException("desktop unreachable")
        val sameBackend = chosen?.backend == backend
        if (session == null) {
            val dir = newIn.value ?: store.prefs.lastCodeDir ?: "/home/m"
            session = client.create(dir, chosen?.providerID?.takeIf { sameBackend }, chosen?.modelID?.takeIf { sameBackend }, settingsFlow.value.takeIf { backend == "claude" })
            currentFlow.value = session
            newIn.value = null
            store.prefs.lastCodeSession = session.id
            store.prefs.lastCodeDir = session.directory
            sessionsFlow.value = listOf(session) + sessionsFlow.value.filter { it.id != session.id }
        }
        val sent = Pending(System.nanoTime(), session.id, body, System.currentTimeMillis(), entriesFlow.value.filter { it.info.role == "user" }.map { it.info.id }.toSet())
        pending.value = pending.value + sent
        try {
            client.prompt(session.id, session.directory, body, chosen?.providerID?.takeIf { sameBackend }, chosen?.modelID?.takeIf { sameBackend })
        } catch (err: Exception) {
            pending.value = pending.value.filter { it.id != sent.id }
            throw err
        }
        reconcile()
        statusFlow.value = statusFlow.value + (session.id to CodeStatus("busy"))
        touch(session.id, System.currentTimeMillis())
        if (session.live != null) syncCurrent()
    }

    fun rename(title: String) = run {
        val session = currentFlow.value ?: return@run
        val name = title.replace(Regex("\\s+"), " ").trim()
        if (name.isEmpty() || name == session.title) return@run
        val client = client(session.backend) ?: throw IOException("desktop unreachable")
        retitle(session.id, name)
        try {
            client.rename(session.id, session.directory, name)
        } catch (err: Exception) {
            retitle(session.id, session.title)
            throw err
        }
    }

    private fun retitle(id: String, title: String) {
        sessionsFlow.value = sessionsFlow.value.map { s -> if (s.id == id) s.copy(title = title).also { it.backend = s.backend } else s }
        currentFlow.value?.takeIf { it.id == id }?.let { s -> currentFlow.value = s.copy(title = title).also { it.backend = s.backend } }
    }

    fun stop() = run {
        val session = currentFlow.value ?: return@run
        client(session.backend)?.abort(session.id, session.directory)
    }

    private val closeJobs = HashMap<String, Job>()
    private val committed = HashSet<String>()
    val closing = MutableStateFlow<Map<String, Long>>(emptyMap())
    val closed = MutableStateFlow(0)

    fun closable(session: CodeSession, status: CodeStatus?): Boolean =
        session.backend == "claude" && (session.live != null || status?.type == "busy")

    fun close(session: CodeSession) {
        val id = session.id
        if (closeJobs.containsKey(id)) return
        closing.value = closing.value + (id to System.currentTimeMillis() + CLOSE_GRACE_MS)
        closeJobs[id] = store.scope.launch {
            val mine = coroutineContext[Job]
            try {
                delay(CLOSE_GRACE_MS)
                committed += id
                val client = client(session.backend) ?: throw IOException("desktop unreachable")
                client.close(id, session.directory)
                forgetLive(id)
                closed.value += 1
                refreshListSoon()
            } catch (err: kotlinx.coroutines.CancellationException) {
                throw err
            } catch (err: Exception) {
                store.report(humanize(err))
            } finally {
                if (closeJobs[id] === mine) {
                    closeJobs.remove(id)
                    committed -= id
                    closing.value = closing.value - id
                }
            }
        }
    }

    fun undoClose(id: String) {
        if (id in committed) return
        closeJobs.remove(id)?.cancel()
        closing.value = closing.value - id
    }

    private fun forgetLive(id: String) {
        statusFlow.value = statusFlow.value - id
        sessionsFlow.value = sessionsFlow.value.map { s -> if (s.id == id) s.copy(live = null).also { it.backend = s.backend } else s }
        currentFlow.value?.takeIf { it.id == id }?.let { s -> currentFlow.value = s.copy(live = null).also { it.backend = s.backend } }
    }

    private val replying = HashSet<String>()

    private fun reply(id: String, post: suspend (CodeClient, String) -> Unit) = run {
        val dir = directory ?: return@run
        val client = currentClient() ?: throw IOException("desktop unreachable")
        if (!replying.add(id)) return@run
        try {
            post(client, dir)
        } finally {
            replying.remove(id)
        }
    }

    fun allow(ask: PermissionAsk, response: String) = reply(ask.id) { client, dir ->
        client.permission(ask.sessionID, ask.id, dir, response)
        asksFlow.value = asksFlow.value.filter { it.id != ask.id }
    }

    fun answer(question: QuestionAsk, answers: List<List<String>>) = reply(question.id) { client, dir ->
        client.answer(question.id, dir, answers)
        questionsFlow.value = questionsFlow.value.filter { it.id != question.id }
    }

    fun rejectQuestion(question: QuestionAsk) = reply(question.id) { client, dir ->
        client.reject(question.id, dir)
        questionsFlow.value = questionsFlow.value.filter { it.id != question.id }
    }

    fun press(ask: ScreenAsk, key: String, text: String? = null) = run {
        val dir = directory ?: return@run
        val client = currentClient() ?: return@run
        if (!replying.add(ask.id)) return@run
        try {
            val next = client.press(ask.sessionID, dir, ask.id, key, text)
            if (currentFlow.value?.id == ask.sessionID) screensFlow.value = screensFlow.value.filter { it.sessionID != ask.sessionID } + listOfNotNull(next)
        } catch (err: IOException) {
            val fresh = runCatching { client.screens(dir) }.getOrDefault(emptyList()).filter { it.sessionID == ask.sessionID }
            if (currentFlow.value?.id == ask.sessionID) screensFlow.value = fresh
            throw err
        } finally {
            replying.remove(ask.id)
        }
    }

    suspend fun watch(backend: String, dir: String?) {
        while (currentCoroutineContext().isActive) {
            val client = client(backend)
            if (client == null) {
                liveFlow.value = false
                delay(2_000)
                continue
            }
            try {
                client.events(dir).collect { event ->
                    liveFlow.value = true
                    handle(event)
                }
            } catch (err: Exception) {
                liveFlow.value = false
            }
            liveFlow.value = false
            delay(2_000)
        }
    }

    private fun syncCurrent() {
        if (syncJob?.isActive == true) {
            syncAgain = true
            return
        }
        syncJob = store.scope.launch {
            do {
                syncAgain = false
                delay(250)
                val session = currentFlow.value ?: break
                val client = client(session.backend) ?: break
                val list = runCatching { client.messages(session.id, session.directory, 80) }.getOrNull() ?: continue
                if (currentFlow.value?.id == session.id) {
                    entriesFlow.value = list
                    followModel(session, list)
                    reconcile()
                }
            } while (syncAgain)
        }
    }

    private fun refreshListSoon() {
        if (listJob?.isActive == true) return
        listJob = store.scope.launch {
            delay(800)
            runCatching { refresh() }
        }
    }

    private fun handle(event: CodeEvent) {
        val p = event.properties
        val sessionID = p["sessionID"]?.jsonPrimitive?.contentOrNull
        val mine = sessionID != null && sessionID == currentFlow.value?.id
        when (event.type) {
            "server.connected" -> {
                if (currentFlow.value != null) {
                    syncCurrent()
                    syncPrompts()
                }
                refreshListSoon()
            }
            "transcript.changed" -> if (sessionID != null) {
                if (mine) syncCurrent()
                val updated = p["updated"]?.jsonPrimitive?.contentOrNull?.toLongOrNull()
                if (updated == null || sessionsFlow.value.none { it.id == sessionID }) refreshListSoon() else touch(sessionID, updated)
            }
            "message.updated" -> if (mine) p["info"]?.let { upsertMessage(json.decodeFromJsonElement<CodeMessage>(it)); reconcile() }
            "message.part.updated" -> if (mine) p["part"]?.let { upsertPart(json.decodeFromJsonElement<CodePart>(it)); reconcile() }
            "message.part.delta" -> if (mine) delta(p)
            "message.removed" -> if (mine) p["messageID"]?.jsonPrimitive?.contentOrNull?.let { id -> entriesFlow.value = entriesFlow.value.filter { it.info.id != id } }
            "message.part.removed" -> if (mine) removePart(p)
            "session.status" -> if (sessionID != null) {
                val status = p["status"]?.let { runCatching { json.decodeFromJsonElement<CodeStatus>(it) }.getOrNull() } ?: CodeStatus()
                if (mine && status.type == "idle") syncCurrent()
                statusFlow.value = if (status.type == "idle") statusFlow.value - sessionID else statusFlow.value + (sessionID to status)
            }
            "session.idle" -> if (sessionID != null) {
                if (mine) syncCurrent()
                statusFlow.value = statusFlow.value - sessionID
            }
            "session.background" -> if (sessionID != null) background(sessionID, p)
            "session.created", "session.updated" -> p["info"]?.let { info ->
                val told = runCatching { json.decodeFromJsonElement<CodeSession>(info) }.getOrNull() ?: return
                val known = sessionsFlow.value.firstOrNull { it.id == told.id } ?: currentFlow.value?.takeIf { it.id == told.id }
                val session = known?.copy(
                    title = told.title.ifBlank { known.title },
                    directory = told.directory.ifBlank { known.directory },
                    parentID = told.parentID ?: known.parentID,
                    time = CodeTime(known.time.created.takeIf { it > 0 } ?: told.time.created, maxOf(known.time.updated, told.time.updated)),
                ) ?: told
                session.backend = known?.backend?.ifEmpty { null } ?: currentFlow.value?.backend?.ifEmpty { null } ?: modelFlow.value?.backend ?: ""
                if (session.parentID == null) sessionsFlow.value = ordered(listOf(session) + sessionsFlow.value.filter { it.id != session.id })
                if (currentFlow.value?.id == session.id) currentFlow.value = session
            }
            "session.deleted" -> if (sessionID != null) {
                sessionsFlow.value = sessionsFlow.value.filter { it.id != sessionID }
                if (currentFlow.value?.id == sessionID) startNew()
            }
            "permission.asked" -> if (mine) runCatching { json.decodeFromJsonElement<PermissionAsk>(p) }.getOrNull()?.let { ask ->
                asksFlow.value = asksFlow.value.filter { it.id != ask.id } + ask
            }
            "permission.replied" -> p["requestID"]?.jsonPrimitive?.contentOrNull?.let { id -> asksFlow.value = asksFlow.value.filter { it.id != id } }
            "question.asked" -> if (mine) runCatching { json.decodeFromJsonElement<QuestionAsk>(p) }.getOrNull()?.let { ask ->
                questionsFlow.value = questionsFlow.value.filter { it.id != ask.id } + ask
            }
            "question.replied", "question.rejected" -> p["requestID"]?.jsonPrimitive?.contentOrNull?.let { id -> questionsFlow.value = questionsFlow.value.filter { it.id != id } }
            "screen.asked" -> if (mine) runCatching { json.decodeFromJsonElement<ScreenAsk>(p) }.getOrNull()?.let { ask ->
                screensFlow.value = screensFlow.value.filter { it.sessionID != ask.sessionID } + ask
            }
            "session.settings" -> if (mine) p["settings"]?.let { raw ->
                val got = runCatching { json.decodeFromJsonElement<SessionSettings>(raw) }.getOrNull() ?: return
                val now = settingsFlow.value
                settingsFlow.value = SessionSettings(got.providerID ?: now.providerID, got.modelID ?: now.modelID, got.mode, got.effort)
                currentFlow.value?.let { followModel(it, entriesFlow.value) }
            }
            "screen.cleared" -> p["requestID"]?.jsonPrimitive?.contentOrNull?.let { id -> screensFlow.value = screensFlow.value.filter { it.id != id } }
            "session.error" -> if (mine) p["error"]?.let { err ->
                val parsed = runCatching { json.decodeFromJsonElement<MessageError>(err) }.getOrNull()
                store.report(IllegalStateException(parsed?.text ?: "session error"))
            }
        }
    }

    private fun upsertMessage(info: CodeMessage) {
        val list = entriesFlow.value
        val index = list.indexOfFirst { it.info.id == info.id }
        entriesFlow.value = if (index < 0) list + CodeEntry(info) else list.toMutableList().also { it[index] = it[index].copy(info = info) }
    }

    private fun upsertPart(part: CodePart) {
        val list = entriesFlow.value.toMutableList()
        val index = list.indexOfFirst { it.info.id == part.messageID }
        if (index < 0) {
            list.add(CodeEntry(CodeMessage(id = part.messageID, sessionID = part.sessionID, role = "assistant"), listOf(part)))
        } else {
            val parts = list[index].parts.toMutableList()
            val at = parts.indexOfFirst { it.id == part.id }
            if (at < 0) parts.add(part) else parts[at] = part
            list[index] = list[index].copy(parts = parts)
        }
        entriesFlow.value = list
    }

    private fun delta(p: JsonObject) {
        if (p["field"]?.jsonPrimitive?.contentOrNull != "text") return
        val messageID = p["messageID"]?.jsonPrimitive?.contentOrNull ?: return
        val partID = p["partID"]?.jsonPrimitive?.contentOrNull ?: return
        val chunk = p["delta"]?.jsonPrimitive?.contentOrNull ?: return
        val list = entriesFlow.value.toMutableList()
        val index = list.indexOfFirst { it.info.id == messageID }
        if (index < 0) return
        val parts = list[index].parts.toMutableList()
        val at = parts.indexOfFirst { it.id == partID }
        if (at < 0) return
        parts[at] = parts[at].copy(text = (parts[at].text ?: "") + chunk)
        list[index] = list[index].copy(parts = parts)
        entriesFlow.value = list
    }

    private fun removePart(p: JsonObject) {
        val messageID = p["messageID"]?.jsonPrimitive?.contentOrNull ?: return
        val partID = p["partID"]?.jsonPrimitive?.contentOrNull ?: return
        entriesFlow.value = entriesFlow.value.map { entry ->
            if (entry.info.id == messageID) entry.copy(parts = entry.parts.filter { it.id != partID }) else entry
        }
    }
}
