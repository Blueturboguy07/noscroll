package app.noscroll.shield

import java.util.Calendar
import java.util.TimeZone

/**
 * Scheduled blocking (bedtime). Kotlin twin of ios/NoScrollCore SleepSchedule.swift —
 * same semantics, same edge cases, same tests.
 *
 * The bug this exists to not ship: SocialLite has two independent public reviews
 * reporting Sleep Mode failing to release at the scheduled end, one user stuck on
 * the "you should be asleep" screen at 9am. The cause is almost certainly a
 * window computed once and cached, which drifts on timezone change, DST, device
 * sleep across the boundary, and any schedule crossing midnight.
 *
 * The rule: NEVER cache the decision. [isActive] is pure and is recomputed from
 * the wall clock and the CURRENT timezone every time.
 */
data class SleepSchedule(
    /** Minutes from local midnight. */
    val startMinute: Int,
    val endMinute: Int,
    val enabled: Boolean,
    /** Calendar weekday numbers (1 = Sunday). Empty = every day. */
    val weekdays: Set<Int> = emptySet(),
) {

    fun isActive(atMillis: Long, timeZone: TimeZone = TimeZone.getDefault()): Boolean {
        if (!enabled) return false
        if (startMinute == endMinute) return false

        val cal = Calendar.getInstance(timeZone).apply { timeInMillis = atMillis }
        val nowMinute = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        val weekday = cal.get(Calendar.DAY_OF_WEEK)

        val crossesMidnight = startMinute > endMinute
        val inWindow: Boolean
        val effectiveWeekday: Int

        if (crossesMidnight) {
            when {
                nowMinute >= startMinute -> {
                    inWindow = true
                    effectiveWeekday = weekday
                }
                nowMinute < endMinute -> {
                    // The morning half belongs to YESTERDAY's schedule. Getting
                    // this wrong makes a Friday-night rule fail at 1am Saturday.
                    inWindow = true
                    effectiveWeekday = if (weekday == Calendar.SUNDAY) Calendar.SATURDAY else weekday - 1
                }
                else -> {
                    inWindow = false
                    effectiveWeekday = weekday
                }
            }
        } else {
            inWindow = nowMinute in startMinute until endMinute
            effectiveWeekday = weekday
        }

        if (!inWindow) return false
        return weekdays.isEmpty() || effectiveWeekday in weekdays
    }

    companion object {
        val DEFAULT = SleepSchedule(
            startMinute = 22 * 60,
            endMinute = 7 * 60,
            enabled = false,
        )
    }
}
