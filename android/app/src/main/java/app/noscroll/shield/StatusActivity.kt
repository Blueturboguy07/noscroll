package app.noscroll.shield

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.CompoundButton
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.browser.customtabs.CustomTabsIntent
import app.noscroll.MainActivity
import app.noscroll.R
import app.noscroll.publik.Publik
import app.noscroll.publik.PublikSignInActivity
import app.noscroll.web.RuleHealth
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * The diagnostic screen this app did not have.
 *
 * "Blocking doesn't work" reports had no way to tell a user *why*: whether the
 * accessibility permission was never granted, or — the bug this screen was
 * built alongside — whether nothing was ever marked as shielded in the first
 * place (see the comment on [ShieldSettings.ensureDefaultsInitialized]).
 * Either way the previous behaviour was silence: the shield simply never
 * appeared, with no signal anywhere in the app that anything was wrong.
 *
 * This screen states the one fact that actually determines whether blocking
 * can run — is the accessibility service on — loudly, with a direct button
 * into the system settings screen that turns it on, plus the current shield
 * list so "nothing is blocked" and "I never actually turned anything on" are
 * distinguishable at a glance.
 *
 * It is also the app's settings screen for publik: "Sign in with publik" (optional gate mode),
 * "Sign out", "Count app use" and "Delete account".
 */
class StatusActivity : Activity() {

    private lateinit var settings: ShieldSettings
    private lateinit var bannerText: TextView
    private lateinit var bannerDetail: TextView
    private lateinit var openSettingsButton: Button
    private lateinit var ruleWarning: TextView
    private lateinit var publikStatus: TextView
    private lateinit var signInButton: Button
    private lateinit var signOutButton: Button
    private val scope = MainScope()
    /** Delete account opened publik's page; when the person comes back, the device is signed out. */
    private var deletePending = false
    private val appName by lazy { getString(R.string.app_name) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        settings = ShieldSettings(this)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 64, 48, 64)
        }

        root.addView(TextView(this).apply {
            text = getString(R.string.status_title)
            textSize = 22f
            setTypeface(typeface, Typeface.BOLD)
        })

        bannerText = TextView(this).apply {
            textSize = 17f
            setPadding(0, 32, 0, 8)
        }
        root.addView(bannerText)

        bannerDetail = TextView(this).apply {
            textSize = 14f
            setPadding(0, 0, 0, 24)
        }
        root.addView(bannerDetail)

        openSettingsButton = Button(this).apply {
            text = getString(R.string.status_open_settings)
            setOnClickListener {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }
        }
        root.addView(openSettingsButton)

        root.addView(TextView(this).apply {
            text = getString(R.string.status_shielded_apps)
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, 48, 0, 16)
        })

        root.addView(serviceRow("com.instagram.android", getString(R.string.status_service_instagram)))
        root.addView(serviceRow("com.google.android.youtube", getString(R.string.status_service_youtube)))

        ruleWarning = TextView(this).apply {
            textSize = 13f
            setPadding(0, 32, 0, 0)
            visibility = android.view.View.GONE
        }
        root.addView(ruleWarning)

        addPublikRows(root)

        setContentView(ScrollView(this).apply { addView(root) })
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun addPublikRows(root: LinearLayout) {
        root.addView(TextView(this).apply {
            text = "publik account"
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, 48, 0, 16)
        })
        publikStatus = TextView(this).apply { textSize = 16f; setPadding(0, 0, 0, 12) }
        root.addView(publikStatus)
        signInButton = Button(this).apply {
            text = "Sign in with publik"
            setOnClickListener { startActivity(Intent(this@StatusActivity, PublikSignInActivity::class.java)) }
        }
        root.addView(signInButton)
        signOutButton = Button(this).apply {
            text = "Sign out"
            setOnClickListener { confirmSignOut() }
        }
        root.addView(signOutButton)
        root.addView(Switch(this).apply {
            text = "Count app use"
            textSize = 16f
            setPadding(0, 12, 0, 12)
            isChecked = Publik.usageConsent(this@StatusActivity)
            setOnCheckedChangeListener { _: CompoundButton, checked: Boolean -> Publik.setUsageConsent(this@StatusActivity, checked) }
        })
        root.addView(TextView(this).apply {
            textSize = 13f
            text = "When you are signed in, $appName tells publik when it opens and each 30 minutes that it stays open, so publik can count app use. It sends nothing about what you look at. Turn off Count app use to stop this."
            setPadding(0, 4, 0, 16)
        })
        root.addView(Button(this).apply {
            text = "Delete account"
            setOnClickListener { confirmDelete() }
        })
    }

    private fun refreshPublik() {
        publikStatus.text = "Checking publik…"
        signInButton.visibility = View.GONE
        signOutButton.visibility = View.GONE
        scope.launch {
            val c = Publik.readCredential(this@StatusActivity)
            val w = c?.let {
                try { Publik.readWallet(it.key).second } catch (e: CancellationException) { throw e } catch (e: Exception) { null }
            }
            val signedIn = w?.claimed == true
            publikStatus.text = when {
                signedIn -> "Signed in as " + (w?.handle?.let { "@$it" } ?: "publik")
                c != null && w == null -> "publik is not reachable."
                else -> "Not signed in."
            }
            signOutButton.visibility = if (c != null && (signedIn || w == null)) View.VISIBLE else View.GONE
            signInButton.visibility = if (!signedIn && Publik.GATE_OPTIONAL) View.VISIBLE else View.GONE
        }
    }

    private fun confirmSignOut() {
        AlertDialog.Builder(this)
            .setTitle("Sign out of publik?")
            .setMessage(
                if (Publik.GATE_OPTIONAL) "The app stops telling publik about app use until you sign in again."
                else "$appName asks you to sign in with publik again before you can use it.",
            )
            // Publik.signOut deletes the key file at once and revokes the key in an app-wide scope (not this screen's).
            .setPositiveButton("Sign out") { _, _ -> Publik.signOut(this@StatusActivity); afterSignOut() }
            .setNegativeButton("Cancel", null)
            .show()
    }

    /** Delete account, step 1: say what is deleted. Step 2: delete the local publik data. Step 3: publik's page. */
    private fun confirmDelete() {
        AlertDialog.Builder(this)
            .setTitle("Delete your publik account?")
            .setMessage(
                "This deletes your publik account for all publik apps, not only for $appName. First, $appName signs you out " +
                    "and deletes its publik data on this device. Then the publik page opens. Confirm the deletion on that page.",
            )
            .setPositiveButton("Delete account") { _, _ ->
                Publik.deleteLocalData(this@StatusActivity)
                deletePending = true
                val url = Uri.parse(Publik.deleteAccountUrl)
                try {
                    CustomTabsIntent.Builder().build().launchUrl(this@StatusActivity, url)
                } catch (e: ActivityNotFoundException) {
                    try { startActivity(Intent(Intent.ACTION_VIEW, url)) } catch (e2: ActivityNotFoundException) { deletePending = false; afterSignOut() }
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    /** Required mode: back to Sign in with publik (a fresh MainActivity). Optional mode: stay here. */
    private fun afterSignOut() {
        if (Publik.GATE_OPTIONAL) { refreshPublik(); return }
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        finish()
    }

    override fun onResume() {
        super.onResume()
        if (deletePending) { deletePending = false; afterSignOut(); return }
        // Accessibility permission is granted in a separate system screen, so
        // it must be re-checked every time this screen becomes visible again
        // rather than once in onCreate.
        refresh()
        refreshPublik()
    }

    private fun refresh() {
        val enabled = AccessibilityStatus.isForegroundMonitorEnabled(this)
        if (enabled) {
            bannerText.text = getString(R.string.status_enabled)
            bannerText.setTextColor(0xFF1B8A3F.toInt())
            bannerDetail.text = ""
            openSettingsButton.visibility = android.view.View.GONE
        } else {
            bannerText.text = getString(R.string.status_disabled)
            bannerText.setTextColor(0xFFB3261E.toInt())
            bannerDetail.text = getString(R.string.status_disabled_detail)
            openSettingsButton.visibility = android.view.View.VISIBLE
        }

        val stale = RuleHealth.staleRules()
        if (stale.isEmpty()) {
            ruleWarning.visibility = android.view.View.GONE
        } else {
            ruleWarning.visibility = android.view.View.VISIBLE
            ruleWarning.text = getString(R.string.status_rule_warning, stale.joinToString(", "))
        }
    }

    private fun serviceRow(pkg: String, label: String): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 12, 0, 12)
        }
        row.addView(
            TextView(this).apply { text = label; textSize = 16f },
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        row.addView(Switch(this).apply {
            isChecked = settings.isShielded(pkg)
            setOnCheckedChangeListener { _: CompoundButton, checked: Boolean ->
                val current = settings.shieldedPackages().toMutableSet()
                if (checked) current += pkg else current -= pkg
                settings.setShielded(current)
            }
        })
        return row
    }
}
