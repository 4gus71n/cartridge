package com.cartridge.app.platform

import platform.Foundation.NSUserDefaults

actual object KeyValueStore {
    private val defaults = NSUserDefaults.standardUserDefaults

    actual fun getString(key: String): String? = defaults.stringForKey(key)

    actual fun putString(key: String, value: String) {
        defaults.setObject(value, key)
    }

    actual fun remove(key: String) {
        defaults.removeObjectForKey(key)
    }
}

actual fun apiBaseUrls(): List<String> = listOf(
    "http://192.168.1.26:8123",
    "http://127.0.0.1:8123",
)
