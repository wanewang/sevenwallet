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
    func exposesWalletIdentityAndCalculatedTotal() throws {
        let first = token(balance: "2", price: "10")
        let second = token(balance: "3", price: "5")
        let savedWallet = SavedWallet(
            name: "Main Wallet",
            address: try EVMAddress(
                "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
            ),
            cardColor: .purple
        )
        let wallet = WalletCardViewModel(
            wallet: savedWallet,
            tokens: [first, second]
        )

        #expect(wallet.id == savedWallet.id)
        #expect(wallet.name == "Main Wallet")
        #expect(wallet.cardColor == .purple)
        #expect(wallet.shortenedAddress == "0x71a2…bc8f92")
        #expect(wallet.totalValue == 35)
        #expect(wallet.formattedTotalValue == "$35.00")
    }

    @Test
    func missingMarketPriceContributesZero() throws {
        let pricedToken = token(balance: "2", price: "10")
        let unpricedToken = token(balance: "999", price: nil)
        let wallet = WalletCardViewModel(
            wallet: try savedWallet(),
            tokens: [pricedToken, unpricedToken]
        )

        #expect(wallet.totalValue == 20)
    }

    @Test
    func emptyWalletTotalsZero() throws {
        let wallet = WalletCardViewModel(
            wallet: try savedWallet(name: "Empty"),
            tokens: []
        )

        #expect(wallet.totalValue == 0)
        #expect(wallet.formattedTotalValue == "$0.00")
    }

    private func savedWallet(name: String = "Main Wallet") throws -> SavedWallet {
        SavedWallet(
            name: name,
            address: try EVMAddress(
                "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
            ),
            cardColor: .blue
        )
    }
}
