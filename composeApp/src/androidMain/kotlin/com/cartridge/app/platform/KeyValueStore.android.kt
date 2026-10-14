package com.cartridge.app.platform

import android.content.Context
import android.content.SharedPreferences

actual object KeyValueStore {
    private val prefs: SharedPreferences
        get() = AndroidAppContext.appContext
            .getSharedPreferences("cartridge", Context.MODE_PRIVATE)

    actual fun getString(key: String): String? = prefs.getString(key, null)

    actual fun putString(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    actual fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }
}
