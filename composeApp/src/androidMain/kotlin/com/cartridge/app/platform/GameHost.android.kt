package com.cartridge.app.platform

import androidx.webkit.WebViewFeature
import androidx.webkit.WebViewCompat
import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.ConsoleMessage
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebResourceErrorCompat
import androidx.webkit.WebViewClientCompat

private const val DESKTOP_USER_AGENT =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

/** Chrome parity shims: fullscreen + pointer lock APIs that games expect. */
private const val COMPAT_SHIM = """
(function() {
  try {
    var proto = Element.prototype;
    if (proto.requestFullscreen) {
      proto.requestFullscreen = function() { return Promise.resolve(); };
    }
    if (proto.webkitRequestFullscreen) {
      proto.webkitRequestFullscreen = function() { return Promise.resolve(); };
    }
    if (document.exitFullscreen) {
      document.exitFullscreen = function() { return Promise.resolve(); };
    }
    Object.defineProperty(document, 'fullscreenEnabled', { get: function() { return true; } });
    Object.defineProperty(document, 'fullscreenElement', { get: function() { return document.documentElement; } });
    if (proto.requestPointerLock) {
      proto.requestPointerLock = function() {
        document.dispatchEvent(new Event('pointerlockchange'));
        return Promise.resolve();
      };
    }
    Object.defineProperty(document, 'pointerLockElement', { get: function() { return document.documentElement; } });
    console.log('Cartridge compat shim ready; secureContext=' + self.isSecureContext + ' crossOriginIsolated=' + self.crossOriginIsolated);
  } catch (e) {}
})();
"""

actual fun externalGameUrl(source: GameSource): String? = when (source) {
    is GameSource.Remote -> source.url
    is GameSource.Local ->
        if (LocalGameServer.port > 0) {
            "http://127.0.0.1:${LocalGameServer.port}/games/${source.entry}"
        } else {
            null
        }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
actual fun GameHost(
    source: GameSource,
    slug: String,
    modifier: Modifier,
    desktopMode: Boolean,
    onPageFinished: () -> Unit,
    onError: (String) -> Unit,
) {
    val currentOnPageFinished by rememberUpdatedState(onPageFinished)
    val currentOnError by rememberUpdatedState(onError)
    val currentSource = source
    val currentDesktopMode = desktopMode

    AndroidView(
        modifier = modifier,
        factory = { context ->
            val debuggable =
                (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
            if (debuggable) {
                WebView.setWebContentsDebuggingEnabled(true)
            }

            // Games are served from a real localhost HTTP server so they get
            // the exact HTTP environment Chrome gives them (headers, secure
            // origin, cross-origin isolation, fetch/XHR, service workers...).
            LocalGameServer.ensureStarted(context)
            val localPort = LocalGameServer.port

            fun isAllowed(url: android.net.Uri): Boolean {
                if (url.host == "127.0.0.1" && url.port == localPort) return true
                return currentSource is GameSource.Remote && url.host == currentSource.allowedHost
            }

            WebView(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
                setBackgroundColor(AndroidColor.BLACK)
                overScrollMode = View.OVER_SCROLL_NEVER
                isVerticalScrollBarEnabled = false
                isHorizontalScrollBarEnabled = false
                isLongClickable = false
                setOnLongClickListener { true }

                settings.apply {
                    javaScriptEnabled = true
                    domStorageEnabled = true
                    mediaPlaybackRequiresUserGesture = false
                    allowFileAccess = false
                    allowContentAccess = false
                    builtInZoomControls = false
                    displayZoomControls = false
                    setSupportZoom(false)
                    // Fit desktop-sized game pages to the screen.
                    useWideViewPort = true
                    loadWithOverviewMode = true
                    if (currentDesktopMode) {
                        userAgentString = DESKTOP_USER_AGENT
                    }
                }

                GameKeyboard.attach(this)

                // Durable saves: window.cartridge.storage + localStorage mirror,
                // bound to this game's slug (GameBridge.kt).
                addJavascriptInterface(AndroidGameBridge(slug), GAME_BRIDGE_NATIVE)
                val docStart = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
                if (docStart) {
                    val origins = buildSet {
                        add("http://127.0.0.1:$localPort")
                        (currentSource as? GameSource.Remote)?.let { add("https://${it.allowedHost}") }
                    }
                    WebViewCompat.addDocumentStartJavaScript(this, GAME_BRIDGE_JS, origins)
                }

                webChromeClient = object : WebChromeClient() {
                    override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                        Log.d(
                            "CartridgeGame",
                            "[${consoleMessage.messageLevel()}] ${consoleMessage.message()} " +
                                "@ ${consoleMessage.sourceId()}:${consoleMessage.lineNumber()}",
                        )
                        return true
                    }

                    // Chrome-like behavior: allow games to use the microphone
                    // and camera instead of silently denying them.
                    override fun onPermissionRequest(request: PermissionRequest) {
                        request.grant(request.resources)
                    }
                }

                webViewClient = object : WebViewClientCompat() {
                    override fun shouldOverrideUrlLoading(
                        view: WebView,
                        request: WebResourceRequest,
                    ): Boolean = !isAllowed(request.url)

                    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                        if (!docStart) view.evaluateJavascript(GAME_BRIDGE_JS, null)
                        view.evaluateJavascript(COMPAT_SHIM, null)
                    }

                    override fun onPageFinished(view: WebView, url: String) {
                        view.evaluateJavascript(COMPAT_SHIM, null)
                        currentOnPageFinished()
                    }

                    override fun onReceivedError(
                        view: WebView,
                        request: WebResourceRequest,
                        error: WebResourceErrorCompat,
                    ) {
                        if (request.isForMainFrame) {
                            currentOnError(error.description.toString())
                        }
                    }
                }

                val startUrl = when (currentSource) {
                    is GameSource.Local ->
                        "http://127.0.0.1:$localPort/games/${currentSource.entry}"
                    is GameSource.Remote -> currentSource.url
                }
                loadUrl(startUrl)
            }
        },
        onRelease = { webView ->
            GameKeyboard.detach(webView)
            webView.removeJavascriptInterface(GAME_BRIDGE_NATIVE)
            webView.stopLoading()
            webView.loadUrl("about:blank")
            webView.destroy()
        },
    )
}
