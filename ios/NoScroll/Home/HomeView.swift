import SwiftUI

/// The home screen: one service at a time in a horizontal carousel, with today's
/// usage above it and that service's settings below.
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

            usage
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
        .onChange(of: state.pendingService) { _, id in
            guard let id, let service = AppState.service(id) else { return }
            selection = id
            openService = service
            state.pendingService = nil
        }
    }

    // MARK: - Pieces

    private var titleBar: some View {
        HStack {
            Text("NoScroll")
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
                .foregroundStyle(Color(hex: 0x9A7B34))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.paperRaised.opacity(0.75), in: Capsule())
    }

    private var usage: some View {
        VStack(spacing: 2) {
            Text("\(AppState.service(selection)?.name.uppercased() ?? "") TODAY")
                .font(Theme.eyebrow(13))
                .tracking(2.2)
                .foregroundStyle(Theme.inkSoft)
            Text(state.usageToday(for: selection))
                .font(Theme.display(52))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            // Requires the FamilyControls entitlement; until it lands this reads
            // "—" rather than inventing a number.
            Button {
                if let s = AppState.service(selection) { showSettingsFor = s }
            } label: {
                HStack(spacing: 3) {
                    Text("see details").font(Theme.body(15, .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.inkSoft)
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
                        .foregroundStyle(Theme.ink.opacity(0.55))
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
                    .overlay { BrandMark(service: service.id, size: 62) }
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

            if service.id == "instagram" {
                Label("switch accounts", systemImage: "person.2.circle")
                    .font(Theme.body(14, .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 14)
            }
        }
    }
}
