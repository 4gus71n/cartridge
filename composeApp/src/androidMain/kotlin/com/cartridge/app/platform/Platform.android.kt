package com.cartridge.app.platform

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

actual fun apiBaseUrls(): List<String> = listOf(
    "http://127.0.0.1:8123", // adb reverse (USB dev)
    "http://192.168.1.24:8123", // Mac on local Wi-Fi (cable-free)
    "http://agustins-macbook-pro.local:8123", // Bonjour name (resolves even if the IP changes)
    "http://10.0.2.2:8123", // emulator alias for the host
)

@Composable
actual fun PlatformBackHandler(enabled: Boolean, onBack: () -> Unit) {
    BackHandler(enabled = enabled, onBack = onBack)
}

@Composable
actual fun LockOrientation(mode: OrientationMode) {
    val view = LocalView.current
    val activity = LocalContext.current.findActivity() ?: return
    if (view.isInEditMode) return

    DisposableEffect(mode) {
        activity.requestedOrientation = when (mode) {
            OrientationMode.PORTRAIT -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            OrientationMode.LANDSCAPE -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            OrientationMode.ANY -> ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
        }
        onDispose { }
    }
}

@Composable
actual fun SystemBarsEffect(immersive: Boolean) {
    val view = LocalView.current
    val activity = LocalContext.current.findActivity()
    val configuration = LocalConfiguration.current
    if (view.isInEditMode || activity == null) return

    DisposableEffect(immersive, configuration.orientation) {
        val window = activity.window
        val controller = WindowCompat.getInsetsController(window, view)
        if (immersive) {
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        onDispose {
            controller.show(WindowInsetsCompat.Type.systemBars())
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
}

@Composable
actual fun rememberSharer(): (String) -> Unit {
    val context = LocalContext.current
    return remember(context) {
        { text ->
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            context.startActivity(
                Intent.createChooser(intent, "Share cartridge")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
}

@Composable
actual fun rememberUrlOpener(): (String) -> Unit {
    val context = LocalContext.current
    return remember(context) {
        { url ->
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }
}

private fun Context.findActivity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}
