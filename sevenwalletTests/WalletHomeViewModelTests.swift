import Foundation
import Testing
@testable import sevenwallet

@MainActor
struct WalletHomeViewModelTests {
    @Test
    func missingConfigurationBecomesHomeError() async {
        let state = AppDependencies.makeAppState(
            arguments: [],
            environment: [:],
            infoDictionary: [:],
            inMemoryStore: true
        )
        await state.session.load()
        let home = state.homeViewModel

        await home.load(wallet: state.session.selectedWallet)

        #expect(home.tokens.isEmpty)
        #expect(home.tokenErrorMessage == "BASE_URL is not configured.")
    }

    @Test
    func fixtureLoadsWithoutRuntimeConfiguration() async {
        let state = AppDependencies.makeAppState(
            arguments: ["UI_TEST_FIXTURE"],
            environment: [:],
            infoDictionary: [:]
        )
        await state.session.load()
        let home = state.homeViewModel

        await home.load(wallet: state.session.selectedWallet)

        #expect(home.walletCard == nil)
        #expect(home.tokens.first?.symbol == "ETH")
        #expect(home.tokens.first?.formattedPrice == "$1,926.42")
        #expect(home.tokenErrorMessage == nil)
    }

    @Test
    func fixtureSupportsPopulatedWalletAndLongTokenList() async {
        let state = AppDependencies.makeAppState(
            arguments: [
                "UI_TEST_FIXTURE",
                "UI_TEST_POPULATED_WALLET",
                "UI_TEST_LONG_TOKEN_LIST"
            ],
            environment: [:],
            infoDictionary: [:]
        )
        await state.session.load()
        let home = state.homeViewModel

        await home.load(wallet: state.session.selectedWallet)

        #expect(home.walletCard?.name == "Main Wallet")
        #expect(home.tokens.count == 16)
        #expect(Set(home.tokens.map(\.id)).count == 16)
    }

    @Test
    func fixtureSupportsTokenFailure() async {
        let state = AppDependencies.makeAppState(
            arguments: ["UI_TEST_FIXTURE", "UI_TEST_TOKEN_ERROR"],
            environment: [:],
            infoDictionary: [:]
        )
        await state.session.load()
        let home = state.homeViewModel

        await home.load(wallet: state.session.selectedWallet)

        #expect(home.tokens.isEmpty)
        #expect(home.tokenErrorMessage == "Unable to load tokens.")
    }

    @Test
    func cancellingDelayedFixtureStopsLoadingWithoutPublishingTokens() async {
        let state = AppDependencies.makeAppState(
            arguments: ["UI_TEST_FIXTURE", "UI_TEST_DELAYED_TOKENS"],
            environment: [:],
            infoDictionary: [:]
        )
        await state.session.load()
        let home = state.homeViewModel

        let load = Task { await home.load(wallet: state.session.selectedWallet) }
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
    func noWalletLoadsNativeTokens() async {
        let repository = PortfolioTokenRepositorySpy(
            nativeScripts: [[.fresh([makeRepositoryToken(price: "1900")])]]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        home.updateWallet(nil)

        #expect(repository.requestedNativePolicies.isEmpty)
        #expect(home.tokens.isEmpty)

        await home.loadSelectedResource()

        #expect(repository.requestedNativePolicies == [.ifExpired])
        #expect(repository.requestedPortfolioAddresses.isEmpty)
        #expect(home.tokens.first?.formattedPrice == "$1,900.00")
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
    func editingIdentityAfterEmptyPortfolioDoesNotReload() async throws {
        let original = try makeSavedWallet(name: "Main", color: .blue)
        let edited = SavedWallet(
            id: original.id,
            name: "Renamed",
            address: original.address,
            cardColor: .amber,
            createdAt: original.createdAt
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioScripts: [[], []]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        await home.load(wallet: original)
        await home.load(wallet: edited)

        #expect(repository.requestedPortfolioAddresses == [original.address])
        #expect(home.walletCard?.name == "Renamed")
        #expect(home.walletCard?.cardColor == .amber)
        #expect(home.tokens.isEmpty)
    }

    @Test
    func editingIdentityDuringPortfolioLoadDoesNotReload() async throws {
        let original = try makeSavedWallet(name: "Main", color: .blue)
        let edited = SavedWallet(
            id: original.id,
            name: "Renamed",
            address: original.address,
            cardColor: .amber,
            createdAt: original.createdAt
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioRequestScripts: [
                .gated(
                    before: [.refreshing],
                    after: [.fresh(makeRepositoryPortfolio(
                        address: original.address,
                        price: "2000"
                    ))]
                )
            ]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        home.updateWallet(original)
        let initialLoad = Task { await home.loadSelectedResource() }
        await repository.waitUntilPortfolioGated()
        await waitForLoading(home)

        home.updateWallet(edited)
        repository.releasePortfolioGate()
        await initialLoad.value

        #expect(repository.requestedPortfolioAddresses == [original.address])
        #expect(home.walletCard?.name == "Renamed")
        #expect(home.walletCard?.cardColor == .amber)
        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
        #expect(!home.isLoadingTokens)
        #expect(home.tokenErrorMessage == nil)
    }

    @Test
    func unresolvedWalletPersistenceBlocksManualNativeLoads() async {
        let repository = PortfolioTokenRepositorySpy(
            nativeScripts: [[], []]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        home.updateLoadingEligibility(false)
        await home.refreshTokens()
        await home.retryTokens()

        #expect(repository.requestedNativePolicies.isEmpty)
    }

    @Test
    func resolvedRetryCanReplaceCancelledLoadBeforeCleanup() async throws {
        let wallet = try makeSavedWallet(name: "Main", color: .blue)
        let fresh = makeRepositoryPortfolio(
            address: wallet.address,
            price: "2000"
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioRequestScripts: [
                .gated(before: [.refreshing], after: []),
                .init(events: [.fresh(fresh)])
            ]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        home.updateWallet(wallet)
        let initialLoad = Task { await home.loadSelectedResource() }
        await repository.waitUntilPortfolioGated()
        await waitForLoading(home)

        home.updateLoadingEligibility(false)
        initialLoad.cancel()
        home.updateLoadingEligibility(true)
        let replacement = Task { await home.loadSelectedResource() }

        await replacement.value
        await initialLoad.value

        #expect(repository.requestedPortfolioAddresses == [
            wallet.address,
            wallet.address
        ])
        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
        #expect(!home.isLoadingTokens)
        #expect(home.tokenErrorMessage == nil)
    }

    @Test
    func cancelledEmptyPortfolioLoadCanRetrySameWallet() async throws {
        let wallet = try makeSavedWallet(name: "Main", color: .blue)
        let repository = PortfolioTokenRepositorySpy(
            portfolioRequestScripts: [
                .gated(before: [.refreshing], after: []),
                .init(events: [.fresh(makeRepositoryPortfolio(
                    address: wallet.address,
                    price: "2000"
                ))])
            ]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        let firstLoad = Task { await home.load(wallet: wallet) }
        await repository.waitUntilPortfolioGated()
        await waitForLoading(home)

        firstLoad.cancel()
        await firstLoad.value
        await repository.waitUntilPortfolioTerminated()

        await home.load(wallet: wallet)

        #expect(repository.requestedPortfolioAddresses == [
            wallet.address, wallet.address
        ])
        #expect(repository.requestedPortfolioPolicies == [
            .ifExpired, .ifExpired
        ])
        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
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
    func latePortfolioValueAndErrorCannotOverwriteNewAddress() async throws {
        let original = try makeSavedWallet(name: "Main", color: .blue)
        let replacement = SavedWallet(
            name: "Second",
            address: try EVMAddress(
                "0x81A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F93"
            ),
            cardColor: .teal
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioRequestScripts: [
                .gated(
                    before: [.refreshing],
                    after: [.fresh(makeRepositoryPortfolio(
                        address: original.address,
                        price: "1000"
                    ))],
                    error: .remoteFailure
                ),
                .init(events: [.fresh(makeRepositoryPortfolio(
                    address: replacement.address,
                    price: "2000"
                ))])
            ]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        let oldLoad = Task { await home.load(wallet: original) }
        await repository.waitUntilPortfolioGated()
        await waitForLoading(home)

        await home.load(wallet: replacement)
        repository.releasePortfolioGate()
        await oldLoad.value
        await repository.waitUntilPortfolioTerminated()

        #expect(home.walletCard?.id == replacement.id)
        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
        #expect(home.tokenErrorMessage == nil)
        #expect(repository.terminatedPortfolioRequests.contains(0))
    }

    @Test
    func latePortfolioErrorCannotOverwriteNewAddressState() async throws {
        let original = try makeSavedWallet(name: "Main", color: .blue)
        let replacement = SavedWallet(
            name: "Second",
            address: try EVMAddress(
                "0x81A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F93"
            ),
            cardColor: .teal
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioRequestScripts: [
                .gated(
                    before: [.refreshing],
                    after: [],
                    error: .remoteFailure
                ),
                .init(events: [.fresh(makeRepositoryPortfolio(
                    address: replacement.address,
                    price: "2000"
                ))])
            ]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        let oldLoad = Task { await home.load(wallet: original) }
        await repository.waitUntilPortfolioGated()
        await waitForLoading(home)

        await home.load(wallet: replacement)
        repository.releasePortfolioGate()
        await oldLoad.value
        await repository.waitUntilPortfolioTerminated()

        #expect(home.walletCard?.id == replacement.id)
        #expect(home.tokens.first?.formattedPrice == "$2,000.00")
        #expect(home.tokenErrorMessage == nil)
        #expect(!home.isLoadingTokens)
        #expect(repository.terminatedPortfolioRequests.contains(0))
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
        #expect(repository.requestedPortfolioPolicies == [
            .ifExpired, .ifExpired, .ifExpired
        ])
    }

    @Test
    func deletingSelectionReturnsToNativeTokensAndIgnoresOldResults() async throws {
        let wallet = try makeSavedWallet(name: "Main", color: .blue)
        let repository = PortfolioTokenRepositorySpy(
            nativeScripts: [[.fresh([makeRepositoryToken(price: "1900")])]],
            portfolioRequestScripts: [
                .gated(before: [.refreshing], after: [])
            ]
        )
        let home = WalletHomeViewModel(tokenRepository: repository)

        let oldLoad = Task { await home.load(wallet: wallet) }
        await repository.waitUntilPortfolioGated()
        await home.load(wallet: nil)
        oldLoad.cancel()
        await oldLoad.value
        await repository.waitUntilPortfolioTerminated()

        #expect(home.walletCard == nil)
        #expect(home.tokens.first?.formattedPrice == "$1,900.00")
        #expect(repository.requestedNativePolicies == [.ifExpired])
        #expect(repository.terminatedPortfolioRequests.contains(0))
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
    func selectedPortfolioThirdPullForcesThenResets() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = ScriptedDateProvider([
            start,
            start.addingTimeInterval(20),
            start.addingTimeInterval(59),
            start.addingTimeInterval(60)
        ])
        let wallet = try makeSavedWallet(name: "Main", color: .blue)
        let repository = PortfolioTokenRepositorySpy(
            portfolioScripts: Array(repeating: [], count: 5)
        )
        let home = WalletHomeViewModel(
            tokenRepository: repository,
            dateProvider: clock.provider
        )

        await home.load(wallet: wallet)
        await home.refreshTokens()
        await home.refreshTokens()
        await home.refreshTokens()
        await home.refreshTokens()

        #expect(repository.requestedPortfolioPolicies == [
            .ifExpired, .ifExpired, .ifExpired, .force, .ifExpired
        ])
    }

    @Test
    func populatedWalletTotalDerivesFromRepositoryRows() async {
        let repository = PortfolioTokenRepositorySpy(nativeScripts: [[
            .fresh([
                makeRepositoryToken(price: "1900"),
                makeRepositoryToken(price: "2000")
            ])
        ]])
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
        #expect(repository.requestedNativePolicies == [.ifExpired])
        #expect(repository.requestedPortfolioAddresses.isEmpty)
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
