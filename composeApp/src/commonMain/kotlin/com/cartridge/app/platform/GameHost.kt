package com.cartridge.app.platform

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/** URL a real browser can open for this game (escape hatch for engine limits). */
expect fun externalGameUrl(source: GameSource): String?

@Composable
expect fun GameHost(
    source: GameSource,
    /** Game slug: namespace for `window.cartridge.storage` (see GameBridge.kt). */
    slug: String,
    modifier: Modifier = Modifier,
    desktopMode: Boolean = false,
    onPageFinished: () -> Unit,
    onError: (String) -> Unit,
)
