import Foundation
import NoScrollCore

/// Drives the schedule. Re-evaluates on foreground, on a tick, and — critically —
/// on `NSSystemTimeZoneDidChange`, which is the notification that a cached
/// window would miss.
@MainActor
final class SleepModeController: ObservableObject {

    @Published private(set) var isActive = false
    @Published var schedule: SleepSchedule {
        didSet { persist(); reevaluate() }
    }

    private let onChange: (Bool) -> Void
    private var timer: Timer?
    private let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        if let data = defaults.data(forKey: ShieldController.Keys.sleepSchedule),
           let decoded = try? JSONDecoder().decode(SleepSchedule.self, from: data) {
            schedule = decoded
        } else {
            schedule = .default
        }
        observe()
        reevaluate()
    }

    private func observe() {
        let nc = NotificationCenter.default
        for name in [
            NSNotification.Name.NSSystemTimeZoneDidChange,
            NSNotification.Name.NSCalendarDayChanged,
        ] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reevaluate() }
            }
        }
        #if canImport(UIKit)
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification,
                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reevaluate() }
        }
        #endif

        // A 30s tick bounds how late a release can be, even if every
        // notification above is missed.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reevaluate() }
        }
    }

    /// Recomputed from scratch every time. No cached window, ever.
    func reevaluate(now: Date = Date()) {
        let active = schedule.isActive(at: now, calendar: .current)
        guard active != isActive else { return }
        isActive = active
        onChange(active)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        defaults.set(data, forKey: ShieldController.Keys.sleepSchedule)
    }

    deinit { timer?.invalidate() }
}

#if canImport(UIKit)
import UIKit
#endif
