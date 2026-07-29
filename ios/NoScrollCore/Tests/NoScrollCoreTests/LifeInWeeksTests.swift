import XCTest
@testable import NoScrollCore

/// The life grid is the most persuasive screen in the app, so its arithmetic is
/// pinned. These cases reproduce the reference exactly: age 18, 4.8 scrolling
/// hours a day, 90-year life → 18/24/24/9/15 and 96%.
final class LifeInWeeksTests: XCTestCase {

    func testReferenceCaseMatchesExactly() {
        let life = LifeInWeeks(age: 18, scrollHoursPerDay: 4.8)

        func years(_ k: LifeInWeeks.Kind) -> Int {
            life.bands.first { $0.kind == k }!.roundedYears
        }

        XCTAssertEqual(years(.past), 18)
        XCTAssertEqual(years(.sleep), 24)
        XCTAssertEqual(years(.work), 24)
        XCTAssertEqual(years(.hygiene), 9)
        // Scrolling + free together are the 15 free years.
        XCTAssertEqual(years(.scrolling) + years(.free), 15)
        XCTAssertEqual(life.scrollPercent, 96)
    }

    func testFreeHoursPerDayIsFive() {
        XCTAssertEqual(LifeInWeeks.Assumptions.default.freeHoursPerDay, 5, accuracy: 0.0001)
    }

    func testScrollShareIsBoundedAtAllOfYourFreeTime() {
        // 12 hours a day of scrolling cannot exceed 100% of 5 free hours.
        let life = LifeInWeeks(age: 20, scrollHoursPerDay: 12)
        XCTAssertEqual(life.scrollPercent, 100)
        XCTAssertEqual(life.bands.first { $0.kind == .free }!.weeks, 0)
    }

    func testNoScrollingLeavesAllFreeTimeIntact() {
        let life = LifeInWeeks(age: 30, scrollHoursPerDay: 0)
        XCTAssertEqual(life.scrollPercent, 0)
        XCTAssertEqual(life.bands.first { $0.kind == .scrolling }!.weeks, 0)
        XCTAssertGreaterThan(life.bands.first { $0.kind == .free }!.weeks, 0)
    }

    func testBandsAlwaysSumToTheWholeLife() {
        for age in [1, 13, 18, 25, 40, 65, 89] {
            for hours in [0.0, 1.0, 4.8, 8.0] {
                let life = LifeInWeeks(age: age, scrollHoursPerDay: hours)
                let expected = Int((90.0 * 52).rounded())
                // Rounding per band can drift a few weeks across six bands.
                XCTAssertEqual(Double(life.totalWeeks), Double(expected), accuracy: 6,
                               "age \(age) hours \(hours)")
            }
        }
    }

    func testAgeIsClampedIntoTheLifespan() {
        let old = LifeInWeeks(age: 200, scrollHoursPerDay: 4.8)
        XCTAssertEqual(old.age, 89)
        XCTAssertGreaterThanOrEqual(old.totalWeeks, 0)

        let young = LifeInWeeks(age: 0, scrollHoursPerDay: 4.8)
        XCTAssertEqual(young.age, 1)
    }

    func testEveryWeekMapsToABand() {
        let life = LifeInWeeks(age: 18, scrollHoursPerDay: 4.8)
        var counts: [LifeInWeeks.Kind: Int] = [:]
        for i in 0..<life.totalWeeks {
            counts[life.kind(forWeek: i), default: 0] += 1
        }
        for band in life.bands where band.weeks > 0 {
            XCTAssertEqual(counts[band.kind], band.weeks, "\(band.kind)")
        }
    }

    /// Older users have less remaining life, so the same daily habit costs fewer
    /// absolute years — the percentage, however, must not move.
    func testPercentageIsIndependentOfAge() {
        let young = LifeInWeeks(age: 18, scrollHoursPerDay: 4.8)
        let older = LifeInWeeks(age: 60, scrollHoursPerDay: 4.8)
        XCTAssertEqual(young.scrollPercent, older.scrollPercent)
        XCTAssertGreaterThan(young.yearsLostToScrolling, older.yearsLostToScrolling)
    }
}
