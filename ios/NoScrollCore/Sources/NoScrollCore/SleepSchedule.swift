import Foundation

/// Scheduled blocking (bedtime).
///
/// This is the single most-reported functional bug in the app we are cloning:
/// two independent reviewers report Sleep Mode failing to release at the
/// scheduled end time — one of them stuck on the "you should be asleep" screen
/// at 9am.
///
/// The cause is almost certainly a window computed once and cached. That drifts
/// on: timezone change, DST transition, device sleep across the boundary, and
/// any schedule that crosses midnight. So this type owns exactly one rule:
///
///     NEVER cache the decision. Recompute from the wall clock and the CURRENT
///     timezone on every foreground and on a periodic tick.
///
/// `isActive(at:)` is pure, which is what makes the cases below testable without
/// a device and without waiting until 3am.
public struct SleepSchedule: Codable, Equatable, Sendable {
    /// Minutes from local midnight.
    public var startMinute: Int
    public var endMinute: Int
    public var enabled: Bool
    /// Weekday numbers (1 = Sunday, matching Calendar). Empty = every day.
    public var weekdays: Set<Int>

    public init(startMinute: Int, endMinute: Int, enabled: Bool, weekdays: Set<Int>) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.enabled = enabled
        self.weekdays = weekdays
    }

    public static let `default` = SleepSchedule(
        startMinute: 22 * 60, endMinute: 7 * 60, enabled: false, weekdays: [])

    /// True if `date`, interpreted in `calendar`'s timezone, falls inside the window.
    ///
    /// Correctly handles a window that crosses midnight (22:00 → 07:00), which
    /// is the common case and the one a naive `start <= now && now < end` gets
    /// wrong for every minute of the night.
    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }

        let comps = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        guard let hour = comps.hour, let minute = comps.minute, let weekday = comps.weekday else {
            return false
        }
        let nowMinute = hour * 60 + minute

        if startMinute == endMinute { return false }

        let crossesMidnight = startMinute > endMinute
        let inWindow: Bool
        let effectiveWeekday: Int

        if crossesMidnight {
            if nowMinute >= startMinute {
                // Evening portion — belongs to today.
                inWindow = true
                effectiveWeekday = weekday
            } else if nowMinute < endMinute {
                // Morning portion — belongs to YESTERDAY's schedule. Getting
                // this wrong is how a Friday-night schedule fails to cover
                // Saturday 1am.
                inWindow = true
                effectiveWeekday = weekday == 1 ? 7 : weekday - 1
            } else {
                inWindow = false
                effectiveWeekday = weekday
            }
        } else {
            inWindow = nowMinute >= startMinute && nowMinute < endMinute
            effectiveWeekday = weekday
        }

        guard inWindow else { return false }
        return weekdays.isEmpty || weekdays.contains(effectiveWeekday)
    }
}
