import Foundation

/// The sign-in poll of the publik gate: it asks "is the person signed in?" (`check`) every `interval`
/// seconds for `duration` seconds (the gate: 3 s for 10 minutes).
///
/// - The checks are on a fixed grid from the start: check n starts at start + n × interval. Each check
///   runs in its own task, so a slow or stalled request never moves the next check. (The old loop waited
///   for each request to end before its next 3 s wait. One request that hung for 6 s moved every later
///   check by 6 s, and the sign-in sheet closed 8.6–9.8 s after the sign-in instead of about 3 s.)
/// - The interval never grows: no back-off, for the whole duration.
/// - A signal on `wake` (the app or the sign-in sheet became active again) starts a check at once.
///
/// Returns true at the first check that returns true. Returns false when the duration ends with no such
/// check (the checks still running get one more interval to answer), or when the task is cancelled.
public enum PublikPoll {
    enum Event: Sendable { case check, found }

    public static func run(interval: TimeInterval = 3, duration: TimeInterval = 600,
                           wake: AsyncStream<Void>? = nil,
                           check: @escaping @Sendable () async -> Bool) async -> Bool {
        var made: AsyncStream<Event>.Continuation?
        let events = AsyncStream<Event>(bufferingPolicy: .unbounded) { made = $0 }
        guard let sink = made else { return false }
        let start = Date()

        // The grid: one event at each interval from the start, whatever the checks do.
        let grid = Task {
            var n = 1.0
            while n * interval <= duration + 0.000_001 {
                let wait = start.addingTimeInterval(n * interval).timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                if Task.isCancelled { return }
                sink.yield(.check)
                n += 1
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            sink.finish()
        }
        // The app or the sheet became active again: check at once.
        let waker = Task {
            guard let wake else { return }
            for await _ in wake {
                if Task.isCancelled { return }
                sink.yield(.check)
            }
        }
        var checks: [Task<Void, Never>] = []
        defer {
            grid.cancel()
            waker.cancel()
            checks.forEach { $0.cancel() }
            sink.finish()
        }
        for await event in events {
            switch event {
            case .found:
                return true
            case .check:
                checks.append(Task { if await check() { sink.yield(.found) } })
            }
        }
        return false
    }
}
