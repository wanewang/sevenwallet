import Foundation
import SwiftData

struct CachedResource<Value: Sendable>: Sendable {
    let value: Value
    let fetchedAt: Date
}

protocol AddressCachePurging: Sendable {
    func purgeAddressData(address: EVMAddress) async throws
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
actor WalletStore: WalletStoreProtocol, AddressCachePurging {
    func loadNativeTokens() throws -> CachedResource<[WalletToken]>? {
        var descriptor = FetchDescriptor<NativeTokensCacheRecord>(predicate: #Predicate { $0.key == "native" })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        guard let snapshot = decodeNativeSnapshot(record.payload),
              let metadata = try tokenMetadata(for: snapshot.tokenKeys) else {
            try invalidateNativeSnapshot(record)
            return nil
        }
        return CachedResource(
            value: snapshot.tokenKeys.compactMap { metadata[$0]?.makeWalletToken(rawBalance: "0", balance: 0) },
            fetchedAt: record.fetchedAt
        )
    }

    func saveNativeTokens(_ value: [WalletToken], fetchedAt: Date) throws {
        let payload = try JSONEncoder().encode(
            NativeTokenSnapshot(version: cachePayloadVersion, tokenKeys: value.map(\.key))
        )
        var descriptor = FetchDescriptor<NativeTokensCacheRecord>(predicate: #Predicate { $0.key == "native" })
        descriptor.fetchLimit = 1

        do {
            try upsertTokenMetadata(value)
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

    func loadPortfolio(address: EVMAddress) throws -> CachedResource<TokenPortfolio>? {
        let normalizedAddress = address.rawValue
        var descriptor = FetchDescriptor<PortfolioCacheRecord>(predicate: #Predicate { $0.address == normalizedAddress })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        guard let snapshot = decodePortfolioSnapshot(record.payload) else {
            try invalidatePortfolioSnapshot(record, address: normalizedAddress)
            return nil
        }

        let balances = try balanceRecords(for: normalizedAddress).sorted { $0.position < $1.position }
        let tokenKeys = balances.map(\.tokenKey)
        guard let metadata = try tokenMetadata(for: tokenKeys) else {
            try invalidatePortfolioSnapshot(record, address: normalizedAddress)
            return nil
        }
        let tokens = balances.compactMap { balance in
            metadata[balance.tokenKey]?.makeWalletToken(
                rawBalance: balance.rawBalance,
                balance: balance.balance
            )
        }
        return CachedResource(
            value: TokenPortfolio(
                address: address,
                fetchedAt: snapshot.fetchedAt,
                network: snapshot.network,
                tokens: tokens
            ),
            fetchedAt: record.fetchedAt
        )
    }

    func savePortfolio(_ value: TokenPortfolio, fetchedAt: Date) throws {
        let normalizedAddress = value.address.rawValue
        let payload = try JSONEncoder().encode(
            PortfolioSnapshot(
                version: cachePayloadVersion,
                fetchedAt: value.fetchedAt,
                network: value.network
            )
        )
        var descriptor = FetchDescriptor<PortfolioCacheRecord>(predicate: #Predicate { $0.address == normalizedAddress })
        descriptor.fetchLimit = 1

        do {
            try upsertTokenMetadata(value.tokens)
            try replaceBalances(value.tokens, walletAddress: normalizedAddress)
            if let record = try modelContext.fetch(descriptor).first {
                record.payload = payload
                record.fetchedAt = fetchedAt
            } else {
                modelContext.insert(
                    PortfolioCacheRecord(
                        address: normalizedAddress,
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

    func loadTransactionPage(address: EVMAddress, limit: Int, pageKey: String?) throws -> CachedResource<TransactionPage>? {
        let key = transactionKey(address: address, limit: limit, pageKey: pageKey)
        var descriptor = FetchDescriptor<TransactionPageCacheRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        return CachedResource(
            value: try JSONDecoder().decode(TransactionPage.self, from: record.payload),
            fetchedAt: record.fetchedAt
        )
    }

    func saveTransactionPage(_ value: TransactionPage, limit: Int, pageKey: String?, fetchedAt: Date) throws {
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

    func purgeAddressData(address: EVMAddress) throws {
        let normalizedAddress = address.rawValue
        let portfolios = try modelContext.fetch(
            FetchDescriptor<PortfolioCacheRecord>(
                predicate: #Predicate { $0.address == normalizedAddress }
            )
        )
        let pages = try modelContext.fetch(
            FetchDescriptor<TransactionPageCacheRecord>(
                predicate: #Predicate { $0.address == normalizedAddress }
            )
        )
        let balances = try balanceRecords(for: normalizedAddress)
        do {
            portfolios.forEach(modelContext.delete)
            pages.forEach(modelContext.delete)
            balances.forEach(modelContext.delete)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func decodeNativeSnapshot(_ payload: Data) -> NativeTokenSnapshot? {
        guard let snapshot = try? JSONDecoder().decode(NativeTokenSnapshot.self, from: payload),
              snapshot.version == cachePayloadVersion else {
            return nil
        }
        return snapshot
    }

    private func decodePortfolioSnapshot(_ payload: Data) -> PortfolioSnapshot? {
        guard let snapshot = try? JSONDecoder().decode(PortfolioSnapshot.self, from: payload),
              snapshot.version == cachePayloadVersion else {
            return nil
        }
        return snapshot
    }

    private func tokenMetadata(for tokenKeys: [String]) throws -> [String: CachedTokenMetadata]? {
        let requiredKeys = Set(tokenKeys)
        var result: [String: CachedTokenMetadata] = [:]
        for record in try modelContext.fetch(FetchDescriptor<TokenCacheRecord>()) where requiredKeys.contains(record.key) {
            guard let metadata = try? JSONDecoder().decode(CachedTokenMetadata.self, from: record.payload),
                  metadata.key == record.key else {
                return nil
            }
            result[record.key] = metadata
        }
        return result.keys.count == requiredKeys.count ? result : nil
    }

    private func upsertTokenMetadata(_ tokens: [WalletToken]) throws {
        var records: [String: TokenCacheRecord] = [:]
        for record in try modelContext.fetch(FetchDescriptor<TokenCacheRecord>()) {
            records[record.key] = record
        }
        for token in tokens {
            let payload = try JSONEncoder().encode(CachedTokenMetadata(token: token))
            if let record = records[token.key] {
                record.payload = payload
            } else {
                let record = TokenCacheRecord(key: token.key, payload: payload)
                modelContext.insert(record)
                records[token.key] = record
            }
        }
    }

    private func balanceRecords(for walletAddress: String) throws -> [TokenBalanceCacheRecord] {
        try modelContext.fetch(
            FetchDescriptor<TokenBalanceCacheRecord>(
                predicate: #Predicate { $0.walletAddress == walletAddress }
            )
        )
    }

    private func replaceBalances(_ tokens: [WalletToken], walletAddress: String) throws {
        var existing: [String: TokenBalanceCacheRecord] = [:]
        for record in try balanceRecords(for: walletAddress) {
            existing[record.tokenKey] = record
        }
        for (position, token) in tokens.enumerated() {
            if let record = existing.removeValue(forKey: token.key) {
                record.rawBalance = token.rawBalance
                record.balance = token.balance
                record.position = position
            } else {
                modelContext.insert(
                    TokenBalanceCacheRecord(
                        key: balanceKey(walletAddress: walletAddress, tokenKey: token.key),
                        walletAddress: walletAddress,
                        tokenKey: token.key,
                        rawBalance: token.rawBalance,
                        balance: token.balance,
                        position: position
                    )
                )
            }
        }
        existing.values.forEach(modelContext.delete)
    }

    private func invalidateNativeSnapshot(_ record: NativeTokensCacheRecord) throws {
        do {
            modelContext.delete(record)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func invalidatePortfolioSnapshot(_ record: PortfolioCacheRecord, address: String) throws {
        let balances = try balanceRecords(for: address)
        do {
            modelContext.delete(record)
            balances.forEach(modelContext.delete)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func balanceKey(walletAddress: String, tokenKey: String) -> String {
        "\(walletAddress)|\(tokenKey.utf8.count):\(tokenKey)"
    }

    private func transactionKey(address: EVMAddress, limit: Int, pageKey: String?) -> String {
        guard let pageKey else {
            return "\(address.rawValue)|\(limit)|none"
        }
        return "\(address.rawValue)|\(limit)|some:\(pageKey.utf8.count):\(pageKey)"
    }
}

private let cachePayloadVersion = 1

private struct NativeTokenSnapshot: Codable {
    let version: Int
    let tokenKeys: [String]
}

private struct PortfolioSnapshot: Codable {
    let version: Int
    let fetchedAt: Date?
    let network: String?
}

private struct CachedTokenMetadata: Codable {
    let tokenAddress: String?
    let symbol: String
    let name: String
    let decimals: Int
    let isNative: Bool
    let price: TokenPrice?
    let logoURL: URL?
    let change24hPercent: Decimal?
    let coinKey: String?
    let marketCapUSD: Decimal?
    let marketDataUpdatedAt: Date?
    let priceUSD: Decimal?

    init(token: WalletToken) {
        tokenAddress = token.tokenAddress
        symbol = token.symbol
        name = token.name
        decimals = token.decimals
        isNative = token.isNative
        price = token.price
        logoURL = token.logoURL
        change24hPercent = token.change24hPercent
        coinKey = token.coinKey
        marketCapUSD = token.marketCapUSD
        marketDataUpdatedAt = token.marketDataUpdatedAt
        priceUSD = token.priceUSD
    }

    var key: String { "\(symbol):\(tokenAddress?.lowercased() ?? "native")" }

    func makeWalletToken(rawBalance: String, balance: Decimal) -> WalletToken {
        WalletToken(
            tokenAddress: tokenAddress,
            symbol: symbol,
            name: name,
            decimals: decimals,
            rawBalance: rawBalance,
            balance: balance,
            isNative: isNative,
            price: price,
            logoURL: logoURL,
            change24hPercent: change24hPercent,
            coinKey: coinKey,
            marketCapUSD: marketCapUSD,
            marketDataUpdatedAt: marketDataUpdatedAt,
            priceUSD: priceUSD
        )
    }
}
