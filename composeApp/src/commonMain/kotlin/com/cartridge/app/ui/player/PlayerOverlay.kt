package com.cartridge.app.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.Monitor
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cartridge.app.platform.GameHost
import com.cartridge.app.platform.GameSource
import com.cartridge.app.platform.PlatformBackHandler
import com.cartridge.app.platform.SystemBarsEffect
import com.cartridge.app.platform.externalGameUrl
import com.cartridge.app.platform.rememberUrlOpener
import com.cartridge.app.state.AppState

@Composable
fun PlayerOverlay(state: AppState) {
    val cartridge = state.playing ?: return

    var attempt by remember(cartridge.id) { mutableStateOf(0) }
    var source by remember(cartridge.id, attempt) { mutableStateOf<GameSource?>(null) }
    var progress by remember(cartridge.id, attempt) { mutableStateOf<Float?>(null) }
    var prepareError by remember(cartridge.id, attempt) { mutableStateOf<String?>(null) }
    var loading by remember(cartridge.id, attempt) { mutableStateOf(true) }
    var pageError by remember(cartridge.id, attempt) { mutableStateOf<String?>(null) }
    var keyboardVisible by remember(cartridge.id) { mutableStateOf(false) }
    var desktopMode by remember(cartridge.id) { mutableStateOf(state.isDesktopMode(cartridge.id)) }
    val openUrl = rememberUrlOpener()
    val externalUrl = source?.let { externalGameUrl(it) }

    PlatformBackHandler(enabled = true) { state.closePlayer() }
    SystemBarsEffect(immersive = true)

    LaunchedEffect(cartridge.id, attempt) {
        runCatching {
            state.gameStorage.resolve(
                slug = cartridge.id,
                bundledPath = if (cartridge.bundled) cartridge.assetPath else null,
                packageUrl = cartridge.packageUrl,
                packageSha256 = cartridge.packageSha256,
                playUrl = cartridge.playUrl,
            ) { value -> progress = value }
        }
            .onSuccess { resolved ->
                source = resolved
                progress = null
            }
            .onFailure { error ->
                prepareError = error.message ?: "Could not prepare this game"
                progress = null
            }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .background(Color.Black),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { state.closePlayer() }) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = "Close game",
                    tint = Color.White,
                )
            }
            IconButton(onClick = { keyboardVisible = !keyboardVisible }) {
                Icon(
                    imageVector = Icons.Filled.Keyboard,
                    contentDescription = "Keyboard controls",
                    tint = if (keyboardVisible) Color(0xFF7C5CFF) else Color.White.copy(alpha = 0.6f),
                )
            }
            IconButton(
                onClick = {
                    desktopMode = !desktopMode
                    state.setDesktopMode(cartridge.id, desktopMode)
                },
            ) {
                Icon(
                    imageVector = Icons.Filled.Monitor,
                    contentDescription = "Desktop mode",
                    tint = if (desktopMode) Color(0xFF7C5CFF) else Color.White.copy(alpha = 0.6f),
                )
            }
            if (externalUrl != null) {
                IconButton(onClick = { openUrl(externalUrl) }) {
                    Icon(
                        imageVector = Icons.Filled.OpenInNew,
                        contentDescription = "Open in browser",
                        tint = Color.White.copy(alpha = 0.6f),
                    )
                }
            }
            Spacer(modifier = Modifier.weight(1f))
        }

        Box(modifier = Modifier.fillMaxWidth().weight(1f)) {
            val currentSource = source
            val currentPrepareError = prepareError
            val currentPageError = pageError

            if (currentSource != null && currentPrepareError == null && currentPageError == null) {
                key(currentSource, desktopMode) {
                    GameHost(
                        source = currentSource,
                        modifier = Modifier.fillMaxSize(),
                        desktopMode = desktopMode,
                        onPageFinished = { loading = false },
                        onError = { message ->
                            pageError = message
                            loading = false
                        },
                    )
                }
            }

            if (currentSource == null && currentPrepareError == null) {
                Column(
                    modifier = Modifier.align(Alignment.Center),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    CircularProgressIndicator(color = Color.White)
                    progress?.let { value ->
                        Text(
                            text = "Downloading for offline… ${(value * 100).toInt()}%",
                            color = Color.White.copy(alpha = 0.7f),
                            fontSize = 13.sp,
                        )
                    }
                }
            }

            if (currentPrepareError != null) {
                ErrorPanel(
                    title = "Couldn't load this cartridge",
                    message = currentPrepareError,
                    onRetry = { attempt += 1 },
                    modifier = Modifier.align(Alignment.Center),
                )
            }

            if (currentPageError != null) {
                ErrorPanel(
                    title = "The cartridge failed to boot",
                    message = currentPageError,
                    onRetry = { pageError = null; loading = true; attempt += 1 },
                    modifier = Modifier.align(Alignment.Center),
                )
            }

            if (loading && currentSource != null && currentPageError == null) {
                CircularProgressIndicator(
                    color = Color.White,
                    modifier = Modifier.align(Alignment.Center),
                )
            }

            if (keyboardVisible && currentPageError == null) {
                KeyboardOverlay(modifier = Modifier.align(Alignment.BottomCenter))
            }
        }
    }
}

@Composable
private fun ErrorPanel(
    title: String,
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = title,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 18.sp,
        )
        Text(
            text = message,
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
        )
        Button(onClick = onRetry) {
            Text("Retry")
        }
    }
}
