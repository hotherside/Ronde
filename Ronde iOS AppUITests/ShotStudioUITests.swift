import XCTest

/// Runs against the Debug preview account and a generated local movie. These checks exercise
/// native navigation and editing; the synthetic fixture is not ball-tracking accuracy evidence.
@MainActor
final class ShotStudioUITests: XCTestCase {
    private let fixtureCardID = "shot-card-0B436158-6DE4-43E8-9317-4EFD8840474A"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSessionNavigationAndAddingARecordingKeepTheSessionContext() throws {
        let app = try launch(screen: "ios-redesign-home")
        let session = app.buttons["session-card-0B436158-6DE4-43E8-9317-4EFD8840474A"]
        reveal(session, in: app)
        capture("Sessions", app: app)
        session.tap()
        let add = app.buttons["session-add-recording"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Shots"].exists)
        add.tap()
        XCTAssertTrue(app.buttons["add-recording-photos"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["recording-session-title"].exists, "Adding a recording must preserve the existing session.")
        XCTAssertTrue(app.buttons["add-recording-files"].exists)
        capture("Add recording", app: app)
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
    }

    func testLibraryOpensStudioAndCancellingDetailsKeepsTheTitle() throws {
        let app = try launch(screen: "ios-redesign-library")
        let card = app.descendants(matching: .any).matching(identifier: fixtureCardID).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["studio-play"].waitForExistence(timeout: 10))

        let details = app.buttons["studio-details"]
        app.buttons["studio-more-options"].tap()
        details.tap()
        let title = app.textFields["shot-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let originalTitle = try XCTUnwrap(title.value as? String)
        XCTAssertFalse(originalTitle.isEmpty)
        title.tap()
        title.typeText(" discarded edit")
        XCTAssertNotEqual(title.value as? String, originalTitle)
        app.navigationBars.buttons["Cancel"].firstMatch.tap()

        app.buttons["studio-more-options"].tap()
        details.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, originalTitle)
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
    }

    func testPauseAndResumeKeepTheCurrentSourcePosition() throws {
        let app = try launch(screen: "ios-redesign-media")
        let position = app.sliders["studio-position"]
        let play = app.buttons["studio-play"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Playback speed,")).firstMatch.tap()
        app.buttons["0.25× speed"].tap()
        position.adjust(toNormalizedSliderPosition: 0.35)
        let soughtTime = try XCTUnwrap(timeValue(of: position))
        XCTAssertGreaterThan(soughtTime, 1.5)

        play.tap()
        waitFor(NSPredicate(format: "label == %@", "Pause"), on: play)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (self.timeValue(of: position) ?? -1) > soughtTime + 0.2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 4), .completed)
        play.tap()
        waitFor(NSPredicate(format: "label == %@", "Play"), on: play)
        let pausedTime = try XCTUnwrap(timeValue(of: position))
        XCTAssertGreaterThan(pausedTime, soughtTime)

        // A paused player must remain still, rather than silently playing behind a Play label.
        let movedWhilePaused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs((self.timeValue(of: position) ?? pausedTime) - pausedTime) > 0.15
        }, object: nil)
        movedWhilePaused.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [movedWhilePaused], timeout: 0.5), .completed)

        play.tap()
        waitFor(NSPredicate(format: "label == %@", "Pause"), on: play)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(timeValue(of: position)), pausedTime - 0.15,
                                    "Play resumes the current position; Replay cut is the explicit restart action.")
        play.tap()
    }

    func testTrimFormatTilesAndSquareExportReachTheNativeShareSheet() throws {
        let app = try launch(screen: "ios-redesign-media")
        XCTAssertTrue(app.buttons["studio-play"].waitForExistence(timeout: 10))
        let trimTab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Trim")).firstMatch
        reveal(trimTab, in: app)
        trimTab.tap()
        let start = app.sliders["studio-trim-start"]
        let end = app.sliders["studio-trim-end"]
        reveal(start, in: app)
        start.adjust(toNormalizedSliderPosition: 0.15)
        reveal(end, in: app)
        end.adjust(toNormalizedSliderPosition: 0.50)
        let cutStart = try XCTUnwrap(timeValue(of: start))
        let cutEnd = try XCTUnwrap(timeValue(of: end))
        XCTAssertGreaterThan(cutStart, 0.3)
        XCTAssertGreaterThan(cutEnd, cutStart + 0.5)
        XCTAssertLessThan(cutEnd, 5)

        let traceTab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Trace")).firstMatch
        reveal(traceTab, in: app)
        traceTab.tap()
        XCTAssertTrue(traceTab.exists)

        let formatTab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Format")).firstMatch
        reveal(formatTab, in: app)
        formatTab.tap()
        for title in ["Original canvas", "9:16 vertical canvas", "1:1 square canvas", "16:9 landscape canvas"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), "Studio format tile \(title) should be available.")
        }
        let studioSquare = app.buttons["1:1 square canvas"]
        reveal(studioSquare, in: app)
        studioSquare.tap()

        app.buttons["studio-share"].tap()
        let square = app.buttons["studio-export-format-square"]
        XCTAssertTrue(square.waitForExistence(timeout: 5))
        reveal(square, in: app)
        square.tap()
        let preview = app.descendants(matching: .any).matching(identifier: "studio-export-preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertEqual(preview.value as? String, "1:1 square")

        let render = app.buttons["studio-export-render"]
        reveal(render, in: app)
        render.tap()
        let ready = app.descendants(matching: .any).matching(identifier: "studio-export-ready").firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 45), "A short local synthetic movie should export successfully.")
        let share = app.buttons["studio-export-share"]
        reveal(share, in: app)
        share.tap()
        // Assert presentation only. Never select a recipient, post, or send anything from a test.
        let systemShareAction = app.cells.matching(NSPredicate(format: "label IN %@", ["Copy", "Save Video", "Save to Files", "AirDrop"])).firstMatch
        XCTAssertTrue(systemShareAction.waitForExistence(timeout: 10), "The completed file should open the system activity sheet.")
    }

    func testCancellingManualTraceDoesNotCreateAnAnnotation() throws {
        let app = try launch(screen: "ios-redesign-media")
        let traceTab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Trace")).firstMatch
        reveal(traceTab, in: app)
        traceTab.tap()
        let manual = app.buttons["studio-manual-trace"]
        reveal(manual, in: app)
        manual.tap()
        let add = app.buttons["Add manual trace"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.navigationBars["Manual trace"].waitForExistence(timeout: 5))
        let fineAdjustment = app.buttons["Fine adjustment"]
        reveal(fineAdjustment, in: app)
        fineAdjustment.tap()
        let horizontal = app.sliders.matching(NSPredicate(format: "label ENDSWITH %@", "horizontal position")).firstMatch
        reveal(horizontal, in: app)
        horizontal.adjust(toNormalizedSliderPosition: 0.65)
        app.navigationBars.buttons["Cancel"].firstMatch.tap()

        XCTAssertTrue(app.buttons["studio-play"].isEnabled, "Closing the editor restores the source player.")
        reveal(manual, in: app)
        manual.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Edit manual trace"].exists)
        XCTAssertFalse(app.buttons["Remove manual trace"].exists)
    }

    func testRecordingBookmarkCreatesShotAndOpensStudioFormats() throws {
        let app = try launch(screen: "ios-recording-studio")
        let position = app.sliders["recording-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        position.adjust(toNormalizedSliderPosition: 0.5)

        let play = app.buttons["recording-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))

        let addBookmark = app.buttons["recording-add-bookmark"]
        reveal(addBookmark, in: app)
        addBookmark.tap()
        let beforeRotation = position.value as? String
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["recording-create-shots"].waitForExistence(timeout: 5))
        XCTAssertEqual(position.value as? String, beforeRotation, "Changing layout must retain the source playhead.")
        XCUIDevice.shared.orientation = .portrait
        capture("Recording Studio bookmark", app: app)

        for identifier in [
            "recording-before-increase",
            "recording-before-decrease",
            "recording-after-increase",
            "recording-after-decrease"
        ] {
            let control = app.buttons[identifier].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Bookmark control \(identifier) should be available.")
            control.tap()
        }

        let createShots = app.buttons["recording-create-shots"]
        reveal(createShots, in: app)
        createShots.tap()

        let openShot = app.buttons["recording-open-shot"].firstMatch
        XCTAssertTrue(openShot.waitForExistence(timeout: 10))
        openShot.tap()
        XCTAssertTrue(app.buttons["studio-play"].waitForExistence(timeout: 10))

        let formatTab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Format")).firstMatch
        reveal(formatTab, in: app)
        formatTab.tap()
        let square = app.buttons["1:1 square canvas"]
        reveal(square, in: app)
        square.tap()
        XCTAssertEqual(square.value as? String, "Selected")
        XCTAssertTrue(app.buttons["9:16 vertical canvas"].exists)
        capture("Shot Studio formats", app: app)
    }

    func testPopulatedConceptReviewKeepsMediaAndToolsVisible() throws {
        let app = try launch(screen: "ios-concept-home")
        let latest = app.buttons["session-card-090F916A-C8E4-449C-B159-990051228290"]
        XCTAssertTrue(latest.waitForExistence(timeout: 10))
        let keeper = app.buttons["shot-card-090F916A-C8E4-449C-B159-990051228300"]
        XCTAssertTrue(keeper.waitForExistence(timeout: 5))
        capture("Concept Sessions", app: app)
        XCTAssertLessThan(latest.frame.minY, 220, "Footage should start in the first quarter of a normal phone screen.")
        XCTAssertTrue(keeper.isHittable, "The latest session and first keeper must share the first viewport.")
        latest.tap()
        let recording = app.buttons["recording-card-090F916A-C8E4-449C-B159-990051228292"]
        XCTAssertTrue(recording.waitForExistence(timeout: 5))
        capture("Concept Session", app: app)
        recording.tap()
        XCTAssertTrue(app.buttons["recording-play"].waitForExistence(timeout: 10))
        app.buttons["Bookmark at 0:10"].tap()
        capture("Concept Recording", app: app)
        app.buttons["Bookmark at 0:06"].tap()
        let openShot = app.buttons["Edit shot"]
        reveal(openShot, in: app)
        openShot.tap()

        let studio = app
        let play = studio.buttons["studio-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        waitFor(NSPredicate(format: "exists == false"), on: studio.staticTexts["Preparing frame controls…"])
        let formatTab = studio.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Format")).firstMatch
        XCTAssertTrue(formatTab.isHittable, "Editing tools should be visible beside the preview on a normal phone.")
        formatTab.tap()
        let square = studio.buttons["1:1 square canvas"]
        XCTAssertTrue(square.isHittable)
        XCTAssertTrue(play.isHittable, "Choosing a format must keep the video transport visible.")
        capture("Concept Shot Studio Original", app: studio)
        square.tap()
        capture("Concept Shot Studio Square", app: studio)
    }

    private func launch(screen: String) throws -> XCUIApplication {
        let bundle = Bundle(for: Self.self)
        let fixture = try XCTUnwrap(
            bundle.url(forResource: "studio-fixture", withExtension: "mp4")
                ?? bundle.url(forResource: "studio-fixture", withExtension: "mp4", subdirectory: "Resources"),
            "Include the generated studio-fixture.mp4 in the UI-test target's resources."
        )
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_AU"]
        app.launchEnvironment["RONDE_PREVIEW_SCREEN"] = screen
        if screen.hasPrefix("ios-concept-") {
            let range = try XCTUnwrap(bundle.url(forResource: "clubhouse-range", withExtension: "mp4"))
            let course = try XCTUnwrap(bundle.url(forResource: "clubhouse-course", withExtension: "mp4"))
            app.launchEnvironment["RONDE_PREVIEW_VIDEO_PATH"] = range.path
            app.launchEnvironment["RONDE_PREVIEW_SECONDARY_VIDEO_PATH"] = course.path
        } else {
            app.launchEnvironment["RONDE_PREVIEW_VIDEO_PATH"] = fixture.path
        }
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), file: file, line: line)
        for _ in 0..<5 where !element.isHittable {
            let scroll = app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable) ?? app.scrollViews.firstMatch
            scroll.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Control must be reachable by scrolling.", file: file, line: line)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        // Multi-display Simulators can render the app away from the main display.
        // Preserve every active display so the artifact can be checked against the UI test.
        let screens = XCUIScreen.screens.isEmpty ? [XCUIScreen.main] : XCUIScreen.screens
        for (index, screen) in screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = "\(name) - display \(index + 1)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func timeValue(of element: XCUIElement) -> Double? {
        guard let value = element.value as? String,
              let timestamp = value.components(separatedBy: " of ").first else { return nil }
        let parts = timestamp.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }

    private func waitFor(_ predicate: NSPredicate, on element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }
}
