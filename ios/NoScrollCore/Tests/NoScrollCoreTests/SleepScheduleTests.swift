import XCTest
@testable import NoScrollCore

/// Regression tests for the bug we are specifically not shipping.
///
/// SocialLite has two independent public reviews reporting Sleep Mode failing to
/// release at the scheduled end — one user stuck on the "you should be asleep"
/// screen at 9am. Every test below is a scenario that would produce exactly that
/// symptom if the window were computed once and cached.
final class SleepScheduleTests: XCTestCase {

    private func cal(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    private func date(_ iso: String, tz: String = "America/Denver") -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: tz)!
        return f.date(from: iso)!
    }

    /// 22:00 → 07:00, the default and the case a naive `start <= now < end`
    /// gets wrong for every single minute of the night.
    func testOvernightWindowCoversTheWholeNight() {
        let s = SleepSchedule(startMinute: 22 * 60, endMinute: 7 * 60,
                              enabled: true, weekdays: [])
        let c = cal("America/Denver")

        XCTAssertTrue(s.isActive(at: date("2026-07-28T22:00:00-06:00"), calendar: c), "22:00")
        XCTAssertTrue(s.isActive(at: date("2026-07-28T23:59:00-06:00"), calendar: c), "23:59")
        XCTAssertTrue(s.isActive(at: date("2026-07-29T00:00:00-06:00"), calendar: c), "midnight")
        XCTAssertTrue(s.isActive(at: date("2026-07-29T03:00:00-06:00"), calendar: c), "03:00")
        XCTAssertTrue(s.isActive(at: date("2026-07-29T06:59:00-06:00"), calendar: c), "06:59")
    }

    /// THE bug. At the end boundary the schedule must release — immediately,
    /// and at 9am it must certainly not still be active.
    func testReleasesExactlyAtEndAndStaysReleased() {
        let s = SleepSchedule(startMinute: 22 * 60, endMinute: 7 * 60,
                              enabled: true, weekdays: [])
        let c = cal("America/Denver")

        XCTAssertFalse(s.isActive(at: date("2026-07-29T07:00:00-06:00"), calendar: c), "07:00")
        XCTAssertFalse(s.isActive(at: date("2026-07-29T09:00:00-06:00"), calendar: c),
                       "9am — the exact symptom in SocialLite's review")
        XCTAssertFalse(s.isActive(at: date("2026-07-29T13:00:00-06:00"), calendar: c), "1pm")
        XCTAssertFalse(s.isActive(at: date("2026-07-29T21:59:00-06:00"), calendar: c), "21:59")
    }

    /// Same instant, different device timezone → different answer. A window
    /// cached at schedule-set time cannot possibly get this right.
    func testTimezoneChangeIsHonouredForTheSameInstant() {
        let s = SleepSchedule(startMinute: 22 * 60, endMinute: 7 * 60,
                              enabled: true, weekdays: [])
        // 2026-07-29T05:00Z == 23:00 previous day in Denver, 14:00 in Tokyo.
        let instant = date("2026-07-29T05:00:00+00:00", tz: "UTC")

        XCTAssertTrue(s.isActive(at: instant, calendar: cal("America/Denver")),
                      "23:00 local — asleep")
        XCTAssertFalse(s.isActive(at: instant, calendar: cal("Asia/Tokyo")),
                       "14:00 local — awake; flying to Tokyo must release the shield")
    }

    /// A daytime window must not be treated as if it crossed midnight.
    func testDaytimeWindow() {
        let s = SleepSchedule(startMinute: 9 * 60, endMinute: 17 * 60,
                              enabled: true, weekdays: [])
        let c = cal("America/Denver")

        XCTAssertFalse(s.isActive(at: date("2026-07-29T08:59:00-06:00"), calendar: c))
        XCTAssertTrue(s.isActive(at: date("2026-07-29T09:00:00-06:00"), calendar: c))
        XCTAssertTrue(s.isActive(at: date("2026-07-29T16:59:00-06:00"), calendar: c))
        XCTAssertFalse(s.isActive(at: date("2026-07-29T17:00:00-06:00"), calendar: c))
        XCTAssertFalse(s.isActive(at: date("2026-07-29T02:00:00-06:00"), calendar: c))
    }

    /// The morning half of an overnight window belongs to the PREVIOUS day's
    /// schedule. Getting this wrong makes a Friday-night rule fail at 1am Saturday.
    func testOvernightWeekdayAttribution() {
        // Friday only. Friday == 6 in Calendar's numbering.
        let s = SleepSchedule(startMinute: 22 * 60, endMinute: 7 * 60,
                              enabled: true, weekdays: [6])
        let c = cal("America/Denver")

        // 2026-07-31 is a Friday.
        XCTAssertTrue(s.isActive(at: date("2026-07-31T23:00:00-06:00"), calendar: c),
                      "Friday 23:00 — inside")
        XCTAssertTrue(s.isActive(at: date("2026-08-01T01:00:00-06:00"), calendar: c),
                      "Saturday 01:00 still belongs to Friday's schedule")
        XCTAssertFalse(s.isActive(at: date("2026-08-01T23:00:00-06:00"), calendar: c),
                       "Saturday 23:00 — Saturday is not selected")
    }

    /// Spring-forward: 02:00–03:00 does not exist in Denver on 2026-03-08.
    /// The schedule must still be active either side of the gap.
    func testDSTSpringForwardDoesNotStrandTheSchedule() {
        let s = SleepSchedule(startMinute: 22 * 60, endMinute: 7 * 60,
                              enabled: true, weekdays: [])
        let c = cal("America/Denver")

        XCTAssertTrue(s.isActive(at: date("2026-03-08T01:30:00-07:00"), calendar: c),
                      "01:30 MST, before the gap")
        XCTAssertTrue(s.isActive(at: date("2026-03-08T03:30:00-06:00"), calendar: c),
                      "03:30 MDT, after the gap")
        XCTAssertFalse(s.isActive(at: date("2026-03-08T08:00:00-06:00"), calendar: c),
                       "08:00 MDT — released")
    }

    func testDisabledScheduleIsNeverActive() {
        let s = SleepSchedule(startMinute: 0, endMinute: 23 * 60 + 59,
                              enabled: false, weekdays: [])
        XCTAssertFalse(s.isActive(at: date("2026-07-29T03:00:00-06:00"),
                                  calendar: cal("America/Denver")))
    }

    /// A zero-width window must block nothing rather than everything.
    func testDegenerateWindowBlocksNothing() {
        let s = SleepSchedule(startMinute: 8 * 60, endMinute: 8 * 60,
                              enabled: true, weekdays: [])
        let c = cal("America/Denver")
        XCTAssertFalse(s.isActive(at: date("2026-07-29T08:00:00-06:00"), calendar: c))
        XCTAssertFalse(s.isActive(at: date("2026-07-29T20:00:00-06:00"), calendar: c))
    }

    /// Sweep every minute of a week in two timezones and assert the schedule is
    /// active for exactly the expected number of minutes. This is the check that
    /// would have caught the shipped bug without anyone having to be awake at 7am.
    func testFullWeekSweepHasExactlyTheExpectedActiveMinutes() {
        let s = SleepSchedule(startMinute: 22 * 60, endMinute: 7 * 60,
                              enabled: true, weekdays: [])

        for tz in ["America/Denver", "Asia/Tokyo", "Europe/London"] {
            let c = cal(tz)
            var active = 0
            // Start at a local midnight and walk 7 days, minute by minute.
            let start = date("2026-06-01T00:00:00+00:00", tz: "UTC")
            for i in 0..<(7 * 24 * 60) {
                if s.isActive(at: start.addingTimeInterval(Double(i) * 60), calendar: c) {
                    active += 1
                }
            }
            // 9 hours a night * 7 nights = 3780 minutes.
            XCTAssertEqual(active, 9 * 60 * 7, "timezone \(tz)")
        }
    }
}
