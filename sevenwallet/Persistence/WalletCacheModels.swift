import Foundation
import SwiftData

@Model
final class NativeTokensCacheRecord {
    @Attribute(.unique) var key = "native"
    var payload: Data
    var fetchedAt: Date

    init(payload: Data, fetchedAt: Date) {
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

@Model
final class PortfolioCacheRecord {
    @Attribute(.unique) var address: String
    var payload: Data
    var fetchedAt: Date

    init(address: String, payload: Data, fetchedAt: Date) {
        self.address = address
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

@Model
final class TransactionPageCacheRecord {
    @Attribute(.unique) var key: String
    var address: String
    var limit: Int
    var pageKey: String?
    var payload: Data
    var fetchedAt: Date

    init(key: String, address: String, limit: Int, pageKey: String?, payload: Data, fetchedAt: Date) {
        self.key = key
        self.address = address
        self.limit = limit
        self.pageKey = pageKey
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

enum WalletCacheSchema {
    static let models: [any PersistentModel.Type] = [
        NativeTokensCacheRecord.self,
        PortfolioCacheRecord.self,
        TransactionPageCacheRecord.self,
        SavedWalletRecord.self,
        WalletSelectionRecord.self
    ]
}
