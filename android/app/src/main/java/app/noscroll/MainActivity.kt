package app.noscroll

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import app.noscroll.shield.ShieldSettings
import app.noscroll.web.EngineInjector
import app.noscroll.web.SessionCookieJar
import app.noscroll.web.WrappedWebViewClient
import kotlinx.coroutines.launch

/**
 * The wrapped browser host.
 *
 * Android's WebView differs from WKWebView in two ways that matter here:
 *
 *  1. There is no per-profile cookie partition, so account isolation is done by
 *     SessionCookieJar rather than by the platform. See that file.
 *  2. `shouldInterceptRequest` exists, so hidden Reel media can be refused at the
 *     network layer instead of merely hidden after download — a real capability
 *     iOS lacks.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var cookieJar: SessionCookieJar
    private lateinit var settings: ShieldSettings

    private var currentService = "instagram"

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        cookieJar = SessionCookieJar(this)
        settings = ShieldSettings(this)

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            // Stock UA, unmodified: a custom user agent is a fingerprint that
            // raises the rate of "suspicious login attempt" checkpoints against
            // our users' own accounts.
            webViewClient = WrappedWebViewClient(
                onRouteChange = { /* engine handles SPA routing in-page */ },
                isMediaBlockingEnabled = { true },
            )
            addJavascriptInterface(EngineInjector.Bridge(), "NoScrollAndroid")
        }

        setContentView(FrameLayout(this).apply { addView(webView) })

        lifecycleScope.launch {
            cookieJar.switchTo(DEFAULT_ACCOUNT)
            EngineInjector.install(this@MainActivity, webView, currentService)
            webView.loadUrl(homeUrl(currentService))
        }
    }

    private fun homeUrl(service: String) = when (service) {
        "youtube" -> "https://m.youtube.com/"
        else -> "https://www.instagram.com/"
    }

    override fun onPause() {
        super.onPause()
        // Persist the outgoing session before anything else can touch the
        // process-global jar.
        cookieJar.currentAccountId()?.let { cookieJar.save(it) }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (webView.canGoBack()) webView.goBack() else super.onBackPressed()
    }

    companion object {
        private const val DEFAULT_ACCOUNT = "default"
    }
}
