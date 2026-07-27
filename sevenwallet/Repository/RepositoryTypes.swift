import Foundation

nonisolated enum RefreshPolicy: Equatable, Sendable {
    case ifExpired
    case force
}

nonisolated enum RepositoryLoadEvent<Value: Sendable>: Sendable {
    case cached(Value)
    case refreshing
    case fresh(Value)
}

extension RepositoryLoadEvent: Equatable where Value: Equatable {}

nonisolated struct DateProvider: Sendable {
    let now: @Sendable () -> Date

    static let system = DateProvider(now: Date.init)
}

protocol TokenRepositoryProtocol: Sendable {
    func nativeTokens(
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<[WalletToken]>, Swift.Error>

    func portfolio(
        address: EVMAddress,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<TokenPortfolio>, Swift.Error>
}

protocol PortfolioLoadControlling: Sendable {
    func suspendPortfolioLoads(address: EVMAddress) async
    func resumePortfolioLoads(address: EVMAddress) async
}

nonisolated struct NoopPortfolioLoadController: PortfolioLoadControlling {
    func suspendPortfolioLoads(address: EVMAddress) async {}
    func resumePortfolioLoads(address: EVMAddress) async {}
}

protocol TransactionRepositoryProtocol: Sendable {
    func transactions(
        address: EVMAddress,
        limit: Int,
        pageKey: String?,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<TransactionPage>, Swift.Error>
}

nonisolated struct TransactionRequestKey: Hashable, Sendable {
    let address: EVMAddress
    let limit: Int
    let pageKey: String?
}

nonisolated enum RepositoryError: Swift.Error, Equatable, LocalizedError {
    case invalidTransactionLimit(Int)
    case storageReadFailed
    case storageWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidTransactionLimit, .storageReadFailed:
            "Unable to load wallet data."
        case .storageWriteFailed:
            "Unable to save wallet data."
        }
    }
}
