import SwiftUI
import WebKit

/// Hosts the wrapped browser and gives it a minimal chrome.
struct WebScreen: View {
    let service: AppState.Service

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var authSurfaceActive = false

    var body: some View {
        NavigationStack {
            container
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(service.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if authSurfaceActive {
                            // Tell the user plainly that we have stepped back on
                            // their login page. It is the moment they are most
                            // likely to suspect a wrapper of phishing them.
                            Label("Sign-in page — NoScroll is paused", systemImage: "lock.open")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Sign-in page. NoScroll is paused and is not reading this page.")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var container: some View {
        if let raw = state.rawBundles[service.id] {
            WebViewContainer(
                service: service,
                engineSource: state.engineSource,
                bundleRaw: raw,
                settings: state.settings,
                onAuthSurface: { authSurfaceActive = $0 }
            )
        } else {
            ContentUnavailableView(
                "Rules unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("NoScroll refuses to open \(service.name) without a verified rule bundle.")
            )
        }
    }
}

/// Bridges the UIKit web controller into SwiftUI.
struct WebViewContainer: UIViewControllerRepresentable {
    let service: AppState.Service
    let engineSource: String
    let bundleRaw: Data
    let settings: [String: Bool]
    let onAuthSurface: (Bool) -> Void

    func makeUIViewController(context: Context) -> WrappedWebViewController {
        let session = WebSession(id: sessionID, service: service.id, displayName: service.name)
        return WrappedWebViewController(
            session: session,
            startURL: service.home,
            dataStore: WKWebsiteDataStore(forIdentifier: sessionID),
            engineSource: engineSource,
            bundleRaw: bundleRaw,
            settings: settings,
            // DEBUG enables the diagnostic message types so the console shows
            // what was blocked. There is no network sink anywhere in this app —
            // the bridge terminates in the native shell — so this is local
            // logging, not telemetry in the sense docs/PRIVACY.md disclaims.
            telemetry: isDebugBuild,
            onBridge: { message in
                #if DEBUG
                // Wiring proof: shows the engine really is running inside this
                // WKWebView, and what it removed. DEBUG only — see
                // docs/PRIVACY.md on what the bridge is permitted to carry.
                print("[NoScroll] \(message)")
                #endif
                if case let .authSurface(active) = message {
                    Task { @MainActor in onAuthSurface(active) }
                }
            }
        )
    }

    func updateUIViewController(_ controller: WrappedWebViewController, context: Context) {}

    /// Stable, DISTINCT per-service identifier so each service keeps its own
    /// persistent cookie jar and sessions survive a cold launch.
    ///
    /// Derived from the service id rather than a hand-maintained table: the
    /// table listed two services and gave every other one the same UUID, which
    /// meant six services shared a single cookie jar.
    private var sessionID: UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, byte) in Array(service.id.utf8).enumerated() {
            bytes[i % 16] = bytes[i % 16] &+ byte &* UInt8(truncatingIfNeeded: i &+ 1)
        }
        // Stamp RFC-4122 version/variant bits so it is a well-formed UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// True only in DEBUG builds. Used to switch on local diagnostic logging.
var isDebugBuild: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
}
