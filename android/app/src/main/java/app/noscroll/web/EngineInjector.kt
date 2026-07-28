package app.noscroll.web

import android.content.Context
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject

/**
 * Loads the shared JS engine and the rule bundle, and injects them at document
 * start.
 *
 * The engine bundle is byte-identical to the one iOS injects — that is the whole
 * point of the architecture. Everything platform-specific stays out here.
 *
 * Android has no `WKUserScript(injectionTime: .atDocumentStart)` equivalent, so
 * `onPageStarted` is the earliest reliable hook. It fires before the page's own
 * scripts run, which is what keeps the blocking CSS ahead of first paint.
 */
object EngineInjector {

    private const val ENGINE_ASSET = "noscroll.js"

    fun install(context: Context, webView: WebView, service: String) {
        val engine = context.assets.open(ENGINE_ASSET).bufferedReader().use { it.readText() }
        val bundle = loadBundle(context, service)

        val config = JSONObject().apply {
            put("bundle", JSONObject(bundle))
            put("settings", JSONObject())
            put("telemetry", false)
        }

        val bootstrap = """
            window.__NOSCROLL_CONFIG = $config;
            $engine
        """.trimIndent()

        val existing = webView.webViewClient
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, url, favicon)
                view?.evaluateJavascript(bootstrap, null)
            }

            override fun shouldInterceptRequest(
                view: WebView?,
                request: android.webkit.WebResourceRequest?,
            ) = (existing as? WrappedWebViewClient)?.shouldInterceptRequest(view, request)

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: android.webkit.WebResourceRequest?,
            ) = (existing as? WrappedWebViewClient)?.shouldOverrideUrlLoading(view, request) ?: false
        }
    }

    /**
     * Three-tier fallback, same as iOS: remote → cached → baked into assets, so
     * a cold first launch with no network still blocks Reels.
     */
    private fun loadBundle(context: Context, service: String): String {
        val cached = context.cacheDir.resolve("noscroll-rules/$service.json")
        if (cached.exists()) return cached.readText()
        return context.assets.open("rules/$service.json").bufferedReader().use { it.readText() }
    }

    /**
     * Receives engine messages. Carries rule ids and counts only — never a URL,
     * never page content. See docs/PRIVACY.md.
     */
    class Bridge {
        @JavascriptInterface
        fun postMessage(json: String) {
            runCatching {
                val msg = JSONObject(json)
                when (msg.optString("type")) {
                    "probe" -> RuleHealth.report(
                        msg.optString("ruleId"),
                        msg.optInt("expected"),
                        msg.optInt("actual"),
                    )
                    else -> Unit
                }
            }
        }
    }
}

/** Local-only record of which rules stopped matching. */
object RuleHealth {
    private val stale = mutableSetOf<String>()

    fun report(ruleId: String, expected: Int, actual: Int) {
        if (expected > 0 && actual == 0) stale += ruleId
    }

    fun staleRules(): Set<String> = stale.toSet()
}
