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

    private let tokenRepository: any TokenRepositoryProtocol
    private let dateProvider: DateProvider
    private var selectedWallet: SavedWallet?
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
            selectedWallet = nil
            compatibilityWallet = wallet
            walletCard = WalletCardViewModel(
                wallet: wallet,
                tokens: []
            )
        } else {
            selectedWallet = nil
            compatibilityWallet = nil
            walletCard = nil
        }
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
        let addressChanged = selectedWallet?.address != wallet?.address
        selectedWallet = wallet
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
            tokenAddress: copy == 0 ? nil : String(format: "0x%040llx", Int64(copy)),
            symbol: symbol,
            name: name,
            decimals: 18,
            rawBalance: "0",
            balance: Decimal(string: balance)!,
            isNative: true,
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
            let stream: AsyncThrowingStream<
                RepositoryLoadEvent<[WalletToken]>,
                Swift.Error
            >
            if let selectedWallet {
                stream = tokenRepository
                    .portfolio(address: selectedWallet.address, policy: policy)
                    .mapValues(\.tokens)
            } else {
                stream = tokenRepository.nativeTokens(policy: policy)
            }

            for try await event in stream {
                guard generation == requestGeneration else { return }
                switch event {
                case .cached(let value), .fresh(let value):
                    updateTokens(value)
                    isLoadingTokens = false
                case .refreshing:
                    isLoadingTokens = true
                }
            }
            guard generation == requestGeneration, !Task.isCancelled else {
                return
            }
            resourceState = .loaded
        } catch {
            guard generation == requestGeneration, !Task.isCancelled else { return }
            tokenErrorMessage = error.localizedDescription
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
