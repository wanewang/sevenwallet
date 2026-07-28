import Foundation

@MainActor
final class TokenRepository: TokenRepositoryProtocol, PortfolioLoadControlling {
    private struct PortfolioTaskEntry {
        let id: UUID
        let task: Task<TokenPortfolio, Swift.Error>
    }

    private struct MarketTaskEntry {
        let id: UUID
        let task: Task<TokenMarketPortfolio, Swift.Error>
    }

    private let remote: any TokenRemoteDataSourceProtocol
    private let store: any WalletStoreProtocol
    private let dateProvider: DateProvider
    private let beforePortfolioTaskCleanup: ((EVMAddress) async -> Void)?
    private let marketRetryDelay: @Sendable (Duration) async throws -> Void
    private var nativeTask: Task<[WalletToken], Swift.Error>?
    private var portfolioTasks: [EVMAddress: PortfolioTaskEntry] = [:]
    private var marketTasks: [EVMAddress: MarketTaskEntry] = [:]
    private var portfolioGenerations: [EVMAddress: Int] = [:]
    private var suspendedPortfolioAddresses: Set<EVMAddress> = []

    init(
        remote: any TokenRemoteDataSourceProtocol,
        store: any WalletStoreProtocol,
        dateProvider: DateProvider = .system,
        beforePortfolioTaskCleanup: ((EVMAddress) async -> Void)? = nil,
        marketRetryDelay: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.remote = remote
        self.store = store
        self.dateProvider = dateProvider
        self.beforePortfolioTaskCleanup = beforePortfolioTaskCleanup
        self.marketRetryDelay = marketRetryDelay
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

    func tokenMarkets(address: EVMAddress) async throws -> TokenMarketPortfolio {
        guard !suspendedPortfolioAddresses.contains(address) else {
            throw CancellationError()
        }
        // A concurrent caller joins the in-flight attempt chain rather than
        // starting a second one. Only the caller that started the chain cancels
        // it, so a joiner going away leaves the shared work running.
        if let entry = marketTasks[address] {
            return try await entry.task.value
        }

        let id = UUID()
        let task = Task { @MainActor in
            try await fetchMarkets(address: address)
        }
        marketTasks[address] = MarketTaskEntry(id: id, task: task)
        let result = await withTaskCancellationHandler {
            await task.result
        } onCancel: {
            task.cancel()
        }
        removeMarketTask(address: address, id: id)
        return try result.get()
    }

    func suspendPortfolioLoads(address: EVMAddress) async {
        suspendedPortfolioAddresses.insert(address)
        portfolioGenerations[address, default: 0] += 1
        if let entry = marketTasks[address] {
            entry.task.cancel()
            _ = await entry.task.result
            removeMarketTask(address: address, id: entry.id)
        }
        guard let entry = portfolioTasks[address] else { return }
        entry.task.cancel()
        _ = await entry.task.result
        removePortfolioTask(address: address, id: entry.id)
    }

    private func fetchMarkets(
        address: EVMAddress
    ) async throws -> TokenMarketPortfolio {
        let retryDelays: [Duration] = [.milliseconds(500), .seconds(1)]
        var retryIndex = 0

        while true {
            try Task.checkCancellation()
            do {
                let value = try await remote.fetchTokenMarkets(address: address)
                try Task.checkCancellation()
                return value
            } catch {
                try Task.checkCancellation()
                guard retryIndex < retryDelays.count,
                      isRetryableMarketError(error) else {
                    // The caller collapses every cause into one message, so
                    // this is the only record of what actually failed.
                    AppLog.marketError(
                        """
                        Token market request failed after \
                        \(retryIndex + 1) attempt(s): \
                        \(String(describing: error))
                        """
                    )
                    throw error
                }
                AppLog.marketWarning(
                    """
                    Token market attempt \(retryIndex + 1) \
                    failed, retrying: \
                    \(String(describing: error))
                    """
                )
                let delay = retryDelays[retryIndex]
                retryIndex += 1
                try await marketRetryDelay(delay)
            }
        }
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

    private func isRetryableMarketError(_ error: any Error) -> Bool {
        guard let error = error as? APIError else { return false }
        switch error {
        case .transport, .nonHTTPResponse:
            return true
        case .http(let status, _):
            return status == 408 || status == 429 || 500...599 ~= status
        case .invalidRequest, .invalidData:
            return false
        }
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

    private func removeMarketTask(address: EVMAddress, id: UUID) {
        guard marketTasks[address]?.id == id else { return }
        marketTasks[address] = nil
    }
}
