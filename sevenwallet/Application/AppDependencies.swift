import Foundation
import SwiftData

@MainActor
struct WalletAppState {
    let session: WalletSession
    let homeViewModel: WalletHomeViewModel
    let tokenRepository: any TokenRepositoryProtocol
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
            homeViewModel: WalletHomeViewModel(tokenRepository: repository),
            tokenRepository: repository
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
        let fixtureCredentialReference = WalletCredentialReference(
            rawValue: UUID(
                uuidString: "00000000-0000-0000-0000-00000000F001"
            )!
        )
        let usesImportedWallet = arguments.contains("UI_TEST_IMPORTED_WALLET")
        let usesCredentialVectorWallet = usesImportedWallet || arguments.contains(
            "UI_TEST_WATCH_ONLY_UPGRADE"
        )
        let credentialVault = FixtureWalletCredentialVault(
            protectionAvailable: !arguments.contains(
                "UI_TEST_CREDENTIAL_PROTECTION_UNAVAILABLE"
            ),
            cancelsAuthentication: arguments.contains(
                "UI_TEST_CREDENTIAL_AUTH_CANCELLED"
            ),
            items: usesImportedWallet ? [
                fixtureCredentialReference: WalletCredentialPayload(
                    kind: .privateKey,
                    bytes: Data(repeating: 1, count: 32)
                )
            ] : [:]
        )

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
            let mainWallet = SavedWallet(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Main Wallet",
                address: try! EVMAddress(
                    usesCredentialVectorWallet
                        ? "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
                        : "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
                ),
                cardColor: .blue,
                createdAt: Date(timeIntervalSince1970: 0),
                credentialReference: usesImportedWallet
                    ? fixtureCredentialReference
                    : nil
            )
            let savingsWallet = SavedWallet(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Savings Wallet",
                address: try! EVMAddress(
                    "0x0000000000000000000000000000000000000002"
                ),
                cardColor: .purple,
                createdAt: Date(timeIntervalSince1970: 1)
            )
            let wallets: [SavedWallet]
            if arguments.contains("UI_TEST_MULTIPLE_WALLETS") {
                wallets = [mainWallet, savingsWallet]
            } else if arguments.contains("UI_TEST_POPULATED_WALLET") {
                wallets = [mainWallet]
            } else {
                wallets = []
            }
            savedWalletStore = FixtureSavedWalletStore(
                snapshot: SavedWalletSnapshot(
                    wallets: wallets,
                    selectedWalletID: wallets.first?.id
                )
            )
        }
        let session = WalletSession(
            store: savedWalletStore,
            cachePurger: cachePurger,
            credentialVault: credentialVault
        )
        return WalletAppState(
            session: session,
            homeViewModel: WalletHomeViewModel(tokenRepository: repository),
            tokenRepository: repository
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
        let repository = FailingTokenRepository(message: message)
        return WalletAppState(
            session: WalletSession(
                store: FailingSavedWalletStore(error: error),
                cachePurger: FailingAddressCachePurger(error: error)
            ),
            homeViewModel: WalletHomeViewModel(
                tokenRepository: repository
            ),
            tokenRepository: repository
        )
    }

    private static func fixtureTokens(copy: Int) -> [WalletToken] {
        [
            fixtureToken(
                symbol: "ETH",
                name: "Ether",
                balance: "0",
                price: "1926.42",
                coinKey: "ethereum-\(copy)",
                copy: copy
            ),
            fixtureToken(
                symbol: "BTC",
                name: "Bitcoin",
                balance: "0.0934",
                price: "104022.48",
                coinKey: "bitcoin-\(copy)",
                copy: copy
            ),
            fixtureToken(
                symbol: "SOL",
                name: "Solana",
                balance: "18.42",
                price: "142.54",
                coinKey: "solana-\(copy)",
                copy: copy
            ),
            fixtureToken(
                symbol: "USDC",
                name: "USD Coin",
                balance: "1500",
                price: "1",
                coinKey: "usd-coin-\(copy)",
                copy: copy
            )
        ]
    }

    private static func fixtureToken(
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
            coinKey: coinKey,
            marketCapUSD: nil,
            marketDataUpdatedAt: nil,
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

    func tokenMarkets(address: EVMAddress) async throws -> TokenMarketPortfolio {
        TokenMarketPortfolio(
            wallet: address,
            network: "ethereum",
            portfolioFetchedAt: Date(timeIntervalSince1970: 0),
            tokens: []
        )
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

    func tokenMarkets(address: EVMAddress) async throws -> TokenMarketPortfolio {
        throw error
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

    func select(id: UUID) throws -> SavedWalletSnapshot {
        snapshot = try snapshot.selecting(id: id)
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
                    createdAt: wallet.createdAt,
                    credentialReference: wallet.credentialReference
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

    func attachCredentialReference(
        id: UUID,
        reference: WalletCredentialReference
    ) throws -> SavedWalletSnapshot {
        guard let wallet = snapshot.wallets.first(where: { $0.id == id }) else {
            throw SavedWalletStoreError.walletNotFound
        }
        guard wallet.credentialReference == nil else {
            throw SavedWalletStoreError.credentialReferenceAlreadyAttached
        }
        snapshot = replacing(wallet, credentialReference: reference)
        return snapshot
    }

    func detachCredentialReference(
        id: UUID
    ) throws -> SavedWalletSnapshot {
        guard let wallet = snapshot.wallets.first(where: { $0.id == id }) else {
            throw SavedWalletStoreError.walletNotFound
        }
        snapshot = replacing(wallet, credentialReference: nil)
        return snapshot
    }

    func rollbackCredentialBackedAdd(
        id: UUID
    ) throws -> SavedWalletSnapshot {
        guard let wallet = snapshot.wallets.first(where: { $0.id == id }) else {
            throw SavedWalletStoreError.walletNotFound
        }
        guard wallet.credentialReference != nil else {
            throw SavedWalletStoreError.credentialReferenceMissing
        }
        return try delete(id: id)
    }

    private func replacing(
        _ wallet: SavedWallet,
        credentialReference: WalletCredentialReference?
    ) -> SavedWalletSnapshot {
        SavedWalletSnapshot(
            wallets: snapshot.wallets.map {
                guard $0.id == wallet.id else { return $0 }
                return SavedWallet(
                    id: wallet.id,
                    name: wallet.name,
                    address: wallet.address,
                    cardColor: wallet.cardColor,
                    createdAt: wallet.createdAt,
                    credentialReference: credentialReference
                )
            },
            selectedWalletID: snapshot.selectedWalletID
        )
    }
}

private actor FixtureWalletCredentialVault: WalletCredentialVault {
    private let protectionAvailable: Bool
    private let cancelsAuthentication: Bool
    private var items: [WalletCredentialReference: WalletCredentialPayload]

    init(
        protectionAvailable: Bool,
        cancelsAuthentication: Bool,
        items: [WalletCredentialReference: WalletCredentialPayload]
    ) {
        self.protectionAvailable = protectionAvailable
        self.cancelsAuthentication = cancelsAuthentication
        self.items = items
    }

    func isProtectionAvailable() -> Bool {
        protectionAvailable
    }

    func presence(
        of reference: WalletCredentialReference
    ) -> WalletCredentialPresence {
        items[reference] == nil ? .missing : .present
    }

    func store(
        _ payload: WalletCredentialPayload,
        for reference: WalletCredentialReference
    ) throws {
        guard protectionAvailable else {
            throw WalletCredentialError.protectionUnavailable
        }
        guard !cancelsAuthentication else {
            throw WalletCredentialError.authenticationCancelled
        }
        items[reference] = payload
    }

    func read(
        for reference: WalletCredentialReference
    ) throws -> WalletCredentialPayload {
        guard let payload = items[reference] else {
            throw WalletCredentialError.credentialNotFound
        }
        return payload
    }

    func delete(for reference: WalletCredentialReference) throws {
        guard protectionAvailable else {
            throw WalletCredentialError.protectionUnavailable
        }
        guard !cancelsAuthentication else {
            throw WalletCredentialError.authenticationCancelled
        }
        guard items.removeValue(forKey: reference) != nil else {
            throw WalletCredentialError.credentialNotFound
        }
    }
}

private actor FailingSavedWalletStore: SavedWalletStoreProtocol {
    let error: AppDependencyFailure

    init(error: AppDependencyFailure) {
        self.error = error
    }

    func loadSnapshot() throws -> SavedWalletSnapshot { throw error }
    func addAndSelect(_ wallet: SavedWallet) throws -> SavedWalletSnapshot { throw error }
    func select(id: UUID) throws -> SavedWalletSnapshot { throw error }
    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) throws -> SavedWalletSnapshot { throw error }
    func delete(id: UUID) throws -> SavedWalletSnapshot { throw error }
    func attachCredentialReference(
        id: UUID,
        reference: WalletCredentialReference
    ) throws -> SavedWalletSnapshot { throw error }
    func detachCredentialReference(
        id: UUID
    ) throws -> SavedWalletSnapshot { throw error }
    func rollbackCredentialBackedAdd(
        id: UUID
    ) throws -> SavedWalletSnapshot { throw error }
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
