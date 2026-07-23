import Foundation
import SwiftData

struct CachedResource<Value: Sendable>: Sendable {
    let value: Value
    let fetchedAt: Date
}

protocol WalletStoreProtocol: Sendable {
    func loadNativeTokens() async throws -> CachedResource<[WalletToken]>?
    func saveNativeTokens(_ value: [WalletToken], fetchedAt: Date) async throws
    func loadPortfolio(address: EVMAddress) async throws -> CachedResource<TokenPortfolio>?
    func savePortfolio(_ value: TokenPortfolio, fetchedAt: Date) async throws
    func loadTransactionPage(address: EVMAddress, limit: Int, pageKey: String?) async throws -> CachedResource<TransactionPage>?
    func saveTransactionPage(_ value: TransactionPage, limit: Int, pageKey: String?, fetchedAt: Date) async throws
}

@ModelActor
actor WalletStore: WalletStoreProtocol {
    func loadNativeTokens() throws -> CachedResource<[WalletToken]>? {
        var descriptor = FetchDescriptor<NativeTokensCacheRecord>(predicate: #Predicate { $0.key == "native" })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        return CachedResource(
            value: try JSONDecoder().decode([WalletToken].self, from: record.payload),
            fetchedAt: record.fetchedAt
        )
    }

    func saveNativeTokens(_ value: [WalletToken], fetchedAt: Date) throws {
        let payload = try JSONEncoder().encode(value)
        var descriptor = FetchDescriptor<NativeTokensCacheRecord>(predicate: #Predicate { $0.key == "native" })
        descriptor.fetchLimit = 1

        do {
            if let record = try modelContext.fetch(descriptor).first {
                record.payload = payload
                record.fetchedAt = fetchedAt
            } else {
                modelContext.insert(NativeTokensCacheRecord(payload: payload, fetchedAt: fetchedAt))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func loadPortfolio(address: EVMAddress) async throws -> CachedResource<TokenPortfolio>? {
        let normalizedAddress = address.rawValue
        var descriptor = FetchDescriptor<PortfolioCacheRecord>(predicate: #Predicate { $0.address == normalizedAddress })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        return CachedResource(
            value: try JSONDecoder().decode(TokenPortfolio.self, from: record.payload),
            fetchedAt: record.fetchedAt
        )
    }

    func savePortfolio(_ value: TokenPortfolio, fetchedAt: Date) async throws {
        let payload = try JSONEncoder().encode(value)
        let normalizedAddress = value.address.rawValue
        var descriptor = FetchDescriptor<PortfolioCacheRecord>(predicate: #Predicate { $0.address == normalizedAddress })
        descriptor.fetchLimit = 1

        do {
            if let record = try modelContext.fetch(descriptor).first {
                record.payload = payload
                record.fetchedAt = fetchedAt
            } else {
                modelContext.insert(PortfolioCacheRecord(address: normalizedAddress, payload: payload, fetchedAt: fetchedAt))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func loadTransactionPage(address: EVMAddress, limit: Int, pageKey: String?) async throws -> CachedResource<TransactionPage>? {
        let key = transactionKey(address: address, limit: limit, pageKey: pageKey)
        var descriptor = FetchDescriptor<TransactionPageCacheRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        return CachedResource(
            value: try JSONDecoder().decode(TransactionPage.self, from: record.payload),
            fetchedAt: record.fetchedAt
        )
    }

    func saveTransactionPage(_ value: TransactionPage, limit: Int, pageKey: String?, fetchedAt: Date) async throws {
        let payload = try JSONEncoder().encode(value)
        let address = value.address
        let key = transactionKey(address: address, limit: limit, pageKey: pageKey)
        var descriptor = FetchDescriptor<TransactionPageCacheRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1

        do {
            if let record = try modelContext.fetch(descriptor).first {
                record.payload = payload
                record.fetchedAt = fetchedAt
            } else {
                modelContext.insert(
                    TransactionPageCacheRecord(
                        key: key,
                        address: address.rawValue,
                        limit: limit,
                        pageKey: pageKey,
                        payload: payload,
                        fetchedAt: fetchedAt
                    )
                )
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func transactionKey(address: EVMAddress, limit: Int, pageKey: String?) -> String {
        guard let pageKey else {
            return "\(address.rawValue)|\(limit)|none"
        }
        return "\(address.rawValue)|\(limit)|some:\(pageKey.utf8.count):\(pageKey)"
    }
}
