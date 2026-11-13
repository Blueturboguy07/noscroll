package app.noscroll

import android.annotation.SuppressLint
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.webkit.WebView
import android.widget.Button
import android.widget.FrameLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import app.noscroll.publik.Publik
import app.noscroll.publik.PublikGateView
import app.noscroll.shield.ShieldSettings
import app.noscroll.shield.StatusActivity
import app.noscroll.web.EngineInjector
import app.noscroll.web.SessionCookieJar
import app.noscroll.web.WrappedWebViewClient
import kotlinx.coroutines.launch

private fun otherService(current: String) = if (current == "instagram") "youtube" else "instagram"
private fun serviceLabel(service: String) = if (service == "youtube") "YouTube" else "Instagram"

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
 *
 * There is no five-tab shell here (Sleep / Home / Shield / You) the way there is
 * on iOS — that UI was never built for this platform; see the README note added
 * alongside this file. What exists is the minimum needed for the wrapper and the
 * shield to both actually be usable: a way to reach the other probe-verified
 * service, and a way to see and change what's shielded (StatusActivity).
 */
class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var wrappedClient: WrappedWebViewClient
    private lateinit var cookieJar: SessionCookieJar
    private lateinit var settings: ShieldSettings
    private lateinit var switchServiceButton: Button

    private var currentService = "instagram"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Sign in with publik comes first (publik/Publik.kt). NoScroll's own screen starts only
        // after the gate lets the person through.
        Publik.watchForeground(application)
        Publik.launchArguments = Publik.launchArgumentsFrom(intent?.extras)
        val gate = PublikGateView(this)
        setContentView(gate.view)
        lifecycleScope.launch {
            Publik.ensureSignedIn(this@MainActivity, gate)
            startApp()
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun startApp() {
        cookieJar = SessionCookieJar(this)
        settings = ShieldSettings(this)
        // Fresh installs must block by default (README: "the core ones —
        // Reels, Shorts, Explore, suggested posts — arrive switched on"). Not
        // calling this was the reason the shield could never appear even
        // with the accessibility permission granted: nothing was ever
        // marked as shielded. Idempotent — see the doc comment on it.
        settings.ensureDefaultsInitialized()

        wrappedClient = WrappedWebViewClient(
            onRouteChange = { /* engine handles SPA routing in-page */ },
            isMediaBlockingEnabled = { true },
        )

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            // Stock UA, unmodified: a custom user agent is a fingerprint that
            // raises the rate of "suspicious login attempt" checkpoints against
            // our users' own accounts.
            webViewClient = wrappedClient
            addJavascriptInterface(EngineInjector.Bridge(), "NoScrollAndroid")
        }

        switchServiceButton = Button(this).apply {
            setOnClickListener { switchService(otherService(currentService)) }
        }

        setContentView(
            FrameLayout(this).apply {
                addView(webView)
                addView(
                    switchServiceButton,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { gravity = Gravity.TOP or Gravity.START; topMargin = 32; leftMargin = 24 },
                )
                // Blocking failures used to be silent — no screen anywhere told
                // you whether the accessibility permission was granted or
                // whether anything was actually marked as shielded. This is
                // the way in to that answer, always reachable regardless of
                // which service is loaded.
                addView(
                    Button(this@MainActivity).apply {
                        text = getString(R.string.status_button)
                        setOnClickListener {
                            startActivity(Intent(this@MainActivity, StatusActivity::class.java))
                        }
                    },
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { gravity = Gravity.TOP or Gravity.END; topMargin = 32; rightMargin = 24 },
                )
            },
        )

        lifecycleScope.launch {
            cookieJar.switchTo(DEFAULT_ACCOUNT)
            loadService(currentService)
        }
    }

    /** User-initiated switch between the two probe-verified services. */
    private fun switchService(service: String) {
        if (service == currentService) return
        currentService = service
        loadService(service)
    }

    private fun loadService(service: String) {
        switchServiceButton.text = getString(R.string.switch_service_button, serviceLabel(otherService(service)))
        EngineInjector.install(this, webView, wrappedClient, service)
        webView.loadUrl(homeUrl(service))
    }

    private fun homeUrl(service: String) = when (service) {
        "youtube" -> "https://m.youtube.com/"
        else -> "https://www.instagram.com/"
    }

    override fun onPause() {
        super.onPause()
        if (!::cookieJar.isInitialized) return // still on Sign in with publik
        // Persist the outgoing session before anything else can touch the
        // process-global jar.
        cookieJar.currentAccountId()?.let { cookieJar.save(it) }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) webView.goBack() else super.onBackPressed()
    }

    companion object {
        private const val DEFAULT_ACCOUNT = "default"
    }
}
