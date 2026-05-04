import AppKit
import Foundation
import UserNotifications
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "NotificationService")

/// Posts macOS user notifications for changes in watched issue folders while
/// the app is in the background. Suppresses notifications when the app is
/// active — the per-tab unseen-changes dot from #0003 is the only signal the
/// user needs while looking. Tapping a notification routes via
/// `AppCommandsController` to activate the right tab and select the issue.
///
/// One reload tick = one call to `notifyChanges(...)`. `IssueStore`'s
/// `FolderWatcher` already debounces file events at 150ms, so we don't add
/// further debouncing here. The only coalescing logic is the rollup threshold:
/// if a single reload introduces more than 5 changes, we collapse to a single
/// "<repo> · N issue changes" notification instead of spamming.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationService()

    /// Threshold above which a reload's individual notifications collapse into
    /// a single rollup. Keeps a `git pull` that touches a dozen files from
    /// firing twelve banners.
    private static let rollupThreshold = 5

    /// Keys used to round-trip routing context through
    /// `UNNotificationRequest.content.userInfo`.
    private enum UserInfoKey {
        static let tabID = "tabID"        // String (UUID)
        static let issueID = "issueID"    // String, optional (absent for rollups)
        static let kind = "kind"          // String, one of: "addition", "removal", "status", "rollup"
    }

    private var hasRequestedAuthorization = false

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    /// Requests alert + sound authorization once per process lifetime. Safe to
    /// call repeatedly; subsequent calls are guarded by
    /// `hasRequestedAuthorization`. If the user denies, posting later just
    /// no-ops at the system level — we don't show a fallback dialog. The user
    /// can flip the switch in System Settings.
    func requestAuthorization() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.warning("authorization request failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.notice("authorization granted=\(granted, privacy: .public)")
            }
        }
    }

    // MARK: - Posting

    /// Builds and submits notifications for the changes detected on a single
    /// reload of `repoName`'s tab. Suppressed entirely when the app is active.
    /// If the total change count exceeds the rollup threshold, a single
    /// summary notification is posted instead.
    func notifyChanges(
        repoName: String,
        tabID: UUID,
        additions: [Issue],
        removals: [Issue],
        statusChanges: [(issue: Issue, oldStatus: IssueStatus, newStatus: IssueStatus)]
    ) {
        // The dot indicator from #0003 already tells the user about changes
        // while they're looking; a banner on top would be noise.
        if NSApplication.shared.isActive { return }

        let total = additions.count + removals.count + statusChanges.count
        guard total > 0 else { return }

        if total > Self.rollupThreshold {
            postRollup(repoName: repoName, tabID: tabID, count: total)
            return
        }

        for issue in additions {
            postIndividual(
                repoName: repoName,
                tabID: tabID,
                issue: issue,
                kind: "addition",
                body: "New in \(repoName)"
            )
        }
        for issue in removals {
            postIndividual(
                repoName: repoName,
                tabID: tabID,
                issue: issue,
                kind: "removal",
                body: "Removed from \(repoName)"
            )
        }
        for change in statusChanges {
            postIndividual(
                repoName: repoName,
                tabID: tabID,
                issue: change.issue,
                kind: "status",
                body: "\(repoName) · Status: \(change.oldStatus.displayName) → \(change.newStatus.displayName)"
            )
        }
    }

    private func postIndividual(
        repoName: String,
        tabID: UUID,
        issue: Issue,
        kind: String,
        body: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "#\(issue.id) — \(issue.title)"
        content.body = body
        content.userInfo = [
            UserInfoKey.tabID: tabID.uuidString,
            UserInfoKey.issueID: issue.id,
            UserInfoKey.kind: kind
        ]
        // Stable identifier per (tab, issue, kind) so rapid duplicate
        // reload-events don't stack the same banner.
        let identifier = "issue.\(tabID.uuidString).\(issue.id).\(kind)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.warning("post failed for \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func postRollup(repoName: String, tabID: UUID, count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(repoName) · \(count) issue changes"
        content.body = "Multiple changes detected — open the tab to review."
        content.userInfo = [
            UserInfoKey.tabID: tabID.uuidString,
            UserInfoKey.kind: "rollup"
        ]
        let identifier = "rollup.\(tabID.uuidString).\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.warning("rollup post failed for \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Routes the tap: activate the app and the existing main window, switch
    /// to the originating tab, and select the issue if one was named in
    /// `userInfo`. Rollup notifications only carry a `tabID`, so the tab
    /// activates without changing selection.
    ///
    /// Window handling (#0026): the main scene is a single-instance
    /// `Window(id: "main")`, so activating the app re-uses the existing window
    /// instead of spawning a new one. We also explicitly bring the window to
    /// the front in case it was hidden (Cmd+H, miniaturized, or the Help
    /// window currently has focus). Cold-launch path: if the tabs model
    /// hasn't been wired up yet, the link sits as `pendingDeepLink` and is
    /// drained from `RootView.onAppear` once `TabsModel.restore()` completes.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let tabIDString = userInfo[UserInfoKey.tabID] as? String
        let issueID = userInfo[UserInfoKey.issueID] as? String

        Task { @MainActor in
            // Stash the routing intent first so a cold launch can pick it up
            // from `RootView.onAppear`.
            if let tabIDString, let tabID = UUID(uuidString: tabIDString) {
                AppCommandsController.shared.pendingDeepLink = AppCommandsController.DeepLink(
                    tabID: tabID,
                    issueID: issueID
                )
            }

            // Bring the app forward. With the main scene now a single-instance
            // `Window`, this won't spawn a second window — it just re-activates
            // the one that already exists.
            NSApplication.shared.activate(ignoringOtherApps: true)

            // Explicitly bring the main window to the front. Handles the
            // case where the user has the Help window focused, or the main
            // window was Cmd+H'd / miniaturized. No-op if already key.
            if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                if mainWindow.isMiniaturized {
                    mainWindow.deminiaturize(nil)
                }
                mainWindow.makeKeyAndOrderFront(nil)
            }

            // Drain immediately if the tabs model is already wired up (warm
            // app path). Otherwise this is a cold launch and `RootView`'s
            // `onAppear` will drain after `TabsModel.restore()` finishes.
            AppCommandsController.shared.consumePendingDeepLinkIfPossible()

            completionHandler()
        }
    }

    /// Allow notifications to display as banners even while the app is
    /// foreground. This handler only runs when the app receives a notification
    /// at all — if the app is active when changes happen we suppress before
    /// posting (`notifyChanges` early-exits), so this is mostly defensive in
    /// case a delivery races with activation.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
