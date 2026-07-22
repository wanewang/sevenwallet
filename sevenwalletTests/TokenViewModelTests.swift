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
