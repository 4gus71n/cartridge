package com.cartridge.app.network

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.ClientRequestException
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.RedirectResponseException
import io.ktor.client.plugins.ServerResponseException
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import kotlin.concurrent.Volatile
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class UserDto(
    val id: Int,
    val email: String,
    @SerialName("is_admin") val isAdmin: Boolean = false,
)

@Serializable
data class AuthResponse(val token: String, val user: UserDto)

@Serializable
private data class Credentials(val email: String, val password: String)

@Serializable
data class GameDto(
    val slug: String,
    val title: String,
    val description: String = "",
    val author: String = "",
    @SerialName("license_spdx") val licenseSpdx: String = "MIT",
    @SerialName("source_url") val sourceUrl: String = "",
    @SerialName("play_url") val playUrl: String = "",
    @SerialName("package_url") val packageUrl: String = "",
    @SerialName("package_sha256") val packageSha256: String = "",
    @SerialName("thumbnail_url") val thumbnailUrl: String = "",
    @SerialName("poster_style") val posterStyle: String = "TAP",
    @SerialName("accent_top") val accentTop: String = "#0B1020",
    @SerialName("accent_bottom") val accentBottom: String = "#1B2350",
    val bundled: Boolean = false,
    val status: String = "",
    val orientation: String = "any",
    val tags: String = "",
    val likes: Int = 0,
    val comments: Int = 0,
    @SerialName("updated_at") val updatedAt: String = "",
    val version: Int = 1,
    @SerialName("title_es") val titleEs: String = "",
    @SerialName("description_es") val descriptionEs: String = "",
    @SerialName("taken_down") val takenDown: Boolean = false,
)

@Serializable
data class DeletePassword(val password: String)

/** `catalog.json` on GitHub Pages: the full feed, readable without the API. */
@Serializable
data class CatalogDto(
    val games: List<GameDto> = emptyList(),
    val sha256: String = "",
)

/** `config.json` on GitHub Pages: where the API currently lives. */
@Serializable
data class ConfigDto(
    @SerialName("api_base_url") val apiBaseUrl: String = "",
    @SerialName("catalog_url") val catalogUrl: String = "",
)

@Serializable
data class LikeDto(val liked: Boolean, val likes: Int)

@Serializable
data class SaveDto(val saved: Boolean)

@Serializable
private data class SaveRequest(@SerialName("collection_id") val collectionId: Int? = null)

@Serializable
data class CollectionDto(
    val id: Int,
    val name: String,
    val count: Int = 0,
    @SerialName("game_slugs") val gameSlugs: List<String> = emptyList(),
)

@Serializable
private data class CollectionRequest(val name: String)

@Serializable
private data class CollectionItemRequest(val slug: String)

@Serializable
data class CommentDto(
    val id: Int,
    val author: String,
    val body: String,
    @SerialName("created_at") val createdAt: String = "",
)

@Serializable
private data class CommentRequest(val body: String)

@Serializable
private data class ReportRequest(val reason: String, val details: String = "")

class ApiClient(
    baseUrls: List<String>,
    private val tokenProvider: () -> String?,
) {
    private val bases = baseUrls.toMutableList()

    private val client = HttpClient {
        expectSuccess = true
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
        install(HttpTimeout) {
            connectTimeoutMillis = 4000
            requestTimeoutMillis = 20000
            socketTimeoutMillis = 20000
        }
    }

    @Volatile
    private var activeBase: String = bases.first()

    /** Try [url] first from now on (e.g. the tunnel URL published in config.json). */
    fun preferBase(url: String) {
        val clean = url.trimEnd('/')
        if (clean.isBlank()) return
        bases.remove(clean)
        bases.add(0, clean)
        activeBase = clean
    }

    /** Pages files are static and public: plain GETs, no API failover. */
    suspend fun pagesConfig(): ConfigDto =
        JSON.decodeFromString(ConfigDto.serializer(), client.get("$PAGES_URL/config.json").bodyAsText())

    /** Returns the parsed catalog plus its raw JSON (cached for offline starts). */
    suspend fun pagesCatalog(url: String = "$PAGES_URL/catalog.json"): Pair<CatalogDto, String> {
        val raw = client.get(url).bodyAsText()
        return decodeCatalog(raw) to raw
    }

    companion object {
        const val PAGES_URL = "https://4gus71n.github.io/cartridge-games"
        private val JSON = Json { ignoreUnknownKeys = true }

        fun decodeCatalog(raw: String): CatalogDto = JSON.decodeFromString(CatalogDto.serializer(), raw)
    }

    private suspend fun <T> execute(block: suspend (String) -> T): T {
        val candidates = listOf(activeBase) + bases.filter { it != activeBase }
        var lastError: Throwable? = null
        for (base in candidates) {
            try {
                val result = block(base)
                activeBase = base
                return result
            } catch (e: RedirectResponseException) {
                activeBase = base
                throw e
            } catch (e: ClientRequestException) {
                activeBase = base
                throw e
            } catch (e: ServerResponseException) {
                activeBase = base
                throw e
            } catch (e: Exception) {
                // Connection-level failure: try the next base URL.
                lastError = e
            }
        }
        throw lastError ?: IllegalStateException("No backend reachable")
    }

    private fun HttpRequestBuilder.auth() {
        tokenProvider()?.let { header(HttpHeaders.Authorization, "Bearer $it") }
    }

    private fun HttpRequestBuilder.jsonBody(value: Any) {
        contentType(ContentType.Application.Json)
        setBody(value)
    }

    suspend fun signup(email: String, password: String): AuthResponse =
        execute { base ->
            client.post("$base/auth/signup") { jsonBody(Credentials(email, password)) }.body()
        }

    suspend fun login(email: String, password: String): AuthResponse =
        execute { base ->
            client.post("$base/auth/login") { jsonBody(Credentials(email, password)) }.body()
        }

    /** Permanently deletes the signed-in account (server checks the password). */
    suspend fun deleteAccount(password: String) {
        execute { base ->
            client.post("$base/auth/delete") { auth(); jsonBody(DeletePassword(password)) }
        }
    }

    /** Base URL of the API that last answered (the public tunnel in production). */
    val currentBase: String get() = activeBase

    suspend fun me(): UserDto = execute { base -> client.get("$base/me") { auth() }.body() }

    suspend fun games(): List<GameDto> =
        execute { base ->
            // Authenticated so the server can hide games this user reported.
            client.get("$base/games?status=verified") { auth() }.body()
        }

    suspend fun like(slug: String): LikeDto =
        execute { base -> client.post("$base/games/$slug/like") { auth() }.body() }

    suspend fun unlike(slug: String): LikeDto =
        execute { base -> client.delete("$base/games/$slug/like") { auth() }.body() }

    suspend fun myLikes(): List<GameDto> =
        execute { base -> client.get("$base/me/likes") { auth() }.body() }

    suspend fun save(slug: String, collectionId: Int?): SaveDto =
        execute { base ->
            client.post("$base/games/$slug/save") {
                auth()
                jsonBody(SaveRequest(collectionId))
            }.body()
        }

    suspend fun unsave(slug: String): SaveDto =
        execute { base -> client.delete("$base/games/$slug/save") { auth() }.body() }

    suspend fun mySaves(): List<GameDto> =
        execute { base -> client.get("$base/me/saves") { auth() }.body() }

    suspend fun collections(): List<CollectionDto> =
        execute { base -> client.get("$base/collections") { auth() }.body() }

    suspend fun createCollection(name: String): CollectionDto =
        execute { base ->
            client.post("$base/collections") { auth(); jsonBody(CollectionRequest(name)) }.body()
        }

    suspend fun addToCollection(collectionId: Int, slug: String): CollectionDto =
        execute { base ->
            client.post("$base/collections/$collectionId/items") {
                auth()
                jsonBody(CollectionItemRequest(slug))
            }.body()
        }

    suspend fun removeFromCollection(collectionId: Int, slug: String): CollectionDto =
        execute { base ->
            client.delete("$base/collections/$collectionId/items/$slug") { auth() }.body()
        }

    suspend fun deleteCollection(collectionId: Int) {
        execute { base -> client.delete("$base/collections/$collectionId") { auth() } }
    }

    suspend fun comments(slug: String): List<CommentDto> =
        execute { base -> client.get("$base/games/$slug/comments").body() }

    suspend fun addComment(slug: String, body: String): CommentDto =
        execute { base ->
            client.post("$base/games/$slug/comments") { auth(); jsonBody(CommentRequest(body)) }.body()
        }

    suspend fun report(slug: String, reason: String, details: String) {
        execute { base ->
            client.post("$base/games/$slug/report") {
                auth()
                jsonBody(ReportRequest(reason, details))
            }
        }
    }
}
