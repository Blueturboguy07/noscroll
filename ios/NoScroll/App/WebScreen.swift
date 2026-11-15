import SwiftUI
import WebKit

/// Hosts the wrapped browser and gives it a minimal chrome.
struct WebScreen: View {
    let service: AppState.Service

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var authSurfaceActive = false
    @State private var showPausedInfo = false

    var body: some View {
        NavigationStack {
            container
                .ignoresSafeArea(edges: .bottom)
                // Tell the user plainly that we have stepped back on their login page. It is the moment
                // they are most likely to suspect a wrapper of phishing them. One sign for every service:
                // a bar under the title with a short label, 44 pt high, that explains itself on a tap.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if authSurfaceActive { pausedSign }
                }
                .navigationTitle(service.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
                .alert("\(AppState.homeScreenName) is paused", isPresented: $showPausedInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("This is a sign-in page. \(AppState.appName) does not hide, read or change anything on it. Blocking starts again after you sign in.")
                }
        }
        .onAppear { state.didOpen(service) }
    }

    /// The paused sign: the same on every service.
    private var pausedSign: some View {
        Button { showPausedInfo = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Sign-in page: \(AppState.homeScreenName) is paused")
                    .font(Theme.body(15, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.paperRaised)
            .overlay(alignment: .bottom) { Divider() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sign-in page. \(AppState.appName) is paused and does not read this page.")
        .accessibilityHint("Shows more about the pause")
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
                description: Text("\(AppState.appName) refuses to open \(service.name) without a verified rule bundle.")
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
        let session = WebSession(id: service.sessionID, service: service.id, displayName: service.name)
        return WrappedWebViewController(
            session: session,
            startURL: service.home,
            dataStore: WKWebsiteDataStore(forIdentifier: service.sessionID),
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
                // A new page that is not a sign-in page: the engine starts there and says "ready" (it says
                // nothing about the sign-in page that came before), so the paused sign goes away.
                if case .ready = message {
                    Task { @MainActor in onAuthSurface(false) }
                }
            }
        )
    }

    func updateUIViewController(_ controller: WrappedWebViewController, context: Context) {}
}

/// True only in DEBUG builds. Used to switch on local diagnostic logging.
var isDebugBuild: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
}
