//
//  sevenwalletUITests.swift
//  sevenwalletUITests
//
//  Created by Wane on 2026/7/22.
//

import XCTest

final class sevenwalletUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testWalletHomeContent() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["wallet-selector-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["theme-toggle-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Main Wallet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["TOTAL VALUE"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["copy-wallet-address-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["manage-tokens-button"].waitForExistence(timeout: 2))

        for symbol in ["ETH", "BTC", "SOL", "USDC"] {
            XCTAssertTrue(app.staticTexts[symbol].firstMatch.waitForExistence(timeout: 2))
        }
    }

    @MainActor
    func testThemeButtonTogglesDisplayedMode() throws {
        let app = XCUIApplication()
        app.launch()

        let themeButton = app.buttons["theme-toggle-button"]
        XCTAssertTrue(themeButton.waitForExistence(timeout: 2))
        XCTAssertEqual(themeButton.label, "Switch to light theme")

        themeButton.tap()

        let switchedToDark = expectation(
            for: NSPredicate(format: "label == %@", "Switch to dark theme"),
            evaluatedWith: themeButton
        )
        wait(for: [switchedToDark], timeout: 2)
    }

    @MainActor
    func testTokensHeaderPinsBelowTopBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TEST_LONG_TOKEN_LIST"]
        app.launch()

        let topBar = app.otherElements["wallet-top-bar"]
        let tokensHeader = app.otherElements["tokens-header"]
        XCTAssertTrue(topBar.waitForExistence(timeout: 2))
        XCTAssertTrue(tokensHeader.waitForExistence(timeout: 2))

        let initialHeaderY = tokensHeader.frame.minY
        let topBarBottom = topBar.frame.maxY

        for _ in 0..<4 where tokensHeader.frame.minY > topBarBottom + 3 {
            app.swipeUp()
        }

        let pinnedHeaderY = tokensHeader.frame.minY
        XCTAssertLessThan(pinnedHeaderY, initialHeaderY)
        XCTAssertEqual(pinnedHeaderY, topBarBottom, accuracy: 3)

        app.swipeUp()
        XCTAssertEqual(tokensHeader.frame.minY, pinnedHeaderY, accuracy: 3)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
