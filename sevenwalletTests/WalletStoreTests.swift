import Foundation
import SwiftData
import Testing
@testable import sevenwallet

@MainActor
struct WalletStoreTests {
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

    @Test func transactionKeyIncludesLimitAndCursor() async throws {
        let store = try makeStore()
        let address = try testAddress()
        let page = TransactionPage(address: address, nextPageKey: "next", transfers: [])

        try await store.saveTransactionPage(page, limit: 25, pageKey: nil, fetchedAt: .distantPast)

        #expect(try await store.loadTransactionPage(address: address, limit: 25, pageKey: nil)?.value == page)
        #expect(try await store.loadTransactionPage(address: address, limit: 100, pageKey: nil) == nil)
        #expect(try await store.loadTransactionPage(address: address, limit: 25, pageKey: "next") == nil)
    }

    @Test func portfolioSnapshotsRemainIsolatedByAddress() async throws {
        let store = try makeStore()
        let firstAddress = try testAddress()
        let secondAddress = try EVMAddress("0x1234567890123456789012345678901234567890")
        let first = TokenPortfolio(address: firstAddress, fetchedAt: nil, network: "ethereum", tokens: [makeToken(price: "100")])
        let replacement = TokenPortfolio(address: firstAddress, fetchedAt: nil, network: "ethereum", tokens: [makeToken(price: "200")])
        let second = TokenPortfolio(address: secondAddress, fetchedAt: nil, network: "ethereum", tokens: [makeToken(price: "300")])

        try await store.savePortfolio(first, fetchedAt: Date(timeIntervalSince1970: 100))
        try await store.savePortfolio(second, fetchedAt: Date(timeIntervalSince1970: 150))
        try await store.savePortfolio(replacement, fetchedAt: Date(timeIntervalSince1970: 200))

        #expect(try await store.loadPortfolio(address: firstAddress)?.value == replacement)
        #expect(try await store.loadPortfolio(address: firstAddress)?.fetchedAt == Date(timeIntervalSince1970: 200))
        #expect(try await store.loadPortfolio(address: secondAddress)?.value == second)
        #expect(try await store.loadPortfolio(address: secondAddress)?.fetchedAt == Date(timeIntervalSince1970: 150))
    }

    @Test func corruptPayloadThrows() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(NativeTokensCacheRecord(payload: Data("not JSON".utf8), fetchedAt: .distantPast))
        try context.save()
        let store = WalletStore(modelContainer: container)

        await #expect(throws: DecodingError.self) {
            try await store.loadNativeTokens()
        }
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

    private func makeToken(price: String) -> WalletToken {
        WalletToken(
            tokenAddress: nil,
            symbol: "ETH",
            name: "Ether",
            decimals: 18,
            rawBalance: "1000000000000000000",
            balance: 1,
            isNative: true,
            price: TokenPrice(currency: "USD", value: Decimal(string: price), lastUpdatedAt: nil),
            logoURL: nil,
            coinKey: "ethereum",
            priceUSD: Decimal(string: price)
        )
    }
}
