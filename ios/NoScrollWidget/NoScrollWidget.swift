import SwiftUI
import WidgetKit

/// Home-screen shortcuts that open a service *through* NoScroll.
///
/// The point is to intercept the habit at its origin. The muscle memory is
/// "tap the icon in that corner of the home screen", so putting NoScroll's own
/// icons in that corner is what actually changes the behaviour — a blocker you
/// have to remember to open is a blocker you stop opening.
///
/// Each tile is a `Link` to `noscroll://open/<service>`, handled in RootView.
struct ServiceEntry: TimelineEntry {
    let date: Date
    let services: [WidgetService]
}

/// Duplicated rather than shared: an extension binary cannot import the app
/// target, and the alternative — a framework target — is more machinery than
/// four names and four colours deserve.
struct WidgetService: Identifiable, Hashable {
    let id: String
    let name: String
    let start: Color
    let end: Color

    static let all: [WidgetService] = [
        .init(id: "instagram", name: "Instagram",
              start: Color(red: 0.88, green: 0.19, blue: 0.42),
              end: Color(red: 0.97, green: 0.47, blue: 0.22)),
        .init(id: "youtube", name: "YouTube",
              start: Color(red: 0.88, green: 0.18, blue: 0.18),
              end: Color(red: 0.62, green: 0.11, blue: 0.11)),
        .init(id: "x", name: "X",
              start: Color(red: 0.17, green: 0.17, blue: 0.17),
              end: Color(red: 0.04, green: 0.04, blue: 0.04)),
        .init(id: "tiktok", name: "TikTok",
              start: Color(red: 0.15, green: 0.96, blue: 0.93),
              end: Color(red: 1.00, green: 0.17, blue: 0.33)),
        .init(id: "reddit", name: "Reddit",
              start: Color(red: 1.00, green: 0.27, blue: 0.00),
              end: Color(red: 0.76, green: 0.23, blue: 0.00)),
        .init(id: "facebook", name: "Facebook",
              start: Color(red: 0.26, green: 0.40, blue: 0.70),
              end: Color(red: 0.11, green: 0.21, blue: 0.34)),
    ]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ServiceEntry {
        ServiceEntry(date: Date(), services: Array(WidgetService.all.prefix(4)))
    }

    func getSnapshot(in context: Context, completion: @escaping (ServiceEntry) -> Void) {
        completion(placeholder(in: context))
    }

    /// Static content, so a single entry that never expires: re-rendering a row
    /// of shortcuts on a timeline would burn budget for no change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ServiceEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}

struct NoScrollWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ServiceEntry

    private var shown: [WidgetService] {
        switch family {
        case .systemSmall: return Array(entry.services.prefix(1))
        case .systemMedium: return Array(entry.services.prefix(4))
        default: return Array(entry.services.prefix(6))
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if family == .systemSmall {
                tile(shown[0], size: 62)
                Text(shown[0].name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            } else {
                HStack(spacing: 14) {
                    ForEach(shown) { service in
                        VStack(spacing: 6) {
                            tile(service, size: 48)
                            Text(service.name)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                Label("NoScroll", systemImage: "square.grid.2x2.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(Color(red: 0.97, green: 0.94, blue: 0.88), for: .widget)
    }

    private func tile(_ service: WidgetService, size: CGFloat) -> some View {
        Link(destination: URL(string: "noscroll://open/\(service.id)")!) {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [service.start, service.end],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay {
                    Text(String(service.name.prefix(1)))
                        .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
        }
    }
}

struct NoScrollWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.noscroll.shortcuts", provider: Provider()) { entry in
            NoScrollWidgetView(entry: entry)
        }
        .configurationDisplayName("NoScroll shortcuts")
        .description("Open your apps through NoScroll, straight from the home screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct NoScrollWidgetBundle: WidgetBundle {
    var body: some Widget { NoScrollWidget() }
}
