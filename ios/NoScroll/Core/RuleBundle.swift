import CryptoKit
import Foundation

/// A rule bundle is DATA, fetched and verified natively before it ever reaches
/// the WebView. Shipping a new selector must never require an App Store release —
/// that is the whole point, and the reason selector rot does not become a
/// week-long outage the way it does for a competitor that hardcodes them.
struct RuleBundle: Codable, Sendable {
    let version: Int
    let minEngine: Int
    var signature: String?
    let services: [String: Service]

    struct Service: Codable, Sendable {
        let match: [String]
        var authAllowList: [String]?
        let surfaces: [String: Surface]
    }

    /// Decoded loosely: the engine is the interpreter, so the shell only needs
    /// the fields it actually shows in settings UI.
    struct Surface: Codable, Sendable {
        let kind: String
        var locked: Bool?
        var defaultEnabled: Bool?
        var label: String?
        var source: String?
    }
}

enum BundleError: Error, LocalizedError {
    case badSignature
    case engineTooOld(required: Int, have: Int)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .badSignature:
            return "Rule bundle signature did not verify."
        case let .engineTooOld(required, have):
            return "Rule bundle requires engine \(required); this build has \(have)."
        case let .malformed(detail):
            return "Rule bundle malformed: \(detail)"
        }
    }
}

/// Loads rule bundles with a three-tier fallback so blocking never simply stops:
///
///   1. remote  — freshest, fetched from the CDN
///   2. cached  — last bundle that verified, kept on disk
///   3. baked   — shipped in the app binary, so a cold first launch with no
///                network still blocks Reels
///
/// A bundle that fails signature verification is discarded and the previous tier
/// is used. An attacker who can MITM the CDN must not be able to switch blocking
/// off, and a botched release must not brick the product.
actor RuleStore {
    static let engineVersion = 1

    private let publicKey: Curve25519.Signing.PublicKey
    private let cacheURL: URL
    private let remoteURL: URL
    private let session: URLSession

    init(publicKeyRaw: Data, remoteURL: URL, session: URLSession = .shared) throws {
        self.publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRaw)
        self.remoteURL = remoteURL
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheURL = caches.appendingPathComponent("noscroll-rules", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    }

    /// Canonical form for signing: the bundle JSON with `signature` removed,
    /// serialised with sorted keys. Must match tools/sign-bundle.mjs exactly.
    ///
    /// `.withoutEscapingSlashes` is NOT optional here. JSONSerialization escapes
    /// every forward slash as `\/` by default, while JSON.stringify does not —
    /// so without it, the canonical bytes differ by one byte per slash (69 of
    /// them in instagram.json) and EVERY signature fails on device while
    /// passing in both languages' own tests. Verified by
    /// tools/verify-canonical.swift, which exists solely to catch this.
    nonisolated static func canonicalize(_ raw: Data) throws -> Data {
        guard var obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw BundleError.malformed("top level is not an object")
        }
        obj.removeValue(forKey: "signature")
        return try JSONSerialization.data(
            withJSONObject: obj,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    nonisolated func verify(_ raw: Data) throws -> RuleBundle {
        let bundle = try JSONDecoder().decode(RuleBundle.self, from: raw)

        guard bundle.minEngine <= Self.engineVersion else {
            throw BundleError.engineTooOld(required: bundle.minEngine, have: Self.engineVersion)
        }
        guard let sigB64 = bundle.signature, let sig = Data(base64Encoded: sigB64) else {
            throw BundleError.badSignature
        }
        let canonical = try Self.canonicalize(raw)
        guard publicKey.isValidSignature(sig, for: canonical) else {
            throw BundleError.badSignature
        }
        return bundle
    }

    /// Returns the best available bundle for a service, newest-first with fallback.
    func load(service: String) async -> (bundle: RuleBundle, raw: Data, tier: String)? {
        if let fresh = await fetchRemote(service: service) { return fresh }
        if let cached = loadCached(service: service) { return cached }
        return loadBaked(service: service)
    }

    private func fetchRemote(service: String) async -> (RuleBundle, Data, String)? {
        let url = remoteURL.appendingPathComponent("\(service).json")
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let bundle = try verify(data)
            // Only cache what verified.
            try? data.write(to: cacheURL.appendingPathComponent("\(service).json"))
            return (bundle, data, "remote")
        } catch {
            return nil
        }
    }

    private func loadCached(service: String) -> (RuleBundle, Data, String)? {
        let url = cacheURL.appendingPathComponent("\(service).json")
        guard let data = try? Data(contentsOf: url), let bundle = try? verify(data) else {
            return nil
        }
        return (bundle, data, "cached")
    }

    private func loadBaked(service: String) -> (RuleBundle, Data, String)? {
        guard let url = Bundle.main.url(forResource: service, withExtension: "json",
                                        subdirectory: "Rules"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        // The baked bundle ships inside our own signed app binary, so a failed
        // signature here means a build mistake rather than an attack — still
        // refuse it, but never leave the user with nothing.
        if let bundle = try? verify(data) { return (bundle, data, "baked") }
        if let bundle = try? JSONDecoder().decode(RuleBundle.self, from: data) {
            assertionFailure("baked bundle \(service).json is unsigned — fix the build script")
            return (bundle, data, "baked-unsigned")
        }
        return nil
    }
}
