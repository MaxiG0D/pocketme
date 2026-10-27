import XCTest

/// Tapping an article is the one thing the library must never lose, whatever gestures sit on its rows.
@MainActor
final class LibraryTapTests: XCTestCase {
    private let title = "Why small software tends to last"
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-PocketMeUITest"]
        app.launch()
    }

    func testTappingRowOpensReader() {
        let row = app.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        #if os(iOS)
        // Compact width swaps the list for the reader; side by side the row turns selected.
        XCTAssertTrue(app.buttons["Reader settings"].waitForExistence(timeout: 5))
        #else
        let card = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(card.wait(for: \.isSelected, toEqual: true, timeout: 5))
        #endif
    }

    #if os(iOS)
    func testSwipeRevealsButtonAndRowStillOpens() {
        let row = app.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        // Other rows carry their own Archive buttons, so look only inside this row's cell.
        let archive = app.cells.containing(.staticText, identifier: title).buttons["Archive"]
        row.swipeLeft()
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        row.swipeRight()
        XCTAssertTrue(archive.waitForNonExistence(timeout: 5))
        app.swipeUp()
        app.swipeDown()
        row.tap()
        XCTAssertTrue(app.buttons["Reader settings"].waitForExistence(timeout: 5))
    }
    #endif
}
