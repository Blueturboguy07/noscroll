import SwiftUI

// MARK: - Welcome

/// "Same apps. No algorithm."
struct WelcomeScreen: View {
    let onStart: () -> Void

    @State private var appear = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x2C2A26), Color(hex: 0x4A443A), Color(hex: 0x6E6553)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Text(AppState.appName)
                    .font(Theme.display(40))
                    .tracking(3)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 16)
                    #if PUBLIK_TEST_HOOKS
                    .background {
                        GeometryReader { g in
                            Color.clear
                                .onAppear { LayoutProbe.titleY = g.frame(in: .global).minY }
                                .onChange(of: g.frame(in: .global).minY) { _, y in LayoutProbe.titleY = y }
                        }
                    }
                    #endif
                    .padding(.top, 12)

                Spacer()

                VStack(spacing: 22) {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color(hex: 0x141317))
                        .frame(width: 118, height: 118)
                        .overlay {
                            // The app mark: a scrollbar parked at the bottom.
                            ZStack {
                                Capsule().fill(.white.opacity(0.26))
                                    .frame(width: 26, height: 68)
                                Capsule().fill(.white)
                                    .frame(width: 18, height: 24)
                                    .offset(y: 20)
                            }
                        }
                        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
                        .scaleEffect(appear ? 1 : 0.86)
                        .opacity(appear ? 1 : 0)

                    Text("Same apps. No algorithm.")
                        .font(Theme.display(25, .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .opacity(appear ? 1 : 0)
                }

                Spacer()
                Spacer()

                PrimaryButton(title: "Take your life back",
                              tint: Theme.paperRaised, foreground: Theme.ink,
                              action: onStart)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 18)
        }
        .task {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { appear = true }
        }
    }
}

// MARK: - Scroll time

/// "How much time do you spend scrolling per day?"
struct ScrollTimeScreen: View {
    @Binding var hours: Double
    let onContinue: () -> Void
    let onBack: () -> Void

    private let range: ClosedRange<Double> = 1...8
    private let average: Double = 4.8

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .font(Theme.body(17, .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.trailing, 12)
                        .tapTarget()
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 18)

            Text("ABOUT YOU")
                .font(Theme.eyebrow())
                .tracking(2.6)
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 18)

            Text("How much time do you spend scrolling per day?")
                .font(Theme.display(29))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 10)

            VStack(spacing: 0) {
                Text(hours >= 8 ? "8+ hours" : String(format: "%.1f hours", hours))
                    .font(Theme.display(52))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text("per day")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.top, 30)

            VStack(spacing: 8) {
                // Always in the layout (only its opacity changes), so the slider never moves under the finger.
                let atAverage = abs(hours - average) < 0.25
                Text("This is the average")
                    .font(Theme.body(13, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.scrolling, in: Capsule())
                    .scaleEffect(atAverage ? 1 : 0.85)
                    .opacity(atAverage ? 1 : 0)
                    .accessibilityHidden(!atAverage)
                Slider(value: $hours, in: range, step: 0.1)
                    .tint(Theme.ink)
                HStack {
                    Text("1 hr")
                    Spacer()
                    Text("8+ hrs")
                }
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .animation(.snappy, value: abs(hours - average) < 0.25)

            Text("Be honest.")
                .font(Theme.body(17, .medium))
                .italic()
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 26)

            Spacer()

            PrimaryButton(title: "Look into the future", action: onContinue)
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 18)
        .background(Theme.paper)
    }
}

// MARK: - Age

/// Asked only to draw the grid — and the copy says so, because asking a stranger
/// their age immediately after install needs a reason attached.
struct AgeSheet: View {
    @Binding var age: Int
    let onConfirm: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 26)

            Text("How old are you?")
                .font(Theme.display(31))
                .foregroundStyle(Theme.ink)
                .padding(.top, 14)

            Text("Used only to draw your life. Your age stays on this phone.")
                .font(Theme.body(16))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.top, 8)

            Picker("Age", selection: $age) {
                ForEach(10...89, id: \.self) { n in
                    Text("\(n)").font(Theme.display(24, .bold)).tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            .padding(.top, 6)

            PrimaryButton(title: "Show me my life", action: onConfirm)
                .padding(.horizontal, 22)
                .padding(.top, 4)

            Button(action: onSkip) {
                Text("Skip")
                    .font(Theme.body(17, .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .tapTarget(minWidth: 88)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
        }
        .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.22), radius: 30, y: 10)
    }
}
