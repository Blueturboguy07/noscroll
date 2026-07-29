import CoreGraphics
import Foundation

/// A minimal SVG path-data parser.
///
/// Exists so brand marks can be real vectors rather than hand-drawn
/// approximations — my first attempt drew them from primitives and they looked
/// like clip art. These are the actual glyph outlines, scaled to any size with
/// no bitmap assets in the repository.
///
/// Supports exactly the command set the shipped marks use, in both absolute and
/// relative form: M L H V C S A Z. Anything else is ignored rather than
/// throwing, because a mark that renders slightly wrong is better than a crash.
public enum SVGPath {

    public static func cgPath(from d: String, viewBox: CGFloat = 24, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let scale = size / viewBox

        var current = CGPoint.zero
        var start = CGPoint.zero
        /// Reflection point for smooth curves (S).
        var lastControl: CGPoint?

        var command: Character = "M"
        let scanner = Scanner(d)

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale, y: y * scale)
        }

        while let next = scanner.peekCommandOrNumber() {
            if let c = next.command {
                command = c
                scanner.advance()
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    current = start
                    lastControl = nil
                    continue
                }
            }

            let relative = command.isLowercase
            let abs = Character(command.uppercased())

            switch abs {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                start = current
                path.move(to: pt(current.x, current.y))
                // A second coordinate pair after M is an implicit lineto.
                command = relative ? "l" : "L"
                lastControl = nil

            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: pt(current.x, current.y))
                lastControl = nil

            case "H":
                guard let x = scanner.number() else { return path }
                current.x = relative ? current.x + x : x
                path.addLine(to: pt(current.x, current.y))
                lastControl = nil

            case "V":
                guard let y = scanner.number() else { return path }
                current.y = relative ? current.y + y : y
                path.addLine(to: pt(current.x, current.y))
                lastControl = nil

            case "C":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = relative ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let c2 = relative ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addCurve(to: pt(end.x, end.y), control1: pt(c1.x, c1.y), control2: pt(c2.x, c2.y))
                current = end
                lastControl = c2

            case "S":
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                // First control is the reflection of the previous one.
                let c1 = lastControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                let c2 = relative ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addCurve(to: pt(end.x, end.y), control1: pt(c1.x, c1.y), control2: pt(c2.x, c2.y))
                current = end
                lastControl = c2

            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(),
                      let rot = scanner.number(), let large = scanner.number(),
                      let sweep = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                addArc(path, from: current, to: end, rx: rx, ry: ry,
                       rotation: rot, largeArc: large != 0, sweep: sweep != 0, scale: scale)
                current = end
                lastControl = nil

            default:
                scanner.advance()
            }
        }
        return path
    }

    /// Endpoint-parameterised arc → centre parameterisation, per the SVG spec's
    /// implementation notes (F.6.5). CoreGraphics has no endpoint arc.
    private static func addArc(_ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint,
                               rx: CGFloat, ry: CGFloat, rotation: CGFloat,
                               largeArc: Bool, sweep: Bool, scale: CGFloat) {
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 {
            path.addLine(to: CGPoint(x: p1.x * scale, y: p1.y * scale))
            return
        }

        let phi = rotation * .pi / 180
        let dx2 = (p0.x - p1.x) / 2, dy2 = (p0.y - p1.y) / 2
        let x1 = cos(phi) * dx2 + sin(phi) * dy2
        let y1 = -sin(phi) * dx2 + cos(phi) * dy2

        // Scale the radii up if they are too small to span the endpoints.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }

        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coef = sign * sqrt(den == 0 ? 0 : num / den)
        let cx1 = coef * rx * y1 / ry
        let cy1 = -coef * ry * x1 / rx

        let cx = cos(phi) * cx1 - sin(phi) * cy1 + (p0.x + p1.x) / 2
        let cy = sin(phi) * cx1 + cos(phi) * cy1 + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            guard len != 0 else { return 0 }
            let a = acos(min(1, max(-1, dot / len)))
            return (ux * vy - uy * vx < 0) ? -a : a
        }

        let startAngle = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // CGPath has no rotated-ellipse arc either, so transform a unit circle.
        let transform = CGAffineTransform(translationX: cx * scale, y: cy * scale)
            .rotated(by: phi)
            .scaledBy(x: rx * scale, y: ry * scale)
        path.addRelativeArc(center: .zero, radius: 1,
                            startAngle: startAngle, delta: delta,
                            transform: transform)
    }
}

/// Tiny cursor over path data. Numbers may be separated by spaces, commas, or
/// nothing at all (`.5.5` is two numbers), which is why this is hand-rolled.
private final class Scanner {
    private let chars: [Character]
    private var i = 0

    init(_ s: String) { chars = Array(s) }

    struct Token {
        let command: Character?
    }

    func peekCommandOrNumber() -> Token? {
        skipSeparators()
        guard i < chars.count else { return nil }
        let c = chars[i]
        if c.isLetter { return Token(command: c) }
        return Token(command: nil)
    }

    func advance() { if i < chars.count { i += 1 } }

    func number() -> CGFloat? {
        skipSeparators()
        guard i < chars.count else { return nil }
        var s = ""
        if chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
        var seenDot = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber {
                s.append(c); i += 1
            } else if c == "." && !seenDot {
                seenDot = true; s.append(c); i += 1
            } else if c == "." && seenDot {
                break  // `.5.5` — the second dot starts a new number
            } else if (c == "e" || c == "E"), i + 1 < chars.count {
                s.append(c); i += 1
                if chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            } else {
                break
            }
        }
        return Double(s).map { CGFloat($0) }
    }

    private func skipSeparators() {
        while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" {
            i += 1
        }
    }
}
