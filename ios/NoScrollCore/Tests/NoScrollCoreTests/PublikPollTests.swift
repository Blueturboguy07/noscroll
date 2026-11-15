import Foundation
import XCTest
@testable import NoScrollCore

/// The sign-in poll (PublikPoll). Blind test round 4: the sign-in sheet closed 8.6–9.8 s after the
/// sign-in in one run (2.7–3.5 s in the others). The old loop waited for each request to end before its
/// next 3 s wait, so one slow request moved every later check. These tests use short intervals; the
/// gate uses 3 s for 10 minutes.
final class PublikPollTests: XCTestCase {
    /// Counts the checks and keeps the time of each one.
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var times: [Date] = []
        private var flag = false

        @discardableResult
        func hit() -> Int {
            lock.lock(); defer { lock.unlock() }
            times.append(Date())
            return times.count
        }
        var stamps: [Date] { lock.lock(); defer { lock.unlock() }; return times }
        var signedIn: Bool {
            get { lock.lock(); defer { lock.unlock() }; return flag }
            set { lock.lock(); flag = newValue; lock.unlock() }
        }
    }

    func testASlowCheckDoesNotDelayTheNextCheck() async {
        let log = Log()
        let start = Date()
        let found = await PublikPoll.run(interval: 0.2, duration: 10) {
            let n = log.hit()
            if n == 1 {
                // The first request hangs for 2 s.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return false
            }
            return n >= 3 // the sign-in is seen at the third check
        }
        let took = Date().timeIntervalSince(start)
        XCTAssertTrue(found)
        // Fixed grid: the third check starts at about 0.6 s. The old loop: 0.2 + 2 + 0.2 + 0.2 = 2.6 s.
        XCTAssertLessThan(took, 1.5, "a slow check delayed the next checks (\(took) s)")
    }

    func testTheIntervalStaysTheSameForTheWholeDuration() async {
        let log = Log()
        let start = Date()
        let found = await PublikPoll.run(interval: 0.2, duration: 2.0) {
            log.hit()
            return false
        }
        XCTAssertFalse(found)
        let stamps = log.stamps
        XCTAssertGreaterThanOrEqual(stamps.count, 9, "too few checks: \(stamps.count)")
        XCTAssertLessThanOrEqual(stamps.count, 11, "too many checks: \(stamps.count)")
        // No back-off: the last gaps are as short as the first ones.
        let gaps = zip(stamps.dropFirst(), stamps).map { $0.timeIntervalSince($1) }
        XCTAssertLessThan(gaps.max() ?? 0, 0.45, "a gap grew: \(gaps)")
        // The checks go on until the end of the duration.
        XCTAssertGreaterThan(stamps.last.map { $0.timeIntervalSince(start) } ?? 0, 1.7)
    }

    func testAWakeChecksAtOnce() async {
        let log = Log()
        var made: AsyncStream<Void>.Continuation?
        let wake = AsyncStream<Void> { made = $0 }
        let start = Date()
        let poll = Task {
            await PublikPoll.run(interval: 30, duration: 600, wake: wake) { log.signedIn }
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        log.signedIn = true
        made?.yield(()) // the app (or the sign-in sheet) became active again
        let found = await poll.value
        let took = Date().timeIntervalSince(start)
        XCTAssertTrue(found)
        XCTAssertLessThan(took, 2.0, "a wake did not check at once (\(took) s; the next grid check is at 30 s)")
    }

    func testItEndsWithFalseAfterTheDuration() async {
        let start = Date()
        let found = await PublikPoll.run(interval: 0.1, duration: 0.5) { false }
        let took = Date().timeIntervalSince(start)
        XCTAssertFalse(found)
        XCTAssertGreaterThanOrEqual(took, 0.5)
        XCTAssertLessThan(took, 2.0)
    }

    func testCancelStopsThePoll() async {
        let start = Date()
        let poll = Task { await PublikPoll.run(interval: 0.1, duration: 600) { false } }
        try? await Task.sleep(nanoseconds: 300_000_000)
        poll.cancel()
        let found = await poll.value
        XCTAssertFalse(found)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
    }
}
