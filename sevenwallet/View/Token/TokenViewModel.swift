import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class TokenViewModel: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let balance: Decimal
    let marketPrice: Decimal?
    let dailyChange: Decimal?
    let logoURL: URL?

    init(token: WalletToken) {
        id = token.id
        symbol = token.symbol
        name = token.name
        balance = token.balance
        marketPrice = token.priceUSD ?? token.price?.value
        dailyChange = token.change24hPercent
        logoURL = token.logoURL
    }

    var formattedPrice: String {
        marketPrice.map(Fmt.usd) ?? "-"
    }

    var formattedBalance: String {
        "\(Fmt.amount(balance)) \(symbol)"
    }

    var formattedDailyChange: String {
        Fmt.pct(dailyChange)
    }

    var iconText: String {
        String(symbol.prefix(1))
    }

    var holdingValue: Decimal {
        balance * (marketPrice ?? 0)
    }

    var iconColor: Color {
        Theme.accent
    }

    func dailyChangeColor(theme: Theme) -> Color {
        guard let dailyChange else { return theme.fg2 }
        return dailyChange >= 0 ? Theme.pos : Theme.neg
    }
}
