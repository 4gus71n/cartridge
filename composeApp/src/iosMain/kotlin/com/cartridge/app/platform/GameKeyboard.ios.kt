package com.cartridge.app.platform

actual object GameKeyboard {
    actual fun send(key: String, down: Boolean) = Unit
}
