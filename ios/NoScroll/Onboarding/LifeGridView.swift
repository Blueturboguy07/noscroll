import SwiftUI

/// "This is your life. Each box is a week."
///
/// ~4,700 boxes, so this draws in a single `Canvas` rather than 4,700 SwiftUI
/// views — a LazyVGrid at this count drops frames on older phones, and the whole
/// point of the screen is the build-up animation being smooth.
///
/// The build reads bottom-up: bands fill in order, then the percentage lands.
/// That ordering is deliberate — the boxes have to feel like they are stacking
/// into a life before the number tells you what happened to it.
struct LifeGridView: View {
    let life: LifeInWeeks
    /// 0...1 fill progress, animated by the parent.
    var progress: Double

    private let columns = 52
    private let spacing: CGFloat = 1.6

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let cols = CGFloat(columns)
            let cell = (size.width - spacing * (cols - 1)) / cols
            guard cell > 0 else { return }
            let radius = cell * 0.34

            let shown = Int((Double(life.totalWeeks) * progress).rounded())
            guard shown > 0 else { return }

            // Group by band so the fill colour is resolved once per band, not
            // once per box.
            var index = 0
            for band in life.bands {
                guard band.weeks > 0 else { continue }
                let colour = Self.colour(for: band.kind)
                var path = Path()
                let end = min(index + band.weeks, shown)
                if index >= shown { break }
                for i in index..<end {
                    let row = i / columns
                    let col = i % columns
                    let x = CGFloat(col) * (cell + spacing)
                    let y = CGFloat(row) * (cell + spacing)
                    path.addRoundedRect(
                        in: CGRect(x: x, y: y, width: cell, height: cell),
                        cornerSize: CGSize(width: radius, height: radius)
                    )
                }
                context.fill(path, with: .color(colour))
                index += band.weeks
            }
        }
        .aspectRatio(gridAspect, contentMode: .fit)
        .accessibilityLabel(accessibilitySummary)
    }

    private var rows: Int {
        Int((Double(life.totalWeeks) / Double(columns)).rounded(.up))
    }

    private var gridAspect: CGFloat {
        // width : height, from the cell grid itself so nothing is squashed.
        CGFloat(columns) / CGFloat(max(rows, 1))
    }

    private var accessibilitySummary: String {
        let years = Int(life.yearsLostToScrolling.rounded())
        return "Your life in weeks. \(life.scrollPercent) percent of your free time, "
            + "about \(years) years, goes to scrolling."
    }

    static func colour(for kind: LifeInWeeks.Kind) -> Color {
        switch kind {
        case .past: return Theme.past
        case .sleep: return Theme.sleep
        case .work: return Theme.work
        case .hygiene: return Theme.hygiene
        case .scrolling: return Theme.scrolling
        case .free: return Theme.free
        }
    }

    static func label(for kind: LifeInWeeks.Kind) -> String {
        switch kind {
        case .past: return "Past"
        case .sleep: return "Sleep"
        case .work: return "Work"
        case .hygiene: return "Hygiene"
        case .scrolling: return "Scrolling"
        case .free: return "Free"
        }
    }
}

/// The full screen: eyebrow, grid with side labels, the number, legend, CTA.
struct LifeScreen: View {
    let life: LifeInWeeks
    let onContinue: () -> Void
    var onBack: (() -> Void)?

    @State private var fill: Double = 0
    @State private var revealNumber = false

    var body: some View {
        VStack(spacing: 0) {
            header

            // Labels are overlaid on the grid, not laid out beside it: they must
            // map onto the GRID's height, and a sibling column stretches to the
            // row height instead, which slid every label down a band.
            LifeGridView(life: life, progress: fill)
                .overlay { bandLabels }
                .padding(.horizontal, 66)

            Spacer(minLength: 8)
            number
            legend.padding(.top, 12)
            Spacer(minLength: 8)

            PrimaryButton(title: "Take it back", tint: Theme.scrolling, foreground: .white) {
                onContinue()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Theme.paper)
        .task { await runBuildAnimation() }
    }

    private func runBuildAnimation() async {
        // Build the grid from the ground up, then land the number.
        withAnimation(.easeOut(duration: 2.1)) { fill = 1 }
        try? await Task.sleep(for: .milliseconds(1900))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { revealNumber = true }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("THIS IS YOUR LIFE")
                    .font(Theme.eyebrow())
                    .tracking(2.6)
                    .foregroundStyle(Theme.inkSoft)
                Text("Each box is a week")
                    .font(Theme.body(17, .semibold))
                    .foregroundStyle(Theme.ink)
            }
            if let onBack {
                HStack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(Theme.body(17, .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    /// Year counts on the left, band names on the right, each sitting at the
    /// vertical midpoint of its own colour run.
    private var bandLabels: some View {
        GeometryReader { geo in
            let total = CGFloat(max(life.totalWeeks, 1))
            ForEach(labelled) { band in
                let mid = (CGFloat(weeksBefore(band)) + CGFloat(band.weeks) / 2) / total
                let y = mid * geo.size.height

                Text("\(band.roundedYears)yrs")
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 58, alignment: .trailing)
                    .position(x: -33, y: y)

                Text(LifeGridView.label(for: band.kind))
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 66, alignment: .leading)
                    .position(x: geo.size.width + 39, y: y)
            }
        }
    }

    /// Bands large enough to carry a label without colliding with its neighbour.
    private var labelled: [LifeInWeeks.Band] {
        life.bands.filter { $0.kind != .free && $0.weeks > 120 }
    }

    private func weeksBefore(_ band: LifeInWeeks.Band) -> Int {
        var n = 0
        for b in life.bands {
            if b.kind == band.kind { break }
            n += b.weeks
        }
        return n
    }

    private var number: some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 0) {
                Text("\(life.scrollPercent)")
                    .font(Theme.display(78))
                Text("%")
                    .font(Theme.display(34))
                    .padding(.top, 12)
            }
            .foregroundStyle(Theme.scrolling)

            Text("of your free time. Gone to scrolling.")
                .font(Theme.display(19, .bold))
                .foregroundStyle(Theme.ink)
        }
        .opacity(revealNumber ? 1 : 0)
        .scaleEffect(revealNumber ? 1 : 0.82)
    }

    private var legend: some View {
        HStack(spacing: 0) {
            ForEach(life.bands) { band in
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LifeGridView.colour(for: band.kind))
                        .frame(width: 13, height: 13)
                    Text(LifeGridView.label(for: band.kind))
                        .font(Theme.body(12, .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
    }
}
