package app.noscroll.web

import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.ByteArrayInputStream

/**
 * The Android content layer.
 *
 * Android has one capability iOS simply does not: `shouldInterceptRequest` lets
 * us drop a subresource at the NETWORK layer. WKWebView has no equivalent, so on
 * iOS a hidden Reel is still downloaded — it costs bandwidth and battery even
 * though the user never sees it. Here we can refuse to fetch it at all.
 *
 * This is a genuine platform asymmetry, and the reason the two shells cannot
 * share one blocking strategy even though they share the entire JS engine.
 *
 * Note what is NOT done here: we never rewrite or inspect page HTML, never
 * intercept an auth request, and never touch a request to a login or challenge
 * endpoint. Blocking is confined to media/XHR for surfaces the user has switched
 * off.
 */
class WrappedWebViewClient(
    private val onRouteChange: (String) -> Unit,
    private val isMediaBlockingEnabled: () -> Boolean,
) : WebViewClient() {

    /**
     * Paths that must never be intercepted, mirroring engine/src/authguard.ts.
     * Duplicated deliberately: this check runs before the engine exists on the
     * page, so it cannot delegate to it.
     */
    private val authPaths = listOf(
        "/accounts/", "/challenge/", "/oauth/", "/two_factor", "/emailsignup",
        "/recover/", "/signin", "/signup", "/login", "/register", "/logout",
        "/2fa", "/verify", "/ServiceLogin",
    )

    private val authHosts = listOf(
        "accounts.google.com", "appleid.apple.com", "login.microsoftonline.com",
    )

    /** Reel/Short media that the engine is hiding anyway — no point fetching it. */
    private val blockedMediaPatterns = listOf(
        Regex("""/reels?/video/"""),
        Regex("""googlevideo\.com/videoplayback.*[?&]sq=.*&shorts"""),
    )

    private val emptyResponse: WebResourceResponse
        get() = WebResourceResponse(
            "text/plain", "utf-8", 204, "No Content",
            emptyMap(), ByteArrayInputStream(ByteArray(0)),
        )

    override fun shouldInterceptRequest(
        view: WebView?,
        request: WebResourceRequest?,
    ): WebResourceResponse? {
        val url = request?.url ?: return null
        val host = url.host.orEmpty()
        val path = url.path.orEmpty()

        // THE INVARIANT, network edition. Never interfere with an auth flow.
        if (authHosts.any { host.endsWith(it) }) return null
        if (authPaths.any { path.startsWith(it, ignoreCase = true) }) return null

        if (!isMediaBlockingEnabled()) return null

        val full = url.toString()
        if (blockedMediaPatterns.any { it.containsMatchIn(full) }) {
            // 204 rather than an error: a failed request produces retry storms
            // and visible error UI; an empty success is silently ignored.
            return emptyResponse
        }
        return null
    }

    override fun shouldOverrideUrlLoading(
        view: WebView?,
        request: WebResourceRequest?,
    ): Boolean {
        val url = request?.url ?: return false
        val scheme = url.scheme?.lowercase()

        // Cancel app-scheme handoffs. The real Instagram app is shielded, so
        // following `intent://` or `instagram://` would bounce the user into a
        // shield screen mid-flow and look like the wrapper crashed.
        if (scheme != null && scheme !in setOf("http", "https", "about", "data", "blob")) {
            return true
        }
        onRouteChange(url.path.orEmpty() + (url.query?.let { "?$it" } ?: ""))
        return false
    }

    override fun onPageFinished(view: WebView?, url: String?) {
        super.onPageFinished(view, url)
        url?.let { onRouteChange(it) }
    }
}
