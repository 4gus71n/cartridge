package com.cartridge.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cartridge.app.platform.LockOrientation
import com.cartridge.app.platform.OrientationMode
import com.cartridge.app.platform.orientationModeOf
import com.cartridge.app.state.AppState
import com.cartridge.app.ui.auth.AuthSheet
import com.cartridge.app.ui.comments.CommentsSheet
import com.cartridge.app.ui.credits.CreditsSheet
import com.cartridge.app.ui.feed.CreateCollectionDialog
import com.cartridge.app.ui.feed.FeedScreen
import com.cartridge.app.ui.feed.SaveSheet
import com.cartridge.app.ui.player.PlayerOverlay
import com.cartridge.app.ui.profile.ProfileOverlay
import com.cartridge.app.ui.report.ReportDialog
import com.cartridge.app.ui.theme.CartridgeTheme
import kotlinx.coroutines.delay

@Composable
fun App() {
    CartridgeTheme {
        val state = remember { AppState() }
        val playing = state.playing
        LockOrientation(
            playing?.let { orientationModeOf(it.orientation) } ?: OrientationMode.PORTRAIT,
        )
        Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
            FeedScreen(
                catalog = state.feed,
                state = state,
                modifier = Modifier.fillMaxSize(),
            )
            PlayerOverlay(state)
            CommentsSheet(state)
            CreditsSheet(state)
            ProfileOverlay(state)
            SaveSheet(state)
            AuthSheet(state)
            CreateCollectionDialog(state)
            ReportDialog(state)
            CartridgeSnackbar(state)
        }
    }
}

@Composable
private fun CartridgeSnackbar(state: AppState) {
    val message = state.snackbar
    LaunchedEffect(message) {
        if (message != null) {
            delay(2600)
            state.clearSnackbar()
        }
    }
    if (message != null) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            Text(
                text = message,
                color = Color.White,
                fontSize = 13.sp,
                modifier = Modifier
                    .navigationBarsPadding()
                    .padding(bottom = 96.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color(0xE6222230))
                    .padding(horizontal = 16.dp, vertical = 10.dp),
            )
        }
    }
}
