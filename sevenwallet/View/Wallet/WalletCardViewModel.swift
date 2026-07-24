import Foundation
import Observation

@MainActor
@Observable
final class WalletCardViewModel {
    let id: UUID
    let name: String
    let address: String
    let cardColor: WalletCardColor
    let tokens: [TokenViewModel]

    init(wallet: SavedWallet, tokens: [TokenViewModel]) {
        id = wallet.id
        name = wallet.name
        address = wallet.address.rawValue
        cardColor = wallet.cardColor
        self.tokens = tokens
    }

    var shortenedAddress: String {
        Fmt.short(address)
    }

    var totalValue: Decimal {
        tokens.reduce(0) { $0 + $1.holdingValue }
    }

    var formattedTotalValue: String {
        Fmt.usd(totalValue)
    }
}
