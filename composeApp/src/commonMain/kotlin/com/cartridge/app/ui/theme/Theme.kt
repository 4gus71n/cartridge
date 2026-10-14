package com.cartridge.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val CartridgeColorScheme = darkColorScheme(
    primary = Color(0xFF7C5CFF),
    onPrimary = Color.White,
    secondary = Color(0xFF22D3EE),
    onSecondary = Color.Black,
    background = Color.Black,
    onBackground = Color.White,
    surface = Color(0xFF141419),
    onSurface = Color.White,
)

@Composable
fun CartridgeTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = CartridgeColorScheme,
        content = content,
    )
}
