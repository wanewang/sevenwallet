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
