import SwiftUI
import UIKit

/// The first-run flow, in order:
///
///   welcome → how much do you scroll → how old are you → this is your life
///   → widgets
///
/// Version 1 has no Screen Time step: the shield needs Apple's Family Controls
/// entitlement, which this build does not have (docs/ENTITLEMENT.md). It also
/// has no ad-blocking step: hiding ads conflicts with the services' terms.
struct OnboardingFlow: View {
    @EnvironmentObject private var state: AppState
    @Binding var isPresented: Bool

    enum Step: Int, CaseIterable {
        case welcome, scrollTime, life, widgets
    }

    @State private var step: Step = .welcome
    @State private var showAgeSheet = false

    /// QA hook: `simctl launch app.noscroll --step life` opens a page directly,
    /// so screenshot runs don't depend on tapping through the whole flow.
    /// Test builds only (PUBLIK_TEST_HOOKS); the App Store build has no hidden hooks.
    private var launchStep: Step? {
        #if !PUBLIK_TEST_HOOKS
        return nil
        #else
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--step"), i + 1 < args.count else { return nil }
        let names: [String: Step] = [
            "welcome": .welcome, "scroll": .scrollTime, "life": .life,
            "widgets": .widgets,
        ]
        return names[args[i + 1]]
        #endif
    }

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()

            switch step {
            case .welcome:
                WelcomeScreen { go(.scrollTime) }
                    .transition(.opacity)

            case .scrollTime:
                ScrollTimeScreen(
                    hours: $state.scrollHoursPerDay,
                    onContinue: { showAgeSheet = true },
                    onBack: { go(.welcome) }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))

            case .life:
                LifeScreen(
                    life: LifeInWeeks(age: state.age, scrollHoursPerDay: state.scrollHoursPerDay),
                    onContinue: { go(.widgets) },
                    onBack: { go(.scrollTime) }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))

            case .widgets:
                WidgetsScreen(onSetUp: finish, onLater: finish)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if showAgeSheet {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                AgeSheet(
                    age: $state.age,
                    onConfirm: { showAgeSheet = false; go(.life) },
                    onSkip: { showAgeSheet = false; go(.life) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if PUBLIK_TEST_HOOKS
        // The PUBLIK_LAYOUT_PROBE hook: the safe area this screen got (CI: it must not be 0 after the gate passes).
        // The reader must respect the safe area: a reader that ignores it reports 0.
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { LayoutProbe.safeTop = g.safeAreaInsets.top; LayoutProbe.start() }
                    .onChange(of: g.safeAreaInsets.top) { _, top in LayoutProbe.safeTop = top }
            }
        }
        #endif
        .onAppear { if let s = launchStep { step = s } }
        .animation(.snappy(duration: 0.35), value: step)
        .animation(.snappy(duration: 0.3), value: showAgeSheet)
    }

    private func go(_ next: Step) { step = next }

    private func finish() {
        state.completeOnboarding()
        isPresented = false
    }
}

#if PUBLIK_TEST_HOOKS
/// The PUBLIK_LAYOUT_PROBE hook (test builds only): 1.5 s after the first onboarding screen appears, the app prints
/// "noscroll-layout: onboarding view-safe-top=<pt> window-safe-top=<pt> title-y=<pt>" and exits.
/// .github/scripts/ios-gate-layout-test.sh runs it right after a sign-in in the in-app browser.
enum LayoutProbe {
    // Written by the views (main thread), read once by the main-actor task below.
    nonisolated(unsafe) static var safeTop: CGFloat = -1
    nonisolated(unsafe) static var titleY: CGFloat = -1
    nonisolated(unsafe) private static var started = false

    static func start() {
        guard !started, Publik.hook("PUBLIK_LAYOUT_PROBE") != nil else { return }
        started = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
            print("noscroll-layout: onboarding view-safe-top=\(Int(safeTop)) window-safe-top=\(Int(window?.safeAreaInsets.top ?? -1)) title-y=\(Int(titleY))")
            exit(0)
        }
    }
}
#endif

// MARK: - Widgets

/// Home-screen widgets that open a service straight through the app.
struct WidgetsScreen: View {
    let onSetUp: () -> Void
    let onLater: () -> Void

    /// iOS exposes no way to open the widget gallery programmatically, so the
    /// honest version of "Set it up" is to show the three steps rather than
    /// pretend a button can do it.
    @State private var showSteps = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 24)

            Text("Add widgets")
                .font(Theme.display(33))
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)

            Text("One tap from your home screen straight into your apps — through \(AppState.appName).")
                .font(Theme.body(17))
                .foregroundStyle(Theme.ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.top, 10)

            Spacer()

            if showSteps {
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Touch and hold an empty part of your home screen")
                    step(2, "Tap Edit, then Add Widget")
                    step(3, "Search for \(AppState.homeScreenName) and add it")
                }
                .padding(.horizontal, 30)
                .transition(.opacity)
            } else {
                widgetPreview
            }

            Spacer()

            PrimaryButton(title: showSteps ? "Done" : "Set it up") {
                if showSteps { onSetUp() } else { showSteps = true }
            }
            .padding(.horizontal, 20)
            SecondaryButton(title: "Maybe later", outlined: true, action: onLater)
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
        .padding(.bottom, 18)
        .background(Theme.paper)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(Theme.display(15, .heavy))
                .foregroundStyle(Theme.paperRaised)
                .frame(width: 26, height: 26)
                .background(Theme.ink, in: Circle())
            Text(text)
                .font(Theme.body(16))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var widgetPreview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                ForEach(AppState.services.prefix(4)) { service in
                    VStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(service.gradient)
                            .frame(width: 54, height: 54)
                            .overlay {
                                Image(systemName: service.symbol)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        Text(service.name)
                            .font(Theme.body(12, .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            Label(AppState.homeScreenName, systemImage: "square.grid.2x2.fill")
                .font(Theme.body(14, .bold))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(18)
        .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 24)
    }
}
