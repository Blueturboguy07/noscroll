import SwiftUI

/// The home screen: one service at a time in a horizontal carousel, with the
/// number of its blocks that are on above it and that service's settings below.
///
/// One service per page rather than a grid, because the grid invites browsing —
/// and an app about not browsing should open onto a decision, not a menu.
struct HomeView: View {
    @EnvironmentObject private var state: AppState

    @State private var selection: String = AppState.services[0].id
    @State private var openService: AppState.Service?
    @State private var showSettingsFor: AppState.Service?
    @State private var showWidgetBanner = true

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            if showWidgetBanner {
                widgetBanner.padding(.horizontal, 18).padding(.top, 4)
            }

            Spacer(minLength: 0)

            blocks
            carousel

            Spacer(minLength: 0)

            if let service = AppState.service(selection) {
                settingsCard(service)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .fullScreenCover(item: $openService) { WebScreen(service: $0) }
        .sheet(item: $showSettingsFor) { ServiceSettingsView(service: $0) }
        // A widget tap lands here: select that service and open it straight
        // away, so the shortcut is one tap rather than two.
        .onChange(of: state.pendingService) { _, id in openPending(id) }
        // A tap that came while Sign in with publik was on screen is already set.
        .onAppear { openPending(state.pendingService) }
    }

    private func openPending(_ id: String?) {
        guard let id, let service = AppState.service(id) else { return }
        selection = id
        openService = service
        state.pendingService = nil
    }

    // MARK: - Pieces

    private var titleBar: some View {
        HStack {
            Text(AppState.appName)
                .font(Theme.display(31))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                if let s = AppState.service(selection) { openService = s }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                        .font(.system(size: 13, weight: .bold))
                    Text("OPEN").font(Theme.display(14, .heavy)).tracking(1)
                }
                .foregroundStyle(Color(hex: 0x725A20)) // 5.2:1 on the capsule
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Color(hex: 0xF0E4C8), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(hex: 0xD9C79C), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    private var widgetBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(colors: [Color(hex: 0xE1306C), Color(hex: 0xF77737)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            Text("Add apps to your home screen")
                .font(Theme.display(16, .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                withAnimation(.snappy) { showWidgetBanner = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        // The 44 pt close button keeps the banner at its old height (58 pt).
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 7)
        .background(Theme.paperRaised.opacity(0.75), in: Capsule())
    }

    /// How many of this service's blocks are on. A real number from the
    /// switches; this build has no Screen Time, so it shows no time figure.
    private var blocks: some View {
        let count = state.blockCount(for: selection)
        return VStack(spacing: 2) {
            Text("\(AppState.service(selection)?.name.uppercased() ?? "") BLOCKS ON")
                .font(Theme.eyebrow(13))
                .tracking(2.2)
                .foregroundStyle(Theme.inkSoft)
            Text("\(count.on) of \(count.total)")
                .font(Theme.display(52))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Button {
                if let s = AppState.service(selection) { showSettingsFor = s }
            } label: {
                HStack(spacing: 3) {
                    Text("see details").font(Theme.body(15, .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 8)
                .tapTarget()
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 14)
    }

    private var carousel: some View {
        TabView(selection: $selection) {
            ForEach(AppState.services) { service in
                ServiceTile(service: service) { openService = service }
                    .tag(service.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .frame(height: 250)
        .animation(.snappy, value: selection)
    }

    private func settingsCard(_ service: AppState.Service) -> some View {
        Button { showSettingsFor = service } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(service.name) Settings")
                        .font(Theme.display(21, .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Customize what's blocked")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.ink.opacity(0.8))
                }
                Spacer()
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(18)
            .background(service.gradient.opacity(0.9),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

}

/// One service in the carousel.
struct ServiceTile: View {
    let service: AppState.Service
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onOpen) {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(service.gradient)
                    .frame(width: 152, height: 152)
                    .overlay {
                        // An SF Symbol, not the service's logo: the logos are not ours to copy.
                        Image(systemName: service.symbol)
                            .font(.system(size: 58, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Open \(service.name)")
                    .overlay(alignment: .bottom) {
                        if service.beta {
                            Text("BETA")
                                .font(Theme.display(11, .heavy))
                                .tracking(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.75), in: Capsule())
                                .offset(y: 10)
                        }
                    }
                    .shadow(color: service.tintDark.opacity(0.35), radius: 22, y: 12)
            }
            .buttonStyle(.plain)

            Text(service.name)
                .font(Theme.body(15, .semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 14)
        }
    }
}
