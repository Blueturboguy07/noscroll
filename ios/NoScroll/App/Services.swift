import SwiftUI

extension AppState {

    /// The services NoScroll wraps.
    ///
    /// NOTE ON ICONS: these render as neutral colour tiles with an SF Symbol and
    /// the service name, not as the platforms' logos. Reproducing Instagram's or TikTok's mark — especially
    /// restyled into a 3D render — is exactly the trademark exposure that gets
    /// wrapper apps pulled, and docs/RULES.md commits us to nominative use only.
    /// The colour and the name are enough to identify the service; the logo is
    /// not ours to redraw.
    struct Service: Identifiable, Hashable {
        let id: String
        let name: String
        let home: URL
        let tint: Color
        let tintDark: Color
        let symbol: String
        /// Beta services are wrapped but not yet probe-verified against the live site.
        let beta: Bool

        var gradient: LinearGradient {
            LinearGradient(colors: [tint, tintDark], startPoint: .topLeading, endPoint: .bottomTrailing)
        }

        /// Stable, DISTINCT per-service identifier so each service keeps its own
        /// persistent cookie jar and sessions survive a cold launch. "Sign out"
        /// in Settings deletes the data in this store.
        ///
        /// Derived from the service id rather than a hand-maintained table: the
        /// table listed two services and gave every other one the same UUID, which
        /// meant six services shared a single cookie jar.
        var sessionID: UUID {
            var bytes = [UInt8](repeating: 0, count: 16)
            for (i, byte) in Array(id.utf8).enumerated() {
                bytes[i % 16] = bytes[i % 16] &+ byte &* UInt8(truncatingIfNeeded: i &+ 1)
            }
            // Stamp RFC-4122 version/variant bits so it is a well-formed UUID.
            bytes[6] = (bytes[6] & 0x0F) | 0x40
            bytes[8] = (bytes[8] & 0x3F) | 0x80
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                               bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                               bytes[12], bytes[13], bytes[14], bytes[15]))
        }
    }

    static let services: [Service] = [
        Service(id: "instagram", name: "Instagram",
                home: URL(string: "https://www.instagram.com/")!,
                tint: Color(hex: 0xE1306C), tintDark: Color(hex: 0xF77737),
                symbol: "camera.fill", beta: false),

        Service(id: "youtube", name: "YouTube",
                home: URL(string: "https://m.youtube.com/")!,
                tint: Color(hex: 0xE02F2F), tintDark: Color(hex: 0x9E1B1B),
                symbol: "play.rectangle.fill", beta: false),

        Service(id: "x", name: "X",
                home: URL(string: "https://x.com/home")!,
                tint: Color(hex: 0x2B2B2B), tintDark: Color(hex: 0x0A0A0A),
                symbol: "xmark", beta: true),

        Service(id: "tiktok", name: "TikTok",
                home: URL(string: "https://www.tiktok.com/following")!,
                tint: Color(hex: 0x25F4EE), tintDark: Color(hex: 0xFE2C55),
                symbol: "music.note", beta: true),

        Service(id: "facebook", name: "Facebook",
                home: URL(string: "https://m.facebook.com/")!,
                tint: Color(hex: 0x4267B2), tintDark: Color(hex: 0x1D3557),
                symbol: "person.2.fill", beta: true),

        Service(id: "linkedin", name: "LinkedIn",
                home: URL(string: "https://www.linkedin.com/feed/")!,
                tint: Color(hex: 0x0A66C2), tintDark: Color(hex: 0x004182),
                symbol: "briefcase.fill", beta: true),

        Service(id: "snapchat", name: "Snapchat",
                home: URL(string: "https://web.snapchat.com/")!,
                tint: Color(hex: 0xFFFC00), tintDark: Color(hex: 0xE0A800),
                symbol: "bolt.fill", beta: true),

        Service(id: "reddit", name: "Reddit",
                home: URL(string: "https://www.reddit.com/")!,
                tint: Color(hex: 0xFF4500), tintDark: Color(hex: 0xC33B00),
                symbol: "bubble.left.and.bubble.right.fill", beta: true),
    ]

    static func service(_ id: String) -> Service? {
        services.first { $0.id == id }
    }
}
