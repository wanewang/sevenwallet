import Foundation
import Testing
@testable import sevenwallet

@MainActor
struct WalletHomeViewModelTests {
    @Test
    func missingConfigurationBecomesHomeError() async {
        let home = AppDependencies.makeHomeViewModel(
            arguments: [],
            environment: [:],
            infoDictionary: [:],
            inMemoryStore: true
        )

        await home.loadTokens()

        #expect(home.tokens.isEmpty)
        #expect(home.tokenErrorMessage == "BASE_URL is not configured.")
    }

    @Test
    func fixtureLoadsWithoutRuntimeConfiguration() async {
        let home = AppDependencies.makeHomeViewModel(
            arguments: ["UI_TEST_FIXTURE"],
            environment: [:],
            infoDictionary: [:]
        )

        await home.loadTokens()

        #expect(home.walletCard == nil)
        #expect(home.tokens.first?.symbol == "ETH")
        #expect(home.tokens.first?.formattedPrice == "$1,926.42")
        #expect(home.tokenErrorMessage == nil)
    }

    @Test
    func fixtureSupportsPopulatedWalletAndLongTokenList() async {
        let home = AppDependencies.makeHomeViewModel(
            arguments: [
                "UI_TEST_FIXTURE",
                "UI_TEST_POPULATED_WALLET",
                "UI_TEST_LONG_TOKEN_LIST"
            ],
            environment: [:],
            infoDictionary: [:]
        )

        await home.loadTokens()

        #expect(home.walletCard?.name == "Main Wallet")
        #expect(home.tokens.count == 16)
        #expect(Set(home.tokens.map(\.id)).count == 16)
    }

    @Test
    func fixtureSupportsTokenFailure() async {
        let home = AppDependencies.makeHomeViewModel(
            arguments: ["UI_TEST_FIXTURE", "UI_TEST_TOKEN_ERROR"],
            environment: [:],
            infoDictionary: [:]
        )

        await home.loadTokens()

        #expect(home.tokens.isEmpty)
        #expect(home.tokenErrorMessage == "Unable to load tokens.")
    }

    @Test
    func cancellingDelayedFixtureStopsLoadingWithoutPublishingTokens() async {
        let home = AppDependencies.makeHomeViewModel(
            arguments: ["UI_TEST_FIXTURE", "UI_TEST_DELAYED_TOKENS"],
            environment: [:],
            infoDictionary: [:]
        )

        let load = Task { await home.loadTokens() }
        await waitForLoading(home)
        #expect(home.isLoadingTokens)

        load.cancel()
        await load.value

        #expect(!home.isLoadingTokens)
        #expect(home.tokens.isEmpty)
        #expect(home.tokenErrorMessage == nil)
    }

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
    func selectedWalletLoadsItsPortfolio() async throws {
        let wallet = SavedWallet(
            name: "Main",
            address: try EVMAddress(
                "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
            ),
            cardColor: .purple
        )
        let portfolio = TokenPortfolio(
            address: wallet.address,
            fetchedAt: nil,
            network: "ethereum",
            tokens: [makeRepositoryToken(price: "2000")]
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioScripts: [[.fresh(portfolio)]]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        await home.load(wallet: wallet)

        #expect(repository.requestedPortfolioAddresses == [wallet.address])
        #expect(home.walletCard?.id == wallet.id)
        #expect(home.walletCard?.name == "Main")
        #expect(home.walletCard?.cardColor == .purple)
        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
    }

    @Test
    func editingIdentityRebuildsCardWithoutReloadingPortfolio() async throws {
        let original = try makeSavedWallet(name: "Main", color: .blue)
        let edited = SavedWallet(
            id: original.id,
            name: "Renamed",
            address: original.address,
            cardColor: .amber,
            createdAt: original.createdAt
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioScripts: [
                [.fresh(TokenPortfolio(
                    address: original.address,
                    fetchedAt: nil,
                    network: "ethereum",
                    tokens: [makeRepositoryToken(price: "2000")]
                ))]
            ]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        await home.load(wallet: original)
        await home.load(wallet: edited)

        #expect(repository.requestedPortfolioAddresses == [original.address])
        #expect(home.walletCard?.name == "Renamed")
        #expect(home.walletCard?.cardColor == .amber)
    }

    @Test
    func changingAddressClearsOldPortfolioRows() async throws {
        let original = try makeSavedWallet(name: "Main", color: .blue)
        let replacement = SavedWallet(
            name: "Second",
            address: try EVMAddress(
                "0x81A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F93"
            ),
            cardColor: .teal
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioScripts: [
                [.fresh(makeRepositoryPortfolio(
                    address: original.address,
                    price: "2000"
                ))],
                [.refreshing]
            ]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        await home.load(wallet: original)
        #expect(home.tokens.first?.formattedPrice == "$2,000.00")

        await home.load(wallet: replacement)

        #expect(repository.requestedPortfolioAddresses == [
            original.address, replacement.address
        ])
        #expect(home.walletCard?.id == replacement.id)
        #expect(home.walletCard?.tokens.isEmpty == true)
        #expect(home.tokens.isEmpty)
    }

    @Test
    func refreshAndRetryUseSelectedPortfolio() async throws {
        let wallet = try makeSavedWallet(name: "Main", color: .blue)
        let portfolio = makeRepositoryPortfolio(
            address: wallet.address,
            price: "2000"
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioScripts: [
                [.fresh(portfolio)],
                [.fresh(portfolio)],
                [.fresh(portfolio)]
            ]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        await home.load(wallet: wallet)
        await home.refreshTokens()
        await home.retryTokens()

        #expect(repository.requestedPortfolioAddresses == [
            wallet.address, wallet.address, wallet.address
        ])
    }

    @Test
    func deletingSelectionReturnsToNativeTokensAndIgnoresOldResults() async throws {
        let wallet = try makeSavedWallet(name: "Main", color: .blue)
        let repository = PortfolioTokenRepositorySpy(
            nativeScripts: [[.fresh([makeRepositoryToken(price: "1900")])]],
            portfolioScripts: [[.refreshing]],
            holdsPortfolioOpen: true
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        let oldLoad = Task { await home.load(wallet: wallet) }
        await waitForLoading(home)
        await home.load(wallet: nil)
        oldLoad.cancel()

        #expect(home.walletCard == nil)
        #expect(home.tokens.first?.formattedPrice == "$1,900.00")
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
        await waitForLoading(home)
        #expect(home.isLoadingTokens)

        repository.releaseGate()
        await load.value
        #expect(!home.isLoadingTokens)
        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
    }

    @Test
    func supersededEventsCannotOverwriteNewerRequestState() async {
        let repository = ScriptedTokenRepository(scripts: [
            .gated(
                before: [.refreshing],
                after: [.fresh([makeRepositoryToken(price: "1000")])],
                error: .remoteFailure
            ),
            .gated(
                before: [.refreshing],
                after: [.fresh([makeRepositoryToken(price: "2000")])]
            )
        ])
        let home = WalletHomeViewModel(tokenRepository: repository)

        let older = Task { await home.loadTokens() }
        await repository.waitUntilGated(request: 0)
        await waitForLoading(home)

        let newer = Task { await home.retryTokens() }
        await repository.waitUntilGated(request: 1)
        await waitForLoading(home)

        repository.releaseGate(request: 0)
        await older.value

        #expect(home.tokens.isEmpty)
        #expect(home.tokenErrorMessage == nil)
        #expect(home.isLoadingTokens)

        repository.releaseGate(request: 1)
        await newer.value

        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
        #expect(home.tokenErrorMessage == nil)
        #expect(!home.isLoadingTokens)
    }

    @Test
    func cancellationCleanupBelongsToActiveRequest() async {
        let repository = ScriptedTokenRepository(scripts: [
            .gated(before: [.refreshing], after: []),
            .gated(before: [.refreshing], after: [])
        ])
        let home = WalletHomeViewModel(tokenRepository: repository)

        let older = Task { await home.loadTokens() }
        await repository.waitUntilGated(request: 0)
        await waitForLoading(home)

        let newer = Task { await home.retryTokens() }
        await repository.waitUntilGated(request: 1)
        await waitForLoading(home)

        older.cancel()
        await older.value
        #expect(home.isLoadingTokens)

        newer.cancel()
        await newer.value
        #expect(!home.isLoadingTokens)
        #expect(home.tokenErrorMessage == nil)
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

    private func waitForLoading(_ home: WalletHomeViewModel) async {
        for _ in 0..<100 {
            guard !home.isLoadingTokens else { return }
            await Task.yield()
        }
    }

    private func makeSavedWallet(
        name: String,
        color: WalletCardColor
    ) throws -> SavedWallet {
        SavedWallet(
            name: name,
            address: try EVMAddress(
                "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
            ),
            cardColor: color
        )
    }
}
