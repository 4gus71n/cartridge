package com.cartridge.app.platform

import android.webkit.WebView
import java.lang.ref.WeakReference

actual object GameKeyboard {
    private var ref: WeakReference<WebView>? = null

    fun attach(view: WebView) {
        ref = WeakReference(view)
    }

    fun detach(view: WebView) {
        if (ref?.get() === view) ref = null
    }

    actual fun send(key: String, down: Boolean) {
        val view = ref?.get() ?: return
        val spec = SPECS[key] ?: return
        val type = if (down) "keydown" else "keyup"
        val shift = if (key == "Shift") ", shiftKey: true" else ""
        val js = "document.dispatchEvent(new KeyboardEvent('$type', {key: '${spec.key}', " +
            "code: '${spec.code}', keyCode: ${spec.keyCode}, which: ${spec.keyCode}, " +
            "bubbles: true, cancelable: true$shift}));"
        view.evaluateJavascript(js, null)
    }

    private data class Spec(val key: String, val code: String, val keyCode: Int)

    private val SPECS = mapOf(
        "W" to Spec("w", "KeyW", 87),
        "A" to Spec("a", "KeyA", 65),
        "S" to Spec("s", "KeyS", 83),
        "D" to Spec("d", "KeyD", 68),
        "ArrowUp" to Spec("ArrowUp", "ArrowUp", 38),
        "ArrowDown" to Spec("ArrowDown", "ArrowDown", 40),
        "ArrowLeft" to Spec("ArrowLeft", "ArrowLeft", 37),
        "ArrowRight" to Spec("ArrowRight", "ArrowRight", 39),
        "Z" to Spec("z", "KeyZ", 90),
        "X" to Spec("x", "KeyX", 88),
        "Space" to Spec(" ", "Space", 32),
        "Enter" to Spec("Enter", "Enter", 13),
        "Shift" to Spec("Shift", "ShiftLeft", 16),
    )
}
