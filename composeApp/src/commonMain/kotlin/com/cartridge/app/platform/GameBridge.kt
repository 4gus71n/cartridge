package com.cartridge.app.platform

/**
 * Durable per-game key/value storage, exposed to games as `window.cartridge.storage`.
 *
 * Games run in a WebView, whose localStorage/IndexedDB can be lost (origin changes,
 * WebView data resets, cache clears). This store lives in the app's own preferences
 * (Android SharedPreferences, iOS NSUserDefaults) under one namespace per game slug,
 * so a game can only see its own data.
 */
expect object GameSaveStore {
    fun get(slug: String, key: String): String?
    fun set(slug: String, key: String, value: String)
    fun remove(slug: String, key: String)
    fun keys(slug: String): List<String>
    fun clear(slug: String)
}

/** Validation + quotas shared by every platform bridge. */
object GameBridgeCore {
    const val MAX_KEY = 256
    const val MAX_VALUE = 1_000_000 // chars
    const val MAX_TOTAL = 5_000_000 // chars per game

    fun get(slug: String, key: String): String? =
        if (key.isEmpty() || key.length > MAX_KEY) null else GameSaveStore.get(slug, key)

    /** Returns false (and stores nothing) when the key/value breaks a limit. */
    fun set(slug: String, key: String, value: String): Boolean {
        if (key.isEmpty() || key.length > MAX_KEY || value.length > MAX_VALUE) return false
        val others = GameSaveStore.keys(slug).filter { it != key }
            .sumOf { (GameSaveStore.get(slug, it)?.length ?: 0) + it.length }
        if (others + key.length + value.length > MAX_TOTAL) return false
        GameSaveStore.set(slug, key, value)
        return true
    }

    fun remove(slug: String, key: String) {
        if (key.isNotEmpty() && key.length <= MAX_KEY) GameSaveStore.remove(slug, key)
    }

    fun keysJson(slug: String): String =
        GameSaveStore.keys(slug).joinToString(",", "[", "]") { "\"" + jsonEscape(it) + "\"" }

    private fun jsonEscape(s: String) = buildString {
        s.forEach { c ->
            when {
                c == '"' -> append("\\\"")
                c == '\\' -> append("\\\\")
                c < ' ' -> append("\\u" + c.code.toString(16).padStart(4, '0'))
                else -> append(c)
            }
        }
    }
}

/** Name of the native object the platform injects (Android addJavascriptInterface). */
const val GAME_BRIDGE_NATIVE = "CartridgeNative"

/**
 * Runs at document start, before any game script:
 * - defines `window.cartridge` = { available, version, platform, storage: {getItem,
 *   setItem, removeItem, keys, clear} } on top of the native object;
 * - mirrors localStorage into it ("ls:" keys): restores keys missing from
 *   localStorage, then writes every setItem/removeItem/clear through, so games that
 *   only use localStorage get durable saves without any change.
 * Explicit storage keys and mirrored localStorage keys live in separate prefixes.
 */
const val GAME_BRIDGE_JS = """
(function () {
  if (window.cartridge && window.cartridge.__ready) return;
  var N = window.CartridgeNative;
  if (!N) return;
  function keys(prefix) {
    try { return JSON.parse(N.keys()).filter(function (k) { return k.indexOf(prefix) === 0; })
      .map(function (k) { return k.slice(prefix.length); }); } catch (e) { return []; }
  }
  var storage = {
    getItem: function (k) { var v = N.getItem('kv:' + String(k)); return v === undefined ? null : v; },
    setItem: function (k, v) { return N.setItem('kv:' + String(k), String(v)); },
    removeItem: function (k) { N.removeItem('kv:' + String(k)); },
    keys: function () { return keys('kv:'); },
    clear: function () { keys('kv:').forEach(function (k) { N.removeItem('kv:' + k); }); }
  };
  window.cartridge = { __ready: true, available: true, version: 1, platform: N.platform(), storage: storage };
  try {
    var ls = window.localStorage, P = Storage.prototype;
    var set = P.setItem, rem = P.removeItem, clr = P.clear;
    keys('ls:').forEach(function (k) {
      if (ls.getItem(k) === null) { var v = N.getItem('ls:' + k); if (v !== null) set.call(ls, k, v); }
    });
    P.setItem = function (k, v) { set.call(this, k, v); if (this === ls) N.setItem('ls:' + String(k), String(v)); };
    P.removeItem = function (k) { rem.call(this, k); if (this === ls) N.removeItem('ls:' + String(k)); };
    P.clear = function () { clr.call(this); if (this === ls) keys('ls:').forEach(function (k) { N.removeItem('ls:' + k); }); };
  } catch (e) { console.log('cartridge localStorage mirror off: ' + e); }
  try { window.dispatchEvent(new Event('cartridgeready')); } catch (e) {}
})();
"""
