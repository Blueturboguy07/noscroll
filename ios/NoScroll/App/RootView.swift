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

/// Shell: the home carousel, with first-run onboarding over the top.
struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HomeView()
            .fullScreenCover(isPresented: $state.needsOnboarding) {
                OnboardingFlow(isPresented: $state.needsOnboarding)
                    .environmentObject(state)
            }
    }
}
