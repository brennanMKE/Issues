// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Important: Use these settings for most targets.
let swiftSettings: [SwiftSetting]? = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "IssuesKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IssuesCore", targets: ["IssuesCore"]),
        .library(name: "IssuesAppKit", targets: ["IssuesAppKit"]),
        .library(name: "IssuesCLI", targets: ["IssuesCLI"]),
        .library(name: "IssuesDashboardCLI", targets: ["IssuesDashboardCLI"]),
    ],
    dependencies: [
        .package(url: "git@github.com:brennanMKE/Watcher.git", branch: "main"),
        .package(url: "https://github.com/gonzalezreal/textual.git", branch: "main"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
        .package(url: "https://github.com/rensbreur/SwiftTUI.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "IssuesCore",
            dependencies: [
                .product(name: "Watcher", package: "Watcher"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "IssuesAppKit",
            dependencies: [
                "IssuesCore",
                .product(name: "Textual", package: "textual"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "IssuesCLI",
            dependencies: ["IssuesCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "IssuesDashboardCLI",
            dependencies: [
                "IssuesCore",
                .product(name: "SwiftTUI", package: "SwiftTUI"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "IssuesKitTests",
            dependencies: ["IssuesCore", "IssuesAppKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
