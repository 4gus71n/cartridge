package com.cartridge.app.ui.feed

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import com.cartridge.app.model.PosterStyle

@Composable
fun PosterArt(style: PosterStyle, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        when (style) {
            PosterStyle.FLAP -> drawFlap()
            PosterStyle.DODGE -> drawDodge()
            PosterStyle.TAP -> drawTap()
            PosterStyle.TILES -> drawTiles()
            PosterStyle.EMINE -> drawEmine()
            PosterStyle.MINE -> drawMine()
            PosterStyle.POOL -> drawPool()
            PosterStyle.INVADER -> drawInvader()
            PosterStyle.TOWER -> drawTower()
            PosterStyle.BRICKS -> drawBricks()
            PosterStyle.TREX -> drawTrex()
            PosterStyle.SNAKE -> drawSnake()
            PosterStyle.CHESS -> drawChess()
            PosterStyle.PACMAN -> drawPacman()
            PosterStyle.HOLE -> drawHole()
            PosterStyle.MATCH -> drawMatch()
            PosterStyle.DEFENSE -> drawDefense()
            PosterStyle.SPACEPI -> drawSpacepi()
        }
    }
}

private fun DrawScope.drawFlap() {
    val w = size.width
    val h = size.height
    val cyan = Color(0xFF22D3EE).copy(alpha = 0.9f)
    val violet = Color(0xFFA78BFA).copy(alpha = 0.85f)

    drawRoundRect(cyan, topLeft = Offset(w * 0.60f, h * 0.10f), size = Size(w * 0.15f, h * 0.26f), cornerRadius = CornerRadius(12f, 12f))
    drawRoundRect(cyan, topLeft = Offset(w * 0.60f, h * 0.48f), size = Size(w * 0.15f, h * 0.32f), cornerRadius = CornerRadius(12f, 12f))
    drawRoundRect(violet, topLeft = Offset(w * 0.16f, h * 0.02f), size = Size(w * 0.12f, h * 0.22f), cornerRadius = CornerRadius(12f, 12f))
    drawRoundRect(violet, topLeft = Offset(w * 0.16f, h * 0.36f), size = Size(w * 0.12f, h * 0.36f), cornerRadius = CornerRadius(12f, 12f))

    drawCircle(Color(0xFFFDE047).copy(alpha = 0.30f), radius = w * 0.085f, center = Offset(w * 0.365f, h * 0.34f))
    drawCircle(Color(0xFFFDE047), radius = w * 0.05f, center = Offset(w * 0.365f, h * 0.34f))

    drawRect(Color(0xFF0F172A), topLeft = Offset(0f, h * 0.84f), size = Size(w, h * 0.16f))

    val stars = listOf(0.10f to 0.12f, 0.30f to 0.08f, 0.80f to 0.20f, 0.50f to 0.15f, 0.90f to 0.52f, 0.08f to 0.60f)
    stars.forEach { (fx, fy) ->
        drawCircle(Color.White.copy(alpha = 0.5f), radius = w * 0.004f, center = Offset(w * fx, h * fy))
    }
}

private fun DrawScope.drawDodge() {
    val w = size.width
    val h = size.height
    val blocks = listOf(
        Triple(0.18f, 0.10f, 0.09f),
        Triple(0.70f, 0.06f, 0.07f),
        Triple(0.45f, 0.22f, 0.08f),
        Triple(0.82f, 0.34f, 0.06f),
        Triple(0.12f, 0.42f, 0.07f),
        Triple(0.60f, 0.52f, 0.10f),
        Triple(0.30f, 0.68f, 0.06f),
    )
    blocks.forEachIndexed { index, (fx, fy, fs) ->
        val color = if (index % 2 == 0) Color(0xFFF472B6) else Color(0xFF22D3EE)
        drawRoundRect(
            color = color.copy(alpha = 0.85f),
            topLeft = Offset(w * fx, h * fy),
            size = Size(w * fs, w * fs),
            cornerRadius = CornerRadius(8f, 8f),
        )
    }
    drawCircle(Color(0xFF4ADE80).copy(alpha = 0.40f), radius = w * 0.09f, center = Offset(w * 0.5f, h * 0.80f))
    drawCircle(Color.White, radius = w * 0.055f, center = Offset(w * 0.5f, h * 0.80f))
}

private fun DrawScope.drawTap() {
    val w = size.width
    val h = size.height
    val rings = listOf(
        Triple(0.28f, 0.22f, 0.10f) to Color(0xFF2DD4BF),
        Triple(0.68f, 0.38f, 0.08f) to Color(0xFFFDE047),
        Triple(0.40f, 0.58f, 0.09f) to Color(0xFFF472B6),
        Triple(0.78f, 0.72f, 0.07f) to Color(0xFF60A5FA),
    )
    rings.forEach { (position, color) ->
        val (fx, fy, fr) = position
        val center = Offset(w * fx, h * fy)
        drawCircle(color.copy(alpha = 0.25f), radius = w * fr, center = center)
        drawCircle(color, radius = w * fr * 0.55f, center = center)
        drawCircle(Color.White.copy(alpha = 0.8f), radius = w * fr * 0.22f, center = center)
    }
}

private fun DrawScope.drawTiles() {
    val w = size.width
    val h = size.height
    val s = w * 0.20f
    val gap = w * 0.03f
    val startX = w * 0.5f - (s * 2 + gap) / 2
    val startY = h * 0.36f - (s * 2 + gap) / 2
    val colors = listOf(Color(0xFFEDC22E), Color(0xFFEDE0C8), Color(0xFFF2B179), Color(0xFFEDE0C8))
    var i = 0
    for (row in 0 until 2) {
        for (col in 0 until 2) {
            val x = startX + col * (s + gap)
            val y = startY + row * (s + gap)
            drawRoundRect(colors[i++].copy(alpha = 0.92f), Offset(x, y), Size(s, s), CornerRadius(10f, 10f))
            drawCircle(Color(0xFF776E65).copy(alpha = 0.30f), radius = s * 0.22f, center = Offset(x + s / 2, y + s / 2))
        }
    }
}

private fun DrawScope.drawEmine() {
    val w = size.width
    val h = size.height
    val faces = listOf(
        0.30f to 0.38f, 0.52f to 0.30f, 0.72f to 0.42f, 0.42f to 0.60f, 0.64f to 0.62f,
    )
    faces.forEachIndexed { index, (fx, fy) ->
        val color = if (index == 3) Color(0xFFEF4444) else Color(0xFFFDE047).copy(alpha = 0.92f)
        val r = w * 0.065f
        drawCircle(color, radius = r, center = Offset(w * fx, h * fy))
        val eye = Color(0xFF1F2937)
        drawCircle(eye, radius = r * 0.12f, center = Offset(w * fx - r * 0.32f, h * fy - r * 0.1f))
        drawCircle(eye, radius = r * 0.12f, center = Offset(w * fx + r * 0.32f, h * fy - r * 0.1f))
        drawArc(
            color = eye,
            startAngle = 20f,
            sweepAngle = 140f,
            useCenter = false,
            topLeft = Offset(w * fx - r * 0.42f, h * fy + r * 0.05f),
            size = Size(r * 0.84f, r * 0.7f),
            style = Stroke(width = r * 0.12f),
        )
    }
}

private fun DrawScope.drawMine() {
    val w = size.width
    val h = size.height
    val cols = 5
    val cell = w * 0.105f
    val gap = w * 0.016f
    val total = cols * cell + (cols - 1) * gap
    val sx = w * 0.5f - total / 2
    val sy = h * 0.42f - total / 2
    for (row in 0 until cols) {
        for (col in 0 until cols) {
            val x = sx + col * (cell + gap)
            val y = sy + row * (cell + gap)
            val mine = (row == 1 && col == 2) || (row == 3 && col == 0) || (row == 2 && col == 4)
            drawRoundRect(
                color = if (mine) Color(0xFFEF4444).copy(alpha = 0.9f) else Color(0xFF94A3B8).copy(alpha = 0.45f),
                topLeft = Offset(x, y),
                size = Size(cell, cell),
                cornerRadius = CornerRadius(4f, 4f),
            )
            if (mine) {
                drawCircle(Color.White.copy(alpha = 0.9f), radius = cell * 0.16f, center = Offset(x + cell / 2, y + cell / 2))
            }
        }
    }
}

private fun DrawScope.drawPool() {
    val w = size.width
    val h = size.height
    drawRoundRect(Color(0xFF166534).copy(alpha = 0.9f), Offset(w * 0.10f, h * 0.52f), Size(w * 0.80f, h * 0.26f), CornerRadius(18f, 18f))
    drawRoundRect(Color(0xFF78350F).copy(alpha = 0.9f), Offset(w * 0.10f, h * 0.52f), Size(w * 0.80f, h * 0.02f), CornerRadius(8f, 8f))

    val r = w * 0.027f
    val cx = w * 0.66f
    val cy = h * 0.34f
    val colors = listOf(Color(0xFFFACC15), Color(0xFFEF4444), Color(0xFF3B82F6), Color(0xFFA855F7), Color(0xFFF97316), Color(0xFF111827))
    var idx = 0
    for (row in 0 until 3) {
        for (col in 0..row) {
            val x = cx + (col - row / 2f) * (r * 2.2f)
            val y = cy + row * (r * 1.9f)
            drawCircle(colors[idx % colors.size], radius = r, center = Offset(x, y))
            idx++
        }
    }
    drawCircle(Color.White, radius = r, center = Offset(w * 0.28f, h * 0.38f))
    drawLine(Color(0xFFE7C08A), Offset(w * 0.12f, h * 0.16f), Offset(w * 0.25f, h * 0.34f), strokeWidth = w * 0.012f)
}

private fun DrawScope.drawInvader() {
    val w = size.width
    val h = size.height
    val alien = Color(0xFF4ADE80).copy(alpha = 0.92f)
    for (i in 0 until 3) {
        val cx = w * (0.24f + 0.26f * i)
        val cy = h * 0.30f
        drawCircle(alien, radius = w * 0.05f, center = Offset(cx, cy))
        drawCircle(Color(0xFF0B1020), radius = w * 0.011f, center = Offset(cx - w * 0.018f, cy - h * 0.01f))
        drawCircle(Color(0xFF0B1020), radius = w * 0.011f, center = Offset(cx + w * 0.018f, cy - h * 0.01f))
        drawLine(alien, Offset(cx - w * 0.05f, cy + h * 0.045f), Offset(cx - w * 0.08f, cy + h * 0.085f), strokeWidth = w * 0.008f)
        drawLine(alien, Offset(cx + w * 0.05f, cy + h * 0.045f), Offset(cx + w * 0.08f, cy + h * 0.085f), strokeWidth = w * 0.008f)
    }
    drawRect(Color(0xFF22D3EE), Offset(w * 0.42f, h * 0.72f), Size(w * 0.16f, h * 0.045f))
    drawRect(Color(0xFF22D3EE), Offset(w * 0.485f, h * 0.66f), Size(w * 0.03f, h * 0.06f))
    drawRect(Color(0xFFFDE047), Offset(w * 0.49f, h * 0.50f), Size(w * 0.02f, h * 0.06f))
}

private fun DrawScope.drawTower() {
    val w = size.width
    val h = size.height
    val bw = w * 0.34f
    val bh = h * 0.052f
    val colors = listOf(Color(0xFFF87171), Color(0xFFFBBF24), Color(0xFF34D399), Color(0xFF60A5FA), Color(0xFFA78BFA), Color(0xFFF472B6))
    for (i in 0 until 7) {
        val x = w * 0.5f - bw / 2 + (if (i % 2 == 0) -w * 0.03f else w * 0.02f)
        val y = h * 0.70f - i * (bh + h * 0.012f)
        drawRoundRect(colors[i % colors.size].copy(alpha = 0.9f), Offset(x, y), Size(bw, bh), CornerRadius(6f, 6f))
    }
    drawLine(Color(0xFF94A3B8).copy(alpha = 0.6f), Offset(w * 0.5f, 0f), Offset(w * 0.5f, h * 0.18f), strokeWidth = w * 0.008f)
}

private fun DrawScope.drawBricks() {
    val w = size.width
    val h = size.height
    val colors = listOf(Color(0xFFF87171), Color(0xFFFBBF24), Color(0xFF34D399), Color(0xFF60A5FA))
    val cols = 5
    val bw = w * 0.12f
    val bh = h * 0.026f
    val gap = w * 0.015f
    val sx = w * 0.5f - (cols * bw + (cols - 1) * gap) / 2
    var idx = 0
    for (row in 0 until 4) {
        for (col in 0 until cols) {
            if (idx != 7) {
                drawRoundRect(
                    colors[row % colors.size].copy(alpha = 0.92f),
                    Offset(sx + col * (bw + gap), h * 0.22f + row * (bh + gap)),
                    Size(bw, bh),
                    CornerRadius(4f, 4f),
                )
            }
            idx++
        }
    }
    drawRoundRect(Color.White.copy(alpha = 0.9f), Offset(w * 0.5f - w * 0.11f, h * 0.78f), Size(w * 0.22f, h * 0.02f), CornerRadius(8f, 8f))
    drawCircle(Color(0xFFFDE047), radius = w * 0.022f, center = Offset(w * 0.44f, h * 0.62f))
}

private fun DrawScope.drawTrex() {
    val w = size.width
    val h = size.height
    val dino = Color(0xFF94A3B8)

    fun block(x: Float, y: Float, bw: Float, bh: Float, color: Color = dino) {
        drawRect(color, Offset(w * x, h * y), Size(w * bw, h * bh))
    }

    block(0.28f, 0.46f, 0.14f, 0.10f)
    block(0.38f, 0.38f, 0.10f, 0.08f)
    block(0.45f, 0.30f, 0.08f, 0.09f)
    block(0.31f, 0.56f, 0.03f, 0.05f)
    block(0.37f, 0.56f, 0.03f, 0.05f)
    block(0.24f, 0.42f, 0.05f, 0.06f)
    drawRect(Color(0xFF0B1020), Offset(w * 0.49f, h * 0.325f), Size(w * 0.012f, h * 0.012f))

    block(0.72f, 0.50f, 0.025f, 0.16f, Color(0xFF4ADE80))
    block(0.695f, 0.54f, 0.02f, 0.03f, Color(0xFF4ADE80))
    block(0.74f, 0.56f, 0.02f, 0.03f, Color(0xFF4ADE80))

    drawRect(Color(0xFF334155), Offset(0f, h * 0.66f), Size(w, h * 0.006f))
    block(0.60f, 0.24f, 0.04f, 0.02f)
}

private fun DrawScope.drawSnake() {
    val w = size.width
    val h = size.height
    val cell = w * 0.09f
    val green = Color(0xFF4ADE80).copy(alpha = 0.92f)
    val body = listOf(
        0.35f to 0.50f,
        0.44f to 0.50f,
        0.53f to 0.50f,
        0.62f to 0.50f,
        0.62f to 0.41f,
    )
    body.forEach { (x, y) ->
        drawRoundRect(green, Offset(w * x, h * y), Size(cell, cell), CornerRadius(6f, 6f))
    }
    drawCircle(Color(0xFF052E16), radius = cell * 0.12f, center = Offset(w * 0.62f + cell * 0.68f, h * 0.41f + cell * 0.3f))
    drawCircle(Color(0xFFEF4444), radius = cell * 0.45f, center = Offset(w * 0.25f, h * 0.68f))
}

private fun DrawScope.drawChess() {
    val w = size.width
    val h = size.height
    val n = 6
    val s = w * 0.52f / n
    val sx = w * 0.5f - n * s / 2
    val sy = h * 0.42f - n * s / 2
    for (row in 0 until n) {
        for (col in 0 until n) {
            val light = (row + col) % 2 == 0
            drawRect(
                if (light) Color(0xFFE2E8F0) else Color(0xFF64748B),
                Offset(sx + col * s, sy + row * s),
                Size(s, s),
            )
        }
    }
    drawCircle(Color(0xFF0F172A), radius = s * 0.36f, center = Offset(sx + s * 3.5f, sy + s * 4.5f))
    drawCircle(Color.White, radius = s * 0.36f, center = Offset(sx + s * 1.5f, sy + s * 0.5f))
    drawCircle(Color(0xFF0F172A), radius = s * 0.30f, center = Offset(sx + s * 2.5f, sy + s * 2.5f))
}

private fun DrawScope.drawPacman() {
    val w = size.width
    val h = size.height
    val r = w * 0.09f

    drawArc(
        color = Color(0xFFFDE047),
        startAngle = 35f,
        sweepAngle = 290f,
        useCenter = true,
        topLeft = Offset(w * 0.32f - r, h * 0.46f - r),
        size = Size(r * 2, r * 2),
    )
    drawCircle(Color(0xFFFDE047).copy(alpha = 0.8f), radius = r * 0.16f, center = Offset(w * 0.53f, h * 0.46f))
    drawCircle(Color(0xFFFDE047).copy(alpha = 0.8f), radius = r * 0.16f, center = Offset(w * 0.62f, h * 0.46f))

    drawGhost(w * 0.70f, h * 0.40f, w * 0.055f, Color(0xFFEF4444))
    drawGhost(w * 0.80f, h * 0.46f, w * 0.055f, Color(0xFF22D3EE))

    drawLine(Color(0xFF3B82F6).copy(alpha = 0.55f), Offset(w * 0.20f, h * 0.62f), Offset(w * 0.72f, h * 0.62f), strokeWidth = w * 0.006f)
    drawLine(Color(0xFF3B82F6).copy(alpha = 0.55f), Offset(w * 0.20f, h * 0.30f), Offset(w * 0.92f, h * 0.30f), strokeWidth = w * 0.006f)
    drawLine(Color(0xFF3B82F6).copy(alpha = 0.55f), Offset(w * 0.20f, h * 0.26f), Offset(w * 0.20f, h * 0.66f), strokeWidth = w * 0.006f)
}

private fun DrawScope.drawGhost(x: Float, y: Float, radius: Float, color: Color) {
    drawCircle(color, radius, Offset(x, y))
    drawRect(color, Offset(x - radius, y), Size(radius * 2, radius * 1.05f))
    drawCircle(Color.White, radius * 0.22f, Offset(x - radius * 0.35f, y - radius * 0.15f))
    drawCircle(Color.White, radius * 0.22f, Offset(x + radius * 0.35f, y - radius * 0.15f))
}

private fun DrawScope.drawHole() {
    val w = size.width
    val h = size.height
    val cell = w * 0.09f
    val cx = w * 0.5f
    val cy = h * 0.42f
    for (i in 0..8) {
        drawLine(
            Color.White.copy(alpha = 0.07f),
            Offset(cx - 4 * cell + i * cell, cy - 4 * cell),
            Offset(cx - 4 * cell + i * cell, cy + 4 * cell),
            strokeWidth = 2f,
        )
        drawLine(
            Color.White.copy(alpha = 0.07f),
            Offset(cx - 4 * cell, cy - 4 * cell + i * cell),
            Offset(cx + 4 * cell, cy - 4 * cell + i * cell),
            strokeWidth = 2f,
        )
    }
    drawCircle(Color(0xFFA855F7).copy(alpha = 0.30f), radius = w * 0.19f, center = Offset(cx, cy))
    drawCircle(Color.Black, radius = w * 0.13f, center = Offset(cx, cy))
    drawRoundRect(Color(0xFFF472B6).copy(alpha = 0.9f), Offset(w * 0.64f, h * 0.26f), Size(w * 0.05f, w * 0.05f), CornerRadius(6f, 6f))
    drawRoundRect(Color(0xFF22D3EE).copy(alpha = 0.9f), Offset(w * 0.24f, h * 0.58f), Size(w * 0.04f, w * 0.04f), CornerRadius(6f, 6f))
}

private fun DrawScope.drawMatch() {
    val w = size.width
    val h = size.height
    drawRoundRect(Color(0xFF1E293B), Offset(w * 0.16f, h * 0.36f), Size(w * 0.30f, h * 0.20f), CornerRadius(12f, 12f))
    drawRoundRect(Color(0xFF1E293B), Offset(w * 0.54f, h * 0.36f), Size(w * 0.30f, h * 0.20f), CornerRadius(12f, 12f))
    drawCircle(Color(0xFFFDE047), w * 0.045f, Offset(w * 0.31f, h * 0.46f))
    drawCircle(Color(0xFF22D3EE), w * 0.045f, Offset(w * 0.69f, h * 0.46f))
    drawLine(Color.White.copy(alpha = 0.5f), Offset(w * 0.47f, h * 0.46f), Offset(w * 0.53f, h * 0.46f), strokeWidth = w * 0.008f)
    drawCircle(Color(0xFFF472B6), w * 0.03f, Offset(w * 0.5f, h * 0.25f))
    drawCircle(Color(0xFF4ADE80), w * 0.022f, Offset(w * 0.38f, h * 0.66f))
    drawCircle(Color(0xFFF97316), w * 0.022f, Offset(w * 0.64f, h * 0.62f))
}

private fun DrawScope.drawDefense() {
    val w = size.width
    val h = size.height
    val path = Path().apply {
        moveTo(w * 0.08f, h * 0.30f)
        lineTo(w * 0.50f, h * 0.30f)
        lineTo(w * 0.50f, h * 0.56f)
        lineTo(w * 0.92f, h * 0.56f)
    }
    drawPath(path, Color(0xFFF59E0B).copy(alpha = 0.30f), style = Stroke(width = w * 0.06f))

    listOf(0.28f to 0.18f, 0.68f to 0.68f, 0.42f to 0.70f).forEach { (fx, fy) ->
        drawCircle(Color(0xFF38BDF8), w * 0.045f, Offset(w * fx, h * fy))
        drawCircle(Color(0xFF0B1020), w * 0.02f, Offset(w * fx, h * fy))
    }
    drawCircle(Color(0xFFEF4444), w * 0.024f, Offset(w * 0.32f, h * 0.30f))
    drawCircle(Color(0xFFEF4444), w * 0.024f, Offset(w * 0.74f, h * 0.56f))
}

private fun DrawScope.drawSpacepi() {
    val w = size.width
    val h = size.height
    listOf(0.25f to 0.55f, 0.50f to 0.35f, 0.75f to 0.60f, 0.40f to 0.72f, 0.65f to 0.24f).forEach { (fx, fy) ->
        drawCircle(Color(0xFF22D3EE).copy(alpha = 0.20f), w * 0.045f, Offset(w * fx, h * fy))
        drawCircle(Color(0xFF22D3EE).copy(alpha = 0.85f), w * 0.018f, Offset(w * fx, h * fy))
    }

    val cx = w * 0.60f
    val cy = h * 0.45f
    val r = w * 0.09f
    drawCircle(Color(0xFFF472B6).copy(alpha = 0.9f), r, Offset(cx, cy), style = Stroke(width = w * 0.008f))
    drawLine(Color(0xFFF472B6), Offset(cx - r * 1.6f, cy), Offset(cx - r * 0.5f, cy), strokeWidth = w * 0.008f)
    drawLine(Color(0xFFF472B6), Offset(cx + r * 0.5f, cy), Offset(cx + r * 1.6f, cy), strokeWidth = w * 0.008f)
    drawLine(Color(0xFFF472B6), Offset(cx, cy - r * 1.6f), Offset(cx, cy - r * 0.5f), strokeWidth = w * 0.008f)
    drawLine(Color(0xFFF472B6), Offset(cx, cy + r * 0.5f), Offset(cx, cy + r * 1.6f), strokeWidth = w * 0.008f)
    drawCircle(Color(0xFFFDE047), w * 0.008f, Offset(w * 0.45f, h * 0.60f))
    drawCircle(Color(0xFFFDE047), w * 0.008f, Offset(w * 0.72f, h * 0.32f))
}
