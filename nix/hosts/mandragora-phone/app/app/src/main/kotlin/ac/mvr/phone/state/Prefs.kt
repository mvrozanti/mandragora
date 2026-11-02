package ac.mvr.phone.state

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class Prefs(context: Context) {
    private val prefs: SharedPreferences = runCatching {
        val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        EncryptedSharedPreferences.create(
            context,
            "mandragora-secure",
            key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }.getOrElse { context.getSharedPreferences("mandragora-plain", Context.MODE_PRIVATE) }

    var syncForkApiKey: String?
        get() = prefs.getString("syncfork_api_key", null)?.ifBlank { null }
        set(value) { prefs.edit().putString("syncfork_api_key", value).apply() }

    var musicRelativePath: String
        get() = prefs.getString("music_relative_path", "Music/") ?: "Music/"
        set(value) { prefs.edit().putString("music_relative_path", value).apply() }
}
