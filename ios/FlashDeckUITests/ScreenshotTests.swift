import XCTest

final class ScreenshotTests: XCTestCase {

    @MainActor
    func testScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        // home — decks load from the network
        let capitals = app.staticTexts["World Capitals"]
        XCTAssertTrue(capitals.waitForExistence(timeout: 30))
        sleep(1)
        attach("01-home")

        // study front, give the flag image a moment
        capitals.tap()
        // first card of World Capitals is France (all boxes equal → deck order)
        let front = app.staticTexts["France"]
        XCTAssertTrue(front.waitForExistence(timeout: 10))
        sleep(3)
        attach("02-study")

        // answer side — tapping the front text taps the card, which flips it
        front.tap()
        XCTAssertTrue(app.staticTexts["Paris"].waitForExistence(timeout: 5))
        sleep(1)
        attach("03-answer")

        // editor — go back explicitly (firstMatch would hit the mute button since 1.3)
        let back = app.navigationBars.buttons.matching(NSPredicate(format: "label == 'Flash Deck' OR label == 'Back'")).firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 5))
        app.buttons["addButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Edit Decks"].firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        attach("04-editor")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
