import SwiftUI

@main
struct NoScrollApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(state)
        }
    }
}

/// The service picker.
///
/// Deliberately calm: no streak counter, no "hours saved" number, no nagging.
/// The complaints against the app this clones cluster around feeling
/// manipulated, and a dashboard that scores you is how that starts.
struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var showSettings = false
    @State private var openService: AppState.Service?

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let error = state.loadError {
                        errorCard(error)
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AppState.services) { service in
                            Button { openService = service } label: { tile(service) }
                                .buttonStyle(.plain)
                        }
                    }

                    footer
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: $state.needsOnboarding) {
                OnboardingView(isPresented: $state.needsOnboarding)
            }
            .fullScreenCover(item: $openService) { service in
                WebScreen(service: service)
            }
            .task {
                // QA hook: `simctl launch app.noscroll --open instagram` jumps
                // straight into a service, so screenshot runs and manual smoke
                // tests are deterministic instead of coordinate-tapping.
                let args = ProcessInfo.processInfo.arguments
                guard let i = args.firstIndex(of: "--open"), i + 1 < args.count else { return }
                openService = AppState.services.first { $0.id == args[i + 1] }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NoScroll").font(.largeTitle.bold())
            Text("The parts you came for. Not the parts that keep you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func tile(_ service: AppState.Service) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: service.symbol)
                .font(.system(size: 26))
                .foregroundStyle(service.tint)
            Text(service.name).font(.headline)
            Text(blockedSummary(for: service.id))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func blockedSummary(for id: String) -> String {
        let all = state.surfaces(for: id)
        guard !all.isEmpty else { return "Rules unavailable" }
        let on = all.filter { state.binding(service: id, surfaces: $0.keys).wrappedValue }.count
        return "\(on) of \(all.count) blocks on"
    }

    private func errorCard(_ message: String) -> some View {
        // A bundle that fails verification is refused rather than silently
        // browsed around — say so instead of pretending everything is fine.
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Your session stays on this device", systemImage: "lock.fill")
                .font(.footnote.weight(.medium))
            Text("You sign in on Instagram's and YouTube's own pages. NoScroll never reads those pages, and nothing you browse is sent anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}
