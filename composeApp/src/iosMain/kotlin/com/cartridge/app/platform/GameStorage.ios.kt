package com.cartridge.app.platform

actual class GameStorage {
    actual fun localEntry(slug: String): String? = null

    actual fun isInstalled(slug: String): Boolean = false

    actual fun needsUpdate(slug: String, sha256: String): Boolean = false

    actual fun delete(slug: String) = Unit

    actual suspend fun resolve(
        slug: String,
        bundledPath: String?,
        packageUrl: String?,
        packageSha256: String?,
        playUrl: String?,
        onProgress: (Float) -> Unit,
    ): GameSource {
        if (!bundledPath.isNullOrBlank()) return GameSource.Bundled(bundledPath)
        throw IllegalStateException("Downloads on iOS land in milestone M6")
    }

    actual suspend fun downloadPackage(
        slug: String,
        packageUrl: String,
        packageSha256: String?,
        onProgress: (Float) -> Unit,
    ): String = throw IllegalStateException("Downloads on iOS land in milestone M6")

    actual suspend fun mirrorRemote(
        slug: String,
        url: String,
        onProgress: (Float) -> Unit,
    ): String = throw IllegalStateException("Downloads on iOS land in milestone M6")
}
