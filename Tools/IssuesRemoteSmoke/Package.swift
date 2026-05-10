// swift-tools-version: 5.9
import PackageDescription

// Standalone smoke-test CLI for Issues.app's remote-access host (#0087).
// Lives outside the Xcode project so it can be `swift run` from any Mac
// without opening Xcode. The wire-types module reuses the same source
// file the host uses (`../../Issues/Remote/RemoteProtocol.swift`) so the
// CLI and the host can never disagree about JSON keys.
let package = Package(
    name: "IssuesRemoteSmoke",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "IssuesRemoteSmoke",
            dependencies: ["IssuesRemoteProtocol"],
            path: "Sources/IssuesRemoteSmoke"
        ),
        // The file at Sources/IssuesRemoteProtocol/RemoteProtocol.swift is a
        // git-tracked symlink to ../../../../Issues/Remote/RemoteProtocol.swift
        // so the wire types stay byte-for-byte identical between the host and
        // the smoke CLI without a duplicate definition.
        .target(
            name: "IssuesRemoteProtocol",
            path: "Sources/IssuesRemoteProtocol"
        )
    ]
)
