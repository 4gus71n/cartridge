package com.cartridge.app.platform

import android.content.Context
import android.content.SharedPreferences
import android.webkit.JavascriptInterface

actual object GameSaveStore {
    private fun prefs(slug: String): SharedPreferences =
        AndroidAppContext.appContext.getSharedPreferences("gamesave.$slug", Context.MODE_PRIVATE)

    actual fun get(slug: String, key: String): String? = prefs(slug).getString(key, null)

    // commit(), not apply(): the write must be on disk before the call returns,
    // because players force-stop the app right after a save. JS interface calls
    // run on a WebView binder thread, so blocking briefly here is fine.
    actual fun set(slug: String, key: String, value: String) {
        prefs(slug).edit().putString(key, value).commit()
    }

    actual fun remove(slug: String, key: String) {
        prefs(slug).edit().remove(key).commit()
    }

    actual fun keys(slug: String): List<String> = prefs(slug).all.keys.sorted()

    actual fun clear(slug: String) {
        prefs(slug).edit().clear().commit()
    }
}

/** Object injected as `window.CartridgeNative`; bound to one game's namespace. */
class AndroidGameBridge(private val slug: String) {
    @JavascriptInterface
    fun getItem(key: String): String? = GameBridgeCore.get(slug, key)

    @JavascriptInterface
    fun setItem(key: String, value: String): Boolean = GameBridgeCore.set(slug, key, value)

    @JavascriptInterface
    fun removeItem(key: String) = GameBridgeCore.remove(slug, key)

    @JavascriptInterface
    fun keys(): String = GameBridgeCore.keysJson(slug)

    @JavascriptInterface
    fun platform(): String = "android"
}
