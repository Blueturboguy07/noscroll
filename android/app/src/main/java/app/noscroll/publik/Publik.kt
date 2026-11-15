// Publik.kt — Sign in with publik, usage counting, and publik API as one provider option.
// The publik module for Android: a Kotlin port of https://publikhq.com/sdk/publik.swift.md, with the
// same gate words, endpoints and rules. Gate mode (PUBLIK_GATE_MODE, BuildConfig.PUBLIK_GATE_MODE):
//   required (default): at start-up, before any screen of the app's own: `val gate = Publik.ensureSignedIn(context, ui)`;
//   optional: the app opens without the gate; the Status screen has "Sign in with publik" (PublikSignInActivity),
//             and at start-up `Publik.resume(context)` starts usage counting only for a device that is signed in.
// ensureSignedIn(context, ui):
//   1. loads or provisions this device's publik key (POST /api/v1/installs);
//   2. shows Sign in with publik until GET /api/v1/wallet says "claimed" (required mode: no other way past it);
//   3. when USES_AI: asks once how the app pays for AI and stores the answer (setChoice changes it);
//   4. starts usage counting: app_opened now, active_session every 30 minutes (POST /api/v1/telemetry).
package app.noscroll.publik

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import app.noscroll.BuildConfig
import app.noscroll.R
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Collections
import java.util.Locale
import java.util.UUID
import java.util.WeakHashMap
import kotlin.system.exitProcess
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** show(): draw the screen and return the button pressed. When the gate cancels the call (its poll saw the sign-in), close the screen. */
interface PublikGateUI {
    suspend fun show(screen: Publik.Screen): String?
    fun open(url: String)
}

object Publik {
    const val APP_SLUG = "noscroll"
    /** The release version: versionName in app/build.gradle.kts. */
    val APP_VERSION: String = BuildConfig.VERSION_NAME
    /** false: the app calls no model. It still signs in and counts users; it skips the plan screen. */
    const val USES_AI = false
    /** PUBLIK_GATE_MODE = optional: the app opens without Sign in with publik; it is on the Status screen. */
    val GATE_OPTIONAL: Boolean = BuildConfig.PUBLIK_GATE_MODE == "optional"
    /** True once the person is signed in in this process: a recreated MainActivity does not show the gate again. Sign out clears it. */
    @Volatile var signedInThisProcess = false
        private set
    /** Revoke calls run here: an app-wide scope that no screen can cancel. */
    private val backgroundScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    /** Delete account, step 3: publik's bare in-app delete page (no site navigation, prices or plan links). */
    val deleteAccountUrl: String get() = "$origin/in-app/delete-account"
    /** The privacy policy: publik's bare in-app page. */
    val privacyUrl: String get() = "$origin/in-app/privacy"

    /**
     * Sign in: the claim_url from publik with `in_app=1` added. The other query items stay byte for byte; an old
     * `in_app` item is replaced. publik redirects it to /in-app/claim/<code>, a bare page with no site links.
     * null when the value is not an http(s) URL with a host.
     */
    fun inAppClaimUrl(claimUrl: String): String? {
        val url = claimUrl.trim()
        val rest = when {
            url.startsWith("https://", ignoreCase = true) -> url.substring(8)
            url.startsWith("http://", ignoreCase = true) -> url.substring(7)
            else -> return null
        }
        if (rest.takeWhile { it != '/' && it != '?' && it != '#' }.isEmpty()) return null
        val hashAt = url.indexOf('#')
        val fragment = if (hashAt >= 0) url.substring(hashAt) else ""
        val beforeHash = if (hashAt >= 0) url.substring(0, hashAt) else url
        val q = beforeHash.indexOf('?')
        val path = if (q >= 0) beforeHash.substring(0, q) else beforeHash
        val items = (if (q >= 0) beforeHash.substring(q + 1) else "").split('&')
            .filter { it.isNotEmpty() && it != "in_app" && !it.startsWith("in_app=") }
        return path + "?" + (items + "in_app=1").joinToString("&") + fragment
    }
    const val TAG = "publik"
    /** Ask for a tier, never a vendor model name. */
    val MODELS = mapOf("fast" to "publik-fast", "balanced" to "publik-balanced", "smart" to "publik-smart")

    data class Credential(val key: String, val baseUrl: String, val installId: String, val claimUrl: String?, val choice: String?)
    data class Wallet(val claimed: Boolean, val claimUrl: String?, val handle: String?, val planKind: String, val planLabel: String?, val balanceMicros: Long, val topUpUrl: String)
    /** buttons: (action, label). */
    data class Screen(val id: String, val title: String, val body: String, val note: String?, val buttons: List<Pair<String, String>>)
    data class Gate(val key: String, val wallet: Wallet, val choice: String?)
    sealed class Provider {
        data class Own(val baseUrl: String, val apiKey: String) : Provider()
        data class PublikApi(val baseUrl: String, val apiKey: String) : Provider()
        object NeedsOwnKey : Provider()
    }
    class PublikException(message: String) : Exception(message)

    // ---------- launch arguments, the test hook and the foreground ----------

    /**
     * The launch's intent extras whose names start with PUBLIK_, for example
     * `adb shell am start -n app.noscroll/.MainActivity --es PUBLIK_SELF_TEST 1`. The environment comes first.
     * DEBUG builds only: in a release build any other app can send extras, so they are never read.
     */
    @Volatile var launchArguments: Map<String, String> = emptyMap()

    fun launchArgumentsFrom(extras: Bundle?): Map<String, String> = try {
        hookArguments(extras?.keySet().orEmpty().associateWith { extras?.getString(it) }, BuildConfig.DEBUG)
    } catch (e: RuntimeException) {
        emptyMap()
    }

    /** The PUBLIK_ extras with a value; none at all when [debug] is false (a release build). */
    internal fun hookArguments(extras: Map<String, String?>, debug: Boolean): Map<String, String> =
        if (!debug) emptyMap()
        else extras.mapNotNull { (k, v) -> if (k.startsWith("PUBLIK_") && !v.isNullOrEmpty()) k to v else null }.toMap()

    private fun env(name: String): String? = System.getenv(name)?.takeIf { it.isNotEmpty() }
    private fun setting(name: String): String? =
        env(name) ?: if (BuildConfig.DEBUG) launchArguments[name]?.takeIf { it.isNotEmpty() } else null

    /**
     * The test hook of the blind test: PUBLIK_API_BASE_URL, for example http://10.0.2.2:8787/api/v1.
     * The launch argument counts in a debug build only; a release build always talks to publik.
     */
    val testBaseUrl: String?
        get() = (env("PUBLIK_API_BASE_URL") ?: if (BuildConfig.DEBUG) launchArguments["PUBLIK_API_BASE_URL"] else null)
            ?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() }
    val origin: String get() = testBaseUrl?.removeSuffix("/api/v1") ?: env("PUBLIK_ORIGIN") ?: "https://publikhq.com" // PUBLIK_ORIGIN: tests only
    val defaultBaseUrl: String get() = "$origin/api/v1"

    /** False while no activity of the app is on screen: the sign-in poll and active_session wait for the foreground. */
    val foreground = MutableStateFlow(true)
    @Volatile private var watching = false

    /** Follows the foreground (the app's started activities). Call it once, from the first activity's onCreate. */
    fun watchForeground(app: Application) {
        if (watching) return
        watching = true
        appName = app.getString(R.string.app_name_full).ifBlank { appName }
        val started = Collections.newSetFromMap(WeakHashMap<Activity, Boolean>())
        app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) { started.add(activity); foreground.value = true }
            override fun onActivityStopped(activity: Activity) { started.remove(activity); foreground.value = started.isNotEmpty() }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    // ---------- the key ----------

    /** PUBLIK_APP_TOKEN, else the token the build put in BuildConfig (app/build.gradle.kts). */
    val appToken: String get() = env("PUBLIK_APP_TOKEN")?.trim() ?: BuildConfig.PUBLIK_APP_TOKEN.trim()
    private val arch: String? by lazy {
        when (Build.SUPPORTED_ABIS?.firstOrNull()) {
            "arm64-v8a" -> "arm64"
            "x86_64" -> "x64"
            else -> null
        }
    }

    /** <app files>/publik: private to this app. */
    fun publikDir(context: Context) = File(context.filesDir, "publik")
    fun credentialFile(context: Context) = File(publikDir(context), "apps/$APP_SLUG.json")

    fun readCredential(context: Context): Credential? = try {
        val o = JSONObject(credentialFile(context).readText())
        val key = o.str("key")
        if (key == null || !key.startsWith("pk_")) null
        else Credential(key, o.str("base_url") ?: defaultBaseUrl, o.str("install_id") ?: "", o.str("claim_url"), o.str("choice"))
    } catch (e: Exception) {
        null
    }

    private fun write(context: Context, c: Credential?) {
        val file = credentialFile(context)
        file.parentFile?.mkdirs()
        val text = if (c == null) "{}" else JSONObject().apply {
            put("key", c.key); put("base_url", c.baseUrl); put("install_id", c.installId)
            c.claimUrl?.let { put("claim_url", it) }
            c.choice?.let { put("choice", it) }
        }.toString()
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(text)
        tmp.setReadable(false, false); tmp.setReadable(true, true); tmp.setWritable(false, false); tmp.setWritable(true, true) // mode 0600
        if (!tmp.renameTo(file)) { file.writeText(text); tmp.delete() }
    }

    /** The person's answer to the plan screen: "publik", "own_key", or null to ask again. Settings call it. */
    fun setChoice(context: Context, choice: String?) {
        try { readCredential(context)?.let { write(context, it.copy(choice = choice)) } } catch (e: Exception) {}
    }

    /** The key this app uses: the stored choice decides. PUBLIK_API_KEY / PUBLIK_API_BASE_URL override (development). */
    fun resolveProvider(context: Context, userKey: Pair<String, String>?): Provider {
        env("PUBLIK_API_KEY")?.let { return Provider.PublikApi(defaultBaseUrl, it) }
        readCredential(context)?.takeIf { it.choice == "publik" }?.let { return Provider.PublikApi(it.baseUrl, it.key) }
        if (userKey != null && userKey.second.isNotEmpty()) return Provider.Own(userKey.first, userKey.second)
        return Provider.NeedsOwnKey
    }

    private suspend fun request(method: String, url: String, body: JSONObject? = null, key: String? = null, timeoutMs: Int = 20_000): Pair<Int, JSONObject> =
        withContext(Dispatchers.IO) {
            val conn = URL(url).openConnection() as HttpURLConnection
            try {
                conn.requestMethod = method
                conn.connectTimeout = timeoutMs
                conn.readTimeout = timeoutMs
                conn.setRequestProperty("content-type", "application/json")
                if (key != null) conn.setRequestProperty("Authorization", "Bearer $key")
                if (body != null) {
                    conn.doOutput = true
                    conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                } else if (method == "POST") { // an empty body (POST /installs/revoke)
                    conn.doOutput = true
                    conn.setFixedLengthStreamingMode(0)
                    conn.outputStream.close()
                }
                val status = conn.responseCode
                val text = (if (status >= 400) conn.errorStream else conn.inputStream)?.bufferedReader()?.use { it.readText() } ?: ""
                status to (try { JSONObject(text) } catch (e: Exception) { JSONObject() })
            } finally {
                conn.disconnect()
            }
        }

    /** POST /api/v1/installs: this device's publik key. Throws a readable message (IOException when publik is not reachable). */
    suspend fun provision(context: Context): Credential {
        val token = appToken
        if (!token.startsWith("pat_")) throw PublikException("This build has no publik app token. Ask the developer for a new build.")
        val prior = readCredential(context)
        var installId = prior?.installId?.takeIf { it.isNotEmpty() } ?: UUID.randomUUID().toString()
        val deviceName = (try { Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) } catch (e: Exception) { null }) ?: Build.MODEL ?: "Android"
        for (attempt in 0 until 2) {
            val fields = JSONObject().apply {
                put("app_token", token); put("app_slug", APP_SLUG); put("app_version", APP_VERSION); put("os", "android"); put("install_id", installId)
                put("device_name", deviceName.take(120)); put("disclosure_version", 1); put("dialects", JSONArray(listOf("chat_completions")))
                arch?.let { put("arch", it) }
            }
            val (status, body) = request("POST", "$origin/api/v1/installs", fields)
            val error = body.optJSONObject("error")
            val key = body.str("key") ?: if (status == 200) prior?.key else null
            if ((status == 200 || status == 201) && key != null) {
                val c = Credential(key, body.str("base_url") ?: defaultBaseUrl, body.str("install_id") ?: installId, body.str("claim_url"), prior?.choice)
                write(context, c) // the key reaches disk before anything else sees it
                return c
            }
            if (status == 200 || error?.str("type") == "install_revoked") { installId = UUID.randomUUID().toString(); continue }
            throw PublikException(error?.str("message") ?: "publik could not set up this device ($status).")
        }
        throw PublikException("publik could not set up this device.")
    }

    /** GET /api/v1/wallet: (status, wallet or null, message). Throws when publik is not reachable. */
    suspend fun readWallet(key: String, timeoutMs: Int = 15_000): Triple<Int, Wallet?, String?> {
        val (status, b) = request("GET", "$origin/api/v1/wallet", key = key, timeoutMs = timeoutMs)
        val state = b.str("claim_state")
        if (status != 200 || state == null) return Triple(status, null, b.optJSONObject("error")?.str("message"))
        val plan = b.optJSONObject("plan")
        return Triple(
            status,
            Wallet(
                claimed = state == "claimed", claimUrl = b.str("claim_url"), handle = b.optJSONObject("account")?.str("handle"),
                planKind = plan?.str("kind") ?: "none", planLabel = plan?.str("label"), balanceMicros = (b.opt("balance_micros") as? Number)?.toLong() ?: 0L,
                topUpUrl = b.str("top_up_url") ?: "$origin/wallet",
            ),
            null,
        )
    }

    /** The app's name in the gate's words (the app label; set by watchForeground). */
    @Volatile var appName: String = "This app"

    /** The words of the gate. The same in every publik module, in the words for a phone: "Tap", "screen", "the publik page". */
    fun gateScreen(id: String, w: Wallet? = null, note: String? = null, message: String? = null): Screen {
        if (id == "unreachable") return Screen(id, "Sign in with publik", message ?: "publik is not reachable. Check your connection.", note, listOf("retry" to "Retry"))
        if (id == "sign_in") {
            return Screen(id, "Sign in with publik", "$appName uses your publik account. Tap Sign in with publik and sign in on the publik page. Then come back here. $appName opens by itself.",
                note, listOf("sign_in" to "Sign in with publik"))
        }
        val who = w?.handle?.let { "You are signed in as @$it." } ?: "You are signed in to publik."
        if (w == null || (w.planKind == "none" && w.balanceMicros <= 0)) {
            return Screen(id, "Choose how to pay for AI", "$who This app uses AI. Get a publik plan, or use your own key.", note,
                listOf("get_plan" to "Get a plan", "own_key" to "Use my own key"))
        }
        val what = if (w.planKind == "plan") "Your plan: ${w.planLabel ?: "publik"}." else String.format(Locale.US, "Your balance: \$%.2f.", w.balanceMicros / 1_000_000.0)
        return Screen(id, "Connect your plan", "$who $what Connect it to use AI in this app, or use your own key.", note,
            listOf("connect" to "Connect your plan", "own_key" to "Use my own key"))
    }

    /**
     * Show a screen; with `until`, poll GET /wallet every 3 s for 10 minutes (PublikPoll). "done": the poll saw it; "timeout": it did not.
     * The checks are on a fixed 3 s grid and each runs on its own, so a slow request never moves the next check, and the
     * interval never grows. The poll checks only while the app is in the foreground; when the app comes back, it checks at once.
     */
    private suspend fun ask(ui: PublikGateUI, screen: Screen, key: String = "", until: ((Wallet) -> Boolean)? = null): String = coroutineScope {
        val answers = Channel<String?>(Channel.UNLIMITED)
        val jobs = mutableListOf<Job>()
        jobs += launch { answers.send(ui.show(screen)) }
        if (until != null) {
            jobs += launch {
                val seen = PublikPoll.run(intervalMs = 3_000, durationMs = 600_000, foreground = foreground) {
                    val w = readWallet(key, timeoutMs = 8_000).second
                    w != null && until(w)
                }
                answers.send(if (seen) "done" else "timeout")
            }
        }
        var answer = "retry"
        var waiting = jobs.size
        while (waiting > 0) {
            val result = answers.receive()
            waiting--
            if (result != null) { answer = result; break }
        }
        jobs.forEach { it.cancel() }
        answer
    }

    /** The gate (see the top of the file). Returns once the person is signed in; `choice` is null when USES_AI is false. */
    suspend fun ensureSignedIn(context: Context, ui: PublikGateUI): Gate {
        val app = context.applicationContext
        selfTestIfAsked(app)
        var signNote: String? = null
        var signPoll = true
        var planNote: String? = null
        var planPoll = false
        val signedIn: (Wallet) -> Boolean = { it.claimed }
        val hasPlan: (Wallet) -> Boolean = { it.planKind != "none" || it.balanceMicros > 0 }
        while (true) {
            val envKey = env("PUBLIK_API_KEY")
            val (c, read) = try {
                val cred = envKey?.let { Credential(it, defaultBaseUrl, "", null, null) } ?: readCredential(app) ?: provision(app)
                cred to readWallet(cred.key)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                ask(ui, gateScreen("unreachable", message = if (e is IOException) null else e.message))
                continue
            }
            val (status, wallet, message) = read
            if (status == 401 && envKey == null) { try { write(app, null) } catch (e: Exception) {}; continue } // a revoked key: provision again
            if (wallet == null) { ask(ui, gateScreen("unreachable", message = message)); continue }
            val w: Wallet = wallet
            if (!w.claimed) {
                val a = ask(ui, gateScreen("sign_in", w, note = signNote), key = c.key, until = if (signPoll) signedIn else null)
                if (a == "sign_in") {
                    // Only publik's bare in-app sign-in page; never a page with site links, prices or plans.
                    val claim = (w.claimUrl ?: c.claimUrl)?.let { inAppClaimUrl(it) }
                    if (claim != null) {
                        ui.open(claim)
                        signNote = "Waiting for you to sign in on the publik page."
                        signPoll = true
                    } else {
                        signNote = "publik sent no sign-in page. Tap Sign in with publik to try again."
                    }
                }
                if (a == "timeout") { signNote = "No sign-in after 10 minutes. Tap Sign in with publik to try again."; signPoll = false }
                continue
            }
            var choice = if (USES_AI) readCredential(app)?.choice else null
            if (USES_AI && choice == null) {
                if (hasPlan(w)) { planNote = null; planPoll = false } // the plan is there: Connect your plan
                val a = ask(ui, gateScreen("choose", w, note = planNote), key = c.key, until = if (planPoll) hasPlan else null)
                planNote = null
                planPoll = false
                if (a == "get_plan") { ui.open(w.topUpUrl); planNote = "Waiting for your plan. Finish on the publik page."; planPoll = true }
                if (a == "timeout") planNote = "No plan after 10 minutes. Tap Get a plan to try again."
                if (a != "connect" && a != "own_key") continue // "done": the plan is there; the next screen is Connect your plan
                choice = if (a == "connect") "publik" else "own_key"
                setChoice(app, choice)
            }
            signedInThisProcess = true
            startTelemetry(app)
            return Gate(c.key, w, choice)
        }
    }

    /** Optional mode, at start-up: no screen. A saved key that GET /wallet says is signed in starts usage counting. */
    suspend fun resume(context: Context): Wallet? {
        val app = context.applicationContext
        selfTestIfAsked(app)
        val c = readCredential(app) ?: return null
        val (status, w, _) = try { readWallet(c.key) } catch (e: CancellationException) { throw e } catch (e: Exception) { return null }
        if (status == 401) { try { write(app, null) } catch (e: Exception) {}; return null } // a revoked key
        if (w == null || !w.claimed) return null
        signedInThisProcess = true
        startTelemetry(app)
        return w
    }

    /**
     * Sign out: stop usage counting, delete the key file FIRST, then revoke the key (POST /api/v1/installs/revoke)
     * with the key held in memory, in the app-wide scope (no screen can cancel it). Best effort; the account stays.
     */
    fun signOut(context: Context) {
        val app = context.applicationContext
        stopTelemetry()
        signedInThisProcess = false
        val key = forgetKey(credentialFile(app)) ?: return
        val url = "$origin/api/v1/installs/revoke"
        backgroundScope.launch {
            try { request("POST", url, key = key, timeoutMs = 10_000) } catch (e: Exception) {}
        }
    }

    /** Sign out, steps 1-2: read the key into memory, then delete the key file. Returns the key, or null. */
    internal fun forgetKey(file: File): String? {
        val key = try { JSONObject(file.readText()).str("key")?.takeIf { it.startsWith("pk_") } } catch (e: Exception) { null }
        file.delete()
        return key
    }

    /** Delete account, step 2: sign out, then delete this app's publik data on the device. consent.json stays. */
    fun deleteLocalData(context: Context) {
        signOut(context)
        publikDir(context.applicationContext).listFiles()?.filter { it.name != "consent.json" }?.forEach { it.deleteRecursively() }
        telemetryId = null
    }

    /** The Status screen switch: false writes {"usage": false} to <publik dir>/consent.json, and then no event is sent. */
    fun usageConsent(context: Context): Boolean =
        try { JSONObject(File(publikDir(context), "consent.json").readText()).opt("usage") != false } catch (e: Exception) { true }

    fun setUsageConsent(context: Context, on: Boolean) {
        try {
            publikDir(context).mkdirs()
            File(publikDir(context), "consent.json").writeText("{\"usage\":$on}\n")
        } catch (e: Exception) {}
    }

    /** PUBLIK_SELF_TEST=1: print the self-test line (stdout and logcat) and exit, in both gate modes. */
    private suspend fun selfTestIfAsked(app: Context) {
        if (setting("PUBLIK_SELF_TEST") != null) {
            val line = selfTest(app)
            println(line)
            Log.i(TAG, line)
            exitProcess(0)
        }
    }

    /**
     * Builder check, run by the BUILT app: PUBLIK_SELF_TEST=1 makes ensureSignedIn() (or resume()) print this line
     * (stdout and logcat, tag "publik") and exit. On a device or emulator:
     * `adb shell am start -n app.noscroll/.MainActivity --es PUBLIK_SELF_TEST 1`, then `adb logcat -d -s publik`.
     */
    suspend fun selfTest(context: Context): String = try {
        val (status, w, message) = readWallet(provision(context).key)
        if (w == null) throw PublikException(message ?: "GET /wallet answered $status")
        "publik self-test: ok $APP_SLUG $APP_VERSION"
    } catch (e: CancellationException) {
        throw e
    } catch (e: IOException) {
        "publik self-test: failed: publik is not reachable. Check your connection."
    } catch (e: Exception) {
        "publik self-test: failed: ${e.message}"
    }

    // ---------- usage counting: /skills/telemetry.md sections 3-5 ----------
    @Volatile private var telemetryJob: Job? = null
    @Volatile private var telemetryId: String? = null
    private val telemetryScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private fun usageOff(context: Context): Boolean {
        val dnt = (env("DO_NOT_TRACK") ?: "").trim().lowercase()
        if (dnt !in listOf("", "0", "false") || (env("PUBLIK_TELEMETRY") ?: "").trim().lowercase() in listOf("0", "false", "off")) return true
        return try { JSONObject(File(publikDir(context), "consent.json").readText()).opt("usage") == false } catch (e: Exception) { false }
    }

    /** One random UUID for this app on this device, in <publik dir>/telemetry.json (mode 0600). */
    private fun telemetryInstallId(context: Context): String {
        telemetryId?.let { return it }
        val file = File(publikDir(context), "telemetry.json")
        fun saved(): String? = try {
            val id = JSONObject(file.readText()).str("install_id")
            if (id != null && id.length == 36 && id[14] == '4') UUID.fromString(id).toString() else null
        } catch (e: Exception) {
            null
        }
        val id = saved() ?: run {
            val fresh = UUID.randomUUID().toString() // if the file cannot be saved, this ID lasts for this run only
            try {
                publikDir(context).mkdirs()
                if (file.createNewFile()) { // never over a file that is there
                    file.setReadable(false, false); file.setReadable(true, true); file.setWritable(false, false); file.setWritable(true, true)
                    file.writeText("{\"install_id\":\"$fresh\",\"created_at\":\"${Instant.now().truncatedTo(ChronoUnit.SECONDS)}\"}\n")
                    fresh
                } else {
                    saved() ?: fresh
                }
            } catch (e: Exception) {
                fresh
            }
        }
        telemetryId = id
        return id
    }

    private suspend fun sendEvent(context: Context, event: String) {
        fun say(result: String) { if (BuildConfig.DEBUG || env("PUBLIK_TELEMETRY_DEBUG") == "1") Log.d(TAG, "publik-telemetry: $event -> $result") }
        if (usageOff(context)) return say("off (opt-out)")
        val key = env("PUBLIK_API_KEY") ?: readCredential(context)?.key
        val body = JSONObject().apply {
            put("v", 1); put("app", APP_SLUG); put("install_id", telemetryInstallId(context)); put("event", event)
            put("app_version", APP_VERSION.removePrefix("v")); put("os", "android")
            arch?.let { put("arch", it) }
        }
        try {
            say(request("POST", env("PUBLIK_TELEMETRY_URL") ?: "$origin/api/v1/telemetry", body, key?.takeIf { it.startsWith("pk_") }, 5_000).first.toString())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            say(e.javaClass.simpleName)
        }
    }

    /** Called by ensureSignedIn() and resume(): only after sign-in. app_opened now, active_session every 30 minutes in the foreground; never fails the app, never blocks. */
    @Synchronized
    fun startTelemetry(context: Context) {
        if (telemetryJob != null) return
        val app = context.applicationContext
        val s = env("PUBLIK_TELEMETRY_INTERVAL_SECONDS")?.toDoubleOrNull() ?: 0.0 // tests only
        val interval = if (s in 1.0..86_400.0) s else 1_800.0
        telemetryJob = telemetryScope.launch {
            sendEvent(app, "app_opened")
            while (true) {
                delay((interval * 1000).toLong())
                foreground.first { it }
                sendEvent(app, "active_session")
            }
        }
    }

    /** Sign out and delete account stop usage counting. */
    @Synchronized
    fun stopTelemetry() {
        telemetryJob?.cancel()
        telemetryJob = null
    }

    // ---------- publik API calls ----------
    /** A 402 renders its message plus exactly ONE link: this one. */
    fun topUpUrlFrom402(body: String): Pair<String, String?> {
        val e = try { JSONObject(body).optJSONObject("error") } catch (x: Exception) { null }
        return (e?.str("message") ?: "Not enough publik API balance.") to e?.str("top_up_url")
    }

    /** `POST /search`: web results for `q` (quote a phrase to find it exactly), one published price per search; on 402 the message and the one link. */
    suspend fun search(baseUrl: String, apiKey: String, q: String, count: Int = 10): Triple<List<JSONObject>, String?, String?> {
        val (status, body) = request("POST", "$baseUrl/search", JSONObject().put("q", q).put("count", count), apiKey, 30_000)
        if (status == 402) { val t = topUpUrlFrom402(body.toString()); return Triple(emptyList(), t.first, t.second) }
        if (status != 200) throw PublikException("publik API answered $status.")
        val results = body.optJSONArray("results") ?: JSONArray()
        return Triple((0 until results.length()).mapNotNull { results.optJSONObject(it) }, null, null)
    }
}

private fun JSONObject.str(name: String): String? = opt(name) as? String
