package ac.mvr.phone.state

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
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

data class CodeModel(val providerID: String, val modelID: String) {
    val label: String get() = modelID.removePrefix("$providerID-")
}

fun parseModel(value: String?): CodeModel? {
    if (value == null) return null
    val provider = value.substringBefore('/', "")
    val model = value.substringAfter('/', "")
    return if (provider.isEmpty() || model.isEmpty()) null else CodeModel(provider, model)
}

class CodeStore(private val store: Store) {
    val client = CodeClient({ "http://${store.desktopIp}:${store.config.value?.code?.port ?: 4096}" }, { store.config.value?.code })

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

    private val providersFlow = MutableStateFlow<CodeProviders?>(null)
    val providers: StateFlow<CodeProviders?> = providersFlow

    private val modelFlow = MutableStateFlow(parseModel(store.prefs.codeModel))
    val model: StateFlow<CodeModel?> = modelFlow

    private val liveFlow = MutableStateFlow(false)
    val live: StateFlow<Boolean> = liveFlow

    private val freshFlow = MutableStateFlow(false)
    val fresh: StateFlow<Boolean> = freshFlow

    val draft = MutableStateFlow("")

    private var loadJob: Job? = null

    val directory: String? get() = currentFlow.value?.directory ?: newIn.value

    suspend fun refresh() {
        try {
            val projects = client.projects().sortedByDescending { it.time.updated }
            projectsFlow.value = projects
            val perProject = coroutineScope {
                projects.take(6).map { project ->
                    async {
                        val list = runCatching { client.sessions(project.worktree, 8) }.getOrDefault(emptyList())
                        val status = runCatching { client.status(project.worktree) }.getOrDefault(emptyMap())
                        list to status
                    }
                }.awaitAll()
            }
            sessionsFlow.value = perProject.flatMap { it.first }.filter { it.parentID == null }.distinctBy { it.id }.sortedByDescending { it.time.updated }
            statusFlow.value = perProject.flatMap { it.second.entries }.associate { it.key to it.value }
            currentFlow.value?.let { cur -> sessionsFlow.value.firstOrNull { it.id == cur.id }?.let { currentFlow.value = it } }
            freshFlow.value = true
        } catch (err: Exception) {
            freshFlow.value = false
            throw err
        }
    }

    suspend fun enter() {
        if (providersFlow.value == null) runCatching { loadProviders() }
        if (currentFlow.value != null || newIn.value != null) return
        runCatching { refresh() }
        val last = store.prefs.lastCodeSession
        val found = sessionsFlow.value.firstOrNull { it.id == last }
        if (found != null) open(found) else startNew()
    }

    private suspend fun loadProviders() {
        val list = client.providers()
        providersFlow.value = list
        if (modelFlow.value == null) {
            val configured = runCatching { client.configuredModel() }.getOrNull()
            modelFlow.value = parseModel(configured) ?: choices().firstOrNull()
        }
    }

    private fun choices(): List<CodeModel> {
        val p = providersFlow.value ?: return emptyList()
        val ids = p.connected.filter { it != "opencode" }.ifEmpty { p.connected }
        return ids.mapNotNull { id -> p.default[id]?.let { CodeModel(id, it) } }
    }

    fun cycleModel() {
        val options = choices()
        if (options.isEmpty()) return
        val index = options.indexOfFirst { it == modelFlow.value }
        val next = options[(index + 1) % options.size]
        modelFlow.value = next
        store.prefs.codeModel = "${next.providerID}/${next.modelID}"
    }

    fun open(session: CodeSession) {
        currentFlow.value = session
        newIn.value = null
        store.prefs.lastCodeSession = session.id
        store.prefs.lastCodeDir = session.directory
        entriesFlow.value = emptyList()
        asksFlow.value = emptyList()
        questionsFlow.value = emptyList()
        loadJob?.cancel()
        loadJob = store.scope.launch { runCatching { load(session) }.onFailure { store.report(it) } }
    }

    private suspend fun load(session: CodeSession) {
        val list = client.messages(session.id, session.directory, 80)
        if (currentFlow.value?.id != session.id) return
        entriesFlow.value = list
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

    fun send(text: String) = store.act {
        val body = text.trim()
        if (body.isEmpty()) return@act
        var session = currentFlow.value
        if (session == null) {
            val dir = newIn.value ?: store.prefs.lastCodeDir ?: "/home/m"
            session = client.create(dir)
            currentFlow.value = session
            newIn.value = null
            store.prefs.lastCodeSession = session.id
            store.prefs.lastCodeDir = session.directory
            sessionsFlow.value = listOf(session) + sessionsFlow.value.filter { it.id != session.id }
        }
        val chosen = modelFlow.value
        client.prompt(session.id, session.directory, body, chosen?.providerID, chosen?.modelID)
        draft.value = ""
        statusFlow.value = statusFlow.value + (session.id to CodeStatus("busy"))
    }

    fun stop() = store.act {
        val session = currentFlow.value ?: return@act
        client.abort(session.id, session.directory)
    }

    fun allow(ask: PermissionAsk, response: String) = store.act {
        val dir = directory ?: return@act
        asksFlow.value = asksFlow.value.filter { it.id != ask.id }
        client.permission(ask.sessionID, ask.id, dir, response)
    }

    fun answer(question: QuestionAsk, answers: List<List<String>>) = store.act {
        val dir = directory ?: return@act
        questionsFlow.value = questionsFlow.value.filter { it.id != question.id }
        client.answer(question.id, dir, answers)
    }

    fun rejectQuestion(question: QuestionAsk) = store.act {
        val dir = directory ?: return@act
        questionsFlow.value = questionsFlow.value.filter { it.id != question.id }
        client.reject(question.id, dir)
    }

    suspend fun watch(dir: String?) {
        while (currentCoroutineContext().isActive) {
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

    private fun handle(event: CodeEvent) {
        val p = event.properties
        val sessionID = p["sessionID"]?.jsonPrimitive?.contentOrNull
        val mine = sessionID != null && sessionID == currentFlow.value?.id
        when (event.type) {
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
