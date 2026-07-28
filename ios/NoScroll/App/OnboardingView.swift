import SwiftUI

/// First-run setup.
///
/// The product has an opinion — the core blocks arrive switched on — but it does
/// not take the choice away. Nothing is locked, and onboarding is where the user
/// sees every switch once and decides, rather than discovering later that
/// something was forced on them.
///
/// Deliberately: no account, no email, no "allow notifications" prompt, no
/// upsell. Two screens and out.
struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @Binding var isPresented: Bool

    @State private var page = 0

    /// QA hook, mirroring RootView's: `--onboarding-page 1` opens the choices
    /// screen directly so screenshot runs don't depend on tapping.
    private var initialPage: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--onboarding-page"), i + 1 < args.count,
              let n = Int(args[i + 1]) else { return 0 }
        return n
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                choices.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .onAppear { page = initialPage }

            Button(page == 0 ? "Choose what to block" : "Start using NoScroll") {
                if page == 0 {
                    withAnimation { page = 1 }
                } else {
                    state.completeOnboarding()
                    isPresented = false
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Color(.systemBackground))
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("NoScroll")
                .font(.system(size: 44, weight: .bold))
            Text("The parts you came for.\nNot the parts that keep you.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                point("rectangle.on.rectangle.slash",
                      "Reels, Shorts and Explore are gone",
                      "Not greyed out — removed from the page.")
                point("bubble.left.and.bubble.right",
                      "Messages and your friends stay",
                      "You keep the people you chose to follow.")
                point("lock",
                      "You sign in on their pages, not ours",
                      "Your session never leaves this device, and NoScroll doesn't read login pages.")
            }
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 26)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What should NoScroll block?")
                    .font(.title2.bold())
                Text("These are our suggestions. Change any of them now, or later in Settings — nothing here is permanent.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 12)

            List {
                ForEach(AppState.services) { service in
                    Section {
                        ForEach(state.surfaces(for: service.id)) { group in
                            Toggle(group.label,
                                   isOn: state.binding(service: service.id, surfaces: group.keys))
                        }
                    } header: {
                        Label(service.name, systemImage: service.symbol)
                            .foregroundStyle(service.tint)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}
