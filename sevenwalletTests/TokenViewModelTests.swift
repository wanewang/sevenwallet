import Foundation
import Testing
@testable import sevenwallet

@MainActor
struct TokenViewModelTests {
    @Test
    func mapsNativeTokenAndFormatsExactDecimalValues() {
        let token = TokenViewModel(token: WalletToken(
            tokenAddress: nil,
            symbol: "ETH",
            name: "Ether",
            decimals: 18,
            rawBalance: "4250000000000000000",
            balance: Decimal(string: "4.25")!,
            isNative: true,
            price: TokenPrice(currency: "USD", value: 2_900, lastUpdatedAt: nil),
            logoURL: URL(string: "https://example.com/eth.png"),
            coinKey: "ethereum",
            priceUSD: Decimal(string: "2936.52")
        ))

        #expect(token.id == "ethereum:native")
        #expect(token.name == "Ether")
        #expect(token.balance == Decimal(string: "4.25"))
        #expect(token.marketPrice == Decimal(string: "2936.52"))
        #expect(token.logoURL == URL(string: "https://example.com/eth.png"))
        #expect(token.formattedPrice == "$2,936.52")
        #expect(token.formattedBalance == "4.25 ETH")
        #expect(token.formattedDailyChange == "-")
        #expect(token.iconText == "E")
        #expect(token.holdingValue == Decimal(string: "12480.21"))
    }

    @Test
    func fallsBackToNestedPrice() {
        let token = TokenViewModel(token: WalletToken(
            tokenAddress: "0xabc",
            symbol: "USDC",
            name: "USD Coin",
            decimals: 6,
            rawBalance: "10000000",
            balance: 10,
            isNative: false,
            price: TokenPrice(currency: "USD", value: Decimal(string: "1.01"), lastUpdatedAt: nil),
            logoURL: nil,
            coinKey: "usd-coin",
            priceUSD: nil
        ))

        #expect(token.marketPrice == Decimal(string: "1.01"))
        #expect(token.formattedPrice == "$1.01")
        #expect(token.holdingValue == Decimal(string: "10.1"))
    }

    @Test
    func missingPriceUsesPlaceholderAndZeroHoldingValue() {
        let token = TokenViewModel(token: WalletToken(
            tokenAddress: nil,
            symbol: "NEW",
            name: "New Token",
            decimals: 18,
            rawBalance: "2",
            balance: 2,
            isNative: true,
            price: nil,
            logoURL: nil,
            coinKey: "new",
            priceUSD: nil
        ))

        #expect(token.marketPrice == nil)
        #expect(token.formattedPrice == "-")
        #expect(token.holdingValue == 0)
    }

    @Test
    func dailyChangeColorUsesNeutralThenSignedColors() {
        let neutral = makeToken(dailyChange: nil)
        let positive = makeToken(dailyChange: 1)
        let negative = makeToken(dailyChange: -1)

        #expect(neutral.dailyChangeColor(theme: .dark) == Theme.dark.fg2)
        #expect(positive.dailyChangeColor(theme: .dark) == Theme.pos)
        #expect(negative.dailyChangeColor(theme: .dark) == Theme.neg)
    }

    private func makeToken(dailyChange: Decimal?) -> TokenViewModel {
        TokenViewModel(
            token: WalletToken(
                tokenAddress: nil,
                symbol: "ETH",
                name: "Ether",
                decimals: 18,
                rawBalance: "0",
                balance: 0,
                isNative: true,
                price: nil,
                logoURL: nil,
                coinKey: "ethereum",
                priceUSD: nil
            ),
            dailyChange: dailyChange
        )
    }
}
