package ac.mvr.phone

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import ac.mvr.phone.inbox.InboxService
import ac.mvr.phone.play.PlaybackService
import ac.mvr.phone.state.Store
import ac.mvr.phone.ui.CodeScreen
import ac.mvr.phone.ui.FindScreen
import ac.mvr.phone.ui.HomeScreen
import ac.mvr.phone.ui.LocalChecking
import ac.mvr.phone.ui.LocalOpenTailscale
import ac.mvr.phone.ui.LocalVpnOff
import ac.mvr.phone.ui.HubScreen
import ac.mvr.phone.ui.AskScreen
import ac.mvr.phone.ui.InboxScreen
import ac.mvr.phone.ui.TeachScreen
import ac.mvr.phone.ui.WatchScreen
import ac.mvr.phone.ui.VoiceScreen
import ac.mvr.phone.ui.MandragoraTheme
import ac.mvr.phone.ui.MoneyScreen
import ac.mvr.phone.ui.MusicScreen
import ac.mvr.phone.ui.SessionsScreen
import ac.mvr.phone.ui.SettingsScreen
import ac.mvr.phone.ui.PanicScreen
import ac.mvr.phone.ui.GpuScreen
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
            val checking by store.checking.collectAsStateWithLifecycle()
            val vpnOff by store.vpnOff.collectAsStateWithLifecycle()
            MandragoraTheme(palette) {
                CompositionLocalProvider(LocalChecking provides checking, LocalVpnOff provides vpnOff, LocalOpenTailscale provides store::openTailscale) {
                    Root()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        requestScreen(intent)
    }

    private fun requestScreen(intent: Intent?) {
        when {
            intent == null -> Unit
            intent.action == Intent.ACTION_SEND -> receiveShared(intent, store)
            else -> intent.getStringExtra("screen")?.let { screen ->
                intent.removeExtra("screen")
                store.requestedScreen.value = screen
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
        store.photos.refreshAllowed()
        InboxService.sync(this)
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
        val routes = remember { routes(store) { screen = it } }
        Scaffold(containerColor = scheme.surface) { padding ->
            Box(modifier = Modifier.fillMaxSize().background(scheme.surface).padding(padding).consumeWindowInsets(padding).imePadding()) {
                AnimatedContent(
                    targetState = screen,
                    transitionSpec = { (fadeIn(tween(180)) + scaleIn(initialScale = 0.96f, animationSpec = tween(220))) togetherWith fadeOut(tween(120)) },
                    label = "screen",
                ) { target ->
                    val route = routes[target]
                    if (route != null) route() else HomeScreen(store) { screen = it }
                }
            }
        }
    }
}

private fun routes(store: Store, go: (String) -> Unit): Map<String, @Composable () -> Unit> = mapOf(
    "music" to { MusicScreen(store, onCollapse = { go("home") }, onFind = { go("find") }) },
    "find" to { FindScreen(store) { go("music") } },
    "money" to { MoneyScreen(store) { go("home") } },
    "hub" to { HubScreen(store) { go("home") } },
    "panic" to { PanicScreen(store) { go("home") } },
    "gpu" to { GpuScreen(store) { go("home") } },
    "settings" to { SettingsScreen(store) { go("home") } },
    "sessions" to { SessionsScreen(store, onOpenSession = { go("code") }) { go("home") } },
    "code" to { CodeScreen(store) { go("home") } },
    "inbox" to { InboxScreen(store, onCollapse = { go("home") }, onOpen = go) },
    "voice" to { VoiceScreen(store) { go("home") } },
    "watch" to { WatchScreen(store) { go("home") } },
    "ask" to { AskScreen(store) { go("home") } },
    "teach" to { TeachScreen(store) { go("home") } },
)

private fun receiveShared(intent: Intent, store: Store) {
    val type = intent.type.orEmpty()
    val clip = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
    else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
    intent.action = null
    if (clip != null && (type.startsWith("audio/") || type.startsWith("video/"))) {
        store.voice.transcribeShared(clip)
        store.requestedScreen.value = "voice"
    }
}
