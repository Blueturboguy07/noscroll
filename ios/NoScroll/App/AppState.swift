import Foundation
import SwiftUI

/// App-wide state: the verified rule bundles, the engine source, and per-surface
/// user settings.
///
/// This build is the **wrapper-only** variant. The shield layer needs the gated
/// `com.apple.developer.family-controls` entitlement (docs/ENTITLEMENT.md), so
/// until that is granted the app is honest about what it does: it gives you a
/// calmer way in, and it does not claim to stop you opening the real app.
@MainActor
final class AppState: ObservableObject {

    @Published private(set) var bundles: [String: RuleBundle] = [:]
    @Published private(set) var rawBundles: [String: Data] = [:]
    @Published private(set) var loadError: String?
    @Published var settings: [String: Bool] = [:] {
        didSet { persistSettings() }
    }

    private(set) var engineSource = ""

    private let settingsKey = "noscroll.settings"
    private let onboardedKey = "noscroll.onboarded"

    /// First run shows onboarding, where the user sees every switch once and
    /// decides. Nothing is forced on.
    @Published var needsOnboarding: Bool

    /// Onboarding answers. Kept on device; the age exists only to draw the
    /// life grid and the copy on that screen says so.
    @Published var age: Int = UserDefaults.standard.object(forKey: "noscroll.age") as? Int ?? 18 {
        didSet { UserDefaults.standard.set(age, forKey: "noscroll.age") }
    }
    @Published var scrollHoursPerDay: Double =
        UserDefaults.standard.object(forKey: "noscroll.scrollHours") as? Double ?? 4.8 {
        didSet { UserDefaults.standard.set(scrollHoursPerDay, forKey: "noscroll.scrollHours") }
    }

    /// True once Screen Time authorisation is granted. Gated on the
    /// FamilyControls entitlement — see docs/ENTITLEMENT.md — so it is false in
    /// every build until Apple approves it.
    @Published private(set) var hasScreenTimeAccess = false

    /// Per-service time today. Real numbers need a DeviceActivityReport
    /// extension under the same entitlement; until then this says so rather
    /// than inventing a figure, which is the exact dishonesty this project is
    /// reacting to.
    func usageToday(for serviceID: String) -> String {
        guard hasScreenTimeAccess else { return "—" }
        let minutes = screenTimeMinutes[serviceID] ?? 0
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    @Published private(set) var screenTimeMinutes: [String: Int] = [:]

    // MARK: - Navigation

    enum Tab: Hashable { case sleep, adjust, home, shield, profile }
    @Published var tab: Tab = .home
    /// Set by a widget tap; HomeView opens this service's browser.
    @Published var pendingService: String?

    /// noscroll://open/<service> — the widget's whole job.
    func handle(url: URL) {
        guard url.scheme == "noscroll", url.host == "open" else { return }
        let id = url.lastPathComponent
        guard Self.service(id) != nil else { return }
        tab = .home
        pendingService = id
    }

    // MARK: - Sleep Mode

    @Published var sleepEnabled = UserDefaults.standard.bool(forKey: "noscroll.sleep.on") {
        didSet { UserDefaults.standard.set(sleepEnabled, forKey: "noscroll.sleep.on") }
    }
    @Published var sleepStart = AppState.time(hour: 22)
    @Published var sleepEnd = AppState.time(hour: 7)

    /// Recomputed on read, never cached — see SleepSchedule.
    var sleepActiveNow: Bool {
        let cal = Calendar.current
        let s = cal.component(.hour, from: sleepStart) * 60 + cal.component(.minute, from: sleepStart)
        let e = cal.component(.hour, from: sleepEnd) * 60 + cal.component(.minute, from: sleepEnd)
        return SleepSchedule(startMinute: s, endMinute: e, enabled: sleepEnabled, weekdays: [])
            .isActive(at: Date())
    }

    private static func time(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Post Mode

    @Published private(set) var postModeUnlocksRemaining = 4

    func beginPostMode() {
        guard postModeUnlocksRemaining > 0 else { return }
        postModeUnlocksRemaining -= 1
        #if NOSCROLL_SHIELD
        shield.beginPostMode()
        #endif
    }

    // MARK: - Telemetry

    @Published var telemetryEnabled = UserDefaults.standard.bool(forKey: "noscroll.telemetry") {
        didSet { UserDefaults.standard.set(telemetryEnabled, forKey: "noscroll.telemetry") }
    }

    func bundleVersion(for serviceID: String) -> String {
        guard let v = bundles[serviceID]?.version else { return "unavailable" }
        return "v\(v)"
    }

    /// Requests Screen Time authorisation.
    ///
    /// Compiled out until the FamilyControls entitlement is granted: without it
    /// the framework is unavailable and linking it fails the build. See
    /// docs/ENTITLEMENT.md — this is the one thing on the critical path.
    func requestScreenTimeAccess() async {
        #if NOSCROLL_SHIELD
        await shield.requestAuthorization()
        hasScreenTimeAccess = shield.authorization == .approved
        #else
        hasScreenTimeAccess = false
        #endif
    }

    init() {
        needsOnboarding = !UserDefaults.standard.bool(forKey: "noscroll.onboarded")
        loadSettings()
        loadEngine()
        loadBundles()
        seedDefaults()
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardedKey)
        needsOnboarding = false
    }

    /// Materialise each surface's default so onboarding shows real switch
    /// positions rather than a screen of greyed-out unknowns.
    private func seedDefaults() {
        for service in Self.services {
            guard let svc = bundles[service.id]?.services[service.id] else { continue }
            for (name, surface) in svc.surfaces where surface.label != nil {
                let key = "\(service.id).\(name)"
                if settings[key] == nil { settings[key] = surface.defaultEnabled ?? false }
            }
        }
    }

    // MARK: - Loading

    private func loadEngine() {
        guard let url = Bundle.main.url(forResource: "noscroll", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            loadError = "engine bundle missing from the app"
            return
        }
        engineSource = source
    }

    /// Bundles are ed25519-signed and verified here, before anything is injected.
    /// The same check runs against a remotely-fetched bundle in RuleStore.
    private func loadBundles() {
        guard let keyURL = Bundle.main.url(forResource: "rules-signing.pub", withExtension: "raw"),
              let keyData = try? Data(contentsOf: keyURL)
        else {
            loadError = "signing key missing from the app"
            return
        }

        let store: RuleStore
        do {
            store = try RuleStore(
                publicKeyRaw: keyData,
                remoteURL: URL(string: "https://rules.noscroll.app/v1/")!
            )
        } catch {
            loadError = "bad signing key: \(error.localizedDescription)"
            return
        }

        for service in Self.services {
            guard let url = Bundle.main.url(forResource: service.id, withExtension: "json"),
                  let data = try? Data(contentsOf: url)
            else {
                loadError = "rule bundle missing: \(service.id)"
                continue
            }
            do {
                bundles[service.id] = try store.verify(data)
                rawBundles[service.id] = data
            } catch {
                // A bundle that does not verify is refused outright. Better to
                // show nothing than to silently browse with blocking disabled.
                loadError = "\(service.id): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Settings

    /// One switch may drive several surfaces. "Block Reels" is both a DOM rule
    /// (the nav icon) and a route rule (typing the URL); the user thinks of that
    /// as one thing, so surfaces sharing a label are presented as one toggle.
    func binding(service: String, surfaces keys: [String]) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self else { return false }
                return keys.contains { key in
                    if let v = self.settings["\(service).\(key)"] { return v }
                    return self.bundles[service]?.services[service]?
                        .surfaces[key]?.defaultEnabled ?? false
                }
            },
            set: { [weak self] newValue in
                guard let self else { return }
                for key in keys { self.settings["\(service).\(key)"] = newValue }
            }
        )
    }

    /// Surfaces in a stable, human order. Suggested-on ones sort first so the
    /// list reads as "here is what we recommend", then the extras.
    struct SurfaceGroup: Identifiable {
        let label: String
        let keys: [String]
        let suggested: Bool
        var id: String { label }
    }

    func surfaces(for service: String) -> [SurfaceGroup] {
        guard let svc = bundles[service]?.services[service] else { return [] }
        var byLabel: [String: (keys: [String], suggested: Bool)] = [:]
        for (key, surface) in svc.surfaces {
            guard let label = surface.label else { continue }
            var entry = byLabel[label] ?? (keys: [], suggested: false)
            entry.keys.append(key)
            entry.suggested = entry.suggested || (surface.defaultEnabled ?? false)
            byLabel[label] = entry
        }
        return byLabel
            .map { SurfaceGroup(label: $0.key, keys: $0.value.keys.sorted(), suggested: $0.value.suggested) }
            .sorted { lhs, rhs in
                if lhs.suggested != rhs.suggested { return lhs.suggested && !rhs.suggested }
                return lhs.label < rhs.label
            }
    }

    private func loadSettings() {
        settings = UserDefaults.standard.dictionary(forKey: settingsKey) as? [String: Bool] ?? [:]
    }

    private func persistSettings() {
        UserDefaults.standard.set(settings, forKey: settingsKey)
    }
}
