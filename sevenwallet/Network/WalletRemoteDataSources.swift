import Foundation

protocol TokenRemoteDataSourceProtocol: Sendable {
    func fetchNativeTokens() async throws -> [WalletToken]
    func fetchPortfolio(address: EVMAddress) async throws -> TokenPortfolio
}

protocol TransactionRemoteDataSourceProtocol: Sendable {
    func fetchTransactions(address: EVMAddress, limit: Int, pageKey: String?) async throws -> TransactionPage
}

struct TokenRemoteDataSource: TokenRemoteDataSourceProtocol, Sendable {
    let client: any APIClientProtocol

    func fetchNativeTokens() async throws -> [WalletToken] {
        let data = try await client.data(for: .nativeTokens)
        do {
            return try JSONDecoder().decode([TokenDTO].self, from: data).map(makeToken)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.invalidData
        }
    }

    func fetchPortfolio(address: EVMAddress) async throws -> TokenPortfolio {
        let data = try await client.data(for: .portfolio(address))
        do {
            let payload = try JSONDecoder().decode(PortfolioDTO.self, from: data)
            guard let returnedAddress = try? EVMAddress(payload.address), returnedAddress == address else {
                throw APIError.invalidData
            }
            return TokenPortfolio(
                address: returnedAddress,
                fetchedAt: try parseDate(payload.fetchedAt),
                network: payload.network,
                tokens: try payload.tokens.map(makeToken)
            )
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.invalidData
        }
    }
}

struct TransactionRemoteDataSource: TransactionRemoteDataSourceProtocol, Sendable {
    let client: any APIClientProtocol

    func fetchTransactions(address: EVMAddress, limit: Int, pageKey: String?) async throws -> TransactionPage {
        let data = try await client.data(for: .transactions(address, limit: limit, pageKey: pageKey))
        do {
            let payload = try JSONDecoder().decode(TransactionPageDTO.self, from: data)
            guard let returnedAddress = try? EVMAddress(payload.address), returnedAddress == address else {
                throw APIError.invalidData
            }
            return TransactionPage(
                address: returnedAddress,
                nextPageKey: payload.nextPageKey,
                transfers: payload.transfers.map {
                    WalletTransfer(
                        asset: $0.asset,
                        blockNumber: $0.blockNum,
                        category: $0.category,
                        from: $0.from,
                        hash: $0.hash,
                        to: $0.to,
                        value: $0.value
                    )
                }
            )
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.invalidData
        }
    }
}

private struct TokenDTO: Decodable {
    let tokenAddress: String?
    let symbol: String
    let name: String
    let decimals: Int
    let rawBalance: String
    let balance: String
    let isNative: Bool
    let price: PriceDTO?
    let logoURI: String?
    let coinKey: String
    let priceUSD: String?
}

private struct PriceDTO: Decodable {
    let currency: String?
    let value: String?
    let lastUpdatedAt: String?
}

private struct PortfolioDTO: Decodable {
    let address: String
    let fetchedAt: String?
    let network: String?
    let tokens: [TokenDTO]
}

private struct TransactionPageDTO: Decodable {
    let address: String
    let nextPageKey: String?
    let transfers: [TransferDTO]
}

private struct TransferDTO: Decodable {
    let asset: String?
    let blockNum: String?
    let category: String?
    let from: String?
    let hash: String?
    let to: String?
    let value: String?
}

private let decimalLocale = Locale(identifier: "en_US_POSIX")
private let decimalPattern = #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#

private func makeToken(_ payload: TokenDTO) throws -> WalletToken {
    return WalletToken(
        tokenAddress: payload.tokenAddress,
        symbol: payload.symbol,
        name: payload.name,
        decimals: payload.decimals,
        rawBalance: payload.rawBalance,
        balance: try parseRequiredDecimal(payload.balance),
        isNative: payload.isNative,
        price: try payload.price.map {
            TokenPrice(
                currency: $0.currency,
                value: try parseDecimal($0.value),
                lastUpdatedAt: try parseDate($0.lastUpdatedAt)
            )
        },
        logoURL: payload.logoURI.flatMap(URL.init(string:)),
        coinKey: payload.coinKey,
        priceUSD: try parseDecimal(payload.priceUSD)
    )
}

private func parseRequiredDecimal(_ rawValue: String) throws -> Decimal {
    guard rawValue.range(of: decimalPattern, options: .regularExpression) != nil,
          let value = Decimal(string: rawValue, locale: decimalLocale) else {
        throw APIError.invalidData
    }
    return value
}

private func parseDecimal(_ rawValue: String?) throws -> Decimal? {
    guard let rawValue else { return nil }
    return try parseRequiredDecimal(rawValue)
}

private func parseDate(_ rawValue: String?) throws -> Date? {
    guard let rawValue else { return nil }
    guard let value = ISO8601DateFormatter().date(from: rawValue) else {
        throw APIError.invalidData
    }
    return value
}
