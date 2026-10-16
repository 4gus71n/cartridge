package com.cartridge.app.model

import androidx.compose.ui.graphics.Color

data class Author(
    val name: String,
    val handle: String,
)

enum class PosterStyle {
    FLAP, DODGE, TAP,
    TILES, EMINE, MINE, POOL, INVADER, TOWER, BRICKS,
    TREX, SNAKE, CHESS, PACMAN, HOLE, MATCH, DEFENSE, SPACEPI,
}

data class Cartridge(
    val id: String,
    val title: String,
    val tagline: String,
    val author: Author,
    val licenseSpdx: String,
    val sourceUrl: String,
    val modifications: String?,
    val assetPath: String,
    val accentTop: Color,
    val accentBottom: Color,
    val seedLikes: Int,
    val seedComments: Int,
    val poster: PosterStyle,
    val bundled: Boolean = true,
    val packageUrl: String? = null,
    val packageSha256: String? = null,
    val playUrl: String? = null,
    val orientation: String = "any",
    val updatedAt: String = "",
    val thumbnailUrl: String? = null,
) {
    val isOriginal: Boolean get() = sourceUrl.isBlank()
}
