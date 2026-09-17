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

        // editor
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 5))
        app.buttons["addButton"].tap()
        XCTAssertTrue(app.staticTexts["Edit Decks"].waitForExistence(timeout: 5))
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
