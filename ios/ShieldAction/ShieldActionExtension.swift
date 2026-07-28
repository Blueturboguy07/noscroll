import Foundation
import ManagedSettings

/// Handles the buttons on the shield screen.
///
/// The primary button must NOT unshield. If tapping "Open in NoScroll" lifted
/// the restriction, the shield would be a speed bump that teaches users the
/// bypass on their very first encounter with it. It defers instead, and the host
/// app picks up the hand-off flag on next launch.
final class ShieldActionExtension: ShieldActionDelegate {

    private let defaults = UserDefaults(suiteName: AppGroup.identifier)

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    private func respond(to action: ShieldAction) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed:
            // Record the intent so the host app can open the right service, then
            // close. `.defer` keeps the shield in place — deliberately.
            defaults?.set(true, forKey: Keys.handoffRequested)
            defaults?.set(Date().timeIntervalSince1970, forKey: Keys.handoffAt)
            return .defer

        case .secondaryButtonPressed:
            return .close

        @unknown default:
            return .close
        }
    }

    enum Keys {
        static let handoffRequested = "noscroll.handoff.requested"
        static let handoffAt = "noscroll.handoff.at"
    }
}

enum AppGroup {
    static let identifier = "group.app.noscroll"
}
