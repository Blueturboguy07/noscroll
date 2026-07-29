import SwiftUI

@main
struct NoScrollApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                // Widgets deep-link straight into a service: noscroll://open/instagram
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
