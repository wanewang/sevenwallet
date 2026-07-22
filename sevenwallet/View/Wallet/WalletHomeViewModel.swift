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
