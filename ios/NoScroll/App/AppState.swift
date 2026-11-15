import Foundation
import SwiftUI
import UIKit
import WebKit

/// App-wide state: the verified rule bundles, the engine source, and per-surface
/// user settings.
///
/// Version 1 is the **browser only**. The Screen Time shield needs Apple's
/// `com.apple.developer.family-controls` entitlement (docs/ENTITLEMENT.md), so
/// this build does not ask for Screen Time and does not claim to stop you
/// opening the real apps. It gives you a calmer way in through its own browser.
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

    /// The full name in the app's own screens ("publik NoScroll"): the Info.plist key
    /// AppFullName, from APP_NAME in ios/Config/App.xcconfig.
    static let appName = (Bundle.main.object(forInfoDictionaryKey: "AppFullName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "publik NoScroll"

    /// The short name under the icon and in the widget gallery ("NoScroll"):
    /// CFBundleDisplayName, from APP_DISPLAY_NAME. Use it where the user must find
    /// the app by the name iOS shows.
    static let homeScreenName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "NoScroll"

    /// Surfaces that hide ads ("sponsored", "promoted"). The app never turns
    /// them on and never shows a switch for them: blocking ads conflicts with
    /// the terms of the services it opens (App Store guideline 5.2.2).
    static let adSurfaceKeys: Set<String> = ["sponsored", "promoted"]

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

    // MARK: - Navigation

    enum Tab: Hashable { case adjust, home, profile }
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

    func bundleVersion(for serviceID: String) -> String {
        guard let v = bundles[serviceID]?.version else { return "unavailable" }
        return "v\(v)"
    }

    // MARK: - Sign out of a service

    /// Services signed out in this run, so Settings can say "Signed out".
    @Published private(set) var signedOutServices: Set<String> = []

    /// Sign out of one service: delete its cookies, storage and cache in this
    /// app's browser on this device. The account at that service stays.
    func signOut(of service: Service) async {
        let store = WKWebsiteDataStore(forIdentifier: service.sessionID)
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        // The saved page state (WrappedWebViewController) can hold a signed-in page.
        UserDefaults.standard.removeObject(forKey: "noscroll.state.\(service.sessionID.uuidString)")
        signedOutServices.insert(service.id)
    }

    /// Opening a service again signs in again, so the "Signed out" mark goes.
    func didOpen(_ service: Service) {
        signedOutServices.remove(service.id)
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
            for (name, surface) in svc.surfaces {
                let key = "\(service.id).\(name)"
                if Self.adSurfaceKeys.contains(name) {
                    // Off, also for people who had turned it on in an older build.
                    if settings[key] != false { settings[key] = false }
                } else if surface.label != nil, settings[key] == nil {
                    settings[key] = surface.defaultEnabled ?? false
                }
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
                for key in keys where !Self.adSurfaceKeys.contains(key) {
                    self.settings["\(service).\(key)"] = newValue
                }
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
        for (key, surface) in svc.surfaces where !Self.adSurfaceKeys.contains(key) {
            guard let label = Self.displayLabel(surface.label) else { continue }
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

    /// The signed rule files name one Instagram switch "Hide Ads & Suggested".
    /// The app does not offer ad blocking, so it shows that switch by what it is for.
    private static func displayLabel(_ label: String?) -> String? {
        label == "Hide Ads & Suggested" ? "Hide suggested posts" : label
    }

    /// How many of a service's switches are on, for the home screen.
    func blockCount(for service: String) -> (on: Int, total: Int) {
        let groups = surfaces(for: service)
        let on = groups.filter { binding(service: service, surfaces: $0.keys).wrappedValue }.count
        return (on, groups.count)
    }

    private func loadSettings() {
        settings = UserDefaults.standard.dictionary(forKey: settingsKey) as? [String: Bool] ?? [:]
    }

    private func persistSettings() {
        UserDefaults.standard.set(settings, forKey: settingsKey)
    }
}
