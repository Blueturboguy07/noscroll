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

    struct Service: Identifiable, Hashable {
        let id: String
        let name: String
        let home: URL
        let tint: Color
        let symbol: String
    }

    static let services: [Service] = [
        .init(id: "instagram", name: "Instagram",
              home: URL(string: "https://www.instagram.com/")!,
              tint: Color(red: 0.86, green: 0.24, blue: 0.55), symbol: "camera.fill"),
        .init(id: "youtube", name: "YouTube",
              home: URL(string: "https://m.youtube.com/")!,
              tint: Color(red: 0.85, green: 0.12, blue: 0.12), symbol: "play.rectangle.fill"),
    ]

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
