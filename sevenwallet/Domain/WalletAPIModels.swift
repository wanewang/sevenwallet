import Foundation

nonisolated protocol TokenIdentifiable: Identifiable where ID == String {
    var symbol: String { get }
    var tokenAddress: String? { get }
}

extension TokenIdentifiable {
    nonisolated var key: String { "\(symbol):\(tokenAddress?.lowercased() ?? "native")" }
    nonisolated var id: String { key }
}

nonisolated struct TokenPrice: Codable, Equatable, Sendable {
    let currency: String?
    let value: Decimal?
    let lastUpdatedAt: Date?
}

nonisolated struct WalletToken: Codable, Equatable, TokenIdentifiable, Sendable {
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

    var marketPriceUSD: Decimal? { priceUSD ?? price?.value }
}

nonisolated struct TokenPortfolio: Codable, Equatable, Sendable {
    let address: EVMAddress
    let fetchedAt: Date?
    let network: String?
    let tokens: [WalletToken]
}

nonisolated struct MarketQuote<ID: Equatable & Sendable>: Equatable, Sendable {
    let id: ID
    let priceUSD: Decimal?
    let change24hPercent: Decimal?
}

typealias CoinGeckoMarket = MarketQuote<String>
typealias CoinMarketCapMarket = MarketQuote<Int>

nonisolated struct TokenMarket: Equatable, TokenIdentifiable, Sendable {
    let tokenAddress: String?
    let symbol: String
    let name: String
    let decimals: Int
    let balance: Decimal
    let coinGecko: CoinGeckoMarket?
    let coinMarketCap: CoinMarketCapMarket?
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
