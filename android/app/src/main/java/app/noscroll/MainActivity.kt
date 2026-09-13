package app.noscroll

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.webkit.WebView
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
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
    private lateinit var statusButton: Button
    private lateinit var toggleControlsButton: Button
    private var controlsVisible = false

    private var currentService = "instagram"

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

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

        switchServiceButton = pillButton().apply {
            setOnClickListener { switchService(otherService(currentService)) }
        }

        // Blocking failures used to be silent — no screen anywhere told
        // you whether the accessibility permission was granted or
        // whether anything was actually marked as shielded. This is
        // the way in to that answer, always reachable regardless of
        // which service is loaded.
        statusButton = pillButton().apply {
            text = getString(R.string.status_button)
            setOnClickListener {
                startActivity(Intent(this@MainActivity, StatusActivity::class.java))
            }
        }

        // A small round handle docked to the middle of the right edge — the one
        // spot on both Instagram and YouTube's mobile layouts with no real nav
        // chrome (their own controls live in the top bar and bottom tab strip).
        // Earlier top-corner placement sat directly on top of YouTube's search
        // icon and Instagram's follow button — this fixes that, not just the look.
        toggleControlsButton = Button(this).apply {
            isAllCaps = false
            setTextColor(Color.WHITE)
            textSize = 16f
            minWidth = 0
            minHeight = 0
            stateListAnimator = null
            setPadding(0, 0, 0, 0)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(PANEL_FILL)
                setStroke(dp(1), PANEL_STROKE)
            }
            setOnClickListener { setControlsVisible(!controlsVisible) }
        }

        val controlsPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.END
            addView(
                switchServiceButton,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { bottomMargin = dp(8) },
            )
            addView(
                statusButton,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { bottomMargin = dp(8) },
            )
            addView(toggleControlsButton, LinearLayout.LayoutParams(dp(40), dp(40)))
        }

        setContentView(
            FrameLayout(this).apply {
                addView(webView)
                addView(
                    controlsPanel,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { gravity = Gravity.END or Gravity.CENTER_VERTICAL; rightMargin = dp(12) },
                )
            },
        )
        setControlsVisible(false)

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

    private fun setControlsVisible(visible: Boolean) {
        controlsVisible = visible
        switchServiceButton.visibility = if (visible) View.VISIBLE else View.GONE
        statusButton.visibility = if (visible) View.VISIBLE else View.GONE
        // Panel is right-edge-docked: '‹' points inward (tap to reveal), '›'
        // points to the edge (tap to tuck away).
        toggleControlsButton.text = getString(
            if (visible) R.string.hide_controls_button else R.string.show_controls_button,
        )
    }

    /** Flat, semi-transparent dark pill — no AppCompat button chrome (caps, shadow, tint). */
    private fun pillButton(): Button = Button(this).apply {
        isAllCaps = false
        setTextColor(Color.WHITE)
        textSize = 13f
        minWidth = 0
        minHeight = 0
        stateListAnimator = null
        setPadding(dp(16), dp(8), dp(16), dp(8))
        background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(18).toFloat()
            setColor(PANEL_FILL)
            setStroke(dp(1), PANEL_STROKE)
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

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

        // Dark glass, not flat Material chrome — reads as an overlay you summon,
        // not another app screen fighting the page underneath for attention.
        private const val PANEL_FILL = 0xCC1B1B1F.toInt()
        private const val PANEL_STROKE = 0x33FFFFFF
    }
}
