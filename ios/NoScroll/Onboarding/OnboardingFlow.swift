import SwiftUI

/// The first-run flow, in order:
///
///   welcome → how much do you scroll → how old are you → this is your life
///   → pick the apps → grant Screen Time → ad blocking → widgets
///
/// The three permission pages carry the 3-dot indicator; the four persuasion
/// pages do not, because they are a narrative rather than a checklist.
struct OnboardingFlow: View {
    @EnvironmentObject private var state: AppState
    @Binding var isPresented: Bool

    enum Step: Int, CaseIterable {
        case welcome, scrollTime, life, pickApps, screenTime, adBlocking, widgets
    }

    @State private var step: Step = .welcome
    @State private var showAgeSheet = false

    /// QA hook: `simctl launch app.noscroll --step life` opens a page directly,
    /// so screenshot runs don't depend on tapping through the whole flow.
    private var launchStep: Step? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--step"), i + 1 < args.count else { return nil }
        let names: [String: Step] = [
            "welcome": .welcome, "scroll": .scrollTime, "life": .life,
            "pick": .pickApps, "screentime": .screenTime,
            "ads": .adBlocking, "widgets": .widgets,
        ]
        return names[args[i + 1]]
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
                    onContinue: { go(.pickApps) },
                    onBack: { go(.scrollTime) }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))

            case .pickApps:
                PickAppsScreen(onNext: { go(.screenTime) }, onSkip: { go(.screenTime) })
                    .transition(.move(edge: .trailing).combined(with: .opacity))

            case .screenTime:
                ScreenTimeScreen(onNext: { go(.adBlocking) }, onSkip: { go(.adBlocking) })
                    .transition(.move(edge: .trailing).combined(with: .opacity))

            case .adBlocking:
                AdBlockingScreen(onContinue: { go(.widgets) }, onSkip: { go(.widgets) })
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
        .onAppear { if let s = launchStep { step = s } }
        .animation(.snappy(duration: 0.35), value: step)
        .animation(.snappy(duration: 0.3), value: showAgeSheet)
        .interactiveDismissDisabled()
    }

    private func go(_ next: Step) { step = next }

    private func finish() {
        state.completeOnboarding()
        isPresented = false
    }
}

// MARK: - Permission pages

/// Choosing which apps NoScroll should stand in front of.
///
/// The real picker is Apple's `FamilyActivityPicker`, which requires the
/// FamilyControls entitlement. Until that is granted this explains the state
/// honestly instead of showing a picker that cannot work.
struct PickAppsScreen: View {
    @EnvironmentObject private var state: AppState
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PageDots(count: 3, index: 0).padding(.top, 6)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.free)
                .padding(.top, 18)

            Group {
                Text("Pick the apps you want to use ")
                    + Text("NoScroll").foregroundColor(Theme.free)
                    + Text(" with:")
            }
            .font(Theme.display(29))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.top, 12)

            pickerPreview.padding(.top, 22)

            Text(state.hasScreenTimeAccess
                 ? "Tap Select the apps below, then follow the steps."
                 : "Selecting apps needs Screen Time access, which comes next.")
                .font(Theme.body(16))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 16)

            Spacer()

            PrimaryButton(title: "Select the apps", action: onNext)
                .padding(.horizontal, 20)
            Button("Skip for now", action: onSkip)
                .font(Theme.body(17, .semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 14)
        }
        .padding(.bottom, 18)
        .background(Theme.paper)
    }

    /// A depiction of the system sheet, not a fake of it — it is visibly a
    /// preview inside a device frame so nobody mistakes it for the real prompt.
    private var pickerPreview: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Block apps").font(Theme.body(15, .semibold)).foregroundStyle(.white)
                Spacer()
                Text("Done")
                    .font(Theme.body(14, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.black.opacity(0.55), in: Capsule())
            }
            .padding(12)

            VStack(spacing: 0) {
                row("square.stack.3d.up.fill", "All Apps & Categories", highlighted: false)
                row("heart.text.square.fill", "Social", highlighted: true)
                row("gamecontroller.fill", "Games", highlighted: false)
                row("popcorn.fill", "Entertainment", highlighted: false)
            }
            .padding(10)
            .background(Color(hex: 0x2A2A2C), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .background(Color(hex: 0x161618), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 44)
    }

    private func row(_ symbol: String, _ title: String, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1.5).frame(width: 20, height: 20)
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.white.opacity(0.9))
                .frame(width: 22)
            Text(title).font(Theme.body(15)).foregroundStyle(.white.opacity(0.92))
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color(hex: 0x0A84FF), lineWidth: 2.5)
            }
        }
    }
}

/// Requesting Screen Time authorisation.
struct ScreenTimeScreen: View {
    @EnvironmentObject private var state: AppState
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var requesting = false

    var body: some View {
        VStack(spacing: 0) {
            PageDots(count: 3, index: 0).padding(.top, 6)

            Text("✋").font(.system(size: 30)).padding(.top, 18)

            Text("Lock the apps")
                .font(Theme.display(33))
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)

            Text("NoScroll needs Screen Time access to send Instagram, TikTok and YouTube back here.")
                .font(Theme.body(17))
                .foregroundStyle(Theme.ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.top, 10)

            Spacer()

            // The reassurance card mirrors Apple's own privacy nutrition wording,
            // and in our case it is literally true: there is no backend at all.
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: 0x0A84FF))
                Text("Social Media Platform Data Not Collected")
                    .font(Theme.body(15, .bold))
                    .foregroundStyle(Theme.ink)
                Text("The developer does not collect any data from social media platforms in this app.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 46)

            Text("Verified by Apple")
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 10)

            PrimaryButton(title: requesting ? "Requesting…" : "Grant access") {
                requesting = true
                Task {
                    await state.requestScreenTimeAccess()
                    requesting = false
                    onNext()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)

            Button("Skip for now", action: onSkip)
                .font(Theme.body(17, .semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 14)
        }
        .padding(.bottom, 18)
        .background(Theme.paper)
    }
}

/// Home-screen widgets that open a service straight through NoScroll.
struct WidgetsScreen: View {
    let onSetUp: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PageDots(count: 3, index: 2).padding(.top, 6)

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 18)

            Text("Add widgets")
                .font(Theme.display(33))
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)

            Text("One tap from your home screen straight into your apps — through NoScroll.")
                .font(Theme.body(17))
                .foregroundStyle(Theme.ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.top, 10)

            Spacer()

            widgetPreview

            Spacer()

            PrimaryButton(title: "Set it up", action: onSetUp)
                .padding(.horizontal, 20)
            SecondaryButton(title: "Maybe later", outlined: true, action: onLater)
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
        .padding(.bottom, 18)
        .background(Theme.paper)
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
            Label("NoScroll", systemImage: "square.grid.2x2.fill")
                .font(Theme.body(14, .bold))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(18)
        .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 24)
    }
}
