package ac.mvr.phone

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import ac.mvr.phone.play.PlaybackService
import ac.mvr.phone.ui.HomeScreen
import ac.mvr.phone.ui.MandragoraTheme
import ac.mvr.phone.ui.Sheet
import ac.mvr.phone.ui.SheetHost
import ac.mvr.phone.ui.StageScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors

class MainActivity : ComponentActivity() {
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private val sharedUrl = mutableStateOf<String?>(null)
    private val requestedSheet = mutableStateOf<Sheet?>(null)

    private val permissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        askPermissions()
        handleShare(intent)
        setContent {
            val palette by store.palette.collectAsStateWithLifecycle()
            MandragoraTheme(palette) {
                Root()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
    }

    private fun handleShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        val url = Regex("https?://\\S+").find(text)?.value ?: return
        sharedUrl.value = url
        requestedSheet.value = Sheet.Get
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

    @androidx.compose.runtime.Composable
    private fun Root() {
        val scheme = MaterialTheme.colorScheme
        var stage by remember { mutableStateOf(false) }
        var sheet by remember { mutableStateOf<Sheet?>(null) }
        val shared by sharedUrl
        val requested by requestedSheet

        LaunchedEffect(requested) {
            if (requested != null) { sheet = requested; requestedSheet.value = null }
        }
        BackHandler(enabled = stage && sheet == null) { stage = false }

        Scaffold(
            containerColor = scheme.surface,
        ) { padding ->
            Box(modifier = Modifier.fillMaxSize().background(scheme.surface).padding(padding)) {
                if (stage) {
                    StageScreen(store, onHome = { stage = false }, onOpenSheet = { sheet = it })
                } else {
                    HomeScreen(
                        store,
                        onOpenSheet = { sheet = it },
                        onOpenStage = { stage = true },
                        onShare = { url -> sharedUrl.value = url; sheet = Sheet.Get },
                    )
                }
                SheetHost(store, sheet, shared, onDismiss = { sheet = null }, onConsumeShare = { sharedUrl.value = null })
            }
        }
    }
}
