import XCTest
@testable import NoScrollCore

/// The app opens only publik's bare in-app pages in its in-app browser.
final class PublikLinksTests: XCTestCase {

    func testClaimURLGetsInAppFlag() {
        XCTAssertEqual(PublikLinks.inAppClaimURL("https://publikhq.com/claim/ABC123")?.absoluteString,
                       "https://publikhq.com/claim/ABC123?in_app=1")
    }

    func testClaimURLKeepsExistingQueryItems() {
        XCTAssertEqual(PublikLinks.inAppClaimURL("https://publikhq.com/claim?code=ABC123&app=noscroll")?.absoluteString,
                       "https://publikhq.com/claim?code=ABC123&app=noscroll&in_app=1")
        // Encoded values stay exactly as publik sent them.
        XCTAssertEqual(PublikLinks.inAppClaimURL("https://publikhq.com/claim?next=%2Fwallet%3Fa%3D1&t=a%2Bb")?.absoluteString,
                       "https://publikhq.com/claim?next=%2Fwallet%3Fa%3D1&t=a%2Bb&in_app=1")
    }

    func testClaimURLReplacesAnOldInAppItemAndKeepsTheFragment() {
        XCTAssertEqual(PublikLinks.inAppClaimURL("https://publikhq.com/claim/X?in_app=0&k=v#top")?.absoluteString,
                       "https://publikhq.com/claim/X?k=v&in_app=1#top")
        XCTAssertEqual(PublikLinks.inAppClaimURL("https://publikhq.com/claim/X?in_app")?.absoluteString,
                       "https://publikhq.com/claim/X?in_app=1")
    }

    func testClaimURLWithATestOrigin() {
        XCTAssertEqual(PublikLinks.inAppClaimURL("http://127.0.0.1:8787/claim")?.absoluteString,
                       "http://127.0.0.1:8787/claim?in_app=1")
    }

    func testClaimURLRejectsValuesThatAreNotWebAddresses() {
        XCTAssertNil(PublikLinks.inAppClaimURL(""))
        XCTAssertNil(PublikLinks.inAppClaimURL("/claim/ABC"))
        XCTAssertNil(PublikLinks.inAppClaimURL("javascript:alert(1)"))
        XCTAssertNil(PublikLinks.inAppClaimURL("noscroll://claim"))
    }

    func testDeleteAccountURLIsTheInAppPage() {
        XCTAssertEqual(PublikLinks.deleteAccountURL(origin: "https://publikhq.com")?.absoluteString,
                       "https://publikhq.com/in-app/delete-account")
    }

    func testPrivacyURLIsTheInAppPage() {
        XCTAssertEqual(PublikLinks.privacyURL(origin: "https://publikhq.com")?.absoluteString,
                       "https://publikhq.com/in-app/privacy")
    }

    func testSupportURLIsTheInAppPage() {
        XCTAssertEqual(PublikLinks.supportURL(origin: "https://publikhq.com")?.absoluteString,
                       "https://publikhq.com/in-app/support")
    }
}
