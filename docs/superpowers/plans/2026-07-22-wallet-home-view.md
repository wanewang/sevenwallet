# WalletHomeView Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a themed wallet dashboard with a fixed top bar, calculated wallet card, and an unbounded lazy Tokens section whose header pins while the wallet card scrolls away.

**Architecture:** Observation-based WalletHomeViewModel, WalletCardViewModel, and shared TokenViewModel instances provide one source of truth. SwiftUI components render the fixed top bar and two scroll sections; the outer LazyVStack owns the pinned Tokens header and direct token-row children.

**Tech Stack:** Swift 5 language mode, SwiftUI, Observation, Swift Testing, XCTest UI testing, iOS 26.2.

## Global Constraints

- Preserve all existing user-owned uncommitted changes and modify only files named in this plan.
- Keep the app deployment target at iOS 26.2 and add no external dependencies.
- Keep the top bar exactly 64 points high.
- Keep the wallet-selection button exactly 72 by 48 points and its chevron in a centered 24-by-24-point frame.
- Keep the theme button exactly 48 by 48 points.
- Show only rectangle.grid.1x2 and chevron.down in the wallet-selection button.
- Use “Tokens,” TokenViewModel, and TokenRowView; do not introduce “Assets” naming.
- Wallet selection and Manage remain intentionally inactive.
- Theme switching and full-address copying remain functional.
- The production sample contains ETH, BTC, SOL, and USDC once; repeated token sets are allowed only behind the UI-test launch argument.
- “Infinite” means an arbitrary number of already-loaded in-memory rows, not repetition, pagination, or network loading in production.
- Reuse Theme and Fmt; add no parallel design system or formatter layer.

## File Structure

- Modify sevenwallet/Theme/Formatting.swift: deterministic USD, amount, percentage, and six-plus-six address formatting.
- Create sevenwallet/View/Token/TokenViewModel.swift: mutable token data and derived display values.
- Create sevenwallet/View/Wallet/WalletCardViewModel.swift: wallet identity, address display, and total calculation.
- Create sevenwallet/View/Wallet/WalletHomeViewModel.swift: theme state, shared token collection, wallet-card model, and sample factory.
- Create sevenwallet/View/Wallet/WalletTopBar.swift: exact top-bar controls and accessibility identifiers.
- Create sevenwallet/View/Wallet/WalletCardView.swift: soft-glass wallet summary and copy action.
- Create sevenwallet/View/Token/TokenRowView.swift: soft-glass grouped token row.
- Modify sevenwallet/View/Wallet/WalletHomePage.swift: fixed top bar, scroll sections, pinned Tokens header, and row composition.
- Modify sevenwallet/sevenwalletApp.swift: inject normal sample data or a longer UI-test-only sample.
- Create sevenwalletTests/FormattingTests.swift: formatting contract tests.
- Create sevenwalletTests/TokenViewModelTests.swift: token calculation and mutation tests.
- Create sevenwalletTests/WalletCardViewModelTests.swift: address and aggregate-value tests.
- Create sevenwalletTests/WalletHomeViewModelTests.swift: sample composition, shared identity, and theme tests.
- Modify sevenwalletUITests/sevenwalletUITests.swift: content, theme-toggle, and pinned-header UI tests.
- Create .gitignore: exclude the local visual-companion .superpowers/ directory.

---

### Task 1: Lock Down Formatting

**Files:**
- Create: sevenwalletTests/FormattingTests.swift
- Modify: sevenwallet/Theme/Formatting.swift

**Interfaces:**
- Consumes: Foundation NumberFormatter.
- Produces: Fmt.usd(_:) -> String, Fmt.amount(_:) -> String, Fmt.pct(_:) -> String, and Fmt.short(_:) -> String.

- [ ] **Step 1: Write the failing formatting tests**

~~~swift
import Testing
@testable import sevenwallet

struct FormattingTests {
    @Test
    func shortAddressUsesSixCharactersOnEachSide() {
        #expect(Fmt.short("0x1234567890ABCDEF") == "0x1234…ABCDEF")
    }

    @Test
    func shortAddressLeavesTwelveCharactersUntouched() {
        #expect(Fmt.short("123456789012") == "123456789012")
    }

    @Test
    func percentageFormattingCoversAllSigns() {
        #expect(Fmt.pct(2.48) == "+2.48%")
        #expect(Fmt.pct(-0.03) == "-0.03%")
        #expect(Fmt.pct(0) == "0.00%")
    }

    @Test
    func usdFormattingIsDeterministic() {
        #expect(Fmt.usd(12_480.21) == "$12,480.21")
    }
}
~~~

- [ ] **Step 2: Run the test and verify the six-plus-four implementation fails**

Run:

~~~bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-home -only-testing:sevenwalletTests/FormattingTests test
~~~

Expected: TEST FAILED; the first test reports 0x1234…CDEF instead of 0x1234…ABCDEF.

- [ ] **Step 3: Replace the formatter implementation**

~~~swift
import Foundation

enum Fmt {
    static func usd(_ n: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: n as NSNumber) ?? "$0.00"
    }

    static func amount(_ n: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: n as NSNumber) ?? "0"
    }

    static func pct(_ n: Double) -> String {
        (n > 0 ? "+" : "") + String(format: "%.2f%%", n)
    }

    static func short(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return String(address.prefix(6)) + "…" + String(address.suffix(6))
    }
}
~~~

- [ ] **Step 4: Run the formatting tests**

Run the command from Step 2.

Expected: TEST SUCCEEDED; all four tests pass.

- [ ] **Step 5: Commit the formatting contract**

~~~bash
git add sevenwallet/Theme/Formatting.swift sevenwalletTests/FormattingTests.swift
git commit --only sevenwallet/Theme/Formatting.swift sevenwalletTests/FormattingTests.swift -m "test: define wallet formatting"
~~~

---

### Task 2: Add Token Calculations

**Files:**
- Create: sevenwalletTests/TokenViewModelTests.swift
- Create: sevenwallet/View/Token/TokenViewModel.swift

**Interfaces:**
- Consumes: Fmt.usd(_:), Fmt.amount(_:), and Fmt.pct(_:).
- Produces: @MainActor @Observable final class TokenViewModel: Identifiable with mutable balance, currentPrice, and dailyChange; derived totalValue, formattedValue, formattedBalance, formattedDailyChange, and isNonnegativeChange.

- [ ] **Step 1: Write the failing token-model tests**

~~~swift
import SwiftUI
import Testing
@testable import sevenwallet

@MainActor
struct TokenViewModelTests {
    @Test
    func calculatesAndFormatsTokenValues() {
        let token = TokenViewModel(
            symbol: "ETH",
            balance: 4.25,
            currentPrice: 2_936.52,
            dailyChange: 2.48,
            iconText: "Ξ",
            iconColor: .blue
        )

        #expect(abs(token.totalValue - 12_480.21) < 0.0001)
        #expect(token.formattedValue == "$12,480.21")
        #expect(token.formattedBalance == "4.25 ETH")
        #expect(token.formattedDailyChange == "+2.48%")
        #expect(token.isNonnegativeChange)
    }

    @Test
    func derivedValuesFollowMutation() {
        let token = TokenViewModel(
            symbol: "USDC",
            balance: 10,
            currentPrice: 1,
            dailyChange: -0.03,
            iconText: "$",
            iconColor: .green
        )

        token.balance = 20
        token.currentPrice = 1.01

        #expect(abs(token.totalValue - 20.2) < 0.0001)
        #expect(token.formattedValue == "$20.20")
        #expect(token.formattedDailyChange == "-0.03%")
        #expect(!token.isNonnegativeChange)
    }
}
~~~

- [ ] **Step 2: Run the token-model tests and verify the missing type fails**

Run:

~~~bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-home -only-testing:sevenwalletTests/TokenViewModelTests test
~~~

Expected: TEST FAILED during compilation because TokenViewModel is not defined.

- [ ] **Step 3: Implement TokenViewModel**

~~~swift
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class TokenViewModel: Identifiable {
    let id: UUID
    let symbol: String
    var balance: Double
    var currentPrice: Double
    var dailyChange: Double
    let iconText: String
    let iconColor: Color

    init(
        id: UUID = UUID(),
        symbol: String,
        balance: Double,
        currentPrice: Double,
        dailyChange: Double,
        iconText: String,
        iconColor: Color
    ) {
        self.id = id
        self.symbol = symbol
        self.balance = balance
        self.currentPrice = currentPrice
        self.dailyChange = dailyChange
        self.iconText = iconText
        self.iconColor = iconColor
    }

    var totalValue: Double {
        balance * currentPrice
    }

    var formattedValue: String {
        Fmt.usd(totalValue)
    }

    var formattedBalance: String {
        "\(Fmt.amount(balance)) \(symbol)"
    }

    var formattedDailyChange: String {
        Fmt.pct(dailyChange)
    }

    var isNonnegativeChange: Bool {
        dailyChange >= 0
    }
}
~~~

- [ ] **Step 4: Run the token-model tests**

Run the command from Step 2.

Expected: TEST SUCCEEDED; both token tests pass.

- [ ] **Step 5: Commit the token model**

~~~bash
git add sevenwallet/View/Token/TokenViewModel.swift sevenwalletTests/TokenViewModelTests.swift
git commit --only sevenwallet/View/Token/TokenViewModel.swift sevenwalletTests/TokenViewModelTests.swift -m "feat: add token view model"
~~~

---

### Task 3: Add Wallet Aggregation

**Files:**
- Create: sevenwalletTests/WalletCardViewModelTests.swift
- Create: sevenwallet/View/Wallet/WalletCardViewModel.swift

**Interfaces:**
- Consumes: [TokenViewModel] and Fmt.short(_:), Fmt.usd(_:).
- Produces: @MainActor @Observable final class WalletCardViewModel with name, address, tokens, shortenedAddress, totalValue, and formattedTotalValue.

- [ ] **Step 1: Write the failing wallet-card tests**

~~~swift
import SwiftUI
import Testing
@testable import sevenwallet

@MainActor
struct WalletCardViewModelTests {
    private func token(balance: Double, price: Double) -> TokenViewModel {
        TokenViewModel(
            symbol: "TKN",
            balance: balance,
            currentPrice: price,
            dailyChange: 0,
            iconText: "T",
            iconColor: .blue
        )
    }

    @Test
    func exposesWalletIdentityAndCalculatedTotal() {
        let first = token(balance: 2, price: 10)
        let second = token(balance: 3, price: 5)
        let wallet = WalletCardViewModel(
            name: "Main Wallet",
            address: "0x1234567890ABCDEF",
            tokens: [first, second]
        )

        #expect(wallet.name == "Main Wallet")
        #expect(wallet.shortenedAddress == "0x1234…ABCDEF")
        #expect(wallet.totalValue == 35)
        #expect(wallet.formattedTotalValue == "$35.00")
    }

    @Test
    func totalTracksSharedTokenMutation() {
        let sharedToken = token(balance: 2, price: 10)
        let wallet = WalletCardViewModel(
            name: "Main Wallet",
            address: "123456789012",
            tokens: [sharedToken]
        )

        sharedToken.balance = 4

        #expect(wallet.totalValue == 40)
        #expect(wallet.shortenedAddress == "123456789012")
    }

    @Test
    func emptyWalletTotalsZero() {
        let wallet = WalletCardViewModel(
            name: "Empty",
            address: "short",
            tokens: []
        )

        #expect(wallet.totalValue == 0)
        #expect(wallet.formattedTotalValue == "$0.00")
    }
}
~~~

- [ ] **Step 2: Run the wallet-card tests and verify the missing type fails**

Run:

~~~bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-home -only-testing:sevenwalletTests/WalletCardViewModelTests test
~~~

Expected: TEST FAILED during compilation because WalletCardViewModel is not defined.

- [ ] **Step 3: Implement WalletCardViewModel**

~~~swift
import Observation

@MainActor
@Observable
final class WalletCardViewModel {
    let name: String
    let address: String
    let tokens: [TokenViewModel]

    init(name: String, address: String, tokens: [TokenViewModel]) {
        self.name = name
        self.address = address
        self.tokens = tokens
    }

    var shortenedAddress: String {
        Fmt.short(address)
    }

    var totalValue: Double {
        tokens.reduce(0) { $0 + $1.totalValue }
    }

    var formattedTotalValue: String {
        Fmt.usd(totalValue)
    }
}
~~~

- [ ] **Step 4: Run the wallet-card tests**

Run the command from Step 2.

Expected: TEST SUCCEEDED; all three wallet-card tests pass.

- [ ] **Step 5: Commit wallet aggregation**

~~~bash
git add sevenwallet/View/Wallet/WalletCardViewModel.swift sevenwalletTests/WalletCardViewModelTests.swift
git commit --only sevenwallet/View/Wallet/WalletCardViewModel.swift sevenwalletTests/WalletCardViewModelTests.swift -m "feat: add wallet card view model"
~~~

---

### Task 4: Compose Screen State and Static Tokens

**Files:**
- Create: sevenwalletTests/WalletHomeViewModelTests.swift
- Create: sevenwallet/View/Wallet/WalletHomeViewModel.swift

**Interfaces:**
- Consumes: TokenViewModel and WalletCardViewModel.
- Produces: @MainActor @Observable final class WalletHomeViewModel, toggleTheme(), and static sample(tokenSetCopies: Int = 1) -> WalletHomeViewModel.
- The tokenSetCopies argument exists only to make the pinned-header UI test scrollable; production always uses the default value 1.

- [ ] **Step 1: Write the failing home-model tests**

~~~swift
import Testing
@testable import sevenwallet

@MainActor
struct WalletHomeViewModelTests {
    @Test
    func sampleUsesRequiredTokensAndSharedInstances() {
        let home = WalletHomeViewModel.sample()

        #expect(home.tokens.map(\.symbol) == ["ETH", "BTC", "SOL", "USDC"])
        #expect(home.walletCard.name == "Main Wallet")
        #expect(home.walletCard.tokens[0] === home.tokens[0])
        #expect(abs(home.walletCard.totalValue - 26_321.496432) < 0.0001)
        #expect(home.walletCard.formattedTotalValue == "$26,321.50")
    }

    @Test
    func themeStartsDarkAndToggles() {
        let home = WalletHomeViewModel.sample()

        #expect(!home.isThemeLight)
        home.toggleTheme()
        #expect(home.isThemeLight)
    }

    @Test
    func testOnlyCopiesCreateEnoughRowsWithoutSharingIdentity() {
        let home = WalletHomeViewModel.sample(tokenSetCopies: 2)

        #expect(home.tokens.count == 8)
        #expect(home.tokens[0].symbol == home.tokens[4].symbol)
        #expect(home.tokens[0] !== home.tokens[4])
    }
}
~~~

- [ ] **Step 2: Run the home-model tests and verify the missing type fails**

Run:

~~~bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-home -only-testing:sevenwalletTests/WalletHomeViewModelTests test
~~~

Expected: TEST FAILED during compilation because WalletHomeViewModel is not defined.

- [ ] **Step 3: Implement WalletHomeViewModel and its sample factory**

~~~swift
import Observation
import SwiftUI

@MainActor
@Observable
final class WalletHomeViewModel {
    var isThemeLight: Bool
    let tokens: [TokenViewModel]
    let walletCard: WalletCardViewModel

    init(
        isThemeLight: Bool = false,
        walletName: String,
        walletAddress: String,
        tokens: [TokenViewModel]
    ) {
        self.isThemeLight = isThemeLight
        self.tokens = tokens
        walletCard = WalletCardViewModel(
            name: walletName,
            address: walletAddress,
            tokens: tokens
        )
    }

    func toggleTheme() {
        isThemeLight.toggle()
    }

    static func sample(tokenSetCopies: Int = 1) -> WalletHomeViewModel {
        let tokens = (0..<tokenSetCopies).flatMap { _ in
            [
                TokenViewModel(
                    symbol: "ETH",
                    balance: 4.25,
                    currentPrice: 2_936.52,
                    dailyChange: 2.48,
                    iconText: "Ξ",
                    iconColor: Theme.accent
                ),
                TokenViewModel(
                    symbol: "BTC",
                    balance: 0.0934,
                    currentPrice: 104_022.48,
                    dailyChange: 1.12,
                    iconText: "₿",
                    iconColor: Theme.warn
                ),
                TokenViewModel(
                    symbol: "SOL",
                    balance: 18.42,
                    currentPrice: 142.54,
                    dailyChange: 4.06,
                    iconText: "S",
                    iconColor: Theme.accentHi
                ),
                TokenViewModel(
                    symbol: "USDC",
                    balance: 1_500,
                    currentPrice: 1,
                    dailyChange: -0.03,
                    iconText: "$",
                    iconColor: Theme.pos
                )
            ]
        }

        return WalletHomeViewModel(
            walletName: "Main Wallet",
            walletAddress: "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92",
            tokens: tokens
        )
    }
}
~~~

- [ ] **Step 4: Run the home-model tests**

Run the command from Step 2.

Expected: TEST SUCCEEDED; all three home-model tests pass.

- [ ] **Step 5: Run every unit test before moving to views**

Run:

~~~bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-home -only-testing:sevenwalletTests test
~~~

Expected: TEST SUCCEEDED with the formatting, token, wallet-card, and home-model suites all passing.

- [ ] **Step 6: Commit screen state**

~~~bash
git add sevenwallet/View/Wallet/WalletHomeViewModel.swift sevenwalletTests/WalletHomeViewModelTests.swift
git commit --only sevenwallet/View/Wallet/WalletHomeViewModel.swift sevenwalletTests/WalletHomeViewModelTests.swift -m "feat: compose wallet home state"
~~~

---

### Task 5: Render the Wallet Content

**Files:**
- Modify: sevenwalletUITests/sevenwalletUITests.swift
- Create: sevenwallet/View/Wallet/WalletTopBar.swift
- Create: sevenwallet/View/Wallet/WalletCardView.swift
- Create: sevenwallet/View/Token/TokenRowView.swift
- Modify: sevenwallet/View/Wallet/WalletHomePage.swift

**Interfaces:**
- Consumes: WalletHomeViewModel, WalletCardViewModel, TokenViewModel, and Theme.
- Produces: WalletTopBar(theme:isThemeLight:onToggleTheme:), WalletCardView(viewModel:theme:), TokenRowView(viewModel:theme:isFirst:isLast:), and injectable WalletHomeView(viewModel:).
- Accessibility identifiers produced: wallet-top-bar, wallet-selector-button, theme-toggle-button, wallet-card, copy-wallet-address-button, tokens-header, and manage-tokens-button.

- [ ] **Step 1: Replace the starter UI test with a failing content test**

Replace testExample() in sevenwalletUITests.swift with:

~~~swift
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
~~~

- [ ] **Step 2: Run the content UI test and verify the empty screen fails**

Run:

~~~bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-home -only-testing:sevenwalletUITests/sevenwalletUITests/testWalletHomeContent test
~~~

Expected: TEST FAILED because wallet-selector-button does not exist.

- [ ] **Step 3: Create the exact top bar**

~~~swift
import SwiftUI

struct WalletTopBar: View {
    let theme: Theme
    let isThemeLight: Bool
    let onToggleTheme: () -> Void

    var body: some View {
        HStack {
            Button(action: {}) {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.grid.1x2")
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 24)
                }
                .font(.system(size: 20, weight: .medium))
                .frame(width: 72, height: 48)
                .background(theme.glass)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.edge, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wallet selector")
            .accessibilityIdentifier("wallet-selector-button")

            Spacer()

            Button(action: onToggleTheme) {
                Image(systemName: isThemeLight ? "sun.max" : "moon")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 48, height: 48)
                    .background(theme.glass)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.edge, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThemeLight ? "Light theme" : "Dark theme")
            .accessibilityIdentifier("theme-toggle-button")
        }
        .frame(height: 64)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet-top-bar")
    }
}
~~~

- [ ] **Step 4: Create the wallet card**

~~~swift
import SwiftUI
import UIKit

struct WalletCardView: View {
    let viewModel: WalletCardViewModel
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text(viewModel.name)
                    .font(.headline)
                    .foregroundStyle(theme.fg1)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Text(viewModel.shortenedAddress)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.fg2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Button {
                        UIPasteboard.general.string = viewModel.address
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy wallet address")
                    .accessibilityIdentifier("copy-wallet-address-button")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TOTAL VALUE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(theme.fg2)

                Text(viewModel.formattedTotalValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.fg1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.edge, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet-card")
    }
}
~~~

- [ ] **Step 5: Create a direct lazy-compatible token row**

~~~swift
import SwiftUI

struct TokenRowView: View {
    let viewModel: TokenViewModel
    let theme: Theme
    let isFirst: Bool
    let isLast: Bool

    private var rowShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: isFirst ? 18 : 0,
                bottomLeading: isLast ? 18 : 0,
                bottomTrailing: isLast ? 18 : 0,
                topTrailing: isFirst ? 18 : 0
            ),
            style: .continuous
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(viewModel.iconText)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(viewModel.iconColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.symbol)
                    .font(.headline)
                    .foregroundStyle(theme.fg1)

                Text(viewModel.formattedDailyChange)
                    .font(.caption)
                    .foregroundStyle(
                        viewModel.isNonnegativeChange ? Theme.pos : Theme.neg
                    )
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.formattedValue)
                    .font(.headline)
                    .foregroundStyle(theme.fg1)

                Text(viewModel.formattedBalance)
                    .font(.caption)
                    .foregroundStyle(theme.fg2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(theme.glass)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.edge).frame(width: 1)
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme.edge).frame(width: 1)
        }
        .overlay(alignment: .top) {
            if isFirst {
                Rectangle().fill(theme.edge).frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isLast ? theme.edge : theme.divider)
                .frame(height: 1)
        }
        .clipShape(rowShape)
    }
}
~~~

- [ ] **Step 6: Compose the first complete screen without pinned behavior**

Replace WalletHomePage.swift with:

~~~swift
import SwiftUI

struct WalletHomeView: View {
    @State private var viewModel: WalletHomeViewModel

    init(viewModel: WalletHomeViewModel = .sample()) {
        _viewModel = State(initialValue: viewModel)
    }

    private var theme: Theme {
        viewModel.isThemeLight ? .light : .dark
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                WalletTopBar(
                    theme: theme,
                    isThemeLight: viewModel.isThemeLight,
                    onToggleTheme: {}
                )

                ScrollView {
                    VStack(spacing: 0) {
                        WalletCardView(
                            viewModel: viewModel.walletCard,
                            theme: theme
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                        tokensHeader

                        ForEach(
                            Array(viewModel.tokens.enumerated()),
                            id: \.element.id
                        ) { index, token in
                            TokenRowView(
                                viewModel: token,
                                theme: theme,
                                isFirst: index == 0,
                                isLast: index == viewModel.tokens.count - 1
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.accent)
        .environment(
            \.colorScheme,
            viewModel.isThemeLight ? .light : .dark
        )
    }

    private var tokensHeader: some View {
        HStack {
            Text("Tokens")
                .font(.title2.bold())
                .foregroundStyle(theme.fg1)

            Spacer()

            Button(action: {}) {
                Label("Manage", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.edge, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("manage-tokens-button")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.bg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tokens-header")
    }
}
~~~

- [ ] **Step 7: Run the content UI test**

Run the command from Step 2.

Expected: TEST SUCCEEDED; all required controls and four production token symbols exist.

- [ ] **Step 8: Commit the visible wallet content**

~~~bash
git add sevenwallet/View/Wallet/WalletTopBar.swift sevenwallet/View/Wallet/WalletCardView.swift sevenwallet/View/Token/TokenRowView.swift sevenwallet/View/Wallet/WalletHomePage.swift sevenwalletUITests/sevenwalletUITests.swift
git commit --only sevenwallet/View/Wallet/WalletTopBar.swift sevenwallet/View/Wallet/WalletCardView.swift sevenwallet/View/Token/TokenRowView.swift sevenwallet/View/Wallet/WalletHomePage.swift sevenwalletUITests/sevenwalletUITests.swift -m "feat: render wallet home content"
~~~

---

### Task 6: Pin the Tokens Header and Connect Theme State

**Files:**
- Modify: sevenwalletUITests/sevenwalletUITests.swift
- Modify: sevenwallet/View/Wallet/WalletHomePage.swift
- Modify: sevenwallet/sevenwalletApp.swift

**Interfaces:**
- Consumes: WalletHomeViewModel.toggleTheme() and WalletHomeViewModel.sample(tokenSetCopies:).
- Produces: one LazyVStack with pinned section headers, a wallet section, a Tokens section, and the UI_TEST_LONG_TOKEN_LIST launch argument used only by the pinned-header test.

- [ ] **Step 1: Add failing theme and pinned-header UI tests**

Add these methods to sevenwalletUITests:

~~~swift
@MainActor
func testThemeButtonTogglesDisplayedMode() throws {
    let app = XCUIApplication()
    app.launch()

    let themeButton = app.buttons["theme-toggle-button"]
    XCTAssertTrue(themeButton.waitForExistence(timeout: 2))
    XCTAssertEqual(themeButton.label, "Dark theme")

    themeButton.tap()

    XCTAssertEqual(themeButton.label, "Light theme")
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
~~~

- [ ] **Step 2: Run the two new tests and verify both behaviors fail**

Run:

~~~bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-home -only-testing:sevenwalletUITests/sevenwalletUITests/testThemeButtonTogglesDisplayedMode -only-testing:sevenwalletUITests/sevenwalletUITests/testTokensHeaderPinsBelowTopBar test
~~~

Expected: TEST FAILED. The theme label remains Dark theme, and the non-pinned header does not settle at the top-bar boundary.

- [ ] **Step 3: Inject longer data only for the pinned-header UI test**

Replace sevenwalletApp.swift with:

~~~swift
import SwiftUI

@main
struct sevenwalletApp: App {
    private var tokenSetCopies: Int {
        ProcessInfo.processInfo.arguments.contains("UI_TEST_LONG_TOKEN_LIST")
            ? 4
            : 1
    }

    var body: some Scene {
        WindowGroup {
            WalletHomeView(
                viewModel: .sample(tokenSetCopies: tokenSetCopies)
            )
        }
    }
}
~~~

- [ ] **Step 4: Replace the temporary scrolling content with two sections**

In WalletHomePage.swift, replace the VStack beginning with WalletTopBar through the end of ScrollView with:

~~~swift
VStack(spacing: 0) {
    WalletTopBar(
        theme: theme,
        isThemeLight: viewModel.isThemeLight,
        onToggleTheme: viewModel.toggleTheme
    )

    ScrollView {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                WalletCardView(
                    viewModel: viewModel.walletCard,
                    theme: theme
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }

            Section {
                ForEach(
                    Array(viewModel.tokens.enumerated()),
                    id: \.element.id
                ) { index, token in
                    TokenRowView(
                        viewModel: token,
                        theme: theme,
                        isFirst: index == 0,
                        isLast: index == viewModel.tokens.count - 1
                    )
                    .padding(.horizontal, 16)
                }
            } header: {
                tokensHeader
            }
        }
        .padding(.bottom, 16)
    }
}
~~~

Do not place a LazyVStack inside the Tokens section. Its ForEach rows must remain direct children of the one outer LazyVStack.

- [ ] **Step 5: Run all WalletHome UI tests**

Run:

~~~bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-home -only-testing:sevenwalletUITests/sevenwalletUITests test
~~~

Expected: TEST SUCCEEDED. Content is present, the theme label toggles, and the Tokens header pins beneath the 64-point top bar.

- [ ] **Step 6: Commit the completed scrolling behavior**

~~~bash
git add sevenwallet/View/Wallet/WalletHomePage.swift sevenwallet/sevenwalletApp.swift sevenwalletUITests/sevenwalletUITests.swift
git commit --only sevenwallet/View/Wallet/WalletHomePage.swift sevenwallet/sevenwalletApp.swift sevenwalletUITests/sevenwalletUITests.swift -m "feat: pin wallet token header"
~~~

---

### Task 7: Run Final Verification and Ignore Companion Files

**Files:**
- Create: .gitignore
- Verify: all production and test files from Tasks 1–6.

**Interfaces:**
- Consumes: the completed WalletHomeView feature.
- Produces: a clean verification record and an ignored .superpowers/ visual-companion directory.

- [ ] **Step 1: Ignore only the visual-companion working directory**

~~~gitignore
.superpowers/
~~~

- [ ] **Step 2: Run every unit and UI test**

Run:

~~~bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-home test
~~~

Expected: TEST SUCCEEDED with the four unit suites and all WalletHome UI tests passing.

- [ ] **Step 3: Build independently with signing disabled**

Run:

~~~bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/sevenwallet-wallet-home CODE_SIGNING_ALLOWED=NO build
~~~

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Check naming, whitespace, and the preserved worktree**

Run:

~~~bash
rg -n "Assets|AssetViewModel|AssetRowView" sevenwallet sevenwalletTests sevenwalletUITests
git diff --check
git status --short
~~~

Expected:

- rg returns no matches.
- git diff --check prints nothing.
- git status lists no new implementation files outside this plan; any pre-existing staged ContentView.swift or Screen.swift changes remain preserved unless a planned commit intentionally included the same file.

- [ ] **Step 5: Commit the ignore rule without including preserved user changes**

~~~bash
git add .gitignore
git commit --only .gitignore -m "chore: ignore brainstorming files"
~~~
