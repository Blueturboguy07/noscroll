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

    init() {
        loadSettings()
        loadEngine()
        loadBundles()
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

    /// Locked surfaces ignore user settings — that is what locked means.
    func isLocked(service: String, surface: String) -> Bool {
        bundles[service]?.services[service]?.surfaces[surface]?.locked == true
    }

    func binding(service: String, surface: String) -> Binding<Bool> {
        let key = "\(service).\(surface)"
        return Binding(
            get: { [weak self] in
                guard let self else { return false }
                if self.isLocked(service: service, surface: surface) { return true }
                if let v = self.settings[key] { return v }
                return self.bundles[service]?.services[service]?
                    .surfaces[surface]?.defaultEnabled ?? false
            },
            set: { [weak self] newValue in
                guard let self, !self.isLocked(service: service, surface: surface) else { return }
                self.settings[key] = newValue
            }
        )
    }

    /// Surfaces in a stable, human order for the settings screen.
    func surfaces(for service: String) -> [(key: String, label: String, locked: Bool)] {
        guard let svc = bundles[service]?.services[service] else { return [] }
        return svc.surfaces
            .filter { $0.value.label != nil }
            .map { (key: $0.key, label: $0.value.label ?? $0.key, locked: $0.value.locked == true) }
            .sorted { lhs, rhs in
                if lhs.locked != rhs.locked { return lhs.locked && !rhs.locked }
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
