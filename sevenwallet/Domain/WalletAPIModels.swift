import Foundation

nonisolated struct TokenPrice: Codable, Equatable, Sendable {
    let currency: String?
    let value: Decimal?
    let lastUpdatedAt: Date?
}

nonisolated struct WalletToken: Codable, Equatable, Identifiable, Sendable {
    let tokenAddress: String?
    let symbol: String
    let name: String
    let decimals: Int
    let rawBalance: String
    let balance: Decimal
    let isNative: Bool
    let price: TokenPrice?
    let logoURL: URL?
    let change24hPercent: Decimal?
    let coinKey: String?
    let marketCapUSD: Decimal?
    let marketDataUpdatedAt: Date?
    let priceUSD: Decimal?

    var key: String { "\(symbol):\(tokenAddress?.lowercased() ?? "native")" }
    var id: String { key }
    var marketPriceUSD: Decimal? { priceUSD ?? price?.value }
}

nonisolated struct TokenPortfolio: Codable, Equatable, Sendable {
    let address: EVMAddress
    let fetchedAt: Date?
    let network: String?
    let tokens: [WalletToken]
}

nonisolated struct CoinGeckoMarket: Equatable, Sendable {
    let id: String
    let priceUSD: Decimal?
    let change24hPercent: Decimal?
}

nonisolated struct CoinMarketCapMarket: Equatable, Sendable {
    let id: Int
    let priceUSD: Decimal?
    let change24hPercent: Decimal?
}

nonisolated struct TokenMarket: Equatable, Identifiable, Sendable {
    let tokenAddress: String?
    let symbol: String
    let name: String
    let decimals: Int
    let balance: Decimal
    let coinGecko: CoinGeckoMarket?
    let coinMarketCap: CoinMarketCapMarket?

    var key: String { "\(symbol):\(tokenAddress?.lowercased() ?? "native")" }
    var id: String { key }
}

nonisolated struct TokenMarketPortfolio: Equatable, Sendable {
    let wallet: EVMAddress
    let network: String
    let portfolioFetchedAt: Date
    let tokens: [TokenMarket]
}

nonisolated struct WalletTransfer: Codable, Equatable, Sendable {
    let asset: String?
    let blockNumber: String?
    let category: String?
    let from: String?
    let hash: String?
    let to: String?
    let value: String?
}

nonisolated struct TransactionPage: Codable, Equatable, Sendable {
    let address: EVMAddress
    let nextPageKey: String?
    let transfers: [WalletTransfer]
}
