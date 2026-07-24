import Foundation
import SwiftData
import Testing
@testable import sevenwallet

@MainActor
struct WalletStoreTests {
    @Test func purgeDeletesOnlyMatchingAddressData() async throws {
        let store = try makeStore()
        let deletedAddress = try testAddress()
        let keptAddress = try EVMAddress("0x1234567890123456789012345678901234567890")
        let deletedPortfolio = TokenPortfolio(
            address: deletedAddress,
            fetchedAt: nil,
            network: "ethereum",
            tokens: [makeToken(balance: "1")]
        )
        let keptPortfolio = TokenPortfolio(
            address: keptAddress,
            fetchedAt: nil,
            network: "ethereum",
            tokens: [makeToken(balance: "2")]
        )
        try await store.saveNativeTokens([makeToken()], fetchedAt: .distantPast)
        try await store.savePortfolio(deletedPortfolio, fetchedAt: .distantPast)
        try await store.savePortfolio(keptPortfolio, fetchedAt: .distantPast)
        try await store.saveTransactionPage(
            TransactionPage(address: deletedAddress, nextPageKey: nil, transfers: []),
            limit: 25,
            pageKey: nil,
            fetchedAt: .distantPast
        )

        try await store.purgeAddressData(address: deletedAddress)

        #expect(try await store.loadPortfolio(address: deletedAddress) == nil)
        #expect(try await store.loadTransactionPage(
            address: deletedAddress,
            limit: 25,
            pageKey: nil
        ) == nil)
        #expect(try await store.loadPortfolio(address: keptAddress)?.value == keptPortfolio)
        #expect(try await store.loadNativeTokens() != nil)
    }

    @Test func nativeSnapshotReplacesAtomically() async throws {
        let store = try makeStore()
        let first = [makeToken(price: "1926.42")]
        let second = [makeToken(price: "2000.00")]

        try await store.saveNativeTokens(first, fetchedAt: Date(timeIntervalSince1970: 100))
        try await store.saveNativeTokens(second, fetchedAt: Date(timeIntervalSince1970: 200))

        let cached = try await store.loadNativeTokens()

        #expect(cached?.value == second)
        #expect(cached?.fetchedAt == Date(timeIntervalSince1970: 200))
    }

    @Test func nativeSnapshotPreservesOrderAndUsesZeroBalances() async throws {
        let store = try makeStore()
        let tokens = [
            makeToken(symbol: "USDC", tokenAddress: "0xABC", rawBalance: "15", balance: "15", price: "1"),
            makeToken(symbol: "ETH", rawBalance: "2", balance: "2", price: "2000")
        ]

        try await store.saveNativeTokens(tokens, fetchedAt: .distantPast)

        let cached = try #require(try await store.loadNativeTokens())

        #expect(cached.value.map(\.symbol) == ["USDC", "ETH"])
        #expect(cached.value.allSatisfy { $0.rawBalance == "0" && $0.balance == 0 })
    }

    @Test func sharedMetadataComposesWalletIsolatedBalances() async throws {
        let container = try makeContainer()
        let store = WalletStore(modelContainer: container)
        let firstAddress = try testAddress()
        let secondAddress = try EVMAddress("0x1234567890123456789012345678901234567890")
        let first = TokenPortfolio(
            address: firstAddress,
            fetchedAt: .distantPast,
            network: "ethereum",
            tokens: [makeToken(symbol: "USDC", tokenAddress: "0xABC", balance: "10", price: "1")]
        )
        let second = TokenPortfolio(
            address: secondAddress,
            fetchedAt: .distantPast,
            network: "ethereum",
            tokens: [makeToken(symbol: "USDC", tokenAddress: "0xABC", balance: "25", price: "1")]
        )

        try await store.savePortfolio(first, fetchedAt: Date(timeIntervalSince1970: 100))
        try await store.savePortfolio(second, fetchedAt: Date(timeIntervalSince1970: 200))

        #expect(try await store.loadPortfolio(address: firstAddress)?.value.tokens.first?.balance == 10)
        #expect(try await store.loadPortfolio(address: secondAddress)?.value.tokens.first?.balance == 25)

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<TokenCacheRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TokenBalanceCacheRecord>()).count == 2)
    }

    @Test func transactionKeyIncludesLimitAndCursor() async throws {
        let store = try makeStore()
        let address = try testAddress()
        let page = TransactionPage(address: address, nextPageKey: "next", transfers: [])

        try await store.saveTransactionPage(page, limit: 25, pageKey: nil, fetchedAt: .distantPast)

        #expect(try await store.loadTransactionPage(address: address, limit: 25, pageKey: nil)?.value == page)
        #expect(try await store.loadTransactionPage(address: address, limit: 100, pageKey: nil) == nil)
        #expect(try await store.loadTransactionPage(address: address, limit: 25, pageKey: "next") == nil)
    }

    @Test func emptyCursorDoesNotShareFirstPageCacheKey() async throws {
        let store = try makeStore()
        let address = try testAddress()
        let page = TransactionPage(address: address, nextPageKey: "next", transfers: [])

        try await store.saveTransactionPage(page, limit: 25, pageKey: nil, fetchedAt: .distantPast)

        #expect(try await store.loadTransactionPage(address: address, limit: 25, pageKey: "") == nil)
    }

    @Test func portfolioReplacementRemovesStaleBalancesAndPreservesOtherWallet() async throws {
        let store = try makeStore()
        let firstAddress = try testAddress()
        let secondAddress = try EVMAddress("0x1234567890123456789012345678901234567890")
        let usdc = "0x1111111111111111111111111111111111111111"
        let first = TokenPortfolio(
            address: firstAddress,
            fetchedAt: nil,
            network: "ethereum",
            tokens: [
                makeToken(symbol: "USDC", tokenAddress: usdc, balance: "1", price: "1"),
                makeToken(symbol: "ETH", balance: "2", price: "2000")
            ]
        )
        let replacement = TokenPortfolio(
            address: firstAddress,
            fetchedAt: Date(timeIntervalSince1970: 20),
            network: "ethereum",
            tokens: [makeToken(symbol: "USDC", tokenAddress: usdc, balance: "4", price: "1")]
        )
        let second = TokenPortfolio(
            address: secondAddress,
            fetchedAt: nil,
            network: "ethereum",
            tokens: [makeToken(symbol: "USDC", tokenAddress: usdc, balance: "3", price: "1")]
        )

        try await store.savePortfolio(first, fetchedAt: Date(timeIntervalSince1970: 100))
        try await store.savePortfolio(second, fetchedAt: Date(timeIntervalSince1970: 150))
        try await store.savePortfolio(replacement, fetchedAt: Date(timeIntervalSince1970: 200))

        #expect(try await store.loadPortfolio(address: firstAddress)?.value == replacement)
        #expect(try await store.loadPortfolio(address: firstAddress)?.fetchedAt == Date(timeIntervalSince1970: 200))
        #expect(try await store.loadPortfolio(address: secondAddress)?.value == second)
        #expect(try await store.loadPortfolio(address: secondAddress)?.fetchedAt == Date(timeIntervalSince1970: 150))
    }

    @Test func legacyNativePayloadIsDiscardedAsCacheMiss() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(NativeTokensCacheRecord(payload: Data("not normalized cache data".utf8), fetchedAt: .distantPast))
        try context.save()
        let store = WalletStore(modelContainer: container)

        #expect(try await store.loadNativeTokens() == nil)

        let verificationContext = ModelContext(container)
        #expect(try verificationContext.fetch(FetchDescriptor<NativeTokensCacheRecord>()).isEmpty)
    }

    @Test func portfolioWithMissingMetadataIsDiscardedAsCacheMiss() async throws {
        let container = try makeContainer()
        let store = WalletStore(modelContainer: container)
        let address = try testAddress()
        let portfolio = TokenPortfolio(
            address: address,
            fetchedAt: nil,
            network: "ethereum",
            tokens: [makeToken(balance: "1")]
        )
        try await store.savePortfolio(portfolio, fetchedAt: .distantPast)

        let context = ModelContext(container)
        for record in try context.fetch(FetchDescriptor<TokenCacheRecord>()) {
            context.delete(record)
        }
        try context.save()

        let reloadedStore = WalletStore(modelContainer: container)
        #expect(try await reloadedStore.loadPortfolio(address: address) == nil)

        let verificationContext = ModelContext(container)
        #expect(try verificationContext.fetch(FetchDescriptor<PortfolioCacheRecord>()).isEmpty)
        #expect(try verificationContext.fetch(FetchDescriptor<TokenBalanceCacheRecord>()).isEmpty)
    }

    private func makeStore() throws -> WalletStore {
        WalletStore(modelContainer: try makeContainer())
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema(WalletCacheSchema.models),
            configurations: configuration
        )
    }

    private func testAddress() throws -> EVMAddress {
        try EVMAddress("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
    }

    private func makeToken(
        symbol: String = "ETH",
        tokenAddress: String? = nil,
        rawBalance: String? = nil,
        balance: String = "0",
        price: String = "100"
    ) -> WalletToken {
        WalletToken(
            tokenAddress: tokenAddress,
            symbol: symbol,
            name: symbol,
            decimals: 18,
            rawBalance: rawBalance ?? balance,
            balance: Decimal(string: balance)!,
            isNative: tokenAddress == nil,
            price: TokenPrice(currency: "USD", value: Decimal(string: price), lastUpdatedAt: nil),
            logoURL: nil,
            change24hPercent: Decimal(string: "1.25"),
            coinKey: symbol.lowercased(),
            marketCapUSD: Decimal(string: "1000"),
            marketDataUpdatedAt: Date(timeIntervalSince1970: 10),
            priceUSD: Decimal(string: price)
        )
    }
}
