package com.cartridge.app.platform

import androidx.compose.runtime.Composable

enum class OrientationMode { PORTRAIT, LANDSCAPE, ANY }

@Composable
expect fun LockOrientation(mode: OrientationMode)

fun orientationModeOf(value: String): OrientationMode = when (value.lowercase()) {
    "portrait" -> OrientationMode.PORTRAIT
    "landscape" -> OrientationMode.LANDSCAPE
    else -> OrientationMode.ANY
}
