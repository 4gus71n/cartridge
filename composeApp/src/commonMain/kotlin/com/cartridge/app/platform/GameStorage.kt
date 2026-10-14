package com.cartridge.app.platform

sealed interface GameSource {
    data class Bundled(val assetPath: String) : GameSource
    data class Local(val entry: String) : GameSource
    data class Remote(val url: String, val allowedHost: String) : GameSource
}

expect class GameStorage() {
    fun localEntry(slug: String): String?
    fun isInstalled(slug: String): Boolean
    fun delete(slug: String)

    suspend fun resolve(
        slug: String,
        bundledPath: String?,
        packageUrl: String?,
        packageSha256: String?,
        playUrl: String?,
        onProgress: (Float) -> Unit,
    ): GameSource

    suspend fun downloadPackage(
        slug: String,
        packageUrl: String,
        packageSha256: String?,
        onProgress: (Float) -> Unit,
    ): String

    suspend fun mirrorRemote(
        slug: String,
        url: String,
        onProgress: (Float) -> Unit,
    ): String
}
