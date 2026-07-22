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
        XCTAssertTrue(app.buttons["theme-toggle-button"].exists)
        XCTAssertTrue(app.staticTexts["Main Wallet"].exists)
        XCTAssertTrue(app.staticTexts["TOTAL VALUE"].exists)
        XCTAssertTrue(app.buttons["copy-wallet-address-button"].exists)
        XCTAssertTrue(app.buttons["manage-tokens-button"].exists)

        for symbol in ["ETH", "BTC", "SOL", "USDC"] {
            XCTAssertTrue(app.staticTexts[symbol].firstMatch.exists)
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
