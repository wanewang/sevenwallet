import Foundation

@MainActor
final class TokenRepository: TokenRepositoryProtocol, PortfolioLoadControlling {
    private struct PortfolioTaskEntry {
        let id: UUID
        let task: Task<TokenPortfolio, Swift.Error>
    }

    private let remote: any TokenRemoteDataSourceProtocol
    private let store: any WalletStoreProtocol
    private let dateProvider: DateProvider
    private let beforePortfolioTaskCleanup: ((EVMAddress) async -> Void)?
    private var nativeTask: Task<[WalletToken], Swift.Error>?
    private var portfolioTasks: [EVMAddress: PortfolioTaskEntry] = [:]
    private var portfolioGenerations: [EVMAddress: Int] = [:]
    private var suspendedPortfolioAddresses: Set<EVMAddress> = []

    init(
        remote: any TokenRemoteDataSourceProtocol,
        store: any WalletStoreProtocol,
        dateProvider: DateProvider = .system,
        beforePortfolioTaskCleanup: ((EVMAddress) async -> Void)? = nil
    ) {
        self.remote = remote
        self.store = store
        self.dateProvider = dateProvider
        self.beforePortfolioTaskCleanup = beforePortfolioTaskCleanup
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
        guard !suspendedPortfolioAddresses.contains(address) else {
            return AsyncThrowingStream { $0.finish() }
        }
        let generation = portfolioGenerations[address, default: 0]
        return AsyncThrowingStream<
            RepositoryLoadEvent<TokenPortfolio>,
            Swift.Error
        > { continuation in
            let task = Task { @MainActor in
                do {
                    guard !suspendedPortfolioAddresses.contains(address),
                          generation == portfolioGenerations[address, default: 0] else {
                        throw CancellationError()
                    }
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

    func suspendPortfolioLoads(address: EVMAddress) async {
        suspendedPortfolioAddresses.insert(address)
        portfolioGenerations[address, default: 0] += 1
        guard let entry = portfolioTasks[address] else { return }
        entry.task.cancel()
        _ = await entry.task.result
        removePortfolioTask(address: address, id: entry.id)
    }

    func resumePortfolioLoads(address: EVMAddress) async {
        suspendedPortfolioAddresses.remove(address)
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
        if let entry = portfolioTasks[address] {
            return try await entry.task.value
        }

        let id = UUID()
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
        portfolioTasks[address] = PortfolioTaskEntry(id: id, task: task)
        let result = await task.result
        if let beforePortfolioTaskCleanup {
            await beforePortfolioTaskCleanup(address)
        }
        removePortfolioTask(address: address, id: id)
        return try result.get()
    }

    func hasActivePortfolioTask(address: EVMAddress) -> Bool {
        portfolioTasks[address] != nil
    }

    private func removePortfolioTask(address: EVMAddress, id: UUID) {
        guard portfolioTasks[address]?.id == id else { return }
        portfolioTasks[address] = nil
    }
}
