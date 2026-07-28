package app.noscroll.shield

import android.content.Context
import androidx.core.content.edit

/**
 * The user's shield configuration, plus the Post Mode unlock budget.
 *
 * Mirrors ShieldController.swift so the two platforms behave identically. Where
 * they must differ (foreground detection, cookie partitioning) that is called
 * out at the site; everything here is deliberately the same on both.
 */
class ShieldSettings(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ---------------------------------------------------------------- shielding

    fun shieldedPackages(): Set<String> =
        prefs.getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()

    fun isShielded(pkg: String): Boolean = pkg in shieldedPackages()

    fun setShielded(packages: Set<String>) {
        prefs.edit { putStringSet(KEY_PACKAGES, packages) }
    }

    // --------------------------------------------------------------- post mode

    /**
     * Post Mode: temporarily unshield so the user can post in the real app —
     * the only correct answer to "you cannot post a Reel from the web".
     *
     * Three properties SocialLite's version lacks:
     *   - a per-day budget, so repeated 10-minute unlocks are not simply
     *     unlimited access with extra steps;
     *   - a grace extension while an upload is genuinely in flight;
     *   - a near-expiry warning.
     */
    fun isTemporarilyUnlocked(pkg: String, now: Long = System.currentTimeMillis()): Boolean {
        val until = prefs.getLong(keyUnlockUntil(pkg), 0L)
        if (until <= 0L) return false
        if (now < until) return true
        if (isUploadInProgress() && now < until + GRACE_MS) return true
        return false
    }

    fun beginPostMode(
        pkg: String,
        durationMs: Long = DEFAULT_POST_MODE_MS,
        now: Long = System.currentTimeMillis(),
    ): Boolean {
        if (unlocksToday(now) >= MAX_UNLOCKS_PER_DAY) return false
        recordUnlock(now)
        prefs.edit { putLong(keyUnlockUntil(pkg), now + durationMs) }
        return true
    }

    fun endPostMode(pkg: String) {
        prefs.edit { remove(keyUnlockUntil(pkg)) }
    }

    fun setUploadInProgress(inProgress: Boolean) {
        prefs.edit { putBoolean(KEY_UPLOADING, inProgress) }
    }

    fun isUploadInProgress(): Boolean = prefs.getBoolean(KEY_UPLOADING, false)

    fun unlocksRemainingToday(now: Long = System.currentTimeMillis()): Int =
        (MAX_UNLOCKS_PER_DAY - unlocksToday(now)).coerceAtLeast(0)

    private fun unlocksToday(now: Long): Int {
        val day = dayStamp(now)
        return if (prefs.getString(KEY_UNLOCK_DAY, null) == day) {
            prefs.getInt(KEY_UNLOCK_COUNT, 0)
        } else {
            0
        }
    }

    private fun recordUnlock(now: Long) {
        val day = dayStamp(now)
        val current = unlocksToday(now)
        prefs.edit {
            putString(KEY_UNLOCK_DAY, day)
            putInt(KEY_UNLOCK_COUNT, current + 1)
        }
    }

    private fun dayStamp(now: Long): String {
        val cal = java.util.Calendar.getInstance()
        cal.timeInMillis = now
        return "%04d-%02d-%02d".format(
            cal.get(java.util.Calendar.YEAR),
            cal.get(java.util.Calendar.MONTH) + 1,
            cal.get(java.util.Calendar.DAY_OF_MONTH),
        )
    }

    private fun keyUnlockUntil(pkg: String) = "unlock.until.$pkg"

    companion object {
        const val MAX_UNLOCKS_PER_DAY = 4
        const val DEFAULT_POST_MODE_MS = 10 * 60 * 1000L
        const val GRACE_MS = 2 * 60 * 1000L

        private const val PREFS = "noscroll.shield"
        private const val KEY_PACKAGES = "shielded.packages"
        private const val KEY_UNLOCK_DAY = "unlock.day"
        private const val KEY_UNLOCK_COUNT = "unlock.count"
        private const val KEY_UPLOADING = "postmode.uploading"

        /** The apps this product exists to shield. */
        val DEFAULT_TARGETS = setOf(
            "com.instagram.android",
            "com.google.android.youtube",
        )
    }
}
