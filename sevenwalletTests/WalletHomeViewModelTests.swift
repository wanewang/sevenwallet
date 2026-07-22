import Testing
@testable import sevenwallet

@MainActor
struct WalletHomeViewModelTests {
    @Test
    func sampleUsesRequiredTokensAndSharedInstances() {
        let home = WalletHomeViewModel.sample()

        #expect(home.tokens.map(\.symbol) == ["ETH", "BTC", "SOL", "USDC"])
        #expect(home.walletCard.name == "Main Wallet")
        #expect(home.walletCard.tokens[0] === home.tokens[0])
        #expect(abs(home.walletCard.totalValue - 26_321.496432) < 0.0001)
        #expect(home.walletCard.formattedTotalValue == "$26,321.50")
    }

    @Test
    func themeStartsDarkAndToggles() {
        let home = WalletHomeViewModel.sample()

        #expect(!home.isThemeLight)
        home.toggleTheme()
        #expect(home.isThemeLight)
    }

    @Test
    func testOnlyCopiesCreateEnoughRowsWithoutSharingIdentity() {
        let home = WalletHomeViewModel.sample(tokenSetCopies: 2)

        #expect(home.tokens.count == 8)
        #expect(home.tokens[0].symbol == home.tokens[4].symbol)
        #expect(home.tokens[0] !== home.tokens[4])
    }
}
