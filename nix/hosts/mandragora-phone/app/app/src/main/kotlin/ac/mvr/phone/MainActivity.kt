package ac.mvr.phone

import android.Manifest
import android.content.ComponentName
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import ac.mvr.phone.play.PlaybackService
import ac.mvr.phone.ui.FindSheet
import ac.mvr.phone.ui.MandragoraTheme
import ac.mvr.phone.ui.MusicScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors

class MainActivity : ComponentActivity() {
    private var controllerFuture: ListenableFuture<MediaController>? = null

    private val permissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        askPermissions()
        setContent {
            val palette by store.palette.collectAsStateWithLifecycle()
            MandragoraTheme(palette) {
                Root()
            }
        }
    }

    private fun askPermissions() {
        val wanted = ArrayList<String>()
        if (Build.VERSION.SDK_INT >= 33) {
            wanted.add(Manifest.permission.POST_NOTIFICATIONS)
            wanted.add(Manifest.permission.READ_MEDIA_AUDIO)
        } else {
            wanted.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        val missing = wanted.filter { checkSelfPermission(it) != android.content.pm.PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) permissions.launch(missing.toTypedArray())
    }

    override fun onStart() {
        super.onStart()
        store.foreground.value = true
        val token = SessionToken(this, ComponentName(this, PlaybackService::class.java))
        controllerFuture = MediaController.Builder(this, token).buildAsync().also { future ->
            future.addListener({ runCatching { future.get() } }, MoreExecutors.directExecutor())
        }
    }

    override fun onStop() {
        store.foreground.value = false
        controllerFuture?.let { MediaController.releaseFuture(it) }
        controllerFuture = null
        super.onStop()
    }

    private fun desktopHoldsVolumeKeys(): Boolean = !store.now.value.phoneOwns && store.reachable.value

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        val step = when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> 4
            KeyEvent.KEYCODE_VOLUME_DOWN -> -4
            else -> return super.onKeyDown(keyCode, event)
        }
        if (!desktopHoldsVolumeKeys()) return super.onKeyDown(keyCode, event)
        store.stepSinkVolumeAsync(step)
        return true
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        val volumeKey = keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        return if (volumeKey && desktopHoldsVolumeKeys()) true else super.onKeyUp(keyCode, event)
    }

    @Composable
    private fun Root() {
        val scheme = MaterialTheme.colorScheme
        var find by remember { mutableStateOf(false) }
        Scaffold(containerColor = scheme.surface) { padding ->
            Box(modifier = Modifier.fillMaxSize().background(scheme.surface).padding(padding)) {
                MusicScreen(store, onFind = { find = true })
                if (find) FindSheet(store, onDismiss = { find = false })
            }
        }
    }
}
