import Foundation

enum RefreshPolicy: Equatable, Sendable {
    case ifExpired
    case force
}

enum RepositoryLoadEvent<Value: Sendable>: Sendable {
    case cached(Value)
    case refreshing
    case fresh(Value)
}

extension RepositoryLoadEvent: Equatable where Value: Equatable {}

struct DateProvider: Sendable {
    let now: @Sendable () -> Date

    nonisolated static let system = DateProvider(now: Date.init)
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
