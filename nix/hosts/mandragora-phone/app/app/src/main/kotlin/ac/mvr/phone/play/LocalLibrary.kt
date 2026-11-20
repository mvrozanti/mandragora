package ac.mvr.phone.play

import android.content.ContentUris
import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.MediaStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class LocalTrack(val uri: Uri, val relativePath: String, val displayName: String, val durationMs: Long)

class LocalLibrary(private val context: Context) {
    suspend fun find(mpdFile: String): LocalTrack? = withContext(Dispatchers.IO) {
        val name = mpdFile.substringAfterLast('/')
        val dir = mpdFile.substringBeforeLast('/', "")
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.RELATIVE_PATH,
            MediaStore.Audio.Media.DURATION,
        )
        val candidates = ArrayList<LocalTrack>()
        context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Audio.Media.DISPLAY_NAME} = ?",
            arrayOf(name),
            null,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val pathCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.RELATIVE_PATH)
            val durCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                candidates.add(
                    LocalTrack(
                        uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id),
                        relativePath = cursor.getString(pathCol) ?: "",
                        displayName = cursor.getString(nameCol) ?: name,
                        durationMs = cursor.getLong(durCol),
                    ),
                )
            }
        }
        if (candidates.isEmpty()) return@withContext null
        if (dir.isNotEmpty()) return@withContext candidates.firstOrNull { "/${it.relativePath.trimEnd('/')}".endsWith("/$dir") }
        candidates.firstOrNull { it.relativePath.contains("Music", ignoreCase = true) } ?: candidates.first()
    }

    suspend fun artwork(uri: Uri): ByteArray? = withContext(Dispatchers.IO) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            retriever.embeddedPicture?.let { Artwork.shrink(it) }
        } catch (err: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    suspend fun names(): Set<String> = withContext(Dispatchers.IO) {
        val names = HashSet<String>()
        context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Audio.Media.DISPLAY_NAME),
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            null,
        )?.use { cursor ->
            val col = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            while (cursor.moveToNext()) cursor.getString(col)?.let(names::add)
        }
        names
    }
}
