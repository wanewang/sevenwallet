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
        app.launchArguments = ["UI_TEST_FIXTURE", "UI_TEST_POPULATED_WALLET"]
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
    func testNoWalletHomeContent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TEST_FIXTURE"]
        app.launch()

        XCTAssertTrue(app.otherElements["empty-wallet-card"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["SEVEN WALLET"].exists)
        XCTAssertTrue(app.staticTexts["Add your first wallet"].exists)
        XCTAssertTrue(app.staticTexts["Import an address to start tracking"].exists)
        XCTAssertFalse(app.buttons["copy-wallet-address-button"].exists)
        XCTAssertTrue(app.staticTexts["ETH"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Ether"].exists)
        XCTAssertTrue(app.staticTexts["-"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["$1,926.42"].exists)
    }

    @MainActor
    func testTokenLoadingIndicator() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TEST_FIXTURE",
            "UI_TEST_DELAYED_TOKENS",
            "UI_TEST_HOLD_TOKEN_LOADING"
        ]
        app.launch()

        let loadingIndicator = app.descendants(matching: .any)
            .matching(identifier: "tokens-loading-indicator")
            .firstMatch
        XCTAssertTrue(loadingIndicator.waitForExistence(timeout: 2))
    }

    @MainActor
    func testInitialTokenError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TEST_FIXTURE", "UI_TEST_TOKEN_ERROR"]
        app.launch()

        XCTAssertTrue(app.staticTexts["token-error-message"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["retry-tokens-button"].exists)
    }

    @MainActor
    func testThemeButtonTogglesDisplayedMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TEST_FIXTURE"]
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
        app.launchArguments = ["UI_TEST_FIXTURE", "UI_TEST_LONG_TOKEN_LIST"]
        app.launch()

        let topBar = app.otherElements["wallet-top-bar"]
        let scrollView = app.scrollViews.firstMatch
        // The pinned section header is exposed as a StaticText (header trait),
        // not an Other, so match it by identifier regardless of element type.
        let tokensHeader = app.descendants(matching: .any)
            .matching(identifier: "tokens-header").firstMatch
        XCTAssertTrue(topBar.waitForExistence(timeout: 2))
        XCTAssertTrue(tokensHeader.waitForExistence(timeout: 2))

        let initialHeaderY = tokensHeader.frame.minY
        // The header pins to the top of the scroll viewport, which sits directly
        // below the top bar (VStack with no spacing).
        let scrollTop = scrollView.frame.minY

        for _ in 0..<4 where tokensHeader.frame.minY > scrollTop + 3 {
            app.swipeUp()
        }

        let pinnedHeaderY = tokensHeader.frame.minY
        XCTAssertLessThan(pinnedHeaderY, initialHeaderY)
        XCTAssertEqual(pinnedHeaderY, scrollTop, accuracy: 3)

        app.swipeUp()
        XCTAssertEqual(tokensHeader.frame.minY, pinnedHeaderY, accuracy: 3)
    }

    @MainActor
    func testWalletCardsShareMinimumHeight() throws {
        let emptyApp = XCUIApplication()
        emptyApp.launchArguments = ["UI_TEST_FIXTURE"]
        emptyApp.launch()

        let emptyCard = emptyApp.otherElements["empty-wallet-card"]
        XCTAssertTrue(emptyCard.waitForExistence(timeout: 2))
        let emptyHeight = emptyCard.frame.height
        emptyApp.terminate()

        let populatedApp = XCUIApplication()
        populatedApp.launchArguments = [
            "UI_TEST_FIXTURE",
            "UI_TEST_POPULATED_WALLET"
        ]
        populatedApp.launch()

        let populatedCard = populatedApp.otherElements["wallet-card"]
        XCTAssertTrue(populatedCard.waitForExistence(timeout: 2))
        let populatedHeight = populatedCard.frame.height

        XCTAssertGreaterThanOrEqual(emptyHeight, 208)
        XCTAssertGreaterThanOrEqual(populatedHeight, 208)
        XCTAssertEqual(emptyHeight, populatedHeight, accuracy: 1)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["UI_TEST_FIXTURE"]
            app.launch()
        }
    }
}
