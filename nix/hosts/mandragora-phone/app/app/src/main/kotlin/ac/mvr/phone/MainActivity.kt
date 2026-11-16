package ac.mvr.phone

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.BackHandler
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import ac.mvr.phone.play.PlaybackService
import ac.mvr.phone.ui.CodeScreen
import ac.mvr.phone.ui.FindScreen
import ac.mvr.phone.ui.HomeScreen
import ac.mvr.phone.ui.HubScreen
import ac.mvr.phone.ui.MandragoraTheme
import ac.mvr.phone.ui.MoneyScreen
import ac.mvr.phone.ui.MusicScreen
import ac.mvr.phone.ui.SettingsScreen
import ac.mvr.phone.ui.PanicScreen
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
        requestScreen(intent)
        setContent {
            val palette by store.palette.collectAsStateWithLifecycle()
            MandragoraTheme(palette) {
                Root()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        requestScreen(intent)
    }

    private fun requestScreen(intent: Intent?) {
        val screen = intent?.getStringExtra("screen") ?: return
        intent.removeExtra("screen")
        store.requestedScreen.value = screen
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
        store.applyIconBucket()
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
        var screen by rememberSaveable { mutableStateOf("home") }
        val requested by store.requestedScreen.collectAsStateWithLifecycle()
        LaunchedEffect(requested) {
            val target = requested ?: return@LaunchedEffect
            screen = target
            store.requestedScreen.value = null
        }
        val focus = LocalFocusManager.current
        val keyboard = LocalSoftwareKeyboardController.current
        LaunchedEffect(screen) {
            if (screen != "find") {
                focus.clearFocus(force = true)
                keyboard?.hide()
            }
        }
        BackHandler(enabled = screen != "home") { screen = if (screen == "find") "music" else "home" }
        Scaffold(containerColor = scheme.surface) { padding ->
            Box(modifier = Modifier.fillMaxSize().background(scheme.surface).padding(padding).consumeWindowInsets(padding).imePadding()) {
                AnimatedContent(
                    targetState = screen,
                    transitionSpec = { (fadeIn(tween(180)) + scaleIn(initialScale = 0.96f, animationSpec = tween(220))) togetherWith fadeOut(tween(120)) },
                    label = "screen",
                ) { target ->
                    when (target) {
                        "music" -> MusicScreen(store, onCollapse = { screen = "home" }, onFind = { screen = "find" })
                        "find" -> FindScreen(store) { screen = "music" }
                        "money" -> MoneyScreen(store) { screen = "home" }
                        "hub" -> HubScreen(store) { screen = "home" }
                        "panic" -> PanicScreen(store) { screen = "home" }
                        "settings" -> SettingsScreen(store) { screen = "home" }
                        "code" -> CodeScreen(store) { screen = "home" }
                        else -> HomeScreen(store) { screen = it }
                    }
                }
            }
        }
    }
}
