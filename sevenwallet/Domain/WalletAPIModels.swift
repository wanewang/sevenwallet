import Foundation

struct TokenPrice: Codable, Equatable, Sendable {
    let currency: String?
    let value: Decimal?
    let lastUpdatedAt: Date?
}

struct WalletToken: Codable, Equatable, Identifiable, Sendable {
    let tokenAddress: String?
    let symbol: String
    let name: String
    let decimals: Int
    let rawBalance: String
    let balance: Decimal
    let isNative: Bool
    let price: TokenPrice?
    let logoURL: URL?
    let coinKey: String
    let priceUSD: Decimal?

    var id: String { "\(coinKey):\(tokenAddress?.lowercased() ?? "native")" }
}

struct TokenPortfolio: Codable, Equatable, Sendable {
    let address: EVMAddress
    let fetchedAt: Date?
    let network: String?
    let tokens: [WalletToken]
}

struct WalletTransfer: Codable, Equatable, Sendable {
    let asset: String?
    let blockNumber: String?
    let category: String?
    let from: String?
    let hash: String?
    let to: String?
    let value: String?
}

struct TransactionPage: Codable, Equatable, Sendable {
    let address: EVMAddress
    let nextPageKey: String?
    let transfers: [WalletTransfer]
}
