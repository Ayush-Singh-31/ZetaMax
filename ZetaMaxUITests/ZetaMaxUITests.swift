import XCTest

final class ZetaMaxUITests: XCTestCase {
    func testCorrectAnswerAutoAdvancesAndReturnIsInert() throws {
        let app = launch()

        let start = app.buttons["startSessionButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.click()

        let answer = app.textFields["answerField"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.typeText("999")
        answer.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(answer.value as? String, "999", "Return must preserve an incomplete answer")

        let questionText = question(in: app)
        XCTAssertTrue(questionText.waitForExistence(timeout: 2))
        let prompt = questionText.label
        answer.typeKey("a", modifierFlags: [.command])
        answer.typeText(try XCTUnwrap(expectedAnswer(for: prompt)))
        XCTAssertTrue(waitForQuestionToChange(questionText, from: prompt))

        answer.typeText("999")
        answer.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(answer.value as? String, "999", "Typing immediately after auto-advance should still reach the focused field")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'accuracy'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Return records'")).firstMatch.exists)
    }

    func testNegativeAnswerAutoSubmits() throws {
        let app = launch(extraArguments: ["-ui-testing-negative"])
        app.buttons["startSessionButton"].click()
        let answer = app.textFields["answerField"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let questionText = question(in: app)
        XCTAssertTrue(questionText.waitForExistence(timeout: 2))
        let prompt = questionText.label
        let expected = try XCTUnwrap(expectedAnswer(for: prompt))
        XCTAssertTrue(expected.hasPrefix("-"))
        answer.typeText(expected)
        XCTAssertTrue(waitForQuestionToChange(questionText, from: prompt))
    }

    func testDecimalAnswerAutoSubmits() throws {
        let app = launch(extraArguments: ["-ui-testing-decimal"])
        app.buttons["startSessionButton"].click()
        let answer = app.textFields["answerField"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let questionText = question(in: app)
        XCTAssertTrue(questionText.waitForExistence(timeout: 2))
        let prompt = questionText.label
        answer.typeText(try XCTUnwrap(expectedAnswer(for: prompt)))
        XCTAssertTrue(waitForQuestionToChange(questionText, from: prompt))
    }

    func testTimingOnlyResultsDashboardAndHistory() throws {
        let app = launch(extraArguments: ["-ui-testing-analytics"])

        app.typeKey("3", modifierFlags: [.command])
        XCTAssertTrue(app.staticTexts["PERFORMANCE LAB"].waitForExistence(timeout: 5))
        for label in ["COMPLETED", "P90", "CONSISTENCY", "RECENT CHANGE", "Performance over time"] {
            XCTAssertTrue(app.staticTexts[label].firstMatch.exists, "Missing timing analytics surface: \(label)")
        }
        let analyticsScroll = try XCTUnwrap(
            app.scrollViews.allElementsBoundByIndex.max { $0.frame.width < $1.frame.width },
            "The analytics detail scroll view should be available"
        )
        for label in [
            "Category difficulty", "Response-time distribution", "Category effort map",
            "Multiplication heatmap", "Session fatigue", "Slowest completions"
        ] {
            let matchingText = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH[c] %@ OR value BEGINSWITH[c] %@", label, label)
            )
            XCTAssertGreaterThan(matchingText.count, 0, "Missing timing analytics surface: \(label)")
        }
        analyticsScroll.swipeUp()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Timing-only analytics"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'accuracy'")).firstMatch.exists)

        app.typeKey("4", modifierFlags: [.command])
        let row = app.descendants(matching: .any)["historySessionRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(app.staticTexts["Question timings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["COMPLETED"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["P90"].firstMatch.exists)

        app.typeKey("1", modifierFlags: [.command])
        app.buttons["startSessionButton"].click()
        let answer = app.textFields["answerField"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let questionText = question(in: app)
        let prompt = questionText.label
        answer.typeText(try XCTUnwrap(expectedAnswer(for: prompt)))
        XCTAssertTrue(waitForQuestionToChange(questionText, from: prompt))
        app.buttons["End"].click()
        XCTAssertTrue(app.staticTexts["Session interrupted"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["COMPLETED"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["P90"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["First try"].exists)
    }

    func testNavigationFitsCompactWindowAndEveryDestinationIsReachable() throws {
        let app = launch(extraArguments: ["-ui-testing-compact"])
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        let destinations: [(String, String)] = [
            ("1", "Train arithmetic, deliberately."),
            ("2", "A transparent diagnosis based on your saved questions—not a black box."),
            ("3", "PERFORMANCE LAB"),
            ("4", "Select a session"),
            ("5", "LOCAL CONTROL")
        ]
        for (shortcut, markerText) in destinations {
            app.typeKey(shortcut, modifierFlags: [.command])
            let marker = app.staticTexts[markerText].firstMatch
            XCTAssertTrue(marker.waitForExistence(timeout: 3), "Could not reach \(markerText)")
            let fitsAWindow = app.windows.allElementsBoundByIndex.contains { window in
                window.frame.insetBy(dx: -1, dy: -1).contains(marker.frame)
            }
            XCTAssertTrue(fitsAWindow, "\(markerText) overflowed the compact window")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Compact · \(markerText)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ApplePersistenceIgnoreState", "YES"] + extraArguments
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 1) {
            app.typeKey("n", modifierFlags: [.command])
            _ = app.windows.firstMatch.waitForExistence(timeout: 3)
        }
        return app
    }

    private func question(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'questionPrompt'"))
            .firstMatch
    }

    private func waitForQuestionToChange(_ question: XCUIElement, from prompt: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", prompt), object: question)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    private func expectedAnswer(for prompt: String) -> String? {
        let parts = prompt.split(separator: " ")
        guard parts.count == 3 else { return nil }
        let left = NSDecimalNumber(string: String(parts[0]))
        let right = NSDecimalNumber(string: String(parts[2]))
        let result: NSDecimalNumber
        switch parts[1] {
        case "+": result = left.adding(right)
        case "−", "-": result = left.subtracting(right)
        case "×", "*": result = left.multiplying(by: right)
        case "÷", "/": result = left.dividing(by: right)
        default: return nil
        }
        return result.stringValue
    }
}
