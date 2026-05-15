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
public final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    public static let shared = NotificationService()

    /// Threshold above which a reload's individual notifications collapse into
    /// a single rollup. Keeps a `git pull` that touches a dozen files from
    /// firing twelve banners.
    private static let rollupThreshold = 5

    /// Keys used to round-trip routing context through
    /// `UNNotificationRequest.content.userInfo`.
    nonisolated private enum UserInfoKey {
        static let tabID = "tabID"        // String (UUID)
        static let issueID = "issueID"    // String, optional (absent for rollups)
        static let kind = "kind"          // String, one of: "addition", "removal", "status", "rollup"
    }

    private var hasRequestedAuthorization = false

    private override init() {
        super.init()
        logger.notice("NotificationService init \(NotificationService.processTag(), privacy: .public)")

        // Observe application lifecycle so we can correlate notification taps
        // with launch / activation events. Critical for diagnosing #0026's
        // multi-process bug: if we see "didFinishLaunching" fire on the
        // existing process whenever a notification is tapped, that means a
        // second process is being spawned in addition to the running one.
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleAppDidFinishLaunching),
            name: NSApplication.didFinishLaunchingNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        // Observe NSWorkspace launches of *any* app that matches our bundle
        // identifier. If a second Issues.app process is launched while this
        // process is still alive, this fires here — the smoking gun for a
        // duplicate-launch path.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceDidLaunchApp(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceDidActivateApp(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    /// Common process-identity tag included in every interesting log line so
    /// we can correlate events across PIDs in the stream output. Format keeps
    /// the line greppable: `pid=12345 bundle=/path/to/Issues.app`.
    public nonisolated static func processTag() -> String {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        return "pid=\(pid) bundle=\(path)"
    }

    @objc private func handleAppDidFinishLaunching(_ note: Notification) {
        logger.notice("APP_DID_FINISH_LAUNCHING \(NotificationService.processTag(), privacy: .public) isActive=\(NSApplication.shared.isActive, privacy: .public)")
    }

    @objc private func handleAppDidBecomeActive(_ note: Notification) {
        logger.info("APP_DID_BECOME_ACTIVE \(NotificationService.processTag(), privacy: .public) windows=\(NSApp.windows.count, privacy: .public)")
    }

    @objc private func handleAppDidResignActive(_ note: Notification) {
        logger.info("APP_DID_RESIGN_ACTIVE \(NotificationService.processTag(), privacy: .public)")
    }

    @objc private func handleWorkspaceDidLaunchApp(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        guard app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
        logger.error("WORKSPACE_DID_LAUNCH_OWN_BUNDLE another \(app.bundleIdentifier ?? "?", privacy: .public) launched: pid=\(app.processIdentifier, privacy: .public) path=\(app.bundleURL?.path ?? "?", privacy: .public). Current process: \(NotificationService.processTag(), privacy: .public). This indicates a duplicate-instance launch.")
    }

    @objc private func handleWorkspaceDidActivateApp(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        guard app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
        let isSelf = app.processIdentifier == ProcessInfo.processInfo.processIdentifier
        logger.info("WORKSPACE_DID_ACTIVATE_OWN_BUNDLE \(isSelf ? "self" : "OTHER", privacy: .public) pid=\(app.processIdentifier, privacy: .public) path=\(app.bundleURL?.path ?? "?", privacy: .public)")
    }

    // MARK: - Authorization

    /// Requests alert + sound authorization once per process lifetime. Safe to
    /// call repeatedly; subsequent calls are guarded by
    /// `hasRequestedAuthorization`. If the user denies, posting later just
    /// no-ops at the system level — we don't show a fallback dialog. The user
    /// can flip the switch in System Settings.
    public func requestAuthorization() {
        guard !hasRequestedAuthorization else {
            logger.debug("requestAuthorization noop (already requested) \(NotificationService.processTag(), privacy: .public)")
            return
        }
        hasRequestedAuthorization = true
        logger.info("requestAuthorization start \(NotificationService.processTag(), privacy: .public)")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.warning("authorization request failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.notice("authorization granted=\(granted, privacy: .public) \(NotificationService.processTag(), privacy: .public)")
            }
        }
    }

    // MARK: - Posting

    /// Builds and submits notifications for the changes detected on a single
    /// reload of a tab. `displayName` is the user-facing folder label
    /// (project.json `name` when present, else the parent folder name) and
    /// is what appears in the notification title/body. Suppressed entirely
    /// when the app is active. If the total change count exceeds the
    /// rollup threshold, a single summary notification is posted instead.
    public func notifyChanges(
        displayName: String,
        tabID: UUID,
        additions: [Issue],
        removals: [Issue],
        statusChanges: [(issue: Issue, oldStatus: IssueStatus, newStatus: IssueStatus)]
    ) {
        let total = additions.count + removals.count + statusChanges.count
        logger.debug("notifyChanges repo=\(displayName, privacy: .public) tabID=\(tabID.uuidString.prefix(8), privacy: .public) additions=\(additions.count, privacy: .public) removals=\(removals.count, privacy: .public) statusChanges=\(statusChanges.count, privacy: .public) isActive=\(NSApplication.shared.isActive, privacy: .public)")

        // The dot indicator from #0003 already tells the user about changes
        // while they're looking; a banner on top would be noise.
        if NSApplication.shared.isActive {
            logger.debug("notifyChanges suppressed — app is active")
            return
        }

        guard total > 0 else { return }

        if total > Self.rollupThreshold {
            logger.info("notifyChanges rollup repo=\(displayName, privacy: .public) count=\(total, privacy: .public)")
            postRollup(displayName: displayName, tabID: tabID, count: total)
            return
        }

        for issue in additions {
            postIndividual(
                tabID: tabID,
                issue: issue,
                kind: "addition",
                body: "New in \(displayName)"
            )
        }
        for issue in removals {
            postIndividual(
                tabID: tabID,
                issue: issue,
                kind: "removal",
                body: "Removed from \(displayName)"
            )
        }
        for change in statusChanges {
            postIndividual(
                tabID: tabID,
                issue: change.issue,
                kind: "status",
                body: "\(displayName) · Status: \(change.oldStatus.displayName) → \(change.newStatus.displayName)"
            )
        }
    }

    private func postIndividual(
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
        logger.info("POST_INDIVIDUAL identifier=\(identifier, privacy: .public) title=\(content.title, privacy: .public)")
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.warning("post failed for \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                logger.debug("post submitted \(identifier, privacy: .public)")
            }
        }
    }

    private func postRollup(displayName: String, tabID: UUID, count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(displayName) · \(count) issue changes"
        content.body = "Multiple changes detected — open the tab to review."
        content.userInfo = [
            UserInfoKey.tabID: tabID.uuidString,
            UserInfoKey.kind: "rollup"
        ]
        let identifier = "rollup.\(tabID.uuidString).\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        logger.info("POST_ROLLUP identifier=\(identifier, privacy: .public) count=\(count, privacy: .public)")
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.warning("rollup post failed for \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                logger.debug("rollup submitted \(identifier, privacy: .public)")
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
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let tabIDString = userInfo[UserInfoKey.tabID] as? String
        let issueID = userInfo[UserInfoKey.issueID] as? String
        let kind = userInfo[UserInfoKey.kind] as? String ?? "?"
        let identifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier

        // Synchronous log first so we capture the entry point even if the
        // dispatched MainActor task gets delayed or the process exits early.
        logger.notice("DID_RECEIVE \(NotificationService.processTag(), privacy: .public) identifier=\(identifier, privacy: .public) action=\(actionIdentifier, privacy: .public) kind=\(kind, privacy: .public) tabID=\(tabIDString ?? "nil", privacy: .public) issueID=\(issueID ?? "nil", privacy: .public)")

        Task { @MainActor in
            logger.debug("DID_RECEIVE main-actor entry windows=\(NSApp.windows.count, privacy: .public) isActive=\(NSApplication.shared.isActive, privacy: .public)")

            // Stash the routing intent first so a cold launch can pick it up
            // from `RootView.onAppear`.
            if let tabIDString, let tabID = UUID(uuidString: tabIDString) {
                AppCommandsController.shared.pendingDeepLink = AppCommandsController.DeepLink(
                    tabID: tabID,
                    issueID: issueID
                )
                logger.debug("DID_RECEIVE pendingDeepLink set tabID=\(tabIDString, privacy: .public) issueID=\(issueID ?? "nil", privacy: .public)")
            } else {
                logger.warning("DID_RECEIVE missing/invalid tabID — not setting pendingDeepLink")
            }

            // Bring the app forward. With the main scene now a single-instance
            // `Window`, this won't spawn a second window — it just re-activates
            // the one that already exists.
            NSApplication.shared.activate(ignoringOtherApps: true)
            logger.debug("DID_RECEIVE called NSApp.activate")

            // Explicitly bring the main window to the front. Handles the
            // case where the user has the Help window focused, or the main
            // window was Cmd+H'd / miniaturized. No-op if already key.
            let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })
            if let mainWindow {
                let wasMin = mainWindow.isMiniaturized
                if wasMin {
                    mainWindow.deminiaturize(nil)
                }
                mainWindow.makeKeyAndOrderFront(nil)
                logger.debug("DID_RECEIVE main window brought forward (wasMiniaturized=\(wasMin, privacy: .public))")
            } else {
                let identifiers = NSApp.windows.compactMap { $0.identifier?.rawValue }.joined(separator: ",")
                logger.warning("DID_RECEIVE no window with id=main found — current window identifiers: [\(identifiers, privacy: .public)]")
            }

            // Drain immediately if the tabs model is already wired up (warm
            // app path). Otherwise this is a cold launch and `RootView`'s
            // `onAppear` will drain after `TabsModel.restore()` finishes.
            AppCommandsController.shared.consumePendingDeepLinkIfPossible()
            logger.debug("DID_RECEIVE consume attempt complete")
        }

        // Tell UN we're done. Apple's contract is "execute completionHandler
        // as soon as possible after processing"; calling it outside the
        // MainActor Task avoids the Swift 6 sending-data-race error (the
        // closure isn't `@Sendable`, so MainActor can't capture it) without
        // changing observable behavior — the routing work above still runs.
        completionHandler()
    }

    /// Allow notifications to display as banners even while the app is
    /// foreground. This handler only runs when the app receives a notification
    /// at all — if the app is active when changes happen we suppress before
    /// posting (`notifyChanges` early-exits), so this is mostly defensive in
    /// case a delivery races with activation.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        logger.info("WILL_PRESENT \(NotificationService.processTag(), privacy: .public) identifier=\(identifier, privacy: .public)")
        completionHandler([.banner, .sound])
    }
}
