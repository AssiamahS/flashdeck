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
        let card = app.descendants(matching: .any).matching(identifier: "studyCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        sleep(3)
        attach("02-study")

        // answer side — tap the card centre to flip it (the stack isn't "hittable" to XCUI)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
