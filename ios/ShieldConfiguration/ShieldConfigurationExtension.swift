import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen a user hits when they open the real Instagram while shielded.
///
/// This is the most-seen screen in the product and it is doing persuasion work,
/// not just blocking: the user is here because a habit fired. Two deliberate
/// choices:
///
///  1. The primary button leads INTO NoScroll rather than just dismissing.
///     A shield that only says "no" trains people to fight it; one that offers
///     the calm version of the same thing redirects the impulse.
///  2. No shame, no streak-loss language, no counters. The research on the app
///     we are cloning shows its loudest complaints cluster around feeling
///     manipulated. Judgemental copy here is what earns that.
///
/// Requires the `com.apple.developer.family-controls` entitlement on THIS target
/// as well as the host app.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private func configuration(appName: String?) -> ShieldConfiguration {
        let name = appName ?? "This app"
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.82),
            icon: UIImage(named: "ShieldGlyph"),
            title: ShieldConfiguration.Label(
                text: "\(name) is set aside",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "You can still read messages and see people you follow — without the feed that goes on forever.",
                color: UIColor.white.withAlphaComponent(0.75)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Open in NoScroll",
                color: .black
            ),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not now",
                color: UIColor.white.withAlphaComponent(0.6)
            )
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration(appName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        configuration(appName: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration(appName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        configuration(appName: webDomain.domain)
    }
}
