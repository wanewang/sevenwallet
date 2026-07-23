import Foundation
import SwiftData

@MainActor
struct WalletAppState {
    let session: WalletSession
    let homeViewModel: WalletHomeViewModel
}

@MainActor
enum AppDependencies {
    static func makeAppState(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        inMemoryStore: Bool = false
    ) -> WalletAppState {
        let schema = Schema(WalletCacheSchema.models)
        let container: ModelContainer
        let usesFixture = arguments.contains("UI_TEST_FIXTURE")
        let persistsFixtureWallets = usesFixture &&
            arguments.contains("UI_TEST_PERSIST_SAVED_WALLETS")

        do {
            let modelConfiguration = persistsFixtureWallets
                ? ModelConfiguration("UITestWallets", schema: schema)
                : ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: usesFixture || inMemoryStore
                )
            container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            if persistsFixtureWallets {
                try preparePersistentFixtureStore(
                    container: container,
                    arguments: arguments
                )
            }
        } catch {
            return unavailableState(message: "Unable to load wallet data.")
        }

        let cacheStore = WalletStore(modelContainer: container)

        if usesFixture {
            return fixtureState(
                arguments: arguments,
                container: persistsFixtureWallets ? container : nil,
                cachePurger: cacheStore
            )
        }

        let savedWalletStore = SavedWalletStore(modelContainer: container)
        let repository: any TokenRepositoryProtocol
        let portfolioLoadController: any PortfolioLoadControlling

        do {
            let configuration = try AppConfiguration(
                environment: environment,
                infoDictionary: infoDictionary
            )
            let client = APIClient(
                baseURL: configuration.baseURL,
                session: .shared
            )
            let remote = TokenRemoteDataSource(client: client)
            let tokenRepository = TokenRepository(
                remote: remote,
                store: cacheStore
            )
            repository = tokenRepository
            portfolioLoadController = tokenRepository
        } catch let error as AppConfiguration.Error {
            repository = FailingTokenRepository(
                message: error.localizedDescription
            )
            portfolioLoadController = NoopPortfolioLoadController()
        } catch {
            repository = FailingTokenRepository(
                message: "Unable to load wallet data."
            )
            portfolioLoadController = NoopPortfolioLoadController()
        }

        return WalletAppState(
            session: WalletSession(
                store: savedWalletStore,
                cachePurger: cacheStore,
                portfolioLoadController: portfolioLoadController
            ),
            homeViewModel: WalletHomeViewModel(tokenRepository: repository)
        )
    }

    private static func fixtureState(
        arguments: [String],
        container: ModelContainer?,
        cachePurger: any AddressCachePurging
    ) -> WalletAppState {
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

        let savedWalletStore: any SavedWalletStoreProtocol
        if let container {
            savedWalletStore = SavedWalletStore(modelContainer: container)
        } else {
            let wallet = arguments.contains("UI_TEST_POPULATED_WALLET")
                ? SavedWallet(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    name: "Main Wallet",
                    address: try! EVMAddress(
                        "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
                    ),
                    cardColor: .blue,
                    createdAt: Date(timeIntervalSince1970: 0)
                )
                : nil
            savedWalletStore = FixtureSavedWalletStore(
                snapshot: SavedWalletSnapshot(
                    wallets: wallet.map { [$0] } ?? [],
                    selectedWalletID: wallet?.id
                )
            )
        }
        let session = WalletSession(
            store: savedWalletStore,
            cachePurger: cachePurger
        )
        return WalletAppState(
            session: session,
            homeViewModel: WalletHomeViewModel(tokenRepository: repository)
        )
    }

    private static func preparePersistentFixtureStore(
        container: ModelContainer,
        arguments: [String]
    ) throws {
        let context = ModelContext(container)

        if arguments.contains("UI_TEST_CLEAR_SAVED_WALLETS") {
            try context.fetch(FetchDescriptor<SavedWalletRecord>())
                .forEach(context.delete)
            try context.fetch(FetchDescriptor<WalletSelectionRecord>())
                .forEach(context.delete)
            try context.save()
        }

        guard arguments.contains("UI_TEST_SEED_SAVED_WALLET") else { return }
        var walletDescriptor = FetchDescriptor<SavedWalletRecord>()
        walletDescriptor.fetchLimit = 1
        guard try context.fetch(walletDescriptor).isEmpty else { return }

        try context.fetch(FetchDescriptor<WalletSelectionRecord>())
            .forEach(context.delete)
        let wallet = SavedWallet(
            name: "Main Wallet",
            address: try EVMAddress(
                "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
            ),
            cardColor: .blue
        )
        context.insert(SavedWalletRecord(wallet: wallet))
        context.insert(WalletSelectionRecord(walletID: wallet.id))
        try context.save()
    }

    private static func unavailableState(message: String) -> WalletAppState {
        let error = AppDependencyFailure(message: message)
        return WalletAppState(
            session: WalletSession(
                store: FailingSavedWalletStore(error: error),
                cachePurger: FailingAddressCachePurger(error: error)
            ),
            homeViewModel: WalletHomeViewModel(
                tokenRepository: FailingTokenRepository(message: message)
            )
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
        AsyncThrowingStream { continuation in
            if holdsLoading {
                continuation.yield(.refreshing)
                return
            }

            let portfolio = TokenPortfolio(
                address: address,
                fetchedAt: nil,
                network: "ethereum",
                tokens: tokens
            )
            guard isDelayed else {
                continuation.yield(.fresh(portfolio))
                continuation.finish()
                return
            }

            continuation.yield(.refreshing)
            let task = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(750))
                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(.fresh(portfolio))
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
            continuation.yield(.refreshing)
            continuation.finish(throwing: error)
        }
    }
}

private actor FixtureSavedWalletStore: SavedWalletStoreProtocol {
    private var snapshot: SavedWalletSnapshot

    init(snapshot: SavedWalletSnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot() -> SavedWalletSnapshot {
        snapshot
    }

    func addAndSelect(_ wallet: SavedWallet) -> SavedWalletSnapshot {
        snapshot = SavedWalletSnapshot(
            wallets: snapshot.wallets + [wallet],
            selectedWalletID: wallet.id
        )
        return snapshot
    }

    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) throws -> SavedWalletSnapshot {
        guard snapshot.wallets.contains(where: { $0.id == id }) else {
            throw SavedWalletStoreError.walletNotFound
        }
        snapshot = SavedWalletSnapshot(
            wallets: snapshot.wallets.map { wallet in
                guard wallet.id == id else { return wallet }
                return SavedWallet(
                    id: wallet.id,
                    name: name,
                    address: wallet.address,
                    cardColor: cardColor,
                    createdAt: wallet.createdAt
                )
            },
            selectedWalletID: snapshot.selectedWalletID
        )
        return snapshot
    }

    func delete(id: UUID) throws -> SavedWalletSnapshot {
        guard snapshot.wallets.contains(where: { $0.id == id }) else {
            throw SavedWalletStoreError.walletNotFound
        }
        let wallets = snapshot.wallets.filter { $0.id != id }
        let selection = snapshot.selectedWalletID == id
            ? wallets.first?.id
            : snapshot.selectedWalletID
        snapshot = SavedWalletSnapshot(
            wallets: wallets,
            selectedWalletID: selection
        )
        return snapshot
    }
}

private actor FailingSavedWalletStore: SavedWalletStoreProtocol {
    let error: AppDependencyFailure

    init(error: AppDependencyFailure) {
        self.error = error
    }

    func loadSnapshot() throws -> SavedWalletSnapshot { throw error }
    func addAndSelect(_ wallet: SavedWallet) throws -> SavedWalletSnapshot { throw error }
    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) throws -> SavedWalletSnapshot { throw error }
    func delete(id: UUID) throws -> SavedWalletSnapshot { throw error }
}

private actor FailingAddressCachePurger: AddressCachePurging {
    let error: AppDependencyFailure

    init(error: AppDependencyFailure) {
        self.error = error
    }

    func purgeAddressData(address: EVMAddress) throws {
        throw error
    }
}

private struct AppDependencyFailure: Swift.Error, LocalizedError, Sendable {
    let message: String

    nonisolated var errorDescription: String? { message }
}
