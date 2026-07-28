import Foundation
import WebKit

/// Per-account, persistent WebView storage.
///
/// This is why the deployment target is iOS 17: `WKWebsiteDataStore(forIdentifier:)`
/// gives named PERSISTENT data stores. Before iOS 17 every non-default store is
/// ephemeral, which means multi-account cannot work correctly — you either share
/// one cookie jar between accounts (they collide) or lose the session on every
/// launch. There is no third option on iOS 16.
///
/// Note the deliberate asymmetry with Android, where `CookieManager` is
/// process-global and this has to be solved a completely different way.
struct WebSession: Identifiable, Hashable, Codable {
    let id: UUID
    var service: String
    var displayName: String

    static func identifier(for id: UUID) -> UUID { id }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [WebSession] = []

    private let defaultsKey = "noscroll.sessions"

    init() { load() }

    func dataStore(for session: WebSession) -> WKWebsiteDataStore {
        // Persistent and isolated. Each account gets its own cookie jar, so
        // switching accounts never leaks one session into another.
        WKWebsiteDataStore(forIdentifier: session.id)
    }

    func add(service: String, displayName: String) -> WebSession {
        let s = WebSession(id: UUID(), service: service, displayName: displayName)
        sessions.append(s)
        save()
        return s
    }

    /// Signing out must actually destroy the session data, not just forget the
    /// row — otherwise the next account created could inherit cookies.
    func remove(_ session: WebSession) async {
        sessions.removeAll { $0.id == session.id }
        save()
        try? await WKWebsiteDataStore.remove(forIdentifier: session.id)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([WebSession].self, from: data)
        else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
