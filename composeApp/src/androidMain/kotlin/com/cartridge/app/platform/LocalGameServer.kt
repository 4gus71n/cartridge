package com.cartridge.app.platform

import android.content.Context
import java.io.File
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket

/**
 * Tiny HTTP server bound to 127.0.0.1 that serves bundled assets and downloaded
 * games with full HTTP semantics (real headers, secure localhost origin).
 * This gives the WebView the same capabilities Chrome has when loading games
 * from a normal web server (cross-origin isolation, SharedArrayBuffer, WASM
 * threads, service workers, fetch/XHR, ...).
 *
 * Routes:
 *   /games/<path>  -> filesDir/games (downloaded packages)
 */
object LocalGameServer {
    private val PREFERRED_PORTS = listOf(47123, 47124, 47125)

    @Volatile
    private var serverSocket: ServerSocket? = null

    @Volatile
    var port: Int = 0
        private set

    fun ensureStarted(context: Context) {
        if (serverSocket != null) return
        synchronized(this) {
            if (serverSocket != null) return
            // A FIXED port keeps every game's origin (http://127.0.0.1:PORT) the same
            // across app restarts. localStorage and IndexedDB (Godot's user://) are
            // keyed by origin: a random port wiped every game's progress on each
            // restart. Fall back to a random port only if ours is taken.
            val loopback = InetAddress.getByName("127.0.0.1")
            val socket = PREFERRED_PORTS.firstNotNullOfOrNull { p ->
                runCatching { ServerSocket(p, 64, loopback) }.getOrNull()
            } ?: ServerSocket(0, 64, loopback)
            port = socket.localPort
            serverSocket = socket
            Thread {
                while (!socket.isClosed) {
                    val client = try {
                        socket.accept()
                    } catch (_: Exception) {
                        break
                    }
                    Thread { handle(context.applicationContext, client) }
                        .apply { isDaemon = true }
                        .start()
                }
            }.apply { isDaemon = true }.start()
        }
    }

    private fun handle(context: Context, socket: Socket) {
        try {
            socket.use { client ->
                client.soTimeout = 10000
                val input = client.getInputStream().bufferedReader(Charsets.ISO_8859_1)
                val requestLine = input.readLine() ?: return
                val path = requestLine.split(" ").getOrNull(1) ?: return
                // Drain headers.
                while (true) {
                    val line = input.readLine() ?: break
                    if (line.isEmpty()) break
                }

                val (status, mimeType, body) = resolve(context, path)
                val headers = buildString {
                    append("HTTP/1.1 $status\r\n")
                    append("Content-Type: $mimeType\r\n")
                    append("Content-Length: ${body.size}\r\n")
                    // Chrome parity: cross-origin isolation like itch.io serves.
                    append("Cross-Origin-Opener-Policy: same-origin\r\n")
                    append("Cross-Origin-Embedder-Policy: require-corp\r\n")
                    append("Cross-Origin-Resource-Policy: cross-origin\r\n")
                    append("Cache-Control: no-cache\r\n")
                    append("Connection: close\r\n")
                    append("\r\n")
                }
                val output: OutputStream = client.getOutputStream()
                output.write(headers.toByteArray(Charsets.ISO_8859_1))
                output.write(body)
                output.flush()
            }
        } catch (_: Exception) {
            // Client went away; nothing to do.
        }
    }

    private fun resolve(context: Context, rawPath: String): Triple<String, String, ByteArray> {
        val path = rawPath.substringBefore('?')
        val parts = path.trimStart('/').split('/')
            .filter { it.isNotEmpty() && it != "." && it != ".." }
        val clean = parts.joinToString("/")
        return try {
            when {
                clean.startsWith("games/") -> {
                    val file = File(context.filesDir, clean)
                    if (!file.isFile) return notFound()
                    Triple("200 OK", mimeTypeOf(file.name), file.readBytes())
                }
                else -> notFound()
            }
        } catch (_: Exception) {
            notFound()
        }
    }

    private fun notFound(): Triple<String, String, ByteArray> =
        Triple("404 Not Found", "text/plain; charset=utf-8", "Not found".toByteArray())

    private fun mimeTypeOf(name: String): String =
        when (name.substringAfterLast('.', "").lowercase()) {
            "html", "htm" -> "text/html; charset=utf-8"
            "js", "mjs" -> "text/javascript; charset=utf-8"
            "css" -> "text/css; charset=utf-8"
            "json" -> "application/json; charset=utf-8"
            "wasm" -> "application/wasm"
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "gif" -> "image/gif"
            "svg" -> "image/svg+xml"
            "webp" -> "image/webp"
            "ico" -> "image/x-icon"
            "mp3" -> "audio/mpeg"
            "ogg", "oga" -> "audio/ogg"
            "wav" -> "audio/wav"
            "m4a" -> "audio/mp4"
            "mp4" -> "video/mp4"
            "webm" -> "video/webm"
            "ttf" -> "font/ttf"
            "otf" -> "font/otf"
            "woff" -> "font/woff"
            "woff2" -> "font/woff2"
            "txt", "md" -> "text/plain; charset=utf-8"
            else -> "application/octet-stream"
        }
}
