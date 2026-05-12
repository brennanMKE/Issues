// swift-tools-version: 5.9
import PackageDescription

// Standalone `issues` CLI for opening or focusing a folder in Issues.app
// (#0119). Lives outside the Xcode project so it can be `swift build`'d
// from any Mac without opening Xcode. The Xcode-integrated install flow
// (Copy Files build phase + in-app NSSavePanel installer) is a follow-up;
// v1 ships as a SwiftPM binary the user manually symlinks.
let package = Package(
    name: "IssuesCLI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "issues", targets: ["IssuesCLI"])
    ],
    targets: [
        .executableTarget(
            name: "IssuesCLI",
            path: "Sources/IssuesCLI"
        )
    ]
)
