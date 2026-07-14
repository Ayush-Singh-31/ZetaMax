import CoreGraphics
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
        XCTAssertEqual(answer.value as? String, "999", "Focus must remain in the field after automatic advancement")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'accuracy'")).firstMatch.exists)
    }

    func testNegativeAndDecimalAnswersAutoSubmit() throws {
        for argument in ["-ui-testing-negative", "-ui-testing-decimal"] {
            let app = launch(extraArguments: [argument])
            app.buttons["startSessionButton"].click()
            let answer = app.textFields["answerField"]
            XCTAssertTrue(answer.waitForExistence(timeout: 5))
            let questionText = question(in: app)
            XCTAssertTrue(questionText.waitForExistence(timeout: 2))
            let prompt = questionText.label
            let expected = try XCTUnwrap(expectedAnswer(for: prompt))
            if argument.contains("negative") { XCTAssertTrue(expected.hasPrefix("-")) }
            answer.typeText(expected)
            XCTAssertTrue(waitForQuestionToChange(questionText, from: prompt))
            app.terminate()
        }
    }

    func testEveryAnalyticsSectionRendersFromTheSharedFixture() throws {
        let sections: [(String, String, String, String)] = [
            ("Overview", "analyticsOverviewSection", "Performance over time", "Analytics · Overview"),
            ("Skills", "analyticsSkillsSection", "Operation timing", "Analytics · Skills"),
            ("Distribution", "analyticsDistributionSection", "Response-time distribution", "Analytics · Distribution"),
            ("Benchmarks", "analyticsBenchmarksSection", "Benchmark outlook", "Analytics · Benchmarks")
        ]

        for (section, identifier, marker, screenshotName) in sections {
            let app = launch(extraArguments: ["-ui-testing-analytics", "-ui-testing-wide", "-ui-testing-analytics-section", section.lowercased()])
            app.typeKey("3", modifierFlags: [.command])
            XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 8), "Missing \(identifier)")
            XCTAssertTrue(app.descendants(matching: .any)["analyticsSectionPicker"].exists)
            XCTAssertTrue(app.staticTexts[marker].firstMatch.waitForExistence(timeout: 5), "Missing \(marker)")
            assertInsideWindow(app.staticTexts[marker].firstMatch, app: app)
            attachScreenshot(app, name: screenshotName)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'accuracy' OR label CONTAINS[c] 'error rate'")).firstMatch.exists)
            app.terminate()
        }
    }

    func testCompactHistoryUsesBoundedListDetailNavigation() throws {
        let app = launch(extraArguments: ["-ui-testing-analytics", "-ui-testing-compact"])
        app.typeKey("4", modifierFlags: [.command])
        let list = app.descendants(matching: .any)["historyCompactList"]
        XCTAssertTrue(list.waitForExistence(timeout: 8))
        assertInsideWindow(list, app: app)

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'historySessionRow-'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        let detail = app.descendants(matching: .any)["historySessionDetail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["historyBackButton"].exists)
        XCTAssertTrue(app.tables["attemptTable"].exists || app.descendants(matching: .any)["attemptTable"].exists)
        assertInsideWindow(detail, app: app)
        let export = app.descendants(matching: .any)["historyDetailExport"]
        XCTAssertTrue(export.exists)
        assertInsideWindow(export, app: app)
        attachScreenshot(app, name: "History · Compact detail")

        app.buttons["historyBackButton"].click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
    }

    func testNavigationAndPrimaryControlsFitCompactWindow() throws {
        let destinations: [(String, String)] = [
            ("1", "practiceScreen"),
            ("2", "recommendationsScreen"),
            ("3", "analyticsFilterBar"),
            ("4", "historyCompactList"),
            ("5", "settingsScreen")
        ]
        for (shortcut, identifier) in destinations {
            let app = launch(extraArguments: ["-ui-testing-compact"])
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
            app.typeKey(shortcut, modifierFlags: [.command])
            let marker = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(marker.waitForExistence(timeout: 5), "Could not reach \(identifier)")
            assertInsideWindow(marker, app: app)
            app.terminate()
        }
    }

    func testVisualLightCompact() throws { try verifyVisualState(appearance: "Light", appearanceArgument: "-ui-testing-light", sizeName: "Compact", sizeArgument: "-ui-testing-compact", width: 860) }
    func testVisualLightMedium() throws { try verifyVisualState(appearance: "Light", appearanceArgument: "-ui-testing-light", sizeName: "Medium", sizeArgument: "-ui-testing-medium", width: 1_100) }
    func testVisualLightWide() throws { try verifyVisualState(appearance: "Light", appearanceArgument: "-ui-testing-light", sizeName: "Wide", sizeArgument: "-ui-testing-wide", width: 1_500) }
    func testVisualDarkCompact() throws { try verifyVisualState(appearance: "Dark", appearanceArgument: "-ui-testing-dark", sizeName: "Compact", sizeArgument: "-ui-testing-compact", width: 860) }
    func testVisualDarkMedium() throws { try verifyVisualState(appearance: "Dark", appearanceArgument: "-ui-testing-dark", sizeName: "Medium", sizeArgument: "-ui-testing-medium", width: 1_100) }
    func testVisualDarkWide() throws { try verifyVisualState(appearance: "Dark", appearanceArgument: "-ui-testing-dark", sizeName: "Wide", sizeArgument: "-ui-testing-wide", width: 1_500) }

    private func verifyVisualState(
        appearance: String,
        appearanceArgument: String,
        sizeName: String,
        sizeArgument: String,
        width: CGFloat
    ) throws {
        let app = launch(extraArguments: ["-ui-testing-analytics", sizeArgument, appearanceArgument])
        defer { app.terminate() }
        XCTAssertTrue(waitForWindowWidth(width, app: app), "Window did not settle at \(sizeName) width")

        app.typeKey("3", modifierFlags: [.command])
        let overview = app.descendants(matching: .any)["analyticsOverviewSection"]
        XCTAssertTrue(overview.waitForExistence(timeout: 8))
        assertInsideWindow(app.descendants(matching: .any)["analyticsFilterBar"].firstMatch, app: app)
        attachScreenshot(app, name: "After · Analytics overview · \(appearance) · \(sizeName)")

        app.typeKey("4", modifierFlags: [.command])
        let historyMarker = app.descendants(matching: .any)[sizeName == "Compact" ? "historyCompactList" : "historyWideList"]
        XCTAssertTrue(historyMarker.waitForExistence(timeout: 8))
        assertInsideWindow(historyMarker, app: app)
        attachScreenshot(app, name: "After · History · \(appearance) · \(sizeName)")
    }

    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ApplePersistenceIgnoreState", "YES"] + extraArguments
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 2) {
            app.typeKey("n", modifierFlags: [.command])
            if !app.windows.firstMatch.waitForExistence(timeout: 10) {
                app.typeKey("n", modifierFlags: [.command])
                _ = app.windows.firstMatch.waitForExistence(timeout: 4)
            }
        }
        return app
    }

    private func assertInsideWindow(_ element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, "Expected element to exist", file: file, line: line)
        let window = app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1)
        XCTAssertTrue(window.contains(element.frame), "\(element.identifier) overflowed the window: \(element.frame) outside \(window)", file: file, line: line)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.exists ? app.windows.firstMatch.screenshot() : app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForWindowWidth(_ expectedWidth: CGFloat, app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement, element.exists else { return false }
                return abs(element.frame.width - expectedWidth) <= 3
            },
            object: window
        )
        return XCTWaiter.wait(for: [settled], timeout: 5) == .completed
    }

    private func question(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'questionPrompt'")).firstMatch
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
