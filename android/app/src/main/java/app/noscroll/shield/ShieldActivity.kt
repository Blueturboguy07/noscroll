package app.noscroll.shield

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import app.noscroll.MainActivity
import app.noscroll.R

/**
 * The Android shield screen — the twin of ShieldConfigurationExtension.swift.
 *
 * Same two deliberate choices as iOS:
 *   1. The primary button leads INTO NoScroll rather than merely dismissing. A
 *      shield that only says "no" trains people to fight it; one that offers the
 *      calm version of the same thing redirects the impulse.
 *   2. No shame, no streak-loss language, no counters. The complaints against
 *      the app we are cloning cluster around feeling manipulated, and
 *      judgemental copy here is what earns that.
 *
 * Built in code rather than XML so the shield has no theme-inflation dependency
 * and can be shown instantly from the accessibility service.
 */
class ShieldActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val blocked = intent.getStringExtra(EXTRA_PACKAGE)
        val appName = friendlyName(blocked)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xF2000000.toInt())
            setPadding(64, 64, 64, 64)
        }

        root.addView(TextView(this).apply {
            text = getString(R.string.shield_title, appName)
            textSize = 24f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
        })

        root.addView(TextView(this).apply {
            text = getString(R.string.shield_subtitle)
            textSize = 15f
            setTextColor(0xB3FFFFFF.toInt())
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 40)
        })

        root.addView(Button(this).apply {
            text = getString(R.string.shield_primary)
            setOnClickListener {
                startActivity(
                    Intent(this@ShieldActivity, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                )
                finish()
            }
        }, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)

        root.addView(Button(this).apply {
            text = getString(R.string.shield_secondary)
            setOnClickListener {
                // Send the user home. We deliberately do NOT press Back inside
                // the other app — see the policy note in ForegroundAppMonitor.
                startActivity(
                    Intent(Intent.ACTION_MAIN)
                        .addCategory(Intent.CATEGORY_HOME)
                        .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                finish()
            }
        }, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)

        setContentView(root)
    }

    /** Back must not simply return to the shielded app. */
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        finish()
    }

    private fun friendlyName(pkg: String?): String = when (pkg) {
        "com.instagram.android" -> "Instagram"
        "com.google.android.youtube" -> "YouTube"
        else -> "This app"
    }

    companion object {
        const val EXTRA_PACKAGE = "app.noscroll.blockedPackage"
    }
}
