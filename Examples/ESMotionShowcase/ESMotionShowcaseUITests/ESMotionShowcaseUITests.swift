import XCTest

final class ESMotionShowcaseUITests: XCTestCase {
  @MainActor
  private func launchApp(
    arguments: [String] = []
  ) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = arguments
    app.launch()
    dismissAccountVerificationPromptIfNeeded()
    XCTAssertTrue(
      element("showcase-home", in: app).waitForExistence(timeout: 5)
    )
    return app
  }

  @MainActor
  func testPortalPresentsAndClosesThroughOnePath() {
    let app = launchApp()
    attachScreenshot(named: "01-home", app: app)
    app.buttons["showcase-portal-card"].tap()
    attachScreenshot(named: "02-immediate-after-tap", app: app)
    XCTAssertTrue(
      element("showcase-detail", in: app).waitForExistence(timeout: 3)
    )
    attachScreenshot(named: "03-detail", app: app)

    app.buttons["showcase-close"].tap()
    XCTAssertTrue(
      element("showcase-home", in: app).waitForExistence(timeout: 3)
    )
    XCTAssertFalse(element("showcase-detail", in: app).exists)
    attachScreenshot(named: "04-returned-home", app: app)
  }

  @MainActor
  func testPortalCanReenterAfterDismissal() {
    let app = launchApp()
    for _ in 0..<3 {
      app.buttons["showcase-portal-card"].tap()
      XCTAssertTrue(
        element("showcase-detail", in: app).waitForExistence(timeout: 3)
      )
      app.buttons["showcase-close"].tap()
      XCTAssertTrue(
        app.buttons["showcase-portal-card"]
          .waitForExistence(timeout: 3)
      )
    }
  }

  @MainActor
  func testEdgeDismissalCompletes() {
    let app = launchApp()
    app.buttons["showcase-portal-card"].tap()
    XCTAssertTrue(
      element("showcase-detail", in: app).waitForExistence(timeout: 3)
    )

    let start = app.coordinate(
      withNormalizedOffset: CGVector(dx: 0.01, dy: 0.52)
    )
    let end = app.coordinate(
      withNormalizedOffset: CGVector(dx: 0.82, dy: 0.52)
    )
    start.press(forDuration: 0.05, thenDragTo: end)

    XCTAssertTrue(
      element("showcase-home", in: app).waitForExistence(timeout: 3)
    )
  }

  @MainActor
  func testRuntimeTelemetryReportsHealthyFullMotion() throws {
    let app = launchApp(arguments: ["--esmotion-debug-hud"])
    let hud = element("motion-debug-hud", in: app)
    XCTAssertTrue(hud.waitForExistence(timeout: 2))

    app.buttons["showcase-portal-card"].tap()
    XCTAssertTrue(
      element("showcase-detail", in: app).waitForExistence(timeout: 3)
    )

    let healthyRuntime = NSPredicate(
      format:
        "value CONTAINS %@ AND value CONTAINS %@ AND value CONTAINS %@",
      "phase presented",
      "failure none",
      "reduced motion false"
    )
    expectation(for: healthyRuntime, evaluatedWith: hud)
    waitForExpectations(timeout: 3)

    let telemetry = String(describing: hud.value)
    let attachment = XCTAttachment(string: telemetry)
    attachment.name = "runtime-telemetry"
    attachment.lifetime = .keepAlways
    add(attachment)
    let firstFrameMilliseconds = try XCTUnwrap(
      metric(named: "first frame", from: telemetry)
    )
    XCTAssertGreaterThan(firstFrameMilliseconds, 0)
    XCTAssertLessThan(firstFrameMilliseconds, 100)
  }

  @MainActor
  private func element(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  @MainActor
  private func dismissAccountVerificationPromptIfNeeded() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for label in ["以后", "Later", "Not Now"] {
      let button = springboard.buttons[label]
      if button.waitForExistence(timeout: 1) {
        button.tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 2))
        Thread.sleep(forTimeInterval: 1)
        return
      }
    }
  }

  private func metric(
    named name: String,
    from telemetry: String
  ) -> Double? {
    guard
      let suffix =
        telemetry
        .components(separatedBy: "\(name) ")
        .dropFirst()
        .first,
      let token = suffix.split(separator: " ").first
    else {
      return nil
    }
    return Double(token)
  }

  @MainActor
  private func attachScreenshot(
    named name: String,
    app: XCUIApplication
  ) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
