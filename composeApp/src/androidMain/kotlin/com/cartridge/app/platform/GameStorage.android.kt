package com.cartridge.app.platform

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.zip.ZipInputStream

actual class GameStorage {
    private val context get() = AndroidAppContext.appContext
    private val gamesDir: File get() = File(context.filesDir, "games").apply { mkdirs() }

    actual fun localEntry(slug: String): String? {
        val dir = File(gamesDir, slug)
        if (!dir.isDirectory) return null
        return ENTRY_CANDIDATES.firstOrNull { File(dir, it).isFile }?.let { "$slug/$it" }
    }

    actual fun isInstalled(slug: String): Boolean = localEntry(slug) != null

    /** sha256 of the installed package; "" for installs that predate the marker (treated as stale). */
    private fun installedSha(slug: String): String? =
        shaMarker(slug).takeIf { it.isFile }?.readText()?.trim() ?: ""

    // Kept beside (not inside) the game dir so unzip/deleteRecursively stay simple.
    private fun shaMarker(slug: String): File = File(gamesDir, ".$slug.sha256")

    actual fun delete(slug: String) {
        File(gamesDir, slug).deleteRecursively()
        shaMarker(slug).delete()
    }

    actual suspend fun resolve(
        slug: String,
        bundledPath: String?,
        packageUrl: String?,
        packageSha256: String?,
        playUrl: String?,
        onProgress: (Float) -> Unit,
    ): GameSource {
        if (!bundledPath.isNullOrBlank()) return GameSource.Bundled(bundledPath)
        localEntry(slug)?.let { entry ->
            // A newer package was published (sha changed): try to update, but
            // keep playing the installed copy when offline.
            val stale = !packageUrl.isNullOrBlank() && !packageSha256.isNullOrBlank() &&
                installedSha(slug)?.equals(packageSha256, ignoreCase = true) == false
            if (!stale) return GameSource.Local(entry)
            return runCatching {
                GameSource.Local(downloadPackage(slug, packageUrl!!, packageSha256, onProgress))
            }.getOrElse { GameSource.Local(entry) }
        }
        if (!packageUrl.isNullOrBlank()) {
            return GameSource.Local(downloadPackage(slug, packageUrl, packageSha256, onProgress))
        }
        if (!playUrl.isNullOrBlank()) {
            val host = runCatching { URL(playUrl).host }.getOrNull()
            if (host != null) return GameSource.Remote(playUrl, host)
        }
        throw IllegalStateException("No playable source for $slug")
    }

    private fun packageUrlCandidates(packageUrl: String): List<String> {
        val candidates = mutableListOf(packageUrl)
        val url = runCatching { URL(packageUrl) }.getOrNull()
        val path = url?.path
        // Only packages served by our own backend can be re-tried against the
        // other API base URLs; public hosts (GitHub Pages, CDNs) are absolute.
        val apiHosts = apiBaseUrls().mapNotNull { runCatching { URL(it).host }.getOrNull() } +
            listOf("localhost", "127.0.0.1")
        if (!path.isNullOrBlank() && url.host in apiHosts) {
            for (base in apiBaseUrls()) {
                val candidate = base.trimEnd('/') + path
                if (candidate !in candidates) candidates.add(candidate)
            }
        }
        return candidates
    }

    actual suspend fun downloadPackage(
        slug: String,
        packageUrl: String,
        packageSha256: String?,
        onProgress: (Float) -> Unit,
    ): String = withContext(Dispatchers.IO) {
        val tmp = File(context.cacheDir, "$slug.zip.tmp")
        var lastError: Exception? = null
        var downloaded = false
        for (candidate in packageUrlCandidates(packageUrl)) {
            try {
                download(candidate, tmp, onProgress)
                downloaded = true
                break
            } catch (error: Exception) {
                android.util.Log.w("GameStorage", "download failed: $candidate", error)
                // Keep the first (most relevant) error: it's the canonical URL.
                if (lastError == null) lastError = error
                onProgress(0f)
            }
        }
        if (!downloaded) {
            throw lastError ?: IllegalStateException("Could not download package")
        }
        if (!packageSha256.isNullOrBlank()) {
            val digest = sha256(tmp)
            if (!digest.equals(packageSha256, ignoreCase = true)) {
                tmp.delete()
                throw IllegalStateException("Package checksum mismatch")
            }
        }
        val target = File(gamesDir, slug)
        target.deleteRecursively()
        target.mkdirs()
        unzip(tmp, target)
        tmp.delete()
        if (!packageSha256.isNullOrBlank()) shaMarker(slug).writeText(packageSha256.lowercase())
        localEntry(slug) ?: throw IllegalStateException("Package has no index.html")
    }

    actual suspend fun mirrorRemote(
        slug: String,
        url: String,
        onProgress: (Float) -> Unit,
    ): String = withContext(Dispatchers.IO) {
        Mirrorer(slug, url, File(gamesDir, slug), onProgress).run()
        localEntry(slug) ?: throw IllegalStateException("Mirror produced no index.html")
    }

    private fun download(url: String, target: File, onProgress: (Float) -> Unit) {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15000
            readTimeout = 30000
            instanceFollowRedirects = true
        }
        try {
            conn.connect()
            val code = conn.responseCode
            if (code !in 200..299) throw IllegalStateException("HTTP $code")
            val total = conn.contentLengthLong
            conn.inputStream.use { input ->
                FileOutputStream(target).use { out ->
                    val buffer = ByteArray(64 * 1024)
                    var readTotal = 0L
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        out.write(buffer, 0, n)
                        readTotal += n
                        if (total > 0) {
                            onProgress((readTotal.toFloat() / total).coerceIn(0f, 1f))
                        }
                    }
                }
            }
        } finally {
            conn.disconnect()
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun unzip(zip: File, target: File) {
        ZipInputStream(FileInputStream(zip)).use { stream ->
            var entry = stream.nextEntry
            while (entry != null) {
                val outFile = File(target, entry.name)
                if (!outFile.canonicalPath.startsWith(target.canonicalPath + File.separator)) {
                    throw IllegalStateException("Unsafe zip entry: ${entry.name}")
                }
                if (entry.isDirectory) {
                    outFile.mkdirs()
                } else {
                    outFile.parentFile?.mkdirs()
                    FileOutputStream(outFile).use { out -> stream.copyTo(out) }
                }
                stream.closeEntry()
                entry = stream.nextEntry
            }
        }
    }

    private class Mirrorer(
        private val slug: String,
        entryUrl: String,
        private val targetDir: File,
        private val onProgress: (Float) -> Unit,
    ) {
        private val entry = stripFragment(entryUrl)
        private val base = URL(entry)
        private val host: String = base.host
        private val seen = mutableSetOf<String>()
        private val queue = ArrayDeque<String>()
        private var files = 0
        private var bytes = 0L

        fun run() {
            targetDir.deleteRecursively()
            targetDir.mkdirs()
            queue.add(entry)
            while (queue.isNotEmpty() && files < MAX_FILES && bytes < MAX_BYTES) {
                val current = queue.removeFirst()
                if (!seen.add(current)) continue
                val url = runCatching { URL(current) }.getOrNull() ?: continue
                if (url.host != host) continue
                val (data, contentType) = fetch(current) ?: continue
                bytes += data.size
                val path = if (current == entry) "index.html" else relPathFor(url)
                val textual = isTextual(url.path, contentType)
                val finalBytes = if (textual) {
                    val text = String(data, Charsets.UTF_8)
                    val css = url.path.endsWith(".css", true) ||
                        (contentType ?: "").contains("text/css")
                    rewriteText(text, url, path, css).toByteArray(Charsets.UTF_8)
                } else {
                    data
                }
                val outFile = File(targetDir, path)
                outFile.parentFile?.mkdirs()
                outFile.writeBytes(finalBytes)
                files++
                onProgress(
                    (files.toFloat() / (files + queue.size).coerceAtLeast(1))
                        .coerceIn(0f, 1f),
                )
            }
        }

        private fun rewriteText(text: String, pageUrl: URL, pageRel: String, css: Boolean): String {
            val patterns = if (css) listOf(CSS_URL, CSS_IMPORT) else listOf(HTML_REF)
            var result = text
            for (pattern in patterns) {
                result = pattern.replace(result) { match ->
                    val ref = match.groupValues.last()
                    val absolute = absolutize(ref, pageUrl) ?: return@replace match.value
                    val target = runCatching { URL(absolute) }.getOrNull()
                        ?: return@replace match.value
                    if (target.host != host) return@replace match.value
                    val normalized = stripFragment(absolute)
                    if (normalized != entry && seen.size + queue.size < MAX_FILES) {
                        queue.add(normalized)
                    }
                    val targetRel = if (normalized == entry) "index.html" else relPathFor(target)
                    val newRef = relativePath(pageRel, targetRel)
                    match.value.replace(ref, newRef)
                }
            }
            return result
        }

        private fun fetch(url: String): Pair<ByteArray, String?>? {
            val conn = runCatching { URL(url).openConnection() as HttpURLConnection }.getOrNull()
                ?: return null
            return try {
                conn.connectTimeout = 15000
                conn.readTimeout = 20000
                conn.instanceFollowRedirects = true
                conn.connect()
                val code = conn.responseCode
                if (code !in 200..299) {
                    null
                } else {
                    val data = conn.inputStream.use { it.readBytes() }
                    data to conn.contentType
                }
            } catch (e: Exception) {
                null
            } finally {
                conn.disconnect()
            }
        }

        private fun isTextual(path: String, contentType: String?): Boolean {
            val type = (contentType ?: "").lowercase()
            return path.endsWith(".html", true) || path.endsWith(".htm", true) ||
                path.endsWith(".css", true) ||
                type.startsWith("text/html") || type.startsWith("text/css")
        }

        private fun relPathFor(url: URL): String {
            var path = url.path.ifEmpty { "/" }
            if (path.endsWith("/")) path += "index.html"
            path = path.trimStart('/')
            val lastSegment = path.substringAfterLast('/')
            if (!lastSegment.contains('.')) path = "$path.html"
            return path.split('/')
                .filter { it.isNotEmpty() && it != "." && it != ".." }
                .joinToString("/")
        }

        private fun relativePath(fromFile: String, toFile: String): String {
            val fromParts = fromFile.split('/').dropLast(1)
            val toParts = toFile.split('/')
            var common = 0
            while (common < fromParts.size && common < toParts.size - 1 &&
                fromParts[common] == toParts[common]
            ) {
                common++
            }
            val ups = List(fromParts.size - common) { ".." }
            val down = toParts.drop(common)
            return (ups + down).joinToString("/").ifEmpty { toFile.substringAfterLast('/') }
        }

        private fun absolutize(ref: String, pageUrl: URL): String? {
            if (ref.isBlank()) return null
            val lower = ref.lowercase()
            if (lower.startsWith("data:") || lower.startsWith("javascript:") ||
                lower.startsWith("mailto:") || lower.startsWith("#") ||
                lower.startsWith("blob:")
            ) {
                return null
            }
            return runCatching {
                if (ref.startsWith("//")) URL(pageUrl.protocol + ":" + ref).toString()
                else URL(pageUrl, ref).toString()
            }.getOrNull()
        }

        private fun stripFragment(url: String): String = url.substringBefore('#')

        private companion object {
            const val MAX_FILES = 250
            const val MAX_BYTES = 30L * 1024 * 1024
            val HTML_REF = Regex("""(?i)(src|href)\s*=\s*["']([^"']+)["']""")
            val CSS_URL = Regex("""(?i)url\(\s*['"]?([^'")]+)['"]?\s*\)""")
            val CSS_IMPORT = Regex("""(?i)@import\s+(?:url\(\s*)?['"]([^'"]+)['"]""")
        }
    }

    private companion object {
        val ENTRY_CANDIDATES = listOf("index.html", "index.htm")
    }
}
