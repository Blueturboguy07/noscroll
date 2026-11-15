import SwiftUI

@main
struct NoScrollApp: App {
    @StateObject private var state = AppState()
    /// Sign in with publik (Publik/Publik.swift). PUBLIK_GATE_MODE (ios/Config/App.xcconfig) decides:
    /// required = the first screen, before any screen of the app's own; optional = a row in Settings.
    @StateObject private var gate = PublikGateModel()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(state)
                .environmentObject(gate)
                // Widgets deep-link straight into a service: noscroll://open/instagram
                // A link that comes during the sign-in waits in AppState until Home shows.
                .onOpenURL { state.handle(url: $0) }
        }
    }
}

/// One stable root view for the whole app. The gate, the first-run onboarding and the tabs are content
/// inside it: no window or root view controller swap, and no modal presentation for the onboarding, so
/// each screen gets its safe area from the window. The gate hands over only after its in-app browser has
/// closed completely (PublikGateModel.run()).
struct AppRoot: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var gate: PublikGateModel

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if gate.showsWall {
                PublikGateView(model: gate)
                    .transition(.opacity)
            } else if state.needsOnboarding {
                OnboardingFlow(isPresented: $state.needsOnboarding)
                    .transition(.opacity)
            } else {
                RootView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: gate.showsWall)
        .animation(.easeInOut(duration: 0.25), value: state.needsOnboarding)
        // Optional mode: no wall. A device that is already signed in starts usage counting.
        .task { await gate.resume() }
    }
}

/// Shell: three tabs (what's blocked, home, settings). The first-run onboarding comes before it (AppRoot).
struct RootView: View {
    @EnvironmentObject private var state: AppState

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
    }
}
