// IssuesUITestsLaunchTests.swift

import XCTest

// The project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise
// promote this class to @MainActor, which doesn't match XCTestCase's
// `nonisolated` overridable members. Marking the class `nonisolated`
// keeps it aligned with the superclass while individual @MainActor test
// methods stay opt-in.
nonisolated final class IssuesUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
