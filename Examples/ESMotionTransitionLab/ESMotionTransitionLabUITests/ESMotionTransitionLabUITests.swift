import XCTest

@MainActor
final class ESMotionTransitionLabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTapAndButtonReturn() {
        let app = launch()
        app.buttons["lab-card"].tap()
        XCTAssertTrue(
            app.otherElements["lab-detail"].waitForExistence(timeout: 5)
        )
        assertHUD(in: app, contains: "presented")
        app.buttons["lab-back"].tap()
        XCTAssertTrue(
            app.buttons["lab-card"].waitForExistence(timeout: 5)
        )
    }

    func testFastRepeatedTapCreatesOneRoute() {
        let app = launch()
        let card = app.buttons["lab-card"]
        card.tap(withNumberOfTaps: 2, numberOfTouches: 1)
        XCTAssertTrue(
            app.otherElements["lab-detail"].waitForExistence(timeout: 5)
        )
        assertHUD(in: app, contains: "presented")
        XCTAssertEqual(app.otherElements.matching(identifier: "lab-detail").count, 1)
    }

    func testShortEdgeDragCancels() {
        let app = launch()
        app.buttons["lab-card"].tap()
        let detail = app.otherElements["lab-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        assertHUD(in: app, contains: "presented")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.5))
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
    }

    func testLongEdgeDragCompletes() {
        let app = launch()
        app.buttons["lab-card"].tap()
        XCTAssertTrue(
            app.otherElements["lab-detail"].waitForExistence(timeout: 5)
        )
        assertHUD(in: app, contains: "presented")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        let hud = app.descendants(matching: .any)["esmotion-debug-hud"]
        XCTAssertTrue(
            app.buttons["lab-card"].waitForExistence(timeout: 5),
            "HUD: \(hud.value as? String ?? "unavailable")"
        )
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    private func assertHUD(
        in app: XCUIApplication,
        contains expectedValue: String
    ) {
        let hud = app.descendants(matching: .any)["esmotion-debug-hud"]
        XCTAssertTrue(hud.waitForExistence(timeout: 5))
        let predicate = NSPredicate(
            format: "value CONTAINS %@",
            expectedValue
        )
        expectation(for: predicate, evaluatedWith: hud)
        waitForExpectations(timeout: 5)
    }
}
