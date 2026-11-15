import Foundation
import XCTest
@testable import NoScrollCore

/// A link that leaves a service opens in the in-app Safari sheet, not in the service's web view
/// (App Store: no unrestricted web access). Sign-in pages stay in the web view.
final class ServiceLinksTests: XCTestCase {
    private func stays(_ link: String, _ domains: [String]) -> Bool {
        ServiceLinks.staysInApp(URL(string: link)!, serviceDomains: domains)
    }

    private let instagram = ServiceLinks.domains(fromMatch: ["*://*.instagram.com/*"])
    private let youtube = ServiceLinks.domains(fromMatch: ["*://*.youtube.com/*", "*://*.youtu.be/*"])
    private let tiktok = ServiceLinks.domains(fromMatch: ["*://*.tiktok.com/*"])
    private let facebook = ServiceLinks.domains(fromMatch: ["*://*.facebook.com/*"])

    func testDomainsComeFromTheMatchPatterns() {
        XCTAssertEqual(instagram, ["instagram.com"])
        XCTAssertEqual(youtube, ["youtube.com", "youtu.be"])
        XCTAssertEqual(ServiceLinks.domains(fromMatch: ["https://www.linkedin.com/*", "*://*/*"]), ["www.linkedin.com"])
    }

    func testPagesOfTheServiceStayInTheWebView() {
        XCTAssertTrue(stays("https://www.instagram.com/p/abc/", instagram))
        XCTAssertTrue(stays("https://instagram.com/", instagram))
        // The link shim: it redirects to the other site, and that redirect opens in the sheet.
        XCTAssertTrue(stays("https://l.instagram.com/?u=https%3A%2F%2Fexample.com", instagram))
        XCTAssertTrue(stays("https://m.youtube.com/watch?v=abc", youtube))
        XCTAssertTrue(stays("https://youtu.be/abc", youtube))
        XCTAssertTrue(stays("https://www.facebook.com/groups/x", facebook))
    }

    func testLinksToOtherSitesOpenInTheSheet() {
        XCTAssertFalse(stays("https://example.com/", instagram))
        XCTAssertFalse(stays("http://example.com/a?b=c", youtube))
        XCTAssertFalse(stays("https://www.google.com/search?q=x", youtube))
        XCTAssertFalse(stays("https://shop.example.net/item", tiktok))
        // Look-alike hosts are other sites.
        XCTAssertFalse(stays("https://instagram.com.example.net/", instagram))
        XCTAssertFalse(stays("https://notinstagram.com/", instagram))
        // Facebook pages from another service are another site; only Facebook's sign-in stays.
        XCTAssertFalse(stays("https://www.facebook.com/somepage", tiktok))
        XCTAssertFalse(stays("https://m.facebook.com/", instagram))
    }

    func testSignInPagesStayInTheWebView() {
        XCTAssertTrue(stays("https://accounts.google.com/ServiceLogin?continue=https://m.youtube.com/", youtube))
        XCTAssertTrue(stays("https://accounts.google.com/o/oauth2/v2/auth?client_id=x", tiktok))
        XCTAssertTrue(stays("https://consent.google.com/m?continue=x", youtube))
        XCTAssertTrue(stays("https://appleid.apple.com/auth/authorize?client_id=x", tiktok))
        XCTAssertTrue(stays("https://www.facebook.com/v19.0/dialog/oauth?client_id=x", tiktok))
        XCTAssertTrue(stays("https://www.facebook.com/dialog/oauth/confirm", instagram))
        XCTAssertTrue(stays("https://m.facebook.com/login.php?next=x", instagram))
        XCTAssertTrue(stays("https://m.facebook.com/checkpoint/123", tiktok))
    }

    func testPagesThatAreNotWebAddressesStay() {
        XCTAssertTrue(stays("about:blank", instagram))
        XCTAssertTrue(stays("data:text/html,hi", instagram))
        XCTAssertTrue(stays("blob:https://www.instagram.com/uuid", instagram))
    }
}
