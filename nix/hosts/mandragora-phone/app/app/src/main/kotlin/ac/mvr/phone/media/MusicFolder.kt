package ac.mvr.phone.media

import android.content.Context
import android.media.MediaScannerConnection
import android.os.Environment
import android.os.storage.StorageManager
import ac.mvr.phone.logic.MirrorFile
import ac.mvr.phone.logic.mirroredName
import ac.mvr.phone.net.Http
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

private const val KEEP_FREE = 2L shl 30
private const val COPY_CHUNK = 1 shl 16

class NoRoom : IOException("the phone is nearly full")

class MusicFolder(private val context: Context) {
    @Suppress("DEPRECATION")
    private val root = File(Environment.getExternalStorageDirectory(), Environment.DIRECTORY_MUSIC)

    fun list(): Map<String, Long> {
        val found = HashMap<String, Long>()
        val pending = ArrayDeque(listOf(root to ""))
        while (pending.isNotEmpty()) {
            val (dir, prefix) = pending.removeFirst()
            for (entry in dir.listFiles().orEmpty()) {
                val rel = prefix + entry.name
                when {
                    entry.name.startsWith(".") -> Unit
                    entry.isDirectory -> pending.addLast(entry to "$rel/")
                    entry.isFile && mirroredName(entry.name) -> found[rel] = entry.length()
                }
            }
        }
        return found
    }

    fun fetch(file: MirrorFile, url: String) {
        val target = File(root, file.path)
        val part = partFor(target)
        if (part.length() > file.size) part.delete()
        val from = part.length()
        if (spare() - (file.size - from) < KEEP_FREE) throw NoRoom()
        if (from < file.size) download(url, part, from)
        place(part, target, file)
        scan(target)
    }

    fun drop(path: String): Boolean {
        val target = File(root, path)
        if (target.exists() && !target.delete()) return false
        scan(target)
        generateSequence(target.parentFile) { it.parentFile }
            .takeWhile { it != root && it.list()?.isEmpty() == true }
            .all { it.delete() }
        return true
    }

    private fun partFor(target: File): File {
        val dir = target.parentFile
        if (dir == null || !(dir.isDirectory || dir.mkdirs())) throw IOException("cannot make the folder for ${target.name}")
        return File(dir, ".${target.name}.part")
    }

    private fun place(part: File, target: File, file: MirrorFile) {
        if (!part.exists()) part.createNewFile()
        if (part.length() != file.size) {
            part.delete()
            throw IOException("${file.path} changed while it was copied")
        }
        val cleared = !target.exists() || target.delete()
        if (!cleared || !part.renameTo(target)) throw IOException("cannot place ${file.path}")
        target.setLastModified(file.mtime * 1000)
    }

    private fun download(url: String, part: File, from: Long) {
        val request = Request.Builder().url(url).apply { if (from > 0) header("Range", "bytes=$from-") }.build()
        Http.client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("${response.code} ${request.url.encodedPath}")
            val body = response.body ?: throw IOException("empty body")
            FileOutputStream(part, response.code == 206).use { out -> body.byteStream().use { it.copyTo(out, COPY_CHUNK) } }
        }
    }

    private fun spare(): Long {
        val storage = context.getSystemService(StorageManager::class.java) ?: return 0L
        return runCatching { storage.getAllocatableBytes(StorageManager.UUID_DEFAULT) }.getOrDefault(0L)
    }

    private fun scan(file: File) {
        MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), null, null)
    }
}
