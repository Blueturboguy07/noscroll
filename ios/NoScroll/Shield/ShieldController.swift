import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// The enforcement layer.
///
/// The wrapper alone enforces nothing — the user just opens Safari. What makes
/// this product work is shielding the real Instagram and YouTube apps so the
/// stripped web version is the only way in.
///
/// REQUIRES the `com.apple.developer.family-controls` entitlement, which is
/// gated by Apple, takes days-to-weeks, and can be denied. It must be requested
/// for the main app AND each of the three extensions. See docs/ENTITLEMENT.md.
@MainActor
final class ShieldController: ObservableObject {

    enum AuthorizationState: Equatable {
        case unknown, denied, approved
    }

    @Published private(set) var authorization: AuthorizationState = .unknown
    @Published private(set) var shieldedApps = FamilyActivitySelection()
    @Published private(set) var postModeExpiry: Date?

    private let store = ManagedSettingsStore(named: .noscroll)
    private let center = AuthorizationCenter.shared
    private let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await center.requestAuthorization(for: .individual)
            authorization = .approved
        } catch {
            // Denial is a supported state, not a crash. If the entitlement is
            // absent entirely the app degrades to wrapper-only and says so
            // honestly rather than claiming an enforcement it cannot deliver.
            authorization = .denied
        }
    }

    // MARK: - Shielding

    func applyShield(_ selection: FamilyActivitySelection) {
        shieldedApps = selection
        persistSelection(selection)
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
    }

    func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }

    // MARK: - Post Mode

    /// Temporarily unshield so the user can post in the real app — the only
    /// correct answer to "you cannot post a Reel from the web". Attempting
    /// private upload APIs instead is precisely what got The OG App pulled.
    ///
    /// Three things SocialLite's version lacks, all of which are bugs we can see
    /// in their reviews or reason about directly:
    ///
    ///  1. A near-expiry warning, so the timer is not a surprise.
    ///  2. A grace extension while an upload is genuinely in progress — a fixed
    ///     wall-clock re-shield otherwise kills a long caption or large video
    ///     mid-send.
    ///  3. A per-day budget, so a 10-minute unlock invoked repeatedly is not
    ///     simply unlimited access with extra steps.
    @discardableResult
    func beginPostMode(duration: TimeInterval = 600) -> Bool {
        guard postModeUnlocksToday() < Self.maxUnlocksPerDay else { return false }
        recordUnlock()
        clearShield()
        let expiry = Date().addingTimeInterval(duration)
        postModeExpiry = expiry
        schedulePostModeEnd(at: expiry)
        return true
    }

    static let maxUnlocksPerDay = 4
    static let graceExtension: TimeInterval = 120

    private func schedulePostModeEnd(at expiry: Date) {
        Task { [weak self] in
            let interval = expiry.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
            }
            await self?.endPostModeIfIdle()
        }
    }

    /// If the shielded app is still in the foreground and actively uploading we
    /// extend rather than cut. `isUploadInProgress` is set by the DeviceActivity
    /// monitor extension via the shared app group.
    private func endPostModeIfIdle() async {
        if defaults.bool(forKey: Keys.uploadInProgress) {
            let extended = Date().addingTimeInterval(Self.graceExtension)
            postModeExpiry = extended
            schedulePostModeEnd(at: extended)
            return
        }
        postModeExpiry = nil
        applyShield(shieldedApps)
    }

    // MARK: - Unlock budget

    private func postModeUnlocksToday() -> Int {
        guard let day = defaults.string(forKey: Keys.unlockDay),
              day == Self.today() else { return 0 }
        return defaults.integer(forKey: Keys.unlockCount)
    }

    private func recordUnlock() {
        let today = Self.today()
        if defaults.string(forKey: Keys.unlockDay) != today {
            defaults.set(today, forKey: Keys.unlockDay)
            defaults.set(0, forKey: Keys.unlockCount)
        }
        defaults.set(postModeUnlocksToday() + 1, forKey: Keys.unlockCount)
    }

    private static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    // MARK: - Persistence

    private func persistSelection(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Keys.selection)
    }

    enum Keys {
        static let selection = "noscroll.shield.selection"
        static let unlockDay = "noscroll.postmode.day"
        static let unlockCount = "noscroll.postmode.count"
        static let uploadInProgress = "noscroll.postmode.uploading"
        static let sleepSchedule = "noscroll.sleep.schedule"
    }
}

extension ManagedSettingsStore.Name {
    static let noscroll = Self("noscroll")
}

enum AppGroup {
    /// Shared between the app and its three Screen Time extensions.
    static let identifier = "group.app.noscroll"
}
