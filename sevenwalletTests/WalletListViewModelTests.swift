import Foundation
import Testing
@testable import sevenwallet

@MainActor
struct WalletListViewModelTests {
    @Test
    func rowsKeepSnapshotOrderAndCalculatePortfolioSummaries() async throws {
        let first = try makeWallet(index: 1, name: "First", color: .purple)
        let second = try makeWallet(index: 2, name: "Second", color: .teal)
        let repository = PortfolioTokenRepositorySpy(portfolioScripts: [
            [.fresh(portfolio(
                address: first.address,
                tokens: [
                    token(symbol: "ETH", balance: "2", price: "100"),
                    token(symbol: "USDC", balance: "3", price: "10")
                ]
            ))],
            [.fresh(portfolio(
                address: second.address,
                tokens: [token(symbol: "ETH", balance: "1", price: "50")]
            ))]
        ])
        let viewModel = WalletListViewModel(tokenRepository: repository)

        await viewModel.load(snapshot: .init(
            wallets: [first, second],
            selectedWalletID: second.id
        ))

        #expect(viewModel.rows.map(\.id) == [first.id, second.id])
        #expect(viewModel.selectedWalletID == second.id)
        #expect(viewModel.rows[0].totalValue == 230)
        #expect(viewModel.rows[0].formattedTotalValue == "$230.00")
        #expect(viewModel.rows[0].assetCount == 2)
        #expect(viewModel.rows[0].formattedAssetCount == "2 assets")
        #expect(viewModel.rows[1].formattedTotalValue == "$50.00")
        #expect(repository.requestedPortfolioAddresses == [
            first.address, second.address
        ])
        #expect(repository.requestedPortfolioPolicies == [
            .ifExpired, .ifExpired
        ])
    }

    @Test
    func cachedSummaryRemainsVisibleUntilFreshSummaryArrives() async throws {
        let wallet = try makeWallet(index: 1, name: "Main", color: .blue)
        let cached = portfolio(
            address: wallet.address,
            tokens: [token(symbol: "ETH", balance: "1", price: "100")]
        )
        let fresh = portfolio(
            address: wallet.address,
            tokens: [token(symbol: "ETH", balance: "2", price: "100")]
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioRequestScripts: [
                .gated(
                    before: [.cached(cached), .refreshing],
                    after: [.fresh(fresh)]
                )
            ]
        )
        let viewModel = WalletListViewModel(tokenRepository: repository)

        let load = Task {
            await viewModel.load(snapshot: .init(
                wallets: [wallet],
                selectedWalletID: wallet.id
            ))
        }
        await repository.waitUntilPortfolioGated()
        await waitForTotal("$100.00", viewModel: viewModel)

        #expect(viewModel.rows.first?.formattedTotalValue == "$100.00")
        #expect(viewModel.rows.first?.isLoading == true)

        repository.releasePortfolioGate()
        await load.value

        #expect(viewModel.rows.first?.formattedTotalValue == "$200.00")
        #expect(viewModel.rows.first?.isLoading == false)
        #expect(viewModel.rows.first?.errorMessage == nil)
    }

    @Test
    func oneFailureDoesNotHideSuccessfulRowsAndPreservesCachedData() async throws {
        let first = try makeWallet(index: 1, name: "First", color: .purple)
        let second = try makeWallet(index: 2, name: "Second", color: .teal)
        let cached = portfolio(
            address: first.address,
            tokens: [token(symbol: "ETH", balance: "1", price: "100")]
        )
        let repository = PortfolioTokenRepositorySpy(
            portfolioRequestScripts: [
                .init(
                    events: [.cached(cached), .refreshing],
                    error: .remoteFailure
                ),
                .init(events: [.fresh(portfolio(
                    address: second.address,
                    tokens: [token(
                        symbol: "ETH",
                        balance: "2",
                        price: "100"
                    )]
                ))])
            ]
        )
        let viewModel = WalletListViewModel(tokenRepository: repository)

        await viewModel.load(snapshot: .init(
            wallets: [first, second],
            selectedWalletID: first.id
        ))

        #expect(viewModel.rows[0].formattedTotalValue == "$100.00")
        #expect(viewModel.rows[0].errorMessage == "Unable to load tokens.")
        #expect(viewModel.rows[1].formattedTotalValue == "$200.00")
        #expect(viewModel.rows[1].errorMessage == nil)
        #expect(viewModel.hasPortfolioFailures)
    }

    @Test
    func failedRowCanRetryWithNormalCachePolicy() async throws {
        let wallet = try makeWallet(index: 1, name: "Main", color: .blue)
        let repository = PortfolioTokenRepositorySpy(
            portfolioRequestScripts: [
                .init(events: [.refreshing], error: .remoteFailure),
                .init(events: [.fresh(portfolio(
                    address: wallet.address,
                    tokens: [token(
                        symbol: "ETH",
                        balance: "2",
                        price: "100"
                    )]
                ))])
            ]
        )
        let viewModel = WalletListViewModel(tokenRepository: repository)
        let snapshot = SavedWalletSnapshot(
            wallets: [wallet],
            selectedWalletID: wallet.id
        )

        await viewModel.load(snapshot: snapshot)

        #expect(viewModel.rows.first?.formattedTotalValue == "Unavailable")
        #expect(viewModel.rows.first?.formattedAssetCount == "Unavailable")
        #expect(viewModel.hasPortfolioFailures)

        await viewModel.retryFailed()

        #expect(viewModel.rows.first?.formattedTotalValue == "$200.00")
        #expect(viewModel.rows.first?.formattedAssetCount == "1 asset")
        #expect(!viewModel.hasPortfolioFailures)
        #expect(repository.requestedPortfolioPolicies == [
            .ifExpired, .ifExpired
        ])
    }

    @Test
    func removingWalletCancelsItsLoadAndKeepsRemainingRow() async throws {
        let first = try makeWallet(index: 1, name: "First", color: .purple)
        let second = try makeWallet(index: 2, name: "Second", color: .teal)
        let repository = PortfolioTokenRepositorySpy(
            portfolioScripts: [[], []],
            holdsPortfolioOpen: true
        )
        let viewModel = WalletListViewModel(tokenRepository: repository)
        let load = Task {
            await viewModel.load(snapshot: .init(
                wallets: [first, second],
                selectedWalletID: first.id
            ))
        }
        await waitForRequestCount(2, repository: repository)

        viewModel.update(snapshot: .init(
            wallets: [second],
            selectedWalletID: second.id
        ))
        await repository.waitUntilPortfolioTerminated(request: 0)

        #expect(viewModel.rows.map(\.id) == [second.id])
        #expect(viewModel.selectedWalletID == second.id)

        viewModel.cancel()
        await repository.waitUntilPortfolioTerminated(request: 1)
        await load.value
    }

    @Test
    func emptySnapshotStartsNoPortfolioLoads() async {
        let repository = PortfolioTokenRepositorySpy(portfolioScripts: [])
        let viewModel = WalletListViewModel(tokenRepository: repository)

        await viewModel.load(snapshot: .init(
            wallets: [],
            selectedWalletID: nil
        ))

        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.selectedWalletID == nil)
        #expect(repository.requestedPortfolioAddresses.isEmpty)
    }

    private func waitForRequestCount(
        _ count: Int,
        repository: PortfolioTokenRepositorySpy
    ) async {
        for _ in 0..<100 where repository.requestedPortfolioAddresses.count < count {
            await Task.yield()
        }
    }

    private func waitForTotal(
        _ total: String,
        viewModel: WalletListViewModel
    ) async {
        for _ in 0..<100 where viewModel.rows.first?.formattedTotalValue != total {
            await Task.yield()
        }
    }

    private func makeWallet(
        index: Int,
        name: String,
        color: WalletCardColor
    ) throws -> SavedWallet {
        SavedWallet(
            id: UUID(uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                index
            ))!,
            name: name,
            address: try EVMAddress(String(
                format: "0x%040x",
                index
            )),
            cardColor: color,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }

    private func portfolio(
        address: EVMAddress,
        tokens: [WalletToken]
    ) -> TokenPortfolio {
        TokenPortfolio(
            address: address,
            fetchedAt: nil,
            network: "ethereum",
            tokens: tokens
        )
    }

    private func token(
        symbol: String,
        balance: String,
        price: String
    ) -> WalletToken {
        WalletToken(
            tokenAddress: symbol == "ETH"
                ? nil
                : "0x0000000000000000000000000000000000000001",
            symbol: symbol,
            name: symbol,
            decimals: 18,
            rawBalance: "0",
            balance: Decimal(string: balance)!,
            isNative: symbol == "ETH",
            price: nil,
            logoURL: nil,
            change24hPercent: nil,
            coinKey: symbol.lowercased(),
            marketCapUSD: nil,
            marketDataUpdatedAt: nil,
            priceUSD: Decimal(string: price)
        )
    }
}
