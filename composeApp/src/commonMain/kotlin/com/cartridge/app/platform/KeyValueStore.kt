package com.cartridge.app.platform

expect object KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun remove(key: String)
}

expect fun apiBaseUrls(): List<String>
