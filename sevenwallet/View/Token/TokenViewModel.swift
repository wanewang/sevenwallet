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
