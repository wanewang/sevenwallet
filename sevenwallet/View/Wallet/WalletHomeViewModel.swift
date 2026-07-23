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
    private var loadsSelectedPortfolio = false
    private var didLoadSelection = false
    private var refreshCoordinator = PullRefreshCoordinator()
    private var requestGeneration = 0

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
            selectedWallet = wallet
            walletCard = WalletCardViewModel(
                wallet: wallet,
                tokens: []
            )
        } else {
            selectedWallet = nil
            walletCard = nil
        }
    }

    func toggleTheme() {
        isThemeLight.toggle()
    }

    func loadTokens() async {
        await consume(policy: .ifExpired)
    }

    func load(wallet: SavedWallet?) async {
        let addressChanged = selectedWallet?.address != wallet?.address
        selectedWallet = wallet
        loadsSelectedPortfolio = true

        if addressChanged {
            tokens = []
        }
        rebuildWalletCard()

        guard addressChanged || !didLoadSelection else { return }
        didLoadSelection = true
        await consume(policy: .ifExpired)
    }

    func refreshTokens() async {
        await consume(policy: refreshCoordinator.recordPull(at: dateProvider.now()))
    }

    func retryTokens() async {
        await consume(policy: .ifExpired)
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
            tokenAddress: nil,
            symbol: symbol,
            name: name,
            decimals: 18,
            rawBalance: "0",
            balance: Decimal(string: balance)!,
            isNative: true,
            price: nil,
            logoURL: nil,
            coinKey: "\(coinKey)-\(copy)",
            priceUSD: Decimal(string: price)
        )
    }

    private func consume(policy: RefreshPolicy) async {
        requestGeneration += 1
        let generation = requestGeneration
        tokenErrorMessage = nil
        defer {
            if generation == requestGeneration {
                isLoadingTokens = false
            }
        }

        do {
            let stream: AsyncThrowingStream<
                RepositoryLoadEvent<[WalletToken]>,
                Swift.Error
            >
            if loadsSelectedPortfolio, let selectedWallet {
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
        walletCard = selectedWallet.map {
            WalletCardViewModel(wallet: $0, tokens: tokens)
        }
    }
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
