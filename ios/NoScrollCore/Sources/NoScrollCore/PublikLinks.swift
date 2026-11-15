import Foundation

/// The publik pages that the app opens in its in-app browser. All of them are publik's bare
/// "in-app" pages: no site navigation, no footer, no prices and no plan links.
public enum PublikLinks {

    /// Sign in: the claim_url from publik with the query item `in_app=1` added. The other query
    /// items stay byte for byte; an old `in_app` item is replaced. publik redirects the result to
    /// /in-app/claim/<code>. nil when the value is not an http(s) URL with a host.
    public static func inAppClaimURL(_ claimURL: String) -> URL? {
        guard var parts = URLComponents(string: claimURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = parts.host, !host.isEmpty
        else { return nil }
        var items = (parts.percentEncodedQuery ?? "").split(separator: "&").map(String.init)
        items.removeAll { $0 == "in_app" || $0.hasPrefix("in_app=") }
        items.append("in_app=1")
        parts.percentEncodedQuery = items.joined(separator: "&")
        return parts.url
    }

    /// Delete account: publik's bare in-app delete page.
    public static func deleteAccountURL(origin: String) -> URL? {
        URL(string: "\(origin)/in-app/delete-account")
    }

    /// Privacy policy: publik's bare in-app privacy page.
    public static func privacyURL(origin: String) -> URL? {
        URL(string: "\(origin)/in-app/privacy")
    }

    /// Help and support: publik's bare in-app support page.
    public static func supportURL(origin: String) -> URL? {
        URL(string: "\(origin)/in-app/support")
    }
}
