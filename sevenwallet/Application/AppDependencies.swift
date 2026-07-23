import Foundation
import SwiftData

@MainActor
enum AppDependencies {
    static func makeHomeViewModel(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        inMemoryStore: Bool = false
    ) -> WalletHomeViewModel {
        if arguments.contains("UI_TEST_FIXTURE") {
            return fixtureHome(arguments: arguments)
        }

        do {
            let configuration = try AppConfiguration(
                environment: environment,
                infoDictionary: infoDictionary
            )
            let schema = Schema(WalletCacheSchema.models)
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemoryStore
            )
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            let store = WalletStore(modelContainer: container)
            let client = APIClient(
                baseURL: configuration.baseURL,
                session: .shared
            )
            let remote = TokenRemoteDataSource(client: client)
            let repository = TokenRepository(remote: remote, store: store)
            return WalletHomeViewModel(tokenRepository: repository)
        } catch let error as AppConfiguration.Error {
            return WalletHomeViewModel(
                tokenRepository: FailingTokenRepository(
                    message: error.localizedDescription
                )
            )
        } catch {
            return WalletHomeViewModel(
                tokenRepository: FailingTokenRepository(
                    message: "Unable to load wallet data."
                )
            )
        }
    }

    private static func fixtureHome(arguments: [String]) -> WalletHomeViewModel {
        let copies = arguments.contains("UI_TEST_LONG_TOKEN_LIST") ? 4 : 1
        let tokens = (0..<copies).flatMap(fixtureTokens(copy:))
        let repository: any TokenRepositoryProtocol

        if arguments.contains("UI_TEST_TOKEN_ERROR") {
            repository = FailingTokenRepository(message: "Unable to load tokens.")
        } else {
            repository = FixtureTokenRepository(
                tokens: tokens,
                isDelayed: arguments.contains("UI_TEST_DELAYED_TOKENS"),
                holdsLoading: arguments.contains("UI_TEST_HOLD_TOKEN_LOADING")
            )
        }

        let hasWallet = arguments.contains("UI_TEST_POPULATED_WALLET")
        return WalletHomeViewModel(
            tokenRepository: repository,
            walletName: hasWallet ? "Main Wallet" : nil,
            walletAddress: hasWallet
                ? "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
                : nil
        )
    }

    private static func fixtureTokens(copy: Int) -> [WalletToken] {
        [
            fixtureToken(
                symbol: "ETH",
                name: "Ether",
                balance: "0",
                price: "1926.42",
                coinKey: "ethereum-\(copy)"
            ),
            fixtureToken(
                symbol: "BTC",
                name: "Bitcoin",
                balance: "0.0934",
                price: "104022.48",
                coinKey: "bitcoin-\(copy)"
            ),
            fixtureToken(
                symbol: "SOL",
                name: "Solana",
                balance: "18.42",
                price: "142.54",
                coinKey: "solana-\(copy)"
            ),
            fixtureToken(
                symbol: "USDC",
                name: "USD Coin",
                balance: "1500",
                price: "1",
                coinKey: "usd-coin-\(copy)"
            )
        ]
    }

    private static func fixtureToken(
        symbol: String,
        name: String,
        balance: String,
        price: String,
        coinKey: String
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
            coinKey: coinKey,
            priceUSD: Decimal(string: price)
        )
    }
}

@MainActor
private final class FixtureTokenRepository: TokenRepositoryProtocol {
    private let tokens: [WalletToken]
    private let isDelayed: Bool
    private let holdsLoading: Bool

    init(tokens: [WalletToken], isDelayed: Bool, holdsLoading: Bool) {
        self.tokens = tokens
        self.isDelayed = isDelayed
        self.holdsLoading = holdsLoading
    }

    func nativeTokens(
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<[WalletToken]>, Swift.Error> {
        AsyncThrowingStream { continuation in
            if holdsLoading {
                continuation.yield(.refreshing)
                return
            }

            guard isDelayed else {
                continuation.yield(.fresh(tokens))
                continuation.finish()
                return
            }

            continuation.yield(.refreshing)
            let task = Task { @MainActor [tokens] in
                do {
                    try await Task.sleep(for: .milliseconds(750))
                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(.fresh(tokens))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func portfolio(
        address: EVMAddress,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<TokenPortfolio>, Swift.Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@MainActor
private final class FailingTokenRepository: TokenRepositoryProtocol {
    private let error: AppDependencyFailure

    init(message: String) {
        error = AppDependencyFailure(message: message)
    }

    func nativeTokens(
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<[WalletToken]>, Swift.Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.refreshing)
            continuation.finish(throwing: error)
        }
    }

    func portfolio(
        address: EVMAddress,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<TokenPortfolio>, Swift.Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

private struct AppDependencyFailure: Swift.Error, LocalizedError, Sendable {
    let message: String

    nonisolated var errorDescription: String? { message }
}
