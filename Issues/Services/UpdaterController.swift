import Foundation
import Sparkle
import os.log

/// Singleton wrapper around `SPUStandardUpdaterController` (#0118).
///
/// Issues.app ships with Sparkle linked but **inert** by default: the menu
/// item under the Issues app menu is disabled until the running bundle's
/// `Info.plist` carries a non-empty `SUFeedURL` (and `SUPublicEDKey` for
/// EdDSA signature verification). That keeps the unconfigured Debug-build
/// experience boring — no surprise network traffic, no broken menu — while
/// the host-side scaffolding (the public key, the appcast at
/// `https://issues.sstools.co/appcast.xml`) gets set up out of band. See
/// `scripts/SPARKLE.md` for the user-facing checklist.
///
/// Once Info.plist is populated, no code change is required: Sparkle picks
/// up the feed URL on the next launch and the menu item enables itself.
@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    private let logger = Logger(subsystem: Logging.subsystem, category: "Updater")
    private let controller: SPUStandardUpdaterController

    private init() {
        // `startingUpdater: true` is safe even when SUFeedURL is unset —
        // Sparkle initializes its internal state but doesn't poll until it
        // has a feed URL to fetch. That avoids the menu item lying about
        // its configured-ness when first interacted with.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// True when `SUFeedURL` is a non-empty string in the running bundle.
    /// The Check for Updates menu item binds `.disabled` to `!isConfigured`,
    /// so a Debug build (or a release before the user wires the plist) shows
    /// a greyed-out item rather than a clickable one that throws an obscure
    /// Sparkle error.
    var isConfigured: Bool {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        return raw?.isEmpty == false
    }

    /// Invoke from the menu action. No-ops cleanly when not configured so a
    /// keyboard shortcut accidentally hitting this can't crash or surface a
    /// Sparkle internal error.
    func checkForUpdates() {
        guard isConfigured else {
            logger.notice("Check for Updates invoked but SUFeedURL is not configured; no-op.")
            return
        }
        controller.checkForUpdates(nil)
    }
}
