import SwiftUI

@main
struct NoScrollApp: App {
    @StateObject private var state = AppState()
    /// Sign in with publik (Publik/Publik.swift): the first screen, before any screen of NoScroll's own.
    @StateObject private var gate = PublikGateModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if gate.signedIn {
                    RootView()
                        .environmentObject(state)
                } else {
                    PublikGateView(model: gate)
                }
            }
            // Widgets deep-link straight into a service: noscroll://open/instagram
            // A link that comes during the sign-in waits in AppState until Home shows.
            .onOpenURL { state.handle(url: $0) }
        }
    }
}

/// Shell: five tabs, with first-run onboarding over the top.
struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView(selection: $state.tab) {
            SleepTab().tag(AppState.Tab.sleep)
                .tabItem { Image(systemName: "moon") }
            AllSettingsTab().tag(AppState.Tab.adjust)
                .tabItem { Image(systemName: "slider.horizontal.3") }
            HomeView().tag(AppState.Tab.home)
                .tabItem { Image(systemName: "house.fill") }
            ShieldTab().tag(AppState.Tab.shield)
                .tabItem { Image(systemName: "shield") }
            ProfileTab().tag(AppState.Tab.profile)
                .tabItem { Image(systemName: "person") }
        }
        .tint(Theme.ink)
        .fullScreenCover(isPresented: $state.needsOnboarding) {
            OnboardingFlow(isPresented: $state.needsOnboarding)
                .environmentObject(state)
        }
    }
}
