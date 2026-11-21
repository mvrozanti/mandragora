package ac.mvr.phone.state

import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import ac.mvr.phone.net.SttClient
import ac.mvr.phone.net.SttStatus
import ac.mvr.phone.net.json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.io.IOException

@Serializable
data class Transcript(
    val id: Long,
    val at: Long,
    val text: String,
    val language: String = "",
    val probability: Double = 0.0,
    val duration: Double = 0.0,
    val elapsed: Double = 0.0,
    val task: String = "transcribe",
    val origin: String = "recording",
)

enum class VoicePhase { IDLE, RECORDING, SENDING }

class VoiceStore(private val store: Store) {
    private val client = SttClient { store.bridgeUrl }

    private val phaseFlow = MutableStateFlow(VoicePhase.IDLE)
    val phase: StateFlow<VoicePhase> = phaseFlow

    private val startedFlow = MutableStateFlow(0L)
    val startedAt: StateFlow<Long> = startedFlow

    private val statusFlow = MutableStateFlow<SttStatus?>(null)
    val status: StateFlow<SttStatus?> = statusFlow

    private val historyFlow = MutableStateFlow(readHistory())
    val history: StateFlow<List<Transcript>> = historyFlow

    private var recorder: MediaRecorder? = null
    private var recording: File? = null

    suspend fun refresh() {
        statusFlow.value = runCatching { client.status() }.onFailure { statusFlow.value = null }.getOrThrow()
    }

    fun warmup() = store.act {
        try {
            client.warmup()
        } catch (err: IOException) {
            throw IllegalStateException(detail(err), err)
        }
        refresh()
    }

    fun record() {
        if (phaseFlow.value != VoicePhase.IDLE) return
        val context = store.appContext
        val file = File(context.cacheDir, "voice-${System.currentTimeMillis()}.m4a")
        val next = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        val started = runCatching {
            next.setAudioSource(MediaRecorder.AudioSource.MIC)
            next.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            next.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            next.setAudioChannels(1)
            next.setAudioSamplingRate(16_000)
            next.setAudioEncodingBitRate(48_000)
            next.setOutputFile(file.path)
            next.prepare()
            next.start()
        }.isSuccess
        if (!started) {
            next.release()
            file.delete()
            store.report(IllegalStateException("the microphone would not start"))
            return
        }
        recorder = next
        recording = file
        startedFlow.value = SystemClock.elapsedRealtime()
        phaseFlow.value = VoicePhase.RECORDING
    }

    fun stop(send: Boolean = true) {
        val current = recorder ?: return
        val file = recording
        recorder = null
        recording = null
        val stopped = runCatching { current.stop() }.isSuccess
        current.release()
        phaseFlow.value = VoicePhase.IDLE
        when {
            file == null -> Unit
            send && stopped && file.length() > 0L -> send(file, "audio/mp4", "recording")
            else -> {
                file.delete()
                if (send && !stopped) store.report(IllegalStateException("too short to send"))
            }
        }
    }

    fun transcribeShared(uri: Uri) = store.act {
        check(phaseFlow.value == VoicePhase.IDLE) { "busy with another clip" }
        val context = store.appContext
        val type = context.contentResolver.getType(uri) ?: "application/octet-stream"
        val name = withContext(Dispatchers.IO) {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }
        val suffix = name?.substringAfterLast('.', "")?.takeIf { it.isNotEmpty() }
            ?: MimeTypeMap.getSingleton().getExtensionFromMimeType(type)
            ?: "bin"
        val file = File(context.cacheDir, "shared-${System.currentTimeMillis()}.$suffix")
        withContext(Dispatchers.IO) {
            val input = context.contentResolver.openInputStream(uri) ?: error("could not read the shared clip")
            input.use { source -> file.outputStream().use { source.copyTo(it) } }
        }
        send(file, type, name ?: "shared")
    }

    private fun send(file: File, type: String, origin: String) = store.act {
        phaseFlow.value = VoicePhase.SENDING
        try {
            val task = store.prefs.voiceTask.value
            val language = store.prefs.voiceLang.value.ifBlank { null }
            val result = try {
                client.transcribe(file, type, task, language)
            } catch (err: IOException) {
                throw IllegalStateException(detail(err), err)
            }
            val entry = Transcript(
                id = System.currentTimeMillis(),
                at = System.currentTimeMillis(),
                text = result.text.ifBlank { "(no speech detected)" },
                language = result.language,
                probability = result.probability,
                duration = result.duration,
                elapsed = result.elapsed,
                task = result.task,
                origin = origin,
            )
            keep(listOf(entry) + historyFlow.value)
            runCatching { refresh() }
        } finally {
            withContext(Dispatchers.IO) { file.delete() }
            phaseFlow.value = VoicePhase.IDLE
        }
    }

    fun forget(id: Long) = keep(historyFlow.value.filterNot { it.id == id })

    private fun keep(list: List<Transcript>) {
        val next = list.take(KEEP)
        historyFlow.value = next
        store.prefs.voiceHistory = json.encodeToString(ListSerializer(Transcript.serializer()), next)
    }

    private fun readHistory(): List<Transcript> =
        store.prefs.voiceHistory?.let { runCatching { json.decodeFromString<List<Transcript>>(it) }.getOrNull() } ?: emptyList()

    private fun detail(err: IOException): String =
        Regex("\"detail\":\\s*\"([^\"]+)\"").find(err.message ?: "")?.groupValues?.get(1) ?: err.message ?: "stt failed"

    private companion object {
        const val KEEP = 30
    }
}
