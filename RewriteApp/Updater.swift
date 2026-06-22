import Foundation
import Sparkle

/// Wraps Sparkle's standard updater. The app checks the appcast feed (set in
/// Info.plist via SUFeedURL), and on a new version shows a "what's new" prompt;
/// on Install it downloads, verifies the EdDSA signature, installs, and
/// relaunches — no manual reinstall.
final class AppUpdater {
    static let shared = AppUpdater()

    let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    /// Manual "Check for Updates…" trigger.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// "1.4.2" -> "1.4" — the feature line the What's New tour keys off, so it
    /// shows once per feature release and not on every minor patch.
    var featureVersion: String {
        let p = currentVersion.split(separator: ".")
        return p.count >= 2 ? "\(p[0]).\(p[1])" : currentVersion
    }
}
