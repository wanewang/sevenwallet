import Foundation

@MainActor
final class TokenRepository: TokenRepositoryProtocol {
    private let remote: any TokenRemoteDataSourceProtocol
    private let store: any WalletStoreProtocol
    private let dateProvider: DateProvider
    private var nativeTask: Task<[WalletToken], Swift.Error>?
    private var portfolioTasks: [EVMAddress: Task<TokenPortfolio, Swift.Error>] = [:]

    init(
        remote: any TokenRemoteDataSourceProtocol,
        store: any WalletStoreProtocol,
        dateProvider: DateProvider = .system
    ) {
        self.remote = remote
        self.store = store
        self.dateProvider = dateProvider
    }

    func nativeTokens(
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<[WalletToken]>, Swift.Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    let cached = try await store.loadNativeTokens()
                    if let cached {
                        continuation.yield(.cached(cached.value))
                    }
                    guard shouldRefresh(cached: cached, policy: policy) else {
                        continuation.finish()
                        return
                    }

                    continuation.yield(.refreshing)
                    let value = try await refreshNative()
                    continuation.yield(.fresh(value))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func portfolio(
        address: EVMAddress,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<TokenPortfolio>, Swift.Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    let cached = try await store.loadPortfolio(address: address)
                    if let cached {
                        continuation.yield(.cached(cached.value))
                    }
                    guard shouldRefresh(cached: cached, policy: policy) else {
                        continuation.finish()
                        return
                    }

                    continuation.yield(.refreshing)
                    let value = try await refreshPortfolio(address: address)
                    continuation.yield(.fresh(value))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func shouldRefresh<Value: Sendable>(
        cached: CachedResource<Value>?,
        policy: RefreshPolicy
    ) -> Bool {
        policy == .force || cached.map {
            dateProvider.now().timeIntervalSince($0.fetchedAt) > 1_800
        } ?? true
    }

    private func refreshNative() async throws -> [WalletToken] {
        if let nativeTask {
            return try await nativeTask.value
        }

        let task = Task { @MainActor in
            let value = try await remote.fetchNativeTokens()
            try await store.saveNativeTokens(value, fetchedAt: dateProvider.now())
            return value
        }
        nativeTask = task
        defer { nativeTask = nil }
        return try await task.value
    }

    private func refreshPortfolio(address: EVMAddress) async throws -> TokenPortfolio {
        if let task = portfolioTasks[address] {
            return try await task.value
        }

        let task = Task { @MainActor in
            let value = try await remote.fetchPortfolio(address: address)
            try await store.savePortfolio(value, fetchedAt: dateProvider.now())
            return value
        }
        portfolioTasks[address] = task
        defer { portfolioTasks[address] = nil }
        return try await task.value
    }
}
