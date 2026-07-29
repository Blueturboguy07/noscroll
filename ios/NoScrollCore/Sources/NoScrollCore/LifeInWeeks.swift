import Foundation

/// The arithmetic behind the "this is your life" grid.
///
/// Every number on that screen is derived, not decorative. At age 18 with a
/// 90-year life the split comes out as 18 past + 24 sleep + 24 work + 9 hygiene
/// + 15 free — and 4.8 scrolling hours against 5 free hours a day is 96%.
///
/// Pure and testable on the host, because a screen whose whole persuasive force
/// rests on a number had better have the right number.
public struct LifeInWeeks: Equatable, Sendable {

    public struct Band: Equatable, Sendable, Identifiable {
        public let kind: Kind
        /// Whole years, for the left-hand labels.
        public let years: Double
        /// Number of week-boxes this band occupies.
        public let weeks: Int
        public var id: Kind { kind }

        public var roundedYears: Int { Int(years.rounded()) }
    }

    public enum Kind: String, CaseIterable, Sendable {
        case past, sleep, work, hygiene, scrolling, free
    }

    /// Assumptions, all adjustable and all stated rather than buried.
    public struct Assumptions: Equatable, Sendable {
        public var lifeExpectancy: Double
        public var sleepHoursPerDay: Double
        public var workHoursPerDay: Double
        public var hygieneHoursPerDay: Double

        public static let `default` = Assumptions(
            lifeExpectancy: 90,
            sleepHoursPerDay: 8,
            workHoursPerDay: 8,
            hygieneHoursPerDay: 3
        )

        public init(lifeExpectancy: Double, sleepHoursPerDay: Double,
                    workHoursPerDay: Double, hygieneHoursPerDay: Double) {
            self.lifeExpectancy = lifeExpectancy
            self.sleepHoursPerDay = sleepHoursPerDay
            self.workHoursPerDay = workHoursPerDay
            self.hygieneHoursPerDay = hygieneHoursPerDay
        }

        /// Hours in a day that are genuinely yours.
        public var freeHoursPerDay: Double {
            max(0, 24 - sleepHoursPerDay - workHoursPerDay - hygieneHoursPerDay)
        }
    }

    public let age: Int
    public let scrollHoursPerDay: Double
    public let assumptions: Assumptions
    public let bands: [Band]
    public let totalWeeks: Int

    /// Share of free time consumed by scrolling, 0...1.
    public let scrollShare: Double

    public var scrollPercent: Int { Int((scrollShare * 100).rounded()) }

    /// Years of remaining free time that scrolling will take.
    public var yearsLostToScrolling: Double {
        bands.first { $0.kind == .scrolling }?.years ?? 0
    }

    public init(age: Int, scrollHoursPerDay: Double, assumptions: Assumptions = .default) {
        let clampedAge = min(max(age, 1), Int(assumptions.lifeExpectancy) - 1)
        self.age = clampedAge
        self.scrollHoursPerDay = max(0, scrollHoursPerDay)
        self.assumptions = assumptions

        let remaining = assumptions.lifeExpectancy - Double(clampedAge)
        let day = 24.0

        let sleepYears = remaining * (assumptions.sleepHoursPerDay / day)
        let workYears = remaining * (assumptions.workHoursPerDay / day)
        let hygieneYears = remaining * (assumptions.hygieneHoursPerDay / day)
        let freeYears = max(0, remaining - sleepYears - workYears - hygieneYears)

        let freeHours = assumptions.freeHoursPerDay
        // Scrolling cannot consume more than all of your free time.
        let share = freeHours > 0 ? min(1, self.scrollHoursPerDay / freeHours) : 1
        self.scrollShare = share

        let scrollingYears = freeYears * share
        let leftoverYears = freeYears - scrollingYears

        let weeksPerYear = 52.0
        func weeks(_ years: Double) -> Int { Int((years * weeksPerYear).rounded()) }

        self.bands = [
            Band(kind: .past, years: Double(clampedAge), weeks: weeks(Double(clampedAge))),
            Band(kind: .sleep, years: sleepYears, weeks: weeks(sleepYears)),
            Band(kind: .work, years: workYears, weeks: weeks(workYears)),
            Band(kind: .hygiene, years: hygieneYears, weeks: weeks(hygieneYears)),
            Band(kind: .scrolling, years: scrollingYears, weeks: weeks(scrollingYears)),
            Band(kind: .free, years: leftoverYears, weeks: weeks(leftoverYears)),
        ]
        self.totalWeeks = self.bands.reduce(0) { $0 + $1.weeks }
    }

    /// The band a given week-box belongs to, for rendering.
    public func kind(forWeek index: Int) -> Kind {
        var cursor = 0
        for band in bands {
            cursor += band.weeks
            if index < cursor { return band.kind }
        }
        return .free
    }
}
