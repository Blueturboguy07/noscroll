package app.noscroll.publik

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.browser.customtabs.CustomTabsIntent
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * The UI of the publik gate (Publik.kt): one full-screen view that draws each Publik.Screen and
 * returns the button pressed. The sign-in page opens in a Custom Tab; when the person comes back
 * to the app, the gate checks at once.
 */
class PublikGateView(private val activity: Activity) : PublikGateUI {
    private val paper = 0xFFF7EFE0.toInt()
    private val ink = 0xFF141414.toInt()
    private val inkSoft = 0xFF6B665B.toInt() // 5.0:1 on paper

    private val spinner = ProgressBar(activity)
    /** The words under the spinner, while the gate checks the saved sign-in. */
    private val checking = text(15f, inkSoft, bold = false).apply { text = "Checking your sign-in…"; setPadding(0, dp(12), 0, 0) }
    private val title = text(30f, ink, bold = true)
    private val body = text(17f, inkSoft, bold = false).apply { setPadding(0, dp(14), 0, 0) }
    private val note = text(15f, ink, bold = true).apply { setPadding(0, dp(14), 0, 0) }
    private val buttons = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(0, dp(28), 0, 0) }
    private var pending: CancellableContinuation<String?>? = null

    /** The view to put on screen. */
    val view: View = ScrollView(activity).apply {
        isFillViewport = true
        setBackgroundColor(paper)
        addView(
            LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(28), dp(24), dp(28), dp(24))
                for (v in listOf(spinner, checking, title, body, note, buttons)) {
                    addView(v, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
                }
            },
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )
    }

    init {
        showLoading()
    }

    override suspend fun show(screen: Publik.Screen): String? = withContext(Dispatchers.Main) {
        suspendCancellableCoroutine { cont ->
            pending?.let { if (it.isActive) it.resume(null) }
            pending = cont
            render(screen) { action ->
                if (pending === cont) {
                    pending = null
                    cont.resume(action)
                }
            }
            cont.invokeOnCancellation {
                activity.runOnUiThread {
                    if (pending === cont) {
                        pending = null
                        showLoading()
                    }
                }
            }
        }
    }

    override fun open(url: String) {
        activity.runOnUiThread {
            val uri = Uri.parse(url)
            try {
                CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(activity, uri)
            } catch (e: ActivityNotFoundException) {
                try { activity.startActivity(Intent(Intent.ACTION_VIEW, uri)) } catch (x: ActivityNotFoundException) {}
            }
        }
    }

    private fun showLoading() {
        spinner.visibility = View.VISIBLE
        checking.visibility = View.VISIBLE
        for (v in listOf(title, body, note, buttons)) v.visibility = View.GONE
    }

    private fun render(screen: Publik.Screen, press: (String) -> Unit) {
        spinner.visibility = View.GONE
        checking.visibility = View.GONE
        title.text = screen.title
        body.text = screen.body
        note.text = screen.note ?: ""
        title.visibility = View.VISIBLE
        body.visibility = View.VISIBLE
        note.visibility = if (screen.note == null) View.GONE else View.VISIBLE
        buttons.removeAllViews()
        screen.buttons.forEachIndexed { index, (action, label) ->
            val primary = index == 0
            buttons.addView(
                Button(activity).apply {
                    text = label
                    isAllCaps = false
                    textSize = 18f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(if (primary) paper else inkSoft)
                    setPadding(dp(16), dp(16), dp(16), dp(16))
                    background = GradientDrawable().apply {
                        cornerRadius = dp(32).toFloat()
                        if (primary) setColor(ink) else { setColor(Color.TRANSPARENT); setStroke(dp(1), inkSoft) }
                    }
                    setOnClickListener { press(action) }
                },
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(10) },
            )
        }
        buttons.visibility = View.VISIBLE
    }

    private fun text(size: Float, color: Int, bold: Boolean) = TextView(activity).apply {
        textSize = size
        setTextColor(color)
        gravity = Gravity.CENTER_HORIZONTAL
        if (bold) setTypeface(typeface, Typeface.BOLD)
    }

    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
}
