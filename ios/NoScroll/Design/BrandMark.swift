import SwiftUI

/// A brand glyph, filled white, sized to fit.
struct BrandMark: View {
    let service: String
    var size: CGFloat = 58

    var body: some View {
        Group {
            if service == "linkedin" {
                linkedin
            } else if let d = BrandPaths.data[service] {
                BrandShape(pathData: d)
                    .fill(.white)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "app.fill").font(.system(size: size))
            }
        }
        .accessibilityHidden(true)
    }

    /// Rounded square with "in" knocked out — LinkedIn is the one mark with no
    /// openly redistributable outline.
    private var linkedin: some View {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
            .fill(.white)
            .frame(width: size, height: size)
            .overlay {
                Text("in")
                    .font(.system(size: size * 0.52, weight: .black, design: .default))
                    .foregroundStyle(Color(hex: 0x0A66C2))
                    .offset(y: -size * 0.02)
            }
    }
}

/// Renders 24x24 SVG path data at whatever size it is given.
struct BrandShape: Shape {
    let pathData: String

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let cg = SVGPath.cgPath(from: pathData, viewBox: 24, size: side)
        var p = Path(cg)
        // Centre it if the frame is not square.
        p = p.offsetBy(dx: (rect.width - side) / 2, dy: (rect.height - side) / 2)
        return p
    }
}
