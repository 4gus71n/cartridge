package com.cartridge.app.ui.credits

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cartridge.app.platform.rememberUrlOpener
import com.cartridge.app.state.AppState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreditsSheet(state: AppState) {
    val cartridge = state.creditsFor ?: return
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val openUrl = rememberUrlOpener()

    ModalBottomSheet(
        onDismissRequest = { state.closeCredits() },
        sheetState = sheetState,
        containerColor = Color(0xFF141419),
        dragHandle = { BottomSheetDefaults.DragHandle() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 36.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = cartridge.title,
                color = Color.White,
                fontWeight = FontWeight.ExtraBold,
                fontSize = 24.sp,
            )
            Text(
                text = "by ${cartridge.author.name} · @${cartridge.author.handle}",
                color = Color.White.copy(alpha = 0.7f),
                fontSize = 14.sp,
            )

            InfoRow(label = "License", value = cartridge.licenseSpdx)

            if (cartridge.isOriginal) {
                InfoRow(label = "Source", value = "Original — made for Cartridge")
            } else {
                InfoRow(
                    label = "Source",
                    value = cartridge.sourceUrl,
                    isLink = true,
                    onClick = { openUrl(cartridge.sourceUrl) },
                )
                cartridge.modifications?.let { modifications ->
                    InfoRow(label = "Modifications", value = modifications)
                }
            }

            Text(
                text = "The full license text ships inside the game package.",
                color = Color.White.copy(alpha = 0.45f),
                fontSize = 12.sp,
            )
        }
    }
}

@Composable
private fun InfoRow(
    label: String,
    value: String,
    isLink: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = label.uppercase(),
            color = Color.White.copy(alpha = 0.45f),
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.sp,
        )
        Text(
            text = value,
            color = if (isLink) Color(0xFF7CB8FF) else Color.White.copy(alpha = 0.92f),
            fontSize = 13.sp,
            modifier = if (isLink && onClick != null) Modifier.clickable(onClick = onClick) else Modifier,
        )
    }
}
