package com.cartridge.app.platform

import platform.Foundation.NSUserDefaults

/**
 * iOS store for the game bridge: one NSUserDefaults suite per game. The iOS game
 * runtime (WKWebView host, roadmap M6) wires `window.CartridgeNative` to
 * [GameBridgeCore] through a WKScriptMessageHandlerWithReply.
 */
actual object GameSaveStore {
    private fun defaults(slug: String): NSUserDefaults =
        NSUserDefaults(suiteName = "cartridge.gamesave.$slug")

    actual fun get(slug: String, key: String): String? = defaults(slug).stringForKey(key)

    actual fun set(slug: String, key: String, value: String) {
        defaults(slug).setObject(value, key)
    }

    actual fun remove(slug: String, key: String) {
        defaults(slug).removeObjectForKey(key)
    }

    actual fun keys(slug: String): List<String> =
        (defaults(slug).persistentDomainForName("cartridge.gamesave.$slug")?.keys ?: emptySet<Any?>())
            .mapNotNull { it as? String }
            .sorted()

    actual fun clear(slug: String) {
        defaults(slug).removePersistentDomainForName("cartridge.gamesave.$slug")
    }
}
