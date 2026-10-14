package com.cartridge.app.platform

import androidx.compose.runtime.Composable

@Composable
expect fun PlatformBackHandler(enabled: Boolean, onBack: () -> Unit)

@Composable
expect fun SystemBarsEffect(immersive: Boolean)

@Composable
expect fun rememberSharer(): (String) -> Unit

@Composable
expect fun rememberUrlOpener(): (String) -> Unit
