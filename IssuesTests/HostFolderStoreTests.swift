import Testing
import IssuesCore
import Foundation
@testable import Issues

#if os(macOS)

/// Tests for `HostFolderStore` (#0085) — concrete `MultiFolderStore` for the
/// host. Each test injects two synthetic `IssueStore`s (different bookmark
/// bytes → different `folderId`s) and exercises share-flag behavior, the
/// global hosting gate, and UserDefaults persistence.
///
/// UserDefaults is process-wide; tests use uniquely-prefixed folderIds so
/// the persisted keys don't collide across runs and clean up in `defer`.
@MainActor
struct HostFolderStoreTests {

    private static func bookmarkBytes(_ s: String) -> Data { Data(s.utf8) }

    private static func makeStore(name: String, issueIds: [String] = []) -> IssueStore {
        let url = URL(fileURLWithPath: "/tmp/\(name)/issues")
        let store = IssueStore(folderURL: url, bookmarkData: bookmarkBytes(name))
        let issues = issueIds.map { id in
            IssuesCore.Issue(
                id: id,
                title: "Issue \(id)",
                status: .open,
                statusRaw: "open",
                module: "Services",
                platform: "macOS",
                firstSeen: nil,
                firstSeenRaw: "",
                closed: nil,
                closedRaw: "",
                description: "",
                fileURL: url.appendingPathComponent("\(id).md"),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                hasAttachments: false
            )
        }
        store.setIssuesForPreview(issues)
        return store
    }

    private static func cleanUp(_ store: HostFolderStore) {
        for s in store.stores {
            if let id = s.folderId {
                UserDefaults.standard.removeObject(forKey: "RemoteServer.sharedFolders.\(id)")
            }
        }
    }

    // MARK: - Hosted folders

    @Test func currentlyHostedFoldersIsEmptyWhenGlobalHostingOff() {
        let store = HostFolderStore()
        defer { Self.cleanUp(store) }
        store.setStores([Self.makeStore(name: "A-\(UUID().uuidString)")])
        store.isGlobalHostingEnabled = false
        // Even if we mark the folder as shared.
        if let id = store.stores.first?.folderId {
            store.setShared(folderId: id, true)
        }
        #expect(store.currentlyHostedFolders().isEmpty)
    }

    @Test func currentlyHostedFoldersFiltersBySharedFlag() {
        let store = HostFolderStore()
        defer { Self.cleanUp(store) }
        let a = Self.makeStore(name: "shared-\(UUID().uuidString)", issueIds: ["0001"])
        let b = Self.makeStore(name: "unshared-\(UUID().uuidString)")
        store.setStores([a, b])
        store.isGlobalHostingEnabled = true
        store.setShared(folderId: a.folderId!, true)
        store.setShared(folderId: b.folderId!, false)

        let hosted = store.currentlyHostedFolders()
        #expect(hosted.count == 1)
        #expect(hosted.first?.id == a.folderId)
        #expect(hosted.first?.issues.count == 1)
    }

    @Test func currentlyHostedFolderForIdRespectsGlobalGate() {
        let store = HostFolderStore()
        defer { Self.cleanUp(store) }
        let a = Self.makeStore(name: "lookup-\(UUID().uuidString)")
        store.setStores([a])
        store.setShared(folderId: a.folderId!, true)

        store.isGlobalHostingEnabled = false
        #expect(store.currentlyHostedFolder(forId: a.folderId!) == nil)

        store.isGlobalHostingEnabled = true
        #expect(store.currentlyHostedFolder(forId: a.folderId!)?.id == a.folderId)
    }

    // MARK: - isShared default

    @Test func newlyEncounteredFolderUsesDefaultIsShared() {
        let store = HostFolderStore()
        defer { Self.cleanUp(store) }
        let a = Self.makeStore(name: "default-\(UUID().uuidString)")
        store.setStores([a])

        store.defaultIsSharedForNewFolders = false
        #expect(store.isShared(folderId: a.folderId!) == false)
    }

    @Test func setSharedPersistsAndOverridesDefault() {
        let id = "persist-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "RemoteServer.sharedFolders.\(id)") }
        let one = HostFolderStore()
        one.setShared(folderId: id, true)

        let two = HostFolderStore()
        two.defaultIsSharedForNewFolders = false
        #expect(two.isShared(folderId: id) == true)
    }

    // MARK: - setSharedForAll

    @Test func setSharedForAllAppliesToEveryStore() {
        let store = HostFolderStore()
        defer { Self.cleanUp(store) }
        let a = Self.makeStore(name: "all-a-\(UUID().uuidString)")
        let b = Self.makeStore(name: "all-b-\(UUID().uuidString)")
        store.setStores([a, b])
        store.isGlobalHostingEnabled = true

        store.setSharedForAll(true)
        #expect(store.isShared(folderId: a.folderId!) == true)
        #expect(store.isShared(folderId: b.folderId!) == true)
        #expect(store.currentlyHostedFolders().count == 2)

        store.setSharedForAll(false)
        #expect(store.currentlyHostedFolders().isEmpty)
    }

    // MARK: - hostDisplayName

    @Test func hostDisplayNameIsNotEmpty() {
        let store = HostFolderStore()
        #expect(!store.hostDisplayName.isEmpty)
    }
}

#endif
