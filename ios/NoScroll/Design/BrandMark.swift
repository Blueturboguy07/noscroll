import SwiftUI

/// The service marks, drawn as vectors rather than shipped as bitmaps.
///
/// Nominative use: these identify which service a tile opens. They are drawn
/// from primitives at runtime, so no third-party artwork is redistributed in
/// the repository.
struct BrandMark: View {
    let service: String
    var size: CGFloat = 58

    var body: some View {
        Group {
            switch service {
            case "instagram": instagram
            case "youtube": youtube
            case "x": letterform("𝕏", weight: .heavy, scale: 0.92)
            case "tiktok": tiktok
            case "facebook": letterform("f", weight: .black, scale: 1.15, design: .default)
            case "linkedin": letterform("in", weight: .black, scale: 0.72)
            case "snapchat": snapchat
            case "reddit": reddit
            default: Image(systemName: "app.fill").font(.system(size: size))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(.white)
    }

    // MARK: - Letterform marks

    private func letterform(_ text: String, weight: Font.Weight,
                            scale: CGFloat, design: Font.Design = .rounded) -> some View {
        Text(text)
            .font(.system(size: size * scale, weight: weight, design: design))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
    }

    // MARK: - Drawn marks

    /// Rounded-square outline, ring, and lens dot.
    private var instagram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(.white, lineWidth: size * 0.095)
            Circle()
                .strokeBorder(.white, lineWidth: size * 0.095)
                .frame(width: size * 0.44, height: size * 0.44)
            Circle()
                .fill(.white)
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: size * 0.22, y: -size * 0.22)
        }
    }

    /// Rounded rectangle with a play triangle knocked out.
    private var youtube: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(.white)
            .frame(width: size, height: size * 0.7)
            .overlay {
                Triangle()
                    .fill(Color(hex: 0xE02F2F))
                    .frame(width: size * 0.24, height: size * 0.28)
                    .offset(x: size * 0.02)
            }
    }

    /// The note: a stem with a hooked flag and a filled head.
    private var tiktok: some View {
        ZStack {
            Path { p in
                let s = size
                p.move(to: CGPoint(x: s * 0.52, y: s * 0.12))
                p.addLine(to: CGPoint(x: s * 0.52, y: s * 0.66))
                p.addQuadCurve(to: CGPoint(x: s * 0.66, y: s * 0.30),
                               control: CGPoint(x: s * 0.78, y: s * 0.58))
                p.addQuadCurve(to: CGPoint(x: s * 0.84, y: s * 0.34),
                               control: CGPoint(x: s * 0.74, y: s * 0.30))
                p.addQuadCurve(to: CGPoint(x: s * 0.64, y: s * 0.12),
                               control: CGPoint(x: s * 0.66, y: s * 0.20))
                p.closeSubpath()
            }
            .fill(.white)

            Circle()
                .strokeBorder(.white, lineWidth: size * 0.11)
                .frame(width: size * 0.4, height: size * 0.4)
                .offset(x: -size * 0.13, y: size * 0.22)
        }
    }

    /// Rounded head with a wavy hem.
    private var snapchat: some View {
        Path { p in
            let s = size
            p.move(to: CGPoint(x: s * 0.5, y: s * 0.08))
            p.addQuadCurve(to: CGPoint(x: s * 0.86, y: s * 0.52),
                           control: CGPoint(x: s * 0.88, y: s * 0.12))
            p.addLine(to: CGPoint(x: s * 0.9, y: s * 0.74))
            p.addQuadCurve(to: CGPoint(x: s * 0.72, y: s * 0.8),
                           control: CGPoint(x: s * 0.8, y: s * 0.84))
            p.addQuadCurve(to: CGPoint(x: s * 0.5, y: s * 0.86),
                           control: CGPoint(x: s * 0.6, y: s * 0.9))
            p.addQuadCurve(to: CGPoint(x: s * 0.28, y: s * 0.8),
                           control: CGPoint(x: s * 0.4, y: s * 0.9))
            p.addQuadCurve(to: CGPoint(x: s * 0.1, y: s * 0.74),
                           control: CGPoint(x: s * 0.2, y: s * 0.84))
            p.addLine(to: CGPoint(x: s * 0.14, y: s * 0.52))
            p.addQuadCurve(to: CGPoint(x: s * 0.5, y: s * 0.08),
                           control: CGPoint(x: s * 0.12, y: s * 0.12))
            p.closeSubpath()
        }
        .fill(.white)
    }

    /// Round head, antenna, two eyes.
    private var reddit: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: size * 0.82, height: size * 0.62)
                .offset(y: size * 0.1)
            Circle()
                .fill(.white)
                .frame(width: size * 0.13, height: size * 0.13)
                .offset(x: size * 0.2, y: -size * 0.3)
            Rectangle()
                .fill(.white)
                .frame(width: size * 0.05, height: size * 0.22)
                .offset(x: size * 0.11, y: -size * 0.21)
            HStack(spacing: size * 0.18) {
                Circle().fill(Color(hex: 0xFF4500)).frame(width: size * 0.12, height: size * 0.12)
                Circle().fill(Color(hex: 0xFF4500)).frame(width: size * 0.12, height: size * 0.12)
            }
            .offset(y: size * 0.06)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
