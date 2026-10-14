package com.cartridge.app.ui.feed

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cartridge.app.model.Cartridge
import com.cartridge.app.state.AppState

@Composable
fun RightRail(
    cartridge: Cartridge,
    state: AppState,
    onShare: () -> Unit,
    onComments: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val liked = state.likedIds.contains(cartridge.id)
    val saved = state.savedIds.contains(cartridge.id)

    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        RailAction(
            icon = if (liked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            label = formatCount(state.likeCount(cartridge)),
            tint = if (liked) Color(0xFFFF2D55) else Color.White,
            onClick = { state.toggleLike(cartridge) },
        )
        RailAction(
            icon = Icons.Filled.ChatBubble,
            label = formatCount(state.commentCount(cartridge)),
            onClick = onComments,
        )
        RailAction(
            icon = Icons.Filled.Share,
            label = "Share",
            onClick = onShare,
        )
        RailAction(
            icon = if (saved) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
            label = if (saved) "Saved" else "Save",
            tint = if (saved) Color(0xFFFDE047) else Color.White,
            onClick = { state.requestSave(cartridge) },
        )
        RailAction(
            icon = Icons.Outlined.Flag,
            label = "Report",
            tint = Color.White.copy(alpha = 0.85f),
            onClick = { state.openReport(cartridge) },
        )
    }
}

@Composable
private fun RailAction(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    tint: Color = Color.White,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = tint,
            modifier = Modifier
                .size(36.dp)
                .clickable(onClick = onClick),
        )
        Text(
            text = label,
            color = Color.White,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            style = TextStyle(shadow = Shadow(Color.Black.copy(alpha = 0.65f), blurRadius = 8f)),
        )
    }
}

private fun formatCount(count: Int): String = when {
    count >= 1_000_000 -> "${count / 1_000_000}.${(count % 1_000_000) / 100_000}M"
    count >= 1_000 -> "${count / 1_000}.${(count % 1_000) / 100}K"
    else -> count.toString()
}
