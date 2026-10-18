package com.cartridge.app.state

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import com.cartridge.app.data.CollectionData
import com.cartridge.app.data.LocalStore
import com.cartridge.app.data.SeedCatalog
import com.cartridge.app.data.SocialCache
import com.cartridge.app.model.Author
import com.cartridge.app.model.Cartridge
import com.cartridge.app.model.PosterStyle
import com.cartridge.app.network.ApiClient
import com.cartridge.app.network.GameDto
import com.cartridge.app.platform.GameStorage
import com.cartridge.app.platform.apiBaseUrls
import io.ktor.client.plugins.ClientRequestException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.launch

data class UserInfo(val id: Int, val email: String)

data class Comment(val id: Int, val author: String, val body: String)

class AppState(
    private val local: LocalStore = LocalStore(),
    val gameStorage: GameStorage = GameStorage(),
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val api = ApiClient(apiBaseUrls()) { local.token }

    var catalog by mutableStateOf(SeedCatalog.cartridges)
        private set

    var user by mutableStateOf<UserInfo?>(null)
        private set

    var authVisible by mutableStateOf(false)
        private set

    var authLoading by mutableStateOf(false)
        private set

    var authError by mutableStateOf<String?>(null)
        private set

    var profileVisible by mutableStateOf(false)
        private set

    var likedIds by mutableStateOf<Set<String>>(emptySet())
        private set

    var savedIds by mutableStateOf<Set<String>>(emptySet())
        private set

    var hiddenIds by mutableStateOf<Set<String>>(emptySet())
        private set

    var seenIds by mutableStateOf<Set<String>>(emptySet())
        private set

    var feed by mutableStateOf<List<Cartridge>>(emptyList())
        private set

    var collections by mutableStateOf<List<CollectionData>>(emptyList())
        private set

    var saveSheetFor by mutableStateOf<Cartridge?>(null)
        private set

    var createCollectionVisible by mutableStateOf(false)
        private set

    var playing by mutableStateOf<Cartridge?>(null)
        private set

    var commenting by mutableStateOf<Cartridge?>(null)
        private set

    var comments by mutableStateOf<List<Comment>>(emptyList())
        private set

    var commentsLoading by mutableStateOf(false)
        private set

    var creditsFor by mutableStateOf<Cartridge?>(null)
        private set

    var reportFor by mutableStateOf<Cartridge?>(null)
        private set

    var reportSubmitting by mutableStateOf(false)
        private set

    var reportError by mutableStateOf<String?>(null)
        private set

    var snackbar by mutableStateOf<String?>(null)
        private set

    private val likeCounts = mutableStateMapOf<String, Int>()
    private val commentCounts = mutableStateMapOf<String, Int>()
    private var localCollectionSeq = -1

    init {
        user = local.email?.let { UserInfo(local.userId ?: 0, it) }
        val social = local.loadSocial()
        likedIds = social.liked.toSet()
        savedIds = social.saved.toSet()
        collections = social.collections
        hiddenIds = social.hidden.toSet()
        seenIds = local.loadSeen()
        recomputeFeed()
        refreshCatalog()
        if (user != null) syncFromServer()
    }

    /** Unseen games first, then newest additions; snapshot so the feed does not
     * reshuffle while the user is scrolling. */
    private fun recomputeFeed() {
        feed = catalog
            .filterNot { hiddenIds.contains(it.id) }
            .withIndex()
            .sortedWith(
                compareBy<IndexedValue<Cartridge>> { seenIds.contains(it.value.id) }
                    .thenByDescending { it.value.updatedAt }
                    .thenBy { it.index },
            )
            .map { it.value }
    }

    fun isDesktopMode(slug: String): Boolean = local.isDesktopMode(slug)

    fun setDesktopMode(slug: String, enabled: Boolean) = local.setDesktopMode(slug, enabled)

    fun markSeen(cartridge: Cartridge) {
        if (seenIds.contains(cartridge.id)) return
        seenIds = seenIds + cartridge.id
        local.saveSeen(seenIds)
    }

    // --- helpers -----------------------------------------------------------

    private fun persistSocial() {
        local.saveSocial(
            SocialCache(
                liked = likedIds.toList(),
                saved = savedIds.toList(),
                collections = collections,
                hidden = hiddenIds.toList(),
            ),
        )
    }



    fun showSnackbar(message: String) {
        snackbar = message
    }

    fun clearSnackbar() {
        snackbar = null
    }

    fun likeCount(cartridge: Cartridge): Int =
        likeCounts[cartridge.id] ?: cartridge.seedLikes

    fun commentCount(cartridge: Cartridge): Int =
        commentCounts[cartridge.id] ?: cartridge.seedComments

    // --- catalog -----------------------------------------------------------

    /**
     * Feed sources, in order: `catalog.json` on GitHub Pages (always up, includes
     * takedowns), then the cached copy of it, then the API list. The API, when
     * reachable, only adds live like/comment counts. After every refresh,
     * installed games whose package sha changed are updated in the background.
     */
    fun refreshCatalog() {
        scope.launch {
            runCatching { api.pagesConfig() }.getOrNull()?.apiBaseUrl
                ?.takeIf { it.startsWith("http") }
                ?.let { api.preferBase(it) }
            val pagesDeferred = async { runCatching { api.pagesCatalog() }.getOrNull() }
            val apiDeferred = async { runCatching { api.games() }.getOrNull() }
            val pages = pagesDeferred.await()
            val apiGames = apiDeferred.await()
            pages?.let { local.saveCatalogRaw(it.second) }
            val pagesGames = pages?.first?.games
                ?: local.loadCatalogRaw()?.let { raw -> runCatching { ApiClient.decodeCatalog(raw).games }.getOrNull() }
            apiGames?.forEach { game ->
                likeCounts[game.slug] = game.likes
                commentCounts[game.slug] = game.comments
            }
            val source = pagesGames?.takeIf { it.isNotEmpty() } ?: apiGames?.takeIf { it.isNotEmpty() }
                ?: return@launch
            source.filter { it.takenDown && gameStorage.isInstalled(it.slug) }
                .forEach { gameStorage.delete(it.slug) }
            val live = source.filterNot { it.takenDown }
            catalog = live.map { it.toCartridge() }
            recomputeFeed()
            updateInstalledGames(live)
        }
    }

    private var updating = false

    /** Re-download installed games that have a newer approved package (one at a time). */
    private fun updateInstalledGames(games: List<GameDto>) {
        if (updating) return
        val stale = games.filter {
            it.packageUrl.isNotBlank() && it.packageSha256.isNotBlank() &&
                gameStorage.needsUpdate(it.slug, it.packageSha256)
        }
        if (stale.isEmpty()) return
        updating = true
        scope.launch {
            try {
                for (game in stale) {
                    if (playing?.id == game.slug) continue // never swap files under a running game
                    runCatching {
                        gameStorage.downloadPackage(game.slug, game.packageUrl, game.packageSha256) {}
                    }
                }
            } finally {
                updating = false
            }
        }
    }

    // --- auth --------------------------------------------------------------

    fun showAuth() {
        authError = null
        authVisible = true
    }

    fun hideAuth() {
        authVisible = false
    }

    fun authenticate(signup: Boolean, email: String, password: String) {
        if (authLoading) return
        authLoading = true
        authError = null
        scope.launch {
            runCatching {
                if (signup) api.signup(email.trim(), password) else api.login(email.trim(), password)
            }
                .onSuccess { response ->
                    local.saveSession(response.token, response.user.id, response.user.email)
                    user = UserInfo(response.user.id, response.user.email)
                    authVisible = false
                    syncFromServer()
                    refreshCatalog()
                }
                .onFailure { authError = friendlyError(it) }
            authLoading = false
        }
    }

    fun logout() {
        local.clearSession()
        local.clearSocial()
        user = null
        likedIds = emptySet()
        savedIds = emptySet()
        collections = emptyList()
        hiddenIds = emptySet()
        profileVisible = false
    }

    fun syncFromServer() {
        scope.launch {
            val localLikes = likedIds
            val localSaves = savedIds
            val localCollections = collections
            runCatching {
                Triple(
                    api.myLikes().map { it.slug }.toSet(),
                    api.mySaves().map { it.slug }.toSet(),
                    api.collections(),
                )
            }.onSuccess { (serverLikes, serverSaves, serverCollections) ->
                (localLikes - serverLikes).forEach { runCatching { api.like(it) } }
                (localSaves - serverSaves).forEach { runCatching { api.save(it, null) } }
                likedIds = localLikes + serverLikes
                savedIds = localSaves + serverSaves

                val serverNames = serverCollections.map { it.name }.toSet()
                for (collection in localCollections) {
                    if (collection.name !in serverNames) {
                        runCatching {
                            val created = api.createCollection(collection.name)
                            collection.slugs.forEach { slug ->
                                runCatching { api.addToCollection(created.id, slug) }
                            }
                        }
                    }
                }

                val refreshed = runCatching { api.collections() }.getOrNull() ?: serverCollections
                val refreshedMapped = refreshed.map { CollectionData(it.id, it.name, it.gameSlugs) }
                val refreshedNames = refreshedMapped.map { it.name }.toSet()
                val stillLocal = localCollections.filter {
                    it.id <= 0 && it.name !in refreshedNames
                }
                collections = refreshedMapped + stillLocal
                persistSocial()
            }
        }
    }

    // --- likes -------------------------------------------------------------

    fun toggleLike(cartridge: Cartridge) {
        if (user == null) {
            showAuth()
            return
        }
        val nowLiked = !likedIds.contains(cartridge.id)
        likedIds = if (nowLiked) likedIds + cartridge.id else likedIds - cartridge.id
        likeCounts[cartridge.id] = (likeCount(cartridge) + if (nowLiked) 1 else -1)
            .coerceAtLeast(0)
        persistSocial()
        if (nowLiked) ensureOffline(cartridge)
        scope.launch {
            runCatching { if (nowLiked) api.like(cartridge.id) else api.unlike(cartridge.id) }
                .onSuccess { result -> likeCounts[cartridge.id] = result.likes }
                .onFailure { showSnackbar("Offline — will sync later") }
        }
    }

    // --- saves & collections ----------------------------------------------

    fun requestSave(cartridge: Cartridge) {
        if (user == null) {
            showAuth()
            return
        }
        saveSheetFor = cartridge
    }

    fun closeSaveSheet() {
        saveSheetFor = null
    }

    private fun markSaved(cartridge: Cartridge, collectionId: Int?) {
        savedIds = savedIds + cartridge.id
        if (collectionId != null) {
            collections = collections.map {
                if (it.id == collectionId) it.copy(slugs = (it.slugs + cartridge.id).distinct())
                else it
            }
        }
        persistSocial()
        ensureOffline(cartridge)
        scope.launch {
            runCatching {
                api.save(cartridge.id, collectionId?.takeIf { it > 0 })
            }.onFailure { showSnackbar("Offline — will sync later") }
        }
    }

    fun saveToAll(cartridge: Cartridge) {
        markSaved(cartridge, null)
        saveSheetFor = null
    }

    fun saveToCollection(cartridge: Cartridge, collectionId: Int) {
        markSaved(cartridge, collectionId)
        saveSheetFor = null
    }

    fun unsave(cartridge: Cartridge) {
        savedIds = savedIds - cartridge.id
        collections = collections.map { it.copy(slugs = it.slugs - cartridge.id) }
        persistSocial()
        saveSheetFor = null
        scope.launch {
            runCatching { api.unsave(cartridge.id) }
                .onFailure { showSnackbar("Offline — will sync later") }
        }
    }

    fun showCreateCollection() {
        createCollectionVisible = true
    }

    fun dismissCreateCollection() {
        createCollectionVisible = false
    }

    fun createCollection(name: String) {
        val trimmed = name.trim()
        createCollectionVisible = false
        if (trimmed.isEmpty()) return

        // Local-first: the collection (and the pending save) exists immediately.
        val localId = localCollectionSeq--
        collections = collections + CollectionData(localId, trimmed, emptyList())
        val pending = saveSheetFor
        if (pending != null) {
            saveToCollection(pending, localId)
        } else {
            persistSocial()
        }

        scope.launch {
            runCatching { api.createCollection(trimmed) }
                .onSuccess { dto ->
                    val slugs = collections.firstOrNull { it.id == localId }?.slugs ?: emptyList()
                    collections = collections.map {
                        if (it.id == localId) CollectionData(dto.id, dto.name, it.slugs) else it
                    }
                    persistSocial()
                    slugs.forEach { slug -> runCatching { api.addToCollection(dto.id, slug) } }
                }
                .onFailure { showSnackbar("Saved locally — will sync later") }
        }
    }

    fun deleteCollection(collectionId: Int) {
        collections = collections.filterNot { it.id == collectionId }
        persistSocial()
        if (collectionId > 0) {
            scope.launch { runCatching { api.deleteCollection(collectionId) } }
        }
    }

    fun collectionCartridges(collection: CollectionData): List<Cartridge> =
        collection.slugs.mapNotNull { slug -> catalog.firstOrNull { it.id == slug } }

    fun likedCartridges(): List<Cartridge> = catalog.filter { likedIds.contains(it.id) }

    fun savedCartridges(): List<Cartridge> = catalog.filter { savedIds.contains(it.id) }

    // --- comments ----------------------------------------------------------

    fun openComments(cartridge: Cartridge) {
        commenting = cartridge
        comments = emptyList()
        commentsLoading = true
        scope.launch {
            runCatching { api.comments(cartridge.id) }
                .onSuccess { list ->
                    comments = list.map { Comment(it.id, it.author, it.body) }
                    commentCounts[cartridge.id] = list.size
                }
            commentsLoading = false
        }
    }

    fun closeComments() {
        commenting = null
        comments = emptyList()
    }

    fun addComment(cartridge: Cartridge, body: String) {
        if (user == null) {
            showAuth()
            return
        }
        val text = body.trim()
        if (text.isEmpty()) return
        scope.launch {
            runCatching { api.addComment(cartridge.id, text) }
                .onSuccess { dto ->
                    comments = comments + Comment(dto.id, dto.author, dto.body)
                    commentCounts[cartridge.id] = commentCount(cartridge) + 1
                }
                .onFailure { showSnackbar("Could not post comment — check connection") }
        }
    }

    // --- profile -----------------------------------------------------------

    fun openProfile() {
        if (user == null) {
            showAuth()
        } else {
            refreshCatalog()
            profileVisible = true
        }
    }

    fun closeProfile() {
        profileVisible = false
    }

    // --- player / credits --------------------------------------------------

    fun play(cartridge: Cartridge) {
        markSeen(cartridge)
        playing = cartridge
    }

    fun closePlayer() {
        playing = null
    }

    fun openCredits(cartridge: Cartridge) {
        creditsFor = cartridge
    }

    fun closeCredits() {
        creditsFor = null
    }

    // --- reports -----------------------------------------------------------

    fun openReport(cartridge: Cartridge) {
        reportError = null
        reportFor = cartridge
    }

    fun closeReport() {
        reportFor = null
        reportError = null
        reportSubmitting = false
    }

    fun submitReport(cartridge: Cartridge, reason: String, details: String) {
        if (reportSubmitting) return
        reportSubmitting = true
        reportError = null
        scope.launch {
            runCatching { api.report(cartridge.id, reason, details.trim()) }
                .onSuccess {
                    hiddenIds = hiddenIds + cartridge.id
                    persistSocial()
                    recomputeFeed()
                    closeReport()
                    showSnackbar(
                        when (reason) {
                            "remove" -> "Removed from the catalog"
                            "unplayable" -> "Game removed — flagged as broken"
                            else -> "Report sent — this game won't show up for you anymore"
                        },
                    )
                }
                .onFailure {
                    reportError = "Couldn't send the report — check connection"
                    reportSubmitting = false
                }
        }
    }

    // --- offline -----------------------------------------------------------

    private fun ensureOffline(cartridge: Cartridge) {
        if (cartridge.bundled || gameStorage.isInstalled(cartridge.id)) return
        scope.launch {
            runCatching {
                when {
                    !cartridge.packageUrl.isNullOrBlank() -> gameStorage.downloadPackage(
                        cartridge.id,
                        cartridge.packageUrl,
                        cartridge.packageSha256,
                    ) {}
                    !cartridge.playUrl.isNullOrBlank() ->
                        gameStorage.mirrorRemote(cartridge.id, cartridge.playUrl) {}
                }
            }
                .onSuccess { showSnackbar("Saved for offline play") }
                .onFailure { showSnackbar("Couldn't save for offline — check connection") }
        }
    }

    private fun friendlyError(error: Throwable): String = when {
        error is ClientRequestException && error.response.status.value == 400 ->
            "That email is already registered"
        error is ClientRequestException && error.response.status.value == 401 ->
            "Invalid email or password"
        else -> "Couldn't reach the server — is the backend running?"
    }

    private fun GameDto.toCartridge(): Cartridge {
        val seed = SeedCatalog.cartridges.firstOrNull { it.id == slug }
        return Cartridge(
            id = slug,
            title = title,
            tagline = description.ifBlank { seed?.tagline ?: "" },
            author = Author(
                name = author.ifBlank { seed?.author?.name ?: "community" },
                handle = seed?.author?.handle
                    ?: author.lowercase().replace(Regex("[^a-z0-9]"), "").ifBlank { slug },
            ),
            licenseSpdx = licenseSpdx,
            sourceUrl = sourceUrl,
            modifications = seed?.modifications,
            assetPath = if (bundled) seed?.assetPath ?: "games/$slug/index.html" else "",
            accentTop = parseColor(accentTop, seed?.accentTop),
            accentBottom = parseColor(accentBottom, seed?.accentBottom),
            seedLikes = likes,
            seedComments = comments,
            poster = runCatching { PosterStyle.valueOf(posterStyle) }
                .getOrDefault(seed?.poster ?: PosterStyle.TAP),
            bundled = bundled,
            packageUrl = packageUrl.ifBlank { null },
            packageSha256 = packageSha256.ifBlank { null },
            playUrl = playUrl.ifBlank { null },
            orientation = orientation,
            updatedAt = updatedAt,
            thumbnailUrl = thumbnailUrl.ifBlank { null },
        )
    }

    private fun parseColor(value: String, fallback: Color?): Color {
        val hex = value.removePrefix("#")
        val parsed = runCatching {
            if (hex.length == 6) Color(0xFF000000 or hex.toLong(16)) else null
        }.getOrNull()
        return parsed ?: fallback ?: Color(0xFF0B1020)
    }
}
