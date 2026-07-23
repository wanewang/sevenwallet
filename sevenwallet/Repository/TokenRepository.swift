import Foundation

@MainActor
final class TokenRepository: TokenRepositoryProtocol, PortfolioLoadCancelling {
    private let remote: any TokenRemoteDataSourceProtocol
    private let store: any WalletStoreProtocol
    private let dateProvider: DateProvider
    private var nativeTask: Task<[WalletToken], Swift.Error>?
    private var portfolioTasks: [EVMAddress: Task<TokenPortfolio, Swift.Error>] = [:]
    private var portfolioGenerations: [EVMAddress: Int] = [:]

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
            let task = Task { @MainActor in
                do {
                    let cached: CachedResource<[WalletToken]>?
                    do {
                        cached = try await store.loadNativeTokens()
                    } catch {
                        throw RepositoryError.storageReadFailed
                    }
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
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func portfolio(
        address: EVMAddress,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<TokenPortfolio>, Swift.Error> {
        let generation = portfolioGenerations[address, default: 0]
        return AsyncThrowingStream<
            RepositoryLoadEvent<TokenPortfolio>,
            Swift.Error
        > { continuation in
            let task = Task { @MainActor in
                do {
                    let cached: CachedResource<TokenPortfolio>?
                    do {
                        cached = try await store.loadPortfolio(address: address)
                    } catch {
                        throw RepositoryError.storageReadFailed
                    }
                    guard generation == portfolioGenerations[address, default: 0] else {
                        throw CancellationError()
                    }
                    if let cached {
                        continuation.yield(.cached(cached.value))
                    }
                    guard shouldRefresh(cached: cached, policy: policy) else {
                        continuation.finish()
                        return
                    }
                    guard generation == portfolioGenerations[address, default: 0] else {
                        throw CancellationError()
                    }

                    continuation.yield(.refreshing)
                    let value = try await refreshPortfolio(address: address)
                    guard generation == portfolioGenerations[address, default: 0] else {
                        throw CancellationError()
                    }
                    continuation.yield(.fresh(value))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    if generation == portfolioGenerations[address, default: 0] {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func cancelPortfolioLoad(address: EVMAddress) async {
        portfolioGenerations[address, default: 0] += 1
        guard let task = portfolioTasks[address] else { return }
        task.cancel()
        _ = await task.result
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
            do {
                try await store.saveNativeTokens(value, fetchedAt: dateProvider.now())
            } catch {
                throw RepositoryError.storageWriteFailed
            }
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
            try Task.checkCancellation()
            do {
                try await store.savePortfolio(value, fetchedAt: dateProvider.now())
            } catch {
                throw RepositoryError.storageWriteFailed
            }
            try Task.checkCancellation()
            return value
        }
        portfolioTasks[address] = task
        defer { portfolioTasks[address] = nil }
        return try await task.value
    }
}
