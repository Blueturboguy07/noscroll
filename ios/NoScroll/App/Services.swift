import SwiftUI

extension AppState {

    /// The services NoScroll wraps.
    ///
    /// NOTE ON ICONS: these render as neutral brand-coloured tiles, not as the
    /// platforms' logos. Reproducing Instagram's or TikTok's mark — especially
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
        /// Surfaces this service exposes as "ad blocking" during onboarding.
        let adSurfaces: [String]
        let adCopyOn: String
        let adCopyOff: String

        var hasAdBlocking: Bool { !adSurfaces.isEmpty }

        var gradient: LinearGradient {
            LinearGradient(colors: [tint, tintDark], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    static let services: [Service] = [
        Service(id: "instagram", name: "Instagram",
                home: URL(string: "https://www.instagram.com/")!,
                tint: Color(hex: 0xE1306C), tintDark: Color(hex: 0xF77737),
                symbol: "camera.fill", beta: false,
                adSurfaces: ["suggested-posts", "sponsored"],
                adCopyOn: "Suggested posts + ads are off",
                adCopyOff: "Suggested posts + ads are showing"),

        Service(id: "youtube", name: "YouTube",
                home: URL(string: "https://m.youtube.com/")!,
                tint: Color(hex: 0xE02F2F), tintDark: Color(hex: 0x9E1B1B),
                symbol: "play.rectangle.fill", beta: false,
                adSurfaces: ["up-next"],
                adCopyOn: "Up-next and recommendations are off",
                adCopyOff: "Up-next and recommendations are showing"),

        Service(id: "x", name: "X",
                home: URL(string: "https://x.com/home")!,
                tint: Color(hex: 0x2B2B2B), tintDark: Color(hex: 0x0A0A0A),
                symbol: "xmark", beta: true,
                adSurfaces: ["promoted"],
                adCopyOn: "Promoted posts are off",
                adCopyOff: "Promoted posts are showing"),

        Service(id: "tiktok", name: "TikTok",
                home: URL(string: "https://www.tiktok.com/following")!,
                tint: Color(hex: 0x25F4EE), tintDark: Color(hex: 0xFE2C55),
                symbol: "music.note", beta: true,
                adSurfaces: [], adCopyOn: "", adCopyOff: ""),

        Service(id: "facebook", name: "Facebook",
                home: URL(string: "https://m.facebook.com/")!,
                tint: Color(hex: 0x4267B2), tintDark: Color(hex: 0x1D3557),
                symbol: "person.2.fill", beta: true,
                adSurfaces: [], adCopyOn: "", adCopyOff: ""),

        Service(id: "linkedin", name: "LinkedIn",
                home: URL(string: "https://www.linkedin.com/feed/")!,
                tint: Color(hex: 0x0A66C2), tintDark: Color(hex: 0x004182),
                symbol: "briefcase.fill", beta: true,
                adSurfaces: [], adCopyOn: "", adCopyOff: ""),

        Service(id: "snapchat", name: "Snapchat",
                home: URL(string: "https://web.snapchat.com/")!,
                tint: Color(hex: 0xFFFC00), tintDark: Color(hex: 0xE0A800),
                symbol: "bolt.fill", beta: true,
                adSurfaces: [], adCopyOn: "", adCopyOff: ""),

        Service(id: "reddit", name: "Reddit",
                home: URL(string: "https://www.reddit.com/")!,
                tint: Color(hex: 0xFF4500), tintDark: Color(hex: 0xC33B00),
                symbol: "bubble.left.and.bubble.right.fill", beta: true,
                adSurfaces: ["promoted"],
                adCopyOn: "Promoted posts are off",
                adCopyOff: "Promoted posts are showing"),
    ]

    static func service(_ id: String) -> Service? {
        services.first { $0.id == id }
    }
}
