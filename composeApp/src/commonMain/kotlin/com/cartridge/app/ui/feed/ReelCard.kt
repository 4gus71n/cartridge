package com.cartridge.app.ui.feed

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import androidx.compose.ui.layout.ContentScale
import com.cartridge.app.model.Cartridge
import com.cartridge.app.platform.rememberSharer
import com.cartridge.app.state.AppState

@Composable
fun ReelCard(
    cartridge: Cartridge,
    state: AppState,
    modifier: Modifier = Modifier,
) {
    val sharer = rememberSharer()

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(cartridge.accentTop, cartridge.accentBottom))),
    ) {
        val thumbnail = cartridge.thumbnailUrl
        if (thumbnail != null) {
            // Published originals ship a real in-game poster; code-drawn art is the fallback.
            SubcomposeAsyncImage(
                model = thumbnail,
                contentDescription = cartridge.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                error = { PosterArt(style = cartridge.poster, modifier = Modifier.fillMaxSize()) },
            )
        } else {
            PosterArt(style = cartridge.poster, modifier = Modifier.fillMaxSize())
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0f to Color.Black.copy(alpha = 0.35f),
                        0.4f to Color.Transparent,
                        1f to Color.Black.copy(alpha = 0.85f),
                    ),
                ),
        )

        PlayButton(
            onClick = { state.play(cartridge) },
            label = cartridge.title,
            modifier = Modifier.align(Alignment.Center),
        )

        RightRail(
            cartridge = cartridge,
            state = state,
            onShare = {
                sharer(
                    "Playing ${cartridge.title} on Cartridge — " +
                        "a playable cartridge by ${cartridge.author.name} (${cartridge.licenseSpdx} licensed).",
                )
            },
            onComments = { state.openComments(cartridge) },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(end = 12.dp, bottom = 140.dp),
        )

        BottomInfo(
            cartridge = cartridge,
            onCredits = { state.openCredits(cartridge) },
            modifier = Modifier
                .align(Alignment.BottomStart)
                .navigationBarsPadding()
                .padding(start = 16.dp, end = 88.dp, bottom = 32.dp),
        )

        BrandMark(
            modifier = Modifier
                .align(Alignment.TopStart)
                .statusBarsPadding()
                .padding(start = 16.dp, top = 12.dp),
        )

        ProfileButton(
            initial = state.user?.email?.take(1)?.uppercase() ?: "",
            onClick = { state.openProfile() },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .statusBarsPadding()
                .padding(end = 16.dp, top = 12.dp),
        )
    }
}

@Composable
private fun ProfileButton(initial: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(38.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.35f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (initial.isEmpty()) {
            Icon(
                imageVector = Icons.Filled.Person,
                contentDescription = "Profile",
                tint = Color.White,
                modifier = Modifier.size(22.dp),
            )
        } else {
            Text(
                text = initial,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
            )
        }
    }
}

@Composable
private fun PlayButton(onClick: () -> Unit, label: String, modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "playPulse")
    val scale by transition.animateFloat(
        initialValue = 1f,
        targetValue = 1.07f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 900, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "playScale",
    )

    Box(
        modifier = modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .size(92.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.94f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.PlayArrow,
            contentDescription = "Play $label",
            tint = Color.Black,
            modifier = Modifier.size(48.dp),
        )
    }
}

@Composable
private fun BottomInfo(
    cartridge: Cartridge,
    onCredits: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(Brush.linearGradient(listOf(Color(0xFF7C5CFF), Color(0xFF22D3EE)))),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = cartridge.author.name.take(1),
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 16.sp,
                )
            }
            Text(
                text = "@${cartridge.author.handle}",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
                style = TextStyle(shadow = Shadow(Color.Black.copy(alpha = 0.5f), blurRadius = 8f)),
            )
        }

        Text(
            text = cartridge.title,
            color = Color.White,
            fontWeight = FontWeight.ExtraBold,
            fontSize = 24.sp,
            style = TextStyle(shadow = Shadow(Color.Black.copy(alpha = 0.5f), blurRadius = 8f)),
        )

        Text(
            text = cartridge.tagline,
            color = Color.White.copy(alpha = 0.92f),
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
        )

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier
                .clip(RoundedCornerShape(999.dp))
                .background(Color.White.copy(alpha = 0.16f))
                .clickable(onClick = onCredits)
                .padding(horizontal = 10.dp, vertical = 6.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.Code,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.9f),
                modifier = Modifier.size(14.dp),
            )
            Text(
                text = "by ${cartridge.author.name} · ${cartridge.licenseSpdx}",
                color = Color.White.copy(alpha = 0.92f),
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun BrandMark(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            imageVector = Icons.Filled.SportsEsports,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = "Cartridge",
            color = Color.White,
            fontWeight = FontWeight.Black,
            fontSize = 18.sp,
            style = TextStyle(shadow = Shadow(Color.Black.copy(alpha = 0.5f), blurRadius = 8f)),
        )
    }
}
