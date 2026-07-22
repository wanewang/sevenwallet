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
