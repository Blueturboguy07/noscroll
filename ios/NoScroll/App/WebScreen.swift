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

    /// Stable per-service identifier so the session survives cold launch.
    /// iOS 17+ named data stores are what make this persistent AND isolated.
    private var sessionID: UUID {
        switch service.id {
        case "instagram": return UUID(uuidString: "A1B2C3D4-0001-4000-8000-000000000001")!
        case "youtube": return UUID(uuidString: "A1B2C3D4-0002-4000-8000-000000000002")!
        default: return UUID(uuidString: "A1B2C3D4-0000-4000-8000-000000000000")!
        }
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
