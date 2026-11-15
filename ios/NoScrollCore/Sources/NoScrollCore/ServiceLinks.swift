import Foundation

/// Which web pages a service's in-app web view may show. A link that leaves the service (another site) opens in
/// the in-app Safari sheet (SFSafariViewController), not in the web view: the web view shows only the service and
/// its sign-in pages, so the app gives no unrestricted web access.
public enum ServiceLinks {

    /// The sign-in pages of other companies that a service may send a person to ("Continue with Google",
    /// "Continue with Apple"). They stay in the web view, so the session cookie lands where the service needs it.
    static let signInHosts = ["accounts.google.com", "consent.google.com", "appleid.apple.com"]

    /// "Continue with Facebook" on another service: only these paths of facebook.com stay in the web view.
    static let facebookSignInPaths = ["/dialog/oauth", "/login", "/checkpoint", "/oauth", "/two_step_verification", "/recover", "/cookie/consent"]

    /// The base domains of a service from the `match` patterns of its rule bundle:
    /// "*://*.instagram.com/*" gives "instagram.com".
    public static func domains(fromMatch patterns: [String]) -> [String] {
        var out: [String] = []
        for pattern in patterns {
            var rest = Substring(pattern)
            if let range = rest.range(of: "://") { rest = rest[range.upperBound...] }
            if let slash = rest.firstIndex(of: "/") { rest = rest[..<slash] }
            var host = String(rest).lowercased()
            while host.hasPrefix("*.") { host.removeFirst(2) }
            if host.hasPrefix(".") { host.removeFirst() }
            guard !host.isEmpty, !host.contains("*"), !out.contains(host) else { continue }
            out.append(host)
        }
        return out
    }

    /// True when `url` may load in the service's web view: a page of the service (its domains and their
    /// subdomains), a sign-in page of another company, or a page that is not a web address (about:blank,
    /// data:, blob:). False for any other web page: it opens in the in-app Safari sheet.
    public static func staysInApp(_ url: URL, serviceDomains: [String]) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        guard scheme == "http" || scheme == "https" else { return true }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return true }
        if serviceDomains.contains(where: { isHost(host, inDomain: $0.lowercased()) }) { return true }
        if signInHosts.contains(host) { return true }
        if isHost(host, inDomain: "facebook.com") {
            // Remove a Graph API version prefix: /v19.0/dialog/oauth -> /dialog/oauth.
            var path = url.path.lowercased()
            if let match = path.range(of: #"^/v[0-9]+(\.[0-9]+)?(?=/)"#, options: .regularExpression) {
                path.removeSubrange(match)
            }
            return facebookSignInPaths.contains { path == $0 || path.hasPrefix($0 + "/") || path.hasPrefix($0 + ".") || path.hasPrefix($0 + "_") }
        }
        return false
    }

    /// "m.instagram.com" is in "instagram.com"; "instagram.com.example.net" and "notinstagram.com" are not.
    static func isHost(_ host: String, inDomain domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
