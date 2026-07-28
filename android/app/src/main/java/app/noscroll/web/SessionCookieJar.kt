package app.noscroll.web

import android.content.Context
import android.webkit.CookieManager
import androidx.core.content.edit
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Per-account cookie isolation on Android.
 *
 * This is the sharpest divergence from iOS in the whole project, and it is worth
 * understanding before touching anything here.
 *
 * On iOS 17 each account gets `WKWebsiteDataStore(forIdentifier:)` — a real,
 * persistent, isolated cookie jar. The platform does the work.
 *
 * Android's `CookieManager` is PROCESS-GLOBAL. There is no per-profile partition
 * in the system WebView. So "multiple accounts" has exactly two possible
 * implementations:
 *
 *   1. A WebView per account in an isolated process (`android:process=":acctN"`),
 *      which is heavy, or
 *   2. Serialise the cookie jar out on switch-away and restore it on switch-to,
 *      which is what this class does.
 *
 * (2) is chosen because account switching is a deliberate, infrequent user action
 * — not something that happens per navigation — and a whole extra process per
 * account is a real memory cost on the low-end devices this app should run well on.
 *
 * The invariant that makes (2) safe: `switchTo` must SAVE the outgoing account
 * before it CLEARS, and clear before it restores. Getting that order wrong leaks
 * one account's session into another, which is a security bug, not a UX one.
 */
class SessionCookieJar(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val cookies: CookieManager = CookieManager.getInstance()

    private var currentAccount: String? = null

    /** Domains whose cookies we persist per account. */
    private val domains = listOf(
        "https://www.instagram.com",
        "https://instagram.com",
        "https://m.youtube.com",
        "https://www.youtube.com",
        "https://youtube.com",
        "https://accounts.google.com",
    )

    fun currentAccountId(): String? = currentAccount

    /**
     * Switch the process-global jar to [accountId].
     *
     * Order is load-bearing: save → clear → restore. A `clear` that ran before
     * `save` would silently destroy the outgoing session; a `restore` that ran
     * before `clear` would merge two accounts' cookies together.
     */
    suspend fun switchTo(accountId: String) {
        if (currentAccount == accountId) return

        currentAccount?.let { save(it) }
        clearAll()
        restore(accountId)
        currentAccount = accountId
    }

    fun save(accountId: String) {
        val snapshot = buildMap {
            for (domain in domains) {
                val raw = cookies.getCookie(domain) ?: continue
                put(domain, raw)
            }
        }
        prefs.edit {
            for ((domain, raw) in snapshot) {
                putString(key(accountId, domain), raw)
            }
            putLong(key(accountId, SAVED_AT), System.currentTimeMillis())
        }
        cookies.flush()
    }

    private fun restore(accountId: String) {
        for (domain in domains) {
            val raw = prefs.getString(key(accountId, domain), null) ?: continue
            // getCookie returns "a=1; b=2"; setCookie takes them one at a time.
            for (pair in raw.split(';')) {
                val trimmed = pair.trim()
                if (trimmed.isEmpty()) continue
                cookies.setCookie(domain, trimmed)
            }
        }
        cookies.flush()
    }

    private suspend fun clearAll() {
        suspendCancellableCoroutine { cont ->
            cookies.removeAllCookies { cont.resumeWith(Result.success(Unit)) }
        }
        cookies.flush()
    }

    /** Signing out must actually destroy the stored jar, not merely forget it. */
    fun forget(accountId: String) {
        prefs.edit {
            for (domain in domains) remove(key(accountId, domain))
            remove(key(accountId, SAVED_AT))
        }
        if (currentAccount == accountId) currentAccount = null
    }

    fun hasStoredSession(accountId: String): Boolean =
        prefs.contains(key(accountId, SAVED_AT))

    private fun key(accountId: String, suffix: String) = "cookie.$accountId.$suffix"

    companion object {
        private const val PREFS = "noscroll.cookies"
        private const val SAVED_AT = "savedAt"
    }
}
