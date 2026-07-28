package app.noscroll.shield

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * The Android enforcement layer.
 *
 * ============================ POLICY NOTE — READ FIRST ============================
 *
 * Google Play's Accessibility policy was tightened on 28 Jan 2026 to ban
 * autonomous "initiate, plan, execute actions" uses. It explicitly carves out:
 *
 *     "deterministic, rule-based automation ... a static, human-defined script
 *      (for example, 'If Trigger X occurs, perform Action Y')"
 *
 * This service is written to sit squarely inside that carve-out, and the
 * Permission Declaration Form quotes that sentence. Concretely:
 *
 *   - It READS one field: the package name of the foreground window.
 *   - It performs NO action inside any other app. There is no `performAction`,
 *     no gesture dispatch, no node traversal, no text extraction. Adding any of
 *     those would move us out of the carve-out and put the listing at risk.
 *   - Its entire decision is a static if/then: if the foreground package is in
 *     the user's own shielded set, show our own Activity.
 *
 * If you are about to add "just one" node query here, don't. Put it in the app.
 * ===================================================================================
 *
 * Prominent disclosure (docs/ANDROID_DISCLOSURE.md) is shown as a standalone
 * onboarding screen during normal usage — a privacy-policy mention does not
 * satisfy the policy.
 */
class ForegroundAppMonitor : AccessibilityService() {

    private lateinit var settings: ShieldSettings

    /** Debounce: window-state events fire in bursts during transitions. */
    private var lastShieldedPackage: String? = null
    private var lastShieldAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        settings = ShieldSettings(applicationContext)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        // The ONLY field read from the event.
        val pkg = event.packageName?.toString() ?: return

        if (pkg == packageName) {
            lastShieldedPackage = null
            return
        }
        if (!settings.isShielded(pkg)) {
            lastShieldedPackage = null
            return
        }
        if (settings.isTemporarilyUnlocked(pkg)) return

        val now = System.currentTimeMillis()
        if (pkg == lastShieldedPackage && now - lastShieldAt < DEBOUNCE_MS) return
        lastShieldedPackage = pkg
        lastShieldAt = now

        showShield(pkg)
    }

    /**
     * Launch OUR OWN activity. We do not press Back, do not dispatch a gesture,
     * and do not attempt to close the other app — all of which would be
     * "performing an action" in another app.
     */
    private fun showShield(blockedPackage: String) {
        val intent = Intent(this, ShieldActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION,
            )
            putExtra(ShieldActivity.EXTRA_PACKAGE, blockedPackage)
        }
        startActivity(intent)
    }

    override fun onInterrupt() = Unit

    companion object {
        private const val DEBOUNCE_MS = 800L
    }
}
