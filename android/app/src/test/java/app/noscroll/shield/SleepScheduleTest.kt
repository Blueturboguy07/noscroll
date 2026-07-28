package app.noscroll.shield

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * The Kotlin half of the Sleep Mode regression suite. These are the same
 * scenarios as ios/NoScrollCore SleepScheduleTests.swift — the two platforms
 * must agree, so the tests are deliberately parallel.
 */
class SleepScheduleTest {

    private fun tz(id: String) = TimeZone.getTimeZone(id)

    private fun millis(iso: String, zone: String): Long {
        val f = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
        f.timeZone = tz(zone)
        return f.parse(iso)!!.time
    }

    private val overnight = SleepSchedule(22 * 60, 7 * 60, enabled = true)

    @Test
    fun overnightWindowCoversTheWholeNight() {
        val z = "America/Denver"
        for (t in listOf(
            "2026-07-28T22:00:00", "2026-07-28T23:59:00",
            "2026-07-29T00:00:00", "2026-07-29T03:00:00", "2026-07-29T06:59:00",
        )) {
            assertTrue(t, overnight.isActive(millis(t, z), tz(z)))
        }
    }

    /** THE bug: it must release at 07:00 and certainly not still be on at 9am. */
    @Test
    fun releasesAtEndAndStaysReleased() {
        val z = "America/Denver"
        for (t in listOf(
            "2026-07-29T07:00:00", "2026-07-29T09:00:00",
            "2026-07-29T13:00:00", "2026-07-29T21:59:00",
        )) {
            assertFalse(t, overnight.isActive(millis(t, z), tz(z)))
        }
    }

    /** Same instant, different device timezone → different answer. */
    @Test
    fun timezoneChangeIsHonouredForTheSameInstant() {
        val instant = millis("2026-07-29T05:00:00", "UTC")
        assertTrue("23:00 Denver — asleep", overnight.isActive(instant, tz("America/Denver")))
        assertFalse("14:00 Tokyo — awake", overnight.isActive(instant, tz("Asia/Tokyo")))
    }

    @Test
    fun daytimeWindowIsNotTreatedAsCrossingMidnight() {
        val s = SleepSchedule(9 * 60, 17 * 60, enabled = true)
        val z = "America/Denver"
        assertFalse(s.isActive(millis("2026-07-29T08:59:00", z), tz(z)))
        assertTrue(s.isActive(millis("2026-07-29T09:00:00", z), tz(z)))
        assertTrue(s.isActive(millis("2026-07-29T16:59:00", z), tz(z)))
        assertFalse(s.isActive(millis("2026-07-29T17:00:00", z), tz(z)))
        assertFalse(s.isActive(millis("2026-07-29T02:00:00", z), tz(z)))
    }

    @Test
    fun overnightWeekdayAttributionBelongsToTheEveningDay() {
        // Friday only.
        val s = SleepSchedule(22 * 60, 7 * 60, enabled = true, weekdays = setOf(Calendar.FRIDAY))
        val z = "America/Denver"
        assertTrue("Fri 23:00", s.isActive(millis("2026-07-31T23:00:00", z), tz(z)))
        assertTrue("Sat 01:00 still Friday's window", s.isActive(millis("2026-08-01T01:00:00", z), tz(z)))
        assertFalse("Sat 23:00", s.isActive(millis("2026-08-01T23:00:00", z), tz(z)))
    }

    @Test
    fun dstSpringForwardDoesNotStrandTheSchedule() {
        val z = "America/Denver"
        assertTrue(overnight.isActive(millis("2026-03-08T01:30:00", z), tz(z)))
        assertTrue(overnight.isActive(millis("2026-03-08T03:30:00", z), tz(z)))
        assertFalse(overnight.isActive(millis("2026-03-08T08:00:00", z), tz(z)))
    }

    @Test
    fun disabledScheduleIsNeverActive() {
        val s = SleepSchedule(0, 23 * 60 + 59, enabled = false)
        assertFalse(s.isActive(millis("2026-07-29T03:00:00", "America/Denver"), tz("America/Denver")))
    }

    @Test
    fun degenerateWindowBlocksNothing() {
        val s = SleepSchedule(8 * 60, 8 * 60, enabled = true)
        val z = "America/Denver"
        assertFalse(s.isActive(millis("2026-07-29T08:00:00", z), tz(z)))
        assertFalse(s.isActive(millis("2026-07-29T20:00:00", z), tz(z)))
    }

    /** Minute-by-minute sweep of a full week: exactly 9h/night * 7 nights. */
    @Test
    fun fullWeekSweepHasExactlyTheExpectedActiveMinutes() {
        val start = millis("2026-06-01T00:00:00", "UTC")
        for (zone in listOf("America/Denver", "Asia/Tokyo", "Europe/London")) {
            var active = 0
            for (i in 0 until 7 * 24 * 60) {
                if (overnight.isActive(start + i * 60_000L, tz(zone))) active++
            }
            assertEquals(zone, 9 * 60 * 7, active)
        }
    }
}
