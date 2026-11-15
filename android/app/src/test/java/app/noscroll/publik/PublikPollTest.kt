package app.noscroll.publik

import java.util.Collections
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The sign-in poll (PublikPoll). Blind test round 4 (iOS): the sign-in page closed 8.6-9.8 s after the sign-in in one run.
 * The old loop waited for each request to end before its next 3 s wait. The tests use short intervals; the gate uses 3 s
 * for 10 minutes.
 */
class PublikPollTest {
    private fun now() = System.nanoTime() / 1_000_000

    @Test
    fun aSlowCheckDoesNotDelayTheNextCheck() = runBlocking {
        val n = AtomicInteger(0)
        val start = now()
        val found = PublikPoll.run(intervalMs = 200, durationMs = 10_000) {
            val i = n.incrementAndGet()
            if (i == 1) { delay(2_000); false } else i >= 3
        }
        val took = now() - start
        assertTrue(found)
        assertTrue("a slow check delayed the next checks ($took ms)", took < 1_500)
    }

    @Test
    fun theIntervalStaysTheSameForTheWholeDuration() = runBlocking {
        val stamps = Collections.synchronizedList(mutableListOf<Long>())
        val start = now()
        val found = PublikPoll.run(intervalMs = 200, durationMs = 2_000) { stamps.add(now()); false }
        assertFalse(found)
        val s = stamps.toList()
        assertTrue("checks: ${s.size}", s.size in 9..11)
        val gaps = s.zipWithNext { a, b -> b - a }
        assertTrue("a gap grew: $gaps", (gaps.maxOrNull() ?: 0) < 450)
        assertTrue("the checks stopped early", s.last() - start > 1_700)
    }

    @Test
    fun theReturnToTheForegroundChecksAtOnce() = runBlocking {
        val foreground = MutableStateFlow(true)
        val signedIn = AtomicBoolean(false)
        val start = now()
        launch {
            delay(200)
            foreground.value = false // the person goes to another app to sign in
            delay(300)
            signedIn.set(true)
            foreground.value = true // and comes back
        }
        val found = PublikPoll.run(intervalMs = 30_000, durationMs = 600_000, foreground = foreground) { signedIn.get() }
        val took = now() - start
        assertTrue(found)
        assertTrue("the return did not check at once ($took ms; the next grid check is at 30 s)", took < 2_000)
    }

    @Test
    fun noCheckRunsInTheBackground() = runBlocking {
        val count = AtomicInteger(0)
        val found = PublikPoll.run(intervalMs = 100, durationMs = 500, foreground = MutableStateFlow(false)) { count.incrementAndGet(); true }
        assertFalse(found)
        assertTrue("checks in the background: ${count.get()}", count.get() == 0)
    }
}
