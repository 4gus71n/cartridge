package com.cartridge.app.platform

/** Sends synthetic keyboard events into the active game WebView. */
expect object GameKeyboard {
    fun send(key: String, down: Boolean)
}
