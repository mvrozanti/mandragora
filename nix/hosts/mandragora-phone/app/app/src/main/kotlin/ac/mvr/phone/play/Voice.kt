package ac.mvr.phone.play

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File

class Voice(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private val file: File get() = File(context.cacheDir, "voice.m4a")

    val recording: Boolean get() = recorder != null

    fun start(): Boolean {
        release()
        file.delete()
        return runCatching {
            val made = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
            recorder = made
            made.setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            made.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            made.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            made.setAudioSamplingRate(16_000)
            made.setAudioChannels(1)
            made.setAudioEncodingBitRate(32_000)
            made.setOutputFile(file.absolutePath)
            made.prepare()
            made.start()
        }.onFailure { release() }.isSuccess
    }

    fun finish(): File? {
        val stopped = runCatching { recorder?.stop() }.isSuccess
        release()
        return file.takeIf { stopped && it.length() > 0 }
    }

    fun cancel() {
        runCatching { recorder?.stop() }
        release()
        file.delete()
    }

    private fun release() {
        recorder?.release()
        recorder = null
    }
}
