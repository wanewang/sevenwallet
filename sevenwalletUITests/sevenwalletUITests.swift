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

        XCTAssertTrue(app.otherElements["wallet-card"].waitForExistence(timeout: 2))
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

        XCTAssertTrue(app.buttons["empty-wallet-card"].waitForExistence(timeout: 2))
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

        let emptyCard = emptyApp.buttons["empty-wallet-card"]
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

        XCTAssertGreaterThanOrEqual(emptyHeight, 212)
        XCTAssertGreaterThanOrEqual(populatedHeight, 212)
        XCTAssertEqual(emptyHeight, populatedHeight, accuracy: 1)
    }

    @MainActor
    func testAddWalletFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TEST_FIXTURE",
            "UI_TEST_PERSIST_SAVED_WALLETS",
            "UI_TEST_CLEAR_SAVED_WALLETS"
        ]
        app.launch()

        let emptyCard = app.buttons["empty-wallet-card"]
        XCTAssertTrue(emptyCard.waitForExistence(timeout: 2))
        emptyCard.tap()

        let name = app.textFields["wallet-name-field"]
        let address = app.textFields["wallet-address-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        name.tap()
        name.typeText("Main Wallet")
        address.tap()
        address.typeText("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
        app.buttons["wallet-color-teal"].tap()
        app.buttons["wallet-primary-action"].tap()

        XCTAssertTrue(app.otherElements["wallet-card"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Main Wallet"].exists)
        XCTAssertFalse(app.buttons["empty-wallet-card"].exists)
    }

    @MainActor
    func testCopyDoesNotOpenEditButEditButtonDoes() throws {
        let app = seededWalletApp()
        app.launch()

        app.buttons["copy-wallet-address-button"].tap()
        XCTAssertFalse(app.textFields["wallet-name-field"].exists)

        app.buttons["edit-wallet-button"].tap()
        XCTAssertTrue(app.staticTexts["Edit wallet"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.textFields["wallet-address-field"].exists)
        XCTAssertTrue(app.staticTexts[
            "0x71a2b3c4d5e6f7890a1b2c3d4e5f67890abc8f92"
        ].exists)
    }

    @MainActor
    func testEditAndConfirmedDelete() throws {
        let app = seededWalletApp()
        app.launch()
        app.buttons["edit-wallet-button"].tap()

        let name = app.textFields["wallet-name-field"]
        name.tap()
        name.clearAndEnterText("Renamed")
        app.buttons["wallet-color-amber"].tap()
        app.buttons["wallet-primary-action"].tap()
        XCTAssertTrue(app.staticTexts["Renamed"].waitForExistence(timeout: 2))

        app.buttons["edit-wallet-button"].tap()
        app.buttons["delete-wallet-button"].tap()
        let deleteConfirmation = app.sheets["Delete wallet?"]
        XCTAssertTrue(deleteConfirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(deleteConfirmation.buttons["Delete wallet"].exists)
        app.otherElements["PopoverDismissRegion"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 2))

        app.buttons["delete-wallet-button"].tap()
        XCTAssertTrue(deleteConfirmation.waitForExistence(timeout: 2))
        deleteConfirmation.buttons["Delete wallet"].tap()
        XCTAssertTrue(app.buttons["empty-wallet-card"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testWalletPersistsAcrossRelaunch() throws {
        let firstLaunch = seededWalletApp()
        firstLaunch.launch()
        XCTAssertTrue(firstLaunch.staticTexts["Main Wallet"].waitForExistence(timeout: 2))
        firstLaunch.terminate()

        let secondLaunch = XCUIApplication()
        secondLaunch.launchArguments = [
            "UI_TEST_FIXTURE",
            "UI_TEST_PERSIST_SAVED_WALLETS"
        ]
        secondLaunch.launch()

        XCTAssertTrue(secondLaunch.staticTexts["Main Wallet"].waitForExistence(timeout: 2))
        XCTAssertTrue(secondLaunch.otherElements["wallet-card"].exists)
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

    private func seededWalletApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TEST_FIXTURE",
            "UI_TEST_PERSIST_SAVED_WALLETS",
            "UI_TEST_CLEAR_SAVED_WALLETS",
            "UI_TEST_SEED_SAVED_WALLET"
        ]
        return app
    }
}

private extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        typeKey("a", modifierFlags: .command)
        typeText(text)
    }
}
