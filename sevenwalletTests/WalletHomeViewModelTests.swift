import Foundation
import Testing
@testable import sevenwallet

@MainActor
struct WalletHomeViewModelTests {
    @Test
    func cachedThenFreshUpdatesRows() async {
        let repository = ScriptedTokenRepository(events: [
            .cached([makeRepositoryToken(price: "1900")]),
            .refreshing,
            .fresh([makeRepositoryToken(price: "2000")])
        ])
        let home = WalletHomeViewModel(tokenRepository: repository)

        await home.loadTokens()

        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
        #expect(!home.isLoadingTokens)
        #expect(home.tokenErrorMessage == nil)
        #expect(home.walletCard == nil)
    }

    @Test
    func refreshingEventKeepsSpinnerVisibleUntilFreshDataArrives() async {
        let repository = ScriptedTokenRepository(scripts: [
            .gated(
                before: [.refreshing],
                after: [.fresh([makeRepositoryToken(price: "2000")])]
            )
        ])
        let home = WalletHomeViewModel(tokenRepository: repository)

        let load = Task { await home.loadTokens() }
        await repository.waitUntilGated()
        for _ in 0..<100 {
            guard !home.isLoadingTokens else { break }
            await Task.yield()
        }
        #expect(home.isLoadingTokens)

        repository.releaseGate()
        await load.value
        #expect(!home.isLoadingTokens)
        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
    }

    @Test
    func initialErrorStopsSpinnerAndShowsConciseMessage() async {
        let repository = ScriptedTokenRepository(
            events: [.refreshing],
            error: .remoteFailure
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        await home.loadTokens()

        #expect(home.tokens.isEmpty)
        #expect(!home.isLoadingTokens)
        #expect(home.tokenErrorMessage == "Unable to load tokens.")
    }

    @Test
    func cachedRowsSurviveRefreshError() async {
        let repository = ScriptedTokenRepository(
            events: [
                .cached([makeRepositoryToken(price: "1900")]),
                .refreshing
            ],
            error: .remoteFailure
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        await home.loadTokens()

        #expect(home.tokens.first?.formattedPrice == "$1,900.00")
        #expect(!home.isLoadingTokens)
        #expect(home.tokenErrorMessage == "Unable to load tokens.")
    }

    @Test
    func retryUsesNormalCachePolicyAndClearsPriorError() async {
        let repository = ScriptedTokenRepository(scripts: [
            .init(events: [.refreshing], error: .remoteFailure),
            .init(events: [.fresh([makeRepositoryToken(price: "2000")])])
        ])
        let home = WalletHomeViewModel(tokenRepository: repository)

        await home.loadTokens()
        #expect(home.tokenErrorMessage != nil)

        await home.retryTokens()

        #expect(repository.requestedPolicies == [.ifExpired, .ifExpired])
        #expect(home.tokenErrorMessage == nil)
        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
    }

    @Test
    func thirdPullInsideWindowForcesThenResets() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = ScriptedDateProvider([
            start,
            start.addingTimeInterval(20),
            start.addingTimeInterval(59),
            start.addingTimeInterval(60)
        ])
        let repository = ScriptedTokenRepository(scripts: Array(
            repeating: .init(events: []),
            count: 4
        ))
        let home = WalletHomeViewModel(
            tokenRepository: repository,
            dateProvider: clock.provider
        )

        await home.refreshTokens()
        await home.refreshTokens()
        await home.refreshTokens()
        await home.refreshTokens()

        #expect(repository.requestedPolicies == [
            .ifExpired, .ifExpired, .force, .ifExpired
        ])
    }

    @Test
    func populatedWalletTotalDerivesFromRepositoryRows() async {
        let repository = ScriptedTokenRepository(events: [
            .fresh([
                makeRepositoryToken(price: "1900"),
                makeRepositoryToken(price: "2000")
            ])
        ])
        let home = WalletHomeViewModel(
            tokenRepository: repository,
            walletName: "Main Wallet",
            walletAddress: "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
        )

        await home.loadTokens()

        #expect(home.walletCard?.name == "Main Wallet")
        #expect(home.walletCard?.tokens[0] === home.tokens[0])
        #expect(home.walletCard?.totalValue == 3_900)
        #expect(home.walletCard?.formattedTotalValue == "$3,900.00")
    }

    @Test
    func themeStartsDarkAndToggles() {
        let repository = ScriptedTokenRepository(events: [])
        let home = WalletHomeViewModel(tokenRepository: repository)

        #expect(!home.isThemeLight)
        home.toggleTheme()
        #expect(home.isThemeLight)
    }
}
