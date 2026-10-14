package com.cartridge.app.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cartridge.app.platform.GameKeyboard
import kotlin.math.roundToInt

@Composable
fun KeyboardOverlay(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 18.dp)
            .padding(bottom = 30.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Bottom,
    ) {
        Joystick()
        ActionCluster()
    }
}

@Composable
private fun Joystick(modifier: Modifier = Modifier) {
    val padRadius = 66.dp
    val knobRadius = 27.dp
    var knob by remember { mutableStateOf(Offset.Zero) }

    Box(
        modifier = modifier
            .size(padRadius * 2)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.10f))
            .border(1.5.dp, Color.White.copy(alpha = 0.22f), CircleShape)
            .pointerInput(Unit) {
                val maxRadius = (padRadius - knobRadius).toPx()
                val deadZone = 10.dp.toPx()
                var held = emptySet<String>()
                awaitEachGesture {
                    val down = awaitFirstDown()
                    down.consume()
                    val center = Offset(size.width / 2f, size.height / 2f)
                    knob = clampToRadius(down.position - center, maxRadius)
                    held = applyKeys(held, keysFor(down.position - center, deadZone))
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                        val offset = change.position - center
                        knob = clampToRadius(offset, maxRadius)
                        held = applyKeys(held, keysFor(offset, deadZone))
                        change.consume()
                    }
                    held = applyKeys(held, emptySet())
                    knob = Offset.Zero
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .offset { IntOffset(knob.x.roundToInt(), knob.y.roundToInt()) }
                .size(knobRadius * 2)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.32f)),
        )
    }
}

private fun clampToRadius(offset: Offset, maxRadius: Float): Offset {
    val distance = offset.getDistance()
    if (distance <= maxRadius || distance == 0f) return offset
    return offset * (maxRadius / distance)
}

/** Direction -> held keys. Diagonals hold both axes; every axis drives WASD and arrows. */
private fun keysFor(offset: Offset, deadZone: Float): Set<String> {
    val keys = mutableSetOf<String>()
    if (offset.x < -deadZone) keys += listOf("A", "ArrowLeft")
    if (offset.x > deadZone) keys += listOf("D", "ArrowRight")
    if (offset.y < -deadZone) keys += listOf("W", "ArrowUp")
    if (offset.y > deadZone) keys += listOf("S", "ArrowDown")
    return keys
}

private fun applyKeys(previous: Set<String>, next: Set<String>): Set<String> {
    (previous - next).forEach { GameKeyboard.send(it, false) }
    (next - previous).forEach { GameKeyboard.send(it, true) }
    return next
}

@Composable
private fun ActionCluster() {
    Column(
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HoldKey("SPACE", keys = listOf("Space"), width = 100.dp, height = 46.dp, fontSize = 11.sp)
            HoldKey("ENTER", keys = listOf("Enter"), width = 56.dp, height = 46.dp, fontSize = 9.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HoldKey("SHIFT", keys = listOf("Shift"), width = 54.dp, height = 50.dp, fontSize = 9.sp)
            HoldKey("Z", keys = listOf("Z"), width = 48.dp, height = 50.dp)
            HoldKey("X", keys = listOf("X"), width = 48.dp, height = 50.dp)
        }
    }
}

@Composable
private fun HoldKey(
    label: String,
    keys: List<String>,
    modifier: Modifier = Modifier,
    width: Dp = 54.dp,
    height: Dp = 54.dp,
    fontSize: TextUnit = 16.sp,
) {
    Box(
        modifier = modifier
            .size(width = width, height = height)
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White.copy(alpha = 0.16f))
            .pointerInput(keys) {
                detectTapGestures(
                    onPress = {
                        keys.forEach { GameKeyboard.send(it, true) }
                        tryAwaitRelease()
                        keys.forEach { GameKeyboard.send(it, false) }
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = Color.White.copy(alpha = 0.92f),
            fontWeight = FontWeight.Bold,
            fontSize = fontSize,
        )
    }
}
