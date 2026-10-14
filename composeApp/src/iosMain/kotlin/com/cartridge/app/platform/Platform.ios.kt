package com.cartridge.app.platform

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import platform.Foundation.NSURL
import platform.UIKit.UIActivityViewController
import platform.UIKit.UIApplication

@Composable
actual fun PlatformBackHandler(enabled: Boolean, onBack: () -> Unit) {
    // iOS has no hardware back button; the iOS shell lands in milestone M6.
}

@Composable
actual fun SystemBarsEffect(immersive: Boolean) {
    // Status bar control is wired up in the iOS host in milestone M6.
}

@Composable
actual fun LockOrientation(mode: OrientationMode) {
    // Orientation control is wired up in the iOS host in milestone M6.
}

@Composable
actual fun rememberSharer(): (String) -> Unit = remember {
    { text ->
        val controller = UIActivityViewController(
            activityItems = listOf(text),
            applicationActivities = null,
        )
        UIApplication.sharedApplication.keyWindow?.rootViewController
            ?.presentViewController(controller, animated = true, completion = null)
    }
}

@Composable
actual fun rememberUrlOpener(): (String) -> Unit = remember {
    { url ->
        NSURL.URLWithString(url)?.let { nsUrl ->
            UIApplication.sharedApplication.openURL(nsUrl)
        }
    }
}
