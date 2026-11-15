package app.noscroll.publik

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * The sign-in poll of the publik gate: it asks "is the person signed in?" (`check`) every `intervalMs` for `durationMs`
 * (the gate: 3 s for 10 minutes).
 *
 * - The checks are on a fixed grid from the start: check n starts at start + n x interval. Each check runs on its own,
 *   so a slow or stalled request never moves the next check. (The old loop waited for each request to end before its
 *   next 3 s wait, so one slow request moved every later check.)
 * - The interval never grows: no back-off, for the whole duration.
 * - While the app is in the background (`foreground` false), grid checks are skipped. When the app comes back to the
 *   foreground, a check starts at once.
 *
 * Returns true at the first check that returns true; false when the duration ends with none (the checks still running
 * get one more interval to answer). A check that is still running when the poll ends is cancelled and not waited for.
 */
object PublikPoll {
    suspend fun run(
        intervalMs: Long = 3_000,
        durationMs: Long = 600_000,
        foreground: StateFlow<Boolean> = MutableStateFlow(true),
        check: suspend () -> Boolean,
    ): Boolean {
        // The checks run in their own scope: the poll does not wait for a request that cannot stop at once.
        val checks = CoroutineScope(currentCoroutineContext() + Job())
        val found = Channel<Boolean>(Channel.CONFLATED)
        fun startCheck() {
            checks.launch {
                val yes = try { check() } catch (e: CancellationException) { throw e } catch (e: Exception) { false }
                if (yes) found.trySend(true)
            }
        }
        try {
            return coroutineScope {
                val grid = launch {
                    val start = System.nanoTime()
                    var n = 1L
                    while (n * intervalMs <= durationMs) {
                        val wait = (start + n * intervalMs * 1_000_000 - System.nanoTime()) / 1_000_000
                        if (wait > 0) delay(wait)
                        if (foreground.value) startCheck()
                        n++
                    }
                    delay(intervalMs)
                    found.trySend(false)
                }
                val waker = launch {
                    var was = foreground.value
                    foreground.collect { now ->
                        if (now && !was) startCheck()
                        was = now
                    }
                }
                val result = found.receive()
                grid.cancel()
                waker.cancel()
                result
            }
        } finally {
            checks.cancel()
        }
    }
}
