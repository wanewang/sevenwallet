import Foundation
import Testing
@testable import sevenwallet

@MainActor
struct WalletCardViewModelTests {
    private func token(balance: String, price: String?) -> TokenViewModel {
        TokenViewModel(token: WalletToken(
            tokenAddress: nil,
            symbol: "TKN",
            name: "Token",
            decimals: 18,
            rawBalance: balance,
            balance: Decimal(string: balance)!,
            isNative: true,
            price: nil,
            logoURL: nil,
            coinKey: "token-\(balance)",
            priceUSD: price.flatMap { Decimal(string: $0) }
        ))
    }

    @Test
    func exposesWalletIdentityAndCalculatedTotal() {
        let first = token(balance: "2", price: "10")
        let second = token(balance: "3", price: "5")
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
    func missingMarketPriceContributesZero() {
        let pricedToken = token(balance: "2", price: "10")
        let unpricedToken = token(balance: "999", price: nil)
        let wallet = WalletCardViewModel(
            name: "Main Wallet",
            address: "123456789012",
            tokens: [pricedToken, unpricedToken]
        )

        #expect(wallet.totalValue == 20)
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
