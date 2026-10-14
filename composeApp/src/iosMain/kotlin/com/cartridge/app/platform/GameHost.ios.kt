package com.cartridge.app.platform

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

actual fun externalGameUrl(source: GameSource): String? =
    (source as? GameSource.Remote)?.url

@Composable
actual fun GameHost(
    source: GameSource,
    modifier: Modifier,
    desktopMode: Boolean,
    onPageFinished: () -> Unit,
    onError: (String) -> Unit,
) {
    Box(modifier = modifier.background(Color.Black), contentAlignment = Alignment.Center) {
        Text(text = "iOS game runtime ships in milestone M6", color = Color.White)
    }
}
