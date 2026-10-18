package com.cartridge.app.data

import com.cartridge.app.platform.KeyValueStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class CollectionData(
    val id: Int,
    val name: String,
    val slugs: List<String> = emptyList(),
)

@Serializable
data class SocialCache(
    val liked: List<String> = emptyList(),
    val saved: List<String> = emptyList(),
    val collections: List<CollectionData> = emptyList(),
    val hidden: List<String> = emptyList(),
)

class LocalStore {
    private val json = Json { ignoreUnknownKeys = true }

    val token: String?
        get() = KeyValueStore.getString(KEY_TOKEN)

    val email: String?
        get() = KeyValueStore.getString(KEY_EMAIL)

    val userId: Int?
        get() = KeyValueStore.getString(KEY_USER_ID)?.toIntOrNull()

    fun saveSession(token: String, userId: Int, email: String) {
        KeyValueStore.putString(KEY_TOKEN, token)
        KeyValueStore.putString(KEY_USER_ID, userId.toString())
        KeyValueStore.putString(KEY_EMAIL, email)
    }

    fun clearSession() {
        KeyValueStore.remove(KEY_TOKEN)
        KeyValueStore.remove(KEY_USER_ID)
        KeyValueStore.remove(KEY_EMAIL)
    }

    fun saveSocial(cache: SocialCache) {
        KeyValueStore.putString(KEY_SOCIAL, json.encodeToString(SocialCache.serializer(), cache))
    }

    fun loadSocial(): SocialCache {
        val raw = KeyValueStore.getString(KEY_SOCIAL) ?: return SocialCache()
        return runCatching { json.decodeFromString(SocialCache.serializer(), raw) }
            .getOrDefault(SocialCache())
    }

    fun clearSocial() {
        KeyValueStore.remove(KEY_SOCIAL)
    }

    fun isDesktopMode(slug: String): Boolean =
        KeyValueStore.getString("game.desktop.$slug") == "1"

    fun setDesktopMode(slug: String, enabled: Boolean) {
        KeyValueStore.putString("game.desktop.$slug", if (enabled) "1" else "0")
    }

    /** Last good `catalog.json` from Pages, so a cold start offline still has a feed. */
    fun loadCatalogRaw(): String? = KeyValueStore.getString(KEY_CATALOG)

    fun saveCatalogRaw(raw: String) {
        KeyValueStore.putString(KEY_CATALOG, raw)
    }

    fun loadSeen(): Set<String> {
        val raw = KeyValueStore.getString(KEY_SEEN) ?: return emptySet()
        return raw.split("\n").filter { it.isNotBlank() }.toSet()
    }

    fun saveSeen(ids: Set<String>) {
        KeyValueStore.putString(KEY_SEEN, ids.joinToString("\n"))
    }

    private companion object {
        const val KEY_TOKEN = "auth.token"
        const val KEY_USER_ID = "auth.userId"
        const val KEY_EMAIL = "auth.email"
        const val KEY_SOCIAL = "social.cache"
        const val KEY_SEEN = "feed.seen"
        const val KEY_CATALOG = "catalog.pages"
    }
}
