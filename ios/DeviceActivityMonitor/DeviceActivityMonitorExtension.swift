import DeviceActivity
import Foundation
import ManagedSettings

/// Applies and lifts the shield on a schedule (Sleep Mode), and drives the
/// Post Mode timer from outside the app process.
///
/// The reason this lives in an extension at all: the host app is not running
/// when a schedule boundary passes. An app-process timer is exactly how you end
/// up shipping the SocialLite bug where Sleep Mode never releases — the app was
/// never foregrounded at 07:00, so nothing ever recomputed.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let store = ManagedSettingsStore(named: .noscroll)
    private let defaults = UserDefaults(suiteName: AppGroup.identifier)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        switch activity {
        case .sleepWindow:
            applyStoredShield()
            defaults?.set(true, forKey: Keys.sleepActive)

        case .postMode:
            break

        default:
            break
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        switch activity {
        case .sleepWindow:
            // The release path. Runs in the extension, so it fires whether or
            // not the user has opened the app since the window began.
            defaults?.set(false, forKey: Keys.sleepActive)
            if !shouldRemainShielded() {
                clearShield()
            }

        case .postMode:
            // Post Mode expiry. Honour an in-flight upload rather than killing
            // it mid-send: the host app sets `uploadInProgress` and we re-arm a
            // short grace window instead of re-shielding immediately.
            if defaults?.bool(forKey: Keys.uploadInProgress) == true {
                defaults?.set(true, forKey: Keys.postModeNeedsGrace)
            } else {
                applyStoredShield()
            }

        default:
            break
        }
    }

    /// Sleep Mode ending must not lift a shield the user set permanently.
    private func shouldRemainShielded() -> Bool {
        defaults?.bool(forKey: Keys.alwaysShielded) ?? true
    }

    private func applyStoredShield() {
        guard let data = defaults?.data(forKey: "noscroll.shield.selection"),
              let tokens = try? JSONDecoder().decode(Set<ApplicationToken>.self, from: data)
        else { return }
        store.shield.applications = tokens.isEmpty ? nil : tokens
    }

    private func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }

    enum Keys {
        static let sleepActive = "noscroll.sleep.active"
        static let uploadInProgress = "noscroll.postmode.uploading"
        static let postModeNeedsGrace = "noscroll.postmode.grace"
        static let alwaysShielded = "noscroll.shield.always"
    }
}

extension DeviceActivityName {
    static let sleepWindow = Self("noscroll.sleep")
    static let postMode = Self("noscroll.postmode")
}

extension ManagedSettingsStore.Name {
    static let noscroll = Self("noscroll")
}

enum AppGroup {
    static let identifier = "group.app.noscroll"
}
