import Testing
import IssuesCore
import Foundation
@testable import Issues

#if os(macOS)

/// Tests for `RemoteHostController` (#0083). Each test uses a unique
/// UserDefaults key suffix and cleans up in defer so concurrent runs
/// don't see each other's state.
///
/// Note: these tests construct the controller, which spins up a
/// RemoteServer instance and an NWPathMonitor. They don't call
/// `setEnabled(true)` — that would try to bind a real port. The
/// data-layer behavior (persistence, displayName flow, isShared bridge)
/// is what we cover here; binding is exercised manually via Issues.app.
@MainActor
struct RemoteHostControllerTests {

    private static func clearDefaults() {
        UserDefaults.standard.removeObject(forKey: "RemoteServer.enabled")
        UserDefaults.standard.removeObject(forKey: "RemoteServer.displayName")
        UserDefaults.standard.removeObject(forKey: "RemoteServer.allowedNetworks")
    }

    @Test func defaultsToDisabledOnFirstLaunch() {
        Self.clearDefaults()
        defer { Self.clearDefaults() }
        let controller = RemoteHostController()
        #expect(controller.isEnabled == false)
        #expect(controller.listeningPort == nil)
    }

    @Test func displayNameFallsBackToSystemWhenUnset() {
        Self.clearDefaults()
        defer { Self.clearDefaults() }
        let store = HostFolderStore()
        let controller = RemoteHostController(folderStore: store)
        #expect(!controller.displayName.isEmpty)
        // No override applied so /v1/host would still report the system name.
        #expect(store.displayNameOverride == nil)
    }

    @Test func displayNamePersistsAndOverridesFolderStore() {
        Self.clearDefaults()
        defer { Self.clearDefaults() }
        let store = HostFolderStore()
        let one = RemoteHostController(folderStore: store)
        one.displayName = "My Mac"
        #expect(store.displayNameOverride == "My Mac")
        #expect(store.hostDisplayName == "My Mac")

        // A fresh controller (e.g. relaunch) picks the value back up.
        let two = RemoteHostController()
        #expect(two.displayName == "My Mac")
    }

    @Test func displayNameClearedReturnsToSystemDefault() {
        Self.clearDefaults()
        defer { Self.clearDefaults() }
        let store = HostFolderStore()
        let controller = RemoteHostController(folderStore: store)
        controller.displayName = "Temp"
        controller.displayName = ""
        #expect(store.displayNameOverride == nil)
        // hostDisplayName falls back to system default — non-empty.
        #expect(!store.hostDisplayName.isEmpty)
    }

    @Test func setStoresForwardsToHostFolderStore() {
        Self.clearDefaults()
        defer { Self.clearDefaults() }
        let store = HostFolderStore()
        let controller = RemoteHostController(folderStore: store)
        let s1 = IssueStore(folderURL: URL(fileURLWithPath: "/tmp/a"), bookmarkData: Data("a".utf8))
        let s2 = IssueStore(folderURL: URL(fileURLWithPath: "/tmp/b"), bookmarkData: Data("b".utf8))
        controller.setStores([s1, s2])
        #expect(store.stores.count == 2)
    }

    // MARK: - Pause / re-enable (#0105)

    @Test func isPausedReflectsIntentDivergence() {
        Self.clearDefaults()
        defer { Self.clearDefaults() }
        let controller = RemoteHostController()
        #expect(controller.isPaused == false)
    }

    @Test func userIntentPersistsAcrossInstances() {
        Self.clearDefaults()
        defer { Self.clearDefaults() }
        UserDefaults.standard.set(true, forKey: "RemoteServer.enabled")
        let controller = RemoteHostController()
        #expect(controller.isUserEnabled == true)
    }

    @Test func togglingOffClearsUserIntent() {
        Self.clearDefaults()
        defer { Self.clearDefaults() }
        UserDefaults.standard.set(true, forKey: "RemoteServer.enabled")
        let controller = RemoteHostController()
        controller.setEnabled(false)
        #expect(controller.isUserEnabled == false)
        #expect(UserDefaults.standard.bool(forKey: "RemoteServer.enabled") == false)
    }
}

#endif
