import SwiftUI

@main
struct NoScrollApp: App {
    @StateObject private var state = AppState()
    /// Sign in with publik (Publik/Publik.swift). PUBLIK_GATE_MODE (ios/Config/App.xcconfig) decides:
    /// required = the first screen, before any screen of the app's own; optional = a row in Settings.
    @StateObject private var gate = PublikGateModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if gate.showsWall {
                    PublikGateView(model: gate)
                } else {
                    RootView()
                        .environmentObject(state)
                        .environmentObject(gate)
                }
            }
            // Widgets deep-link straight into a service: noscroll://open/instagram
            // A link that comes during the sign-in waits in AppState until Home shows.
            .onOpenURL { state.handle(url: $0) }
        }
    }
}

/// Shell: three tabs (what's blocked, home, settings), with first-run onboarding over the top.
struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var gate: PublikGateModel

    var body: some View {
        TabView(selection: $state.tab) {
            AllSettingsTab().tag(AppState.Tab.adjust)
                .tabItem { Label("Blocks", systemImage: "slider.horizontal.3") }
            HomeView().tag(AppState.Tab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }
            ProfileTab().tag(AppState.Tab.profile)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.ink)
        .fullScreenCover(isPresented: $state.needsOnboarding) {
            OnboardingFlow(isPresented: $state.needsOnboarding)
                .environmentObject(state)
        }
        // Optional mode: no wall. A device that is already signed in starts usage counting.
        .task { await gate.resume() }
    }
}
