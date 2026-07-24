import XCTest

@MainActor
final class ESMotionDemoUITests: XCTestCase {
    func testCardPresentsAndBackButtonDismisses() {
        let app = launchApp()
        continueAfterFailure = false
        let card = app.buttons["demo-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        card.tap()
        let detail = app.otherElements["demo-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))

        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertFalse(detail.exists)
    }

    func testRapidRepeatedTapCreatesOneDestination() {
        let app = launchApp()
        let card = app.buttons["demo-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        card.doubleTap()

        XCTAssertTrue(
            app.otherElements["demo-detail"].waitForExistence(timeout: 5)
        )
        XCTAssertEqual(app.otherElements.matching(identifier: "demo-detail").count, 1)
    }

    func testEdgeSwipeCompletesDismissal() {
        let app = launchApp()
        presentCard(in: app)
        let window = app.windows.firstMatch
        let start = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)
        )
        let end = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5)
        )

        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(
            app.buttons["demo-card"].waitForExistence(timeout: 5)
        )
    }

    func testShortEdgeSwipeCancelsDismissal() {
        let app = launchApp()
        presentCard(in: app)
        let window = app.windows.firstMatch
        let start = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)
        )
        let end = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)
        )

        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(
            app.otherElements["demo-detail"].waitForExistence(timeout: 5)
        )
    }

    func testMissingSourceFallsBackWithoutBlockingNavigation() {
        let app = launchApp()
        let fallback = app.buttons["demo-fallback"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 5))

        fallback.tap()

        XCTAssertTrue(
            app.navigationBars["Fallback"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.otherElements["fallback-detail"].exists)
    }

    func testDeepLinkStyleLaunchShowsDestination() {
        let app = XCUIApplication()
        app.launchEnvironment["ESMOTION_DEBUG_HUD"] = "1"
        app.launchArguments.append("ESMOTION_DEEP_LINK_DEMO")
        app.launch()

        XCTAssertTrue(
            app.otherElements["demo-detail"].waitForExistence(timeout: 5)
        )
    }

    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["ESMOTION_DEBUG_HUD"] = "1"
        app.launch()
        return app
    }

    private func presentCard(in app: XCUIApplication) {
        let card = app.buttons["demo-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(
            app.otherElements["demo-detail"].waitForExistence(timeout: 5)
        )
    }
}
