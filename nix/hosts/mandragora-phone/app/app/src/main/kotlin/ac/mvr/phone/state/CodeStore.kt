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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonPrimitive
import java.io.IOException

data class CodeModel(val backend: String, val providerID: String, val modelID: String) {
    val label: String
        get() = when {
            backend == "claude" && providerID == "claude" -> "claude"
            backend == "claude" -> providerID
            else -> "$backend · ${modelID.removePrefix("$providerID-")}"
        }

    val key: String get() = "$backend/$providerID/$modelID"
}

fun parseModel(value: String?): CodeModel? {
    val parts = value?.split('/', limit = 3) ?: return null
    if (parts.size != 3 || parts.any { it.isEmpty() }) return null
    return CodeModel(parts[0], parts[1], parts[2])
}

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

    private val providersFlow = MutableStateFlow<Map<String, CodeProviders>>(emptyMap())
    val providers: StateFlow<Map<String, CodeProviders>> = providersFlow

    private val modelFlow = MutableStateFlow(parseModel(store.prefs.codeModel))
    val model: StateFlow<CodeModel?> = modelFlow

    private val liveFlow = MutableStateFlow(false)
    val live: StateFlow<Boolean> = liveFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    val draft = MutableStateFlow("")

    private var loadJob: Job? = null
    private var syncJob: Job? = null
    private var syncAgain = false
    private var listJob: Job? = null

    val directory: String? get() = currentFlow.value?.directory ?: newIn.value

    private fun currentClient(): CodeClient? {
        val backend = currentFlow.value?.backend?.ifEmpty { null } ?: modelFlow.value?.backend ?: backends().firstOrNull()?.id ?: return null
        return client(backend)
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
                    async {
                        val projects = runCatching { client.projects() }.getOrDefault(emptyList()).sortedByDescending { it.time.updated }
                        val perProject = projects.take(6).map { project ->
                            async {
                                val list = runCatching { client.sessions(project.worktree, 8) }.getOrDefault(emptyList())
                                val status = runCatching { client.status(project.worktree) }.getOrDefault(emptyMap())
                                list to status
                            }
                        }.awaitAll()
                        Triple(projects, perProject.flatMap { it.first }, perProject.flatMap { it.second.entries }.associate { it.key to it.value })
                    }
                }.awaitAll()
            }
            projectsFlow.value = perBackend.flatMap { it.first }.distinctBy { it.worktree }.sortedByDescending { it.time.updated }
            sessionsFlow.value = perBackend.flatMap { it.second }.filter { it.parentID == null }.distinctBy { it.backend + it.id }.sortedByDescending { it.time.updated }
            statusFlow.value = perBackend.flatMap { it.third.entries }.associate { it.key to it.value }
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
    }

    private fun choices(): List<CodeModel> {
        val ordered = backends().sortedBy { if (it.id == "claude") 0 else 1 }
        return ordered.flatMap { access ->
            val p = providersFlow.value[access.id] ?: return@flatMap emptyList()
            val ids = p.connected.filter { it != "opencode" }.ifEmpty { p.connected }
            ids.mapNotNull { id -> p.default[id]?.let { CodeModel(access.id, id, it) } }
        }
    }

    private fun followModel(session: CodeSession, entries: List<CodeEntry>) {
        val last = entries.lastOrNull { it.info.role == "assistant" && it.info.providerID != null }?.info ?: return
        val options = choices().filter { it.backend == session.backend }
        val match = options.firstOrNull { it.providerID == last.providerID && it.modelID == last.modelID }
            ?: options.firstOrNull { it.providerID == last.providerID }
            ?: return
        if (modelFlow.value != match) modelFlow.value = match
    }

    fun cycleModel() {
        val backend = currentFlow.value?.backend?.ifEmpty { null }
        val options = choices().filter { backend == null || it.backend == backend }
        if (options.isEmpty()) return
        val index = options.indexOfFirst { it == modelFlow.value }
        val next = options[(index + 1) % options.size]
        modelFlow.value = next
        store.prefs.codeModel = next.key
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
        loadJob?.cancel()
        loadJob = store.scope.launch { runCatching { load(session) }.onFailure { store.report(humanize(it)) } }
    }

    private suspend fun load(session: CodeSession) {
        val client = client(session.backend) ?: throw IOException("desktop unreachable")
        val list = client.messages(session.id, session.directory, 80)
        if (currentFlow.value?.id != session.id) return
        entriesFlow.value = list
        followModel(session, list)
        val pending = runCatching { client.permissions(session.directory) }.getOrDefault(emptyList()).filter { it.sessionID == session.id }
        val open = runCatching { client.questions(session.directory) }.getOrDefault(emptyList()).filter { it.sessionID == session.id }
        if (currentFlow.value?.id != session.id) return
        asksFlow.value = pending
        questionsFlow.value = open
    }

    fun startNew(directory: String? = null) {
        val dir = directory ?: store.prefs.lastCodeDir ?: projectsFlow.value.firstOrNull()?.worktree ?: "/home/m"
        currentFlow.value = null
        entriesFlow.value = emptyList()
        asksFlow.value = emptyList()
        questionsFlow.value = emptyList()
        newIn.value = dir
        store.prefs.lastCodeDir = dir
    }

    private fun humanize(err: Throwable): Throwable {
        if (err !is IOException) return err
        val found = errorText.find(err.message ?: "")?.groupValues?.get(1) ?: return err
        return IllegalStateException(found, err)
    }

    private fun run(block: suspend () -> Unit): Job = store.scope.launch {
        try { block() } catch (err: Exception) { store.report(humanize(err)) }
    }

    fun send(text: String) = run {
        val body = text.trim()
        if (body.isEmpty()) return@run
        var session = currentFlow.value
        val chosen = modelFlow.value
        val backend = session?.backend?.ifEmpty { null } ?: chosen?.backend ?: choices().firstOrNull()?.backend ?: "claude"
        val client = client(backend) ?: throw IOException("desktop unreachable")
        val sameBackend = chosen?.backend == backend
        if (session == null) {
            val dir = newIn.value ?: store.prefs.lastCodeDir ?: "/home/m"
            session = client.create(dir, chosen?.providerID?.takeIf { sameBackend }, chosen?.modelID?.takeIf { sameBackend })
            currentFlow.value = session
            newIn.value = null
            store.prefs.lastCodeSession = session.id
            store.prefs.lastCodeDir = session.directory
            sessionsFlow.value = listOf(session) + sessionsFlow.value.filter { it.id != session.id }
        }
        client.prompt(session.id, session.directory, body, chosen?.providerID?.takeIf { sameBackend }, chosen?.modelID?.takeIf { sameBackend })
        draft.value = ""
        statusFlow.value = statusFlow.value + (session.id to CodeStatus("busy"))
    }

    fun stop() = run {
        val session = currentFlow.value ?: return@run
        client(session.backend)?.abort(session.id, session.directory)
    }

    fun allow(ask: PermissionAsk, response: String) = run {
        val dir = directory ?: return@run
        asksFlow.value = asksFlow.value.filter { it.id != ask.id }
        currentClient()?.permission(ask.sessionID, ask.id, dir, response)
    }

    fun answer(question: QuestionAsk, answers: List<List<String>>) = run {
        val dir = directory ?: return@run
        questionsFlow.value = questionsFlow.value.filter { it.id != question.id }
        currentClient()?.answer(question.id, dir, answers)
    }

    fun rejectQuestion(question: QuestionAsk) = run {
        val dir = directory ?: return@run
        questionsFlow.value = questionsFlow.value.filter { it.id != question.id }
        currentClient()?.reject(question.id, dir)
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
                if (currentFlow.value != null) syncCurrent()
                refreshListSoon()
            }
            "transcript.changed" -> if (sessionID != null) {
                if (mine) syncCurrent()
                val updated = p["updated"]?.jsonPrimitive?.contentOrNull?.toLongOrNull()
                val known = sessionsFlow.value.firstOrNull { it.id == sessionID }
                if (known == null || updated == null) refreshListSoon()
                else sessionsFlow.value = sessionsFlow.value.map { if (it.id == sessionID) it.copy(time = it.time.copy(updated = updated)).also { c -> c.backend = it.backend } else it }.sortedByDescending { it.time.updated }
            }
            "message.updated" -> if (mine) p["info"]?.let { upsertMessage(json.decodeFromJsonElement<CodeMessage>(it)) }
            "message.part.updated" -> if (mine) p["part"]?.let { upsertPart(json.decodeFromJsonElement<CodePart>(it)) }
            "message.part.delta" -> if (mine) delta(p)
            "message.removed" -> if (mine) p["messageID"]?.jsonPrimitive?.contentOrNull?.let { id -> entriesFlow.value = entriesFlow.value.filter { it.info.id != id } }
            "message.part.removed" -> if (mine) removePart(p)
            "session.status" -> if (sessionID != null) {
                val status = p["status"]?.let { runCatching { json.decodeFromJsonElement<CodeStatus>(it) }.getOrNull() } ?: CodeStatus()
                statusFlow.value = if (status.type == "idle") statusFlow.value - sessionID else statusFlow.value + (sessionID to status)
            }
            "session.idle" -> if (sessionID != null) statusFlow.value = statusFlow.value - sessionID
            "session.created", "session.updated" -> p["info"]?.let { info ->
                val session = runCatching { json.decodeFromJsonElement<CodeSession>(info) }.getOrNull() ?: return
                session.backend = currentFlow.value?.backend?.ifEmpty { null } ?: modelFlow.value?.backend ?: ""
                if (session.parentID == null) sessionsFlow.value = (listOf(session) + sessionsFlow.value.filter { it.id != session.id }).sortedByDescending { it.time.updated }
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
