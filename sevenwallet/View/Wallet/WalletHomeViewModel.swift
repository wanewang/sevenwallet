import Foundation
import Observation

@MainActor
@Observable
final class WalletHomeViewModel {
    var isThemeLight: Bool
    private(set) var tokens: [TokenViewModel]
    private(set) var isLoadingTokens = false
    private(set) var tokenErrorMessage: String?
    private(set) var walletCard: WalletCardViewModel?
    private(set) var walletSnapshot = SavedWalletSnapshot(
        wallets: [],
        selectedWalletID: nil
    )

    private let tokenRepository: any TokenRepositoryProtocol
    private let dateProvider: DateProvider
    private var compatibilityWallet: SavedWallet?
    private var resourceState = ResourceState.idle
    private var refreshCoordinator = PullRefreshCoordinator()
    private var requestGeneration = 0
    private var isLoadingEligible = true

    init(
        isThemeLight: Bool = false,
        tokenRepository: any TokenRepositoryProtocol,
        dateProvider: DateProvider = .system,
        walletName: String? = nil,
        walletAddress: String? = nil
    ) {
        self.isThemeLight = isThemeLight
        self.tokenRepository = tokenRepository
        self.dateProvider = dateProvider
        tokens = []

        if let walletName,
           let walletAddress,
           let address = try? EVMAddress(walletAddress) {
            let wallet = SavedWallet(
                name: walletName,
                address: address,
                cardColor: .blue
            )
            compatibilityWallet = wallet
            walletCard = WalletCardViewModel(
                wallet: wallet,
                tokens: []
            )
        } else {
            compatibilityWallet = nil
            walletCard = nil
        }
    }

    private var selectedWallet: SavedWallet? {
        walletSnapshot.selectedWallet
    }

    func toggleTheme() {
        isThemeLight.toggle()
    }

    func loadTokens() async {
        guard isLoadingEligible else { return }
        await consume(policy: .ifExpired)
    }

    func load(wallet: SavedWallet?) async {
        updateWallet(wallet)
        await loadSelectedResource()
    }

    func updateWallet(_ wallet: SavedWallet?) {
        updateWallets(
            SavedWalletSnapshot(
                wallets: wallet.map { [$0] } ?? [],
                selectedWalletID: wallet?.id
            )
        )
    }

    func updateWallets(_ snapshot: SavedWalletSnapshot) {
        let addressChanged =
            selectedWallet?.address != snapshot.selectedWallet?.address
        walletSnapshot = snapshot
        compatibilityWallet = nil

        if addressChanged {
            requestGeneration += 1
            tokens = []
            isLoadingTokens = false
            tokenErrorMessage = nil
            resourceState = .idle
        }
        rebuildWalletCard()
    }

    func loadSelectedResource() async {
        guard isLoadingEligible, resourceState == .idle else { return }
        await consume(policy: .ifExpired)
    }

    func refreshTokens() async {
        guard isLoadingEligible else { return }
        await consume(policy: refreshCoordinator.recordPull(at: dateProvider.now()))
    }

    func retryTokens() async {
        guard isLoadingEligible else { return }
        await consume(policy: .ifExpired)
    }

    func updateLoadingEligibility(_ isEligible: Bool) {
        guard isLoadingEligible != isEligible else { return }
        isLoadingEligible = isEligible
        guard !isEligible else { return }

        requestGeneration += 1
        isLoadingTokens = false
        resourceState = .idle
    }

    static func sample(tokenSetCopies: Int = 1) -> WalletHomeViewModel {
        let values = (0..<tokenSetCopies).flatMap { copy in
            [
                sampleToken(
                    symbol: "ETH",
                    name: "Ether",
                    balance: "4.25",
                    price: "2936.52",
                    coinKey: "ethereum",
                    copy: copy
                ),
                sampleToken(
                    symbol: "BTC",
                    name: "Bitcoin",
                    balance: "0.0934",
                    price: "104022.48",
                    coinKey: "bitcoin",
                    copy: copy
                ),
                sampleToken(
                    symbol: "SOL",
                    name: "Solana",
                    balance: "18.42",
                    price: "142.54",
                    coinKey: "solana",
                    copy: copy
                ),
                sampleToken(
                    symbol: "USDC",
                    name: "USD Coin",
                    balance: "1500",
                    price: "1",
                    coinKey: "usd-coin",
                    copy: copy
                )
            ]
        }

        let home = WalletHomeViewModel(
            tokenRepository: StaticTokenRepository(tokens: values),
            walletName: "Main Wallet",
            walletAddress: "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
        )
        home.updateTokens(values)
        return home
    }

    private static func sampleToken(
        symbol: String,
        name: String,
        balance: String,
        price: String,
        coinKey: String,
        copy: Int
    ) -> WalletToken {
        WalletToken(
            tokenAddress: copy == 0 ? nil : String(format: "0x%040llx", UInt64(copy)),
            symbol: symbol,
            name: name,
            decimals: 18,
            rawBalance: "0",
            balance: Decimal(string: balance)!,
            isNative: copy == 0,
            price: nil,
            logoURL: nil,
            change24hPercent: nil,
            coinKey: "\(coinKey)-\(copy)",
            marketCapUSD: nil,
            marketDataUpdatedAt: nil,
            priceUSD: Decimal(string: price)
        )
    }

    private func consume(policy: RefreshPolicy) async {
        requestGeneration += 1
        let generation = requestGeneration
        let wallet = selectedWallet
        resourceState = .loading
        tokenErrorMessage = nil
        defer {
            if generation == requestGeneration {
                isLoadingTokens = false
                if resourceState == .loading {
                    resourceState = .idle
                }
            }
        }

        do {
            var latestTokens: [WalletToken]?
            let stream: AsyncThrowingStream<
                RepositoryLoadEvent<[WalletToken]>,
                Swift.Error
            >
            if let wallet {
                stream = tokenRepository
                    .portfolio(address: wallet.address, policy: policy)
                    .mapValues(\.tokens)
            } else {
                stream = tokenRepository.nativeTokens(policy: policy)
            }

            for try await event in stream {
                guard generation == requestGeneration else { return }
                switch event {
                case .cached(let value), .fresh(let value):
                    latestTokens = value
                    updateTokens(value)
                    isLoadingTokens = false
                case .refreshing:
                    isLoadingTokens = true
                }
            }
            guard generation == requestGeneration, !Task.isCancelled else {
                return
            }

            if let wallet, let latestTokens, !latestTokens.isEmpty {
                isLoadingTokens = true
                do {
                    let markets = try await tokenRepository.tokenMarkets(
                        address: wallet.address
                    )
                    guard generation == requestGeneration,
                          !Task.isCancelled else {
                        return
                    }
                    updateTokens(enrich(latestTokens, with: markets.tokens))
                } catch is CancellationError {
                    return
                } catch {
                    // Every cause shows the same message, so record the real
                    // one before it is discarded.
                    AppLog.marketError(
                        """
                        Market enrichment failed, keeping portfolio values: \
                        \(String(describing: error))
                        """
                    )
                    guard generation == requestGeneration,
                          !Task.isCancelled else {
                        return
                    }
                    tokenErrorMessage = "Market data is unavailable."
                    resourceState = .loaded
                    return
                }
            }
            resourceState = .loaded
        } catch {
            guard generation == requestGeneration, !Task.isCancelled else { return }
            tokenErrorMessage = error.localizedDescription
        }
    }

    private func enrich(
        _ tokens: [WalletToken],
        with markets: [TokenMarket]
    ) -> [WalletToken] {
        let marketsByID = Dictionary(
            markets.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return tokens.map { token in
            guard let market = marketsByID[token.id] else { return token }
            let coinGecko = market.coinGecko.map {
                (priceUSD: $0.priceUSD, change24hPercent: $0.change24hPercent)
            }
            let coinMarketCap = market.coinMarketCap.map {
                (priceUSD: $0.priceUSD, change24hPercent: $0.change24hPercent)
            }

            // The provider supplying the 24h change also supplies the price,
            // so both fields describe the same snapshot. CoinGecko leads unless
            // only CoinMarketCap has a change.
            let coinGeckoLeads = coinGecko?.change24hPercent != nil
                || coinMarketCap?.change24hPercent == nil
            let leader = coinGeckoLeads ? coinGecko : coinMarketCap
            let follower = coinGeckoLeads ? coinMarketCap : coinGecko

            return WalletToken(
                tokenAddress: token.tokenAddress,
                symbol: token.symbol,
                name: token.name,
                decimals: token.decimals,
                rawBalance: token.rawBalance,
                balance: token.balance,
                isNative: token.isNative,
                price: token.price,
                logoURL: token.logoURL,
                change24hPercent: leader?.change24hPercent
                    ?? token.change24hPercent,
                coinKey: token.coinKey,
                marketCapUSD: token.marketCapUSD,
                marketDataUpdatedAt: token.marketDataUpdatedAt,
                priceUSD: leader?.priceUSD
                    ?? follower?.priceUSD
                    ?? token.priceUSD
            )
        }
    }

    private func updateTokens(_ value: [WalletToken]) {
        let rows = value.map { TokenViewModel(token: $0) }
        tokens = rows
        rebuildWalletCard()
    }

    private func rebuildWalletCard() {
        walletCard = (selectedWallet ?? compatibilityWallet).map {
            WalletCardViewModel(wallet: $0, tokens: tokens)
        }
    }
}

private enum ResourceState: Equatable {
    case idle
    case loading
    case loaded
}

private struct StaticTokenRepository: TokenRepositoryProtocol {
    let tokens: [WalletToken]

    func nativeTokens(
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<[WalletToken]>, Swift.Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.cached(tokens))
            continuation.finish()
        }
    }

    func portfolio(
        address: EVMAddress,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<TokenPortfolio>, Swift.Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func tokenMarkets(address: EVMAddress) async throws -> TokenMarketPortfolio {
        TokenMarketPortfolio(
            wallet: address,
            network: "ethereum",
            portfolioFetchedAt: Date(timeIntervalSince1970: 0),
            tokens: []
        )
    }
}

private extension AsyncThrowingStream {
    func mapValues<Input, Output>(
        _ transform: @escaping @Sendable (Input) -> Output
    ) -> AsyncThrowingStream<RepositoryLoadEvent<Output>, Swift.Error>
    where Element == RepositoryLoadEvent<Input>, Failure == Swift.Error {
        AsyncThrowingStream<RepositoryLoadEvent<Output>, Swift.Error> { continuation in
            let task = Task {
                do {
                    for try await event in self {
                        switch event {
                        case .cached(let value):
                            continuation.yield(.cached(transform(value)))
                        case .refreshing:
                            continuation.yield(.refreshing)
                        case .fresh(let value):
                            continuation.yield(.fresh(transform(value)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
