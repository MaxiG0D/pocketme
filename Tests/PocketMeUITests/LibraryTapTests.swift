import XCTest

/// Tapping an article is the one thing the library must never lose, whatever gestures sit on its rows.
@MainActor
final class LibraryTapTests: XCTestCase {
    private let title = "Why small software tends to last"
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Pins the layout for the run, whatever the last run left in the simulator's defaults.
        app.launchArguments = ["-PocketMeUITest", "-libraryLayout", "list"]
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

    private func openVideo() {
        let video = app.staticTexts["A short film about slow mornings"].firstMatch
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10))
        // The film is the oldest row, below the fold and not built until scrolled to.
        for _ in 0..<5 where !video.exists || !video.isHittable { app.swipeUp() }
        XCTAssertTrue(video.isHittable)
        video.tap()
    }

    func testTheaterModeAndBack() {
        openVideo()
        let enter = app.buttons["Theater mode"].firstMatch
        XCTAssertTrue(enter.waitForExistence(timeout: 5))
        // Picture in Picture is offered only once a video is playing.
        XCTAssertFalse(app.buttons["Picture in Picture"].exists)
        enter.tap()
        let leave = app.buttons["Leave theater mode"]
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        leave.tap()
        XCTAssertTrue(leave.waitForNonExistence(timeout: 5))
    }

    /// Theater mode on play is off by default, so Play just plays inline.
    func testPlayStaysInlineByDefault() {
        openVideo()
        let play = app.buttons["Play video"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.buttons["Leave theater mode"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Theater mode"].exists)
    }

    #if os(iOS)
    func testTappingGridCardOpensReader() {
        app.terminate()
        app.launchArguments = ["-PocketMeUITest", "-libraryLayout", "grid"]
        app.launch()
        let card = app.staticTexts[title].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        // The list stays built behind the grid; none of it may reach VoiceOver.
        XCTAssertEqual(app.staticTexts.matching(identifier: title).count, 1)
        card.tap()
        XCTAssertTrue(app.buttons["Reader settings"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["Reader settings"].waitForExistence(timeout: 5))
    }

    func testArchiveFromReaderReturnsToList() {
        let row = app.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let archive = app.buttons["Archive"].firstMatch
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        XCTAssertTrue(app.buttons["Reader settings"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForNonExistence(timeout: 5))
    }

    func testDeleteFromReaderAsksFirst() {
        let row = app.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let delete = app.buttons["Delete"].firstMatch
        // Narrow bars fold the overflow into the system's More menu.
        if !delete.waitForExistence(timeout: 5) { app.buttons["More"].firstMatch.tap() }
        delete.tap()
        XCTAssertTrue(app.staticTexts["Delete this article?"].waitForExistence(timeout: 5))
        // The dialog's button is drawn above the toolbar's, which stays in the tree behind it.
        app.buttons.matching(identifier: "Delete").allElementsBoundByIndex.last!.tap()
        XCTAssertTrue(app.buttons["Reader settings"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForNonExistence(timeout: 5))
    }

    func testTheaterOnPlaySettingIsOffByDefault() {
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.descendants(matching: .any)["Theater mode on play"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "Off")
    }

    func testSwitchingLayoutsKeepsTapsOnTheRightArticle() {
        app.terminate()
        // Unpinned, so the toggle can change the stored layout.
        app.launchArguments = ["-PocketMeUITest"]
        app.launch()
        let toGrid = app.buttons["Show as grid"], toList = app.buttons["Show as list"]
        XCTAssertTrue(toGrid.waitForExistence(timeout: 10) || toList.exists)
        if toList.exists { toList.tap() }
        for button in [toGrid, toList, toGrid, toList] {
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts.matching(identifier: title).count, 1)
        }
        app.staticTexts[title].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reader settings"].waitForExistence(timeout: 5))
    }

    func testSwipeRevealsButtonAndRowStillOpens() {
        let row = app.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        // A row draws its Archive button only while swiped open; the filter pill is the one that is always there.
        let archive = app.buttons.matching(identifier: "Archive")
        let resting = archive.count
        func waitForCount(_ count: Int) -> Bool {
            let end = Date().addingTimeInterval(5)
            while archive.count != count && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
            return archive.count == count
        }
        row.swipeLeft()
        XCTAssertTrue(waitForCount(resting + 1))
        row.swipeRight()
        XCTAssertTrue(waitForCount(resting))
        app.swipeUp()
        app.swipeDown()
        row.tap()
        XCTAssertTrue(app.buttons["Reader settings"].waitForExistence(timeout: 5))
    }
    #endif
}
