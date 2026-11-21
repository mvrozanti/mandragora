package ac.mvr.phone.media

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Size
import ac.mvr.phone.logic.PhoneMediaItem
import ac.mvr.phone.logic.hex
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.security.MessageDigest

data class Digest(val sha256: String, val length: Long)

private const val THUMB_PX = 320
private const val THUMB_QUALITY = 80
private const val READ_CHUNK = 1 shl 16
private val DRAINED = listOf(
    "DCIM/",
    "Pictures/",
    "Movies/",
    "Android/media/com.whatsapp/WhatsApp/Media/",
    "Recordings/",
    "Download/",
)
private val KINDS = mapOf(
    MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE to "image",
    MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO to "video",
    MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO to "audio",
)

class PhoneMedia(private val context: Context) {
    private val resolver get() = context.contentResolver

    fun allowed(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()

    fun list(): List<PhoneMediaItem> = query(null, null)

    fun find(id: Long): PhoneMediaItem? = query("${MediaStore.MediaColumns._ID} = ?", arrayOf(id.toString())).firstOrNull()

    private fun query(extra: String?, extraArgs: Array<String>?): List<PhoneMediaItem> {
        val path = MediaStore.MediaColumns.RELATIVE_PATH
        val visual = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?, ?) AND ($path IS NULL OR $path NOT LIKE ?)"
        val drained = DRAINED.joinToString(" OR ") { "$path LIKE ?" }
        val scope = "(($visual) OR (($drained) AND ${MediaStore.MediaColumns.MIME_TYPE} IS NOT NULL))"
        val selection = if (extra == null) scope else "$scope AND $extra"
        val args = arrayOf(
            MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
            MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString(),
            "Music/%",
        ) + DRAINED.map { "$it%" } + (extraArgs ?: emptyArray())
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.DATE_MODIFIED,
        )
        val found = mutableListOf<PhoneMediaItem>()
        resolver.query(MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL), projection, selection, args, null)?.use { c ->
            while (c.moveToNext()) {
                found += PhoneMediaItem(
                    id = c.getLong(0),
                    name = c.getString(1).orEmpty(),
                    path = c.getString(2).orEmpty(),
                    kind = KINDS[c.getInt(3)] ?: "file",
                    mime = c.getString(4).orEmpty(),
                    size = c.getLong(5),
                    taken = c.getLong(6),
                    modified = c.getLong(7),
                )
            }
        }
        return found
    }

    private fun uri(item: PhoneMediaItem): Uri = ContentUris.withAppendedId(
        when (item.kind) {
            "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            else -> MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        },
        item.id,
    )

    fun open(item: PhoneMediaItem): InputStream = resolver.openInputStream(uri(item)) ?: error("cannot open ${item.name}")

    fun digest(item: PhoneMediaItem): Digest {
        val sha = MessageDigest.getInstance("SHA-256")
        var length = 0L
        open(item).use { input ->
            val buffer = ByteArray(READ_CHUNK)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                sha.update(buffer, 0, n)
                length += n
            }
        }
        return Digest(hex(sha.digest()), length)
    }

    fun thumbnail(item: PhoneMediaItem): ByteArray {
        val bitmap = resolver.loadThumbnail(uri(item), Size(THUMB_PX, THUMB_PX), null)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, THUMB_QUALITY, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    fun delete(item: PhoneMediaItem): Boolean =
        runCatching { resolver.delete(uri(item), null, null) > 0 }.getOrDefault(false) || deleteFile(item)

    private fun deleteFile(item: PhoneMediaItem): Boolean {
        @Suppress("DEPRECATION")
        val file = File(Environment.getExternalStorageDirectory(), item.path + item.name)
        val deleted = file.isFile && file.delete()
        if (deleted) MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), null, null)
        return deleted
    }
}
