import Foundation

@MainActor
final class TransactionRepository: TransactionRepositoryProtocol {
    private let remote: any TransactionRemoteDataSourceProtocol
    private let store: any WalletStoreProtocol
    private let dateProvider: DateProvider
    private var tasks: [TransactionRequestKey: Task<TransactionPage, Swift.Error>] = [:]

    init(
        remote: any TransactionRemoteDataSourceProtocol,
        store: any WalletStoreProtocol,
        dateProvider: DateProvider = .system
    ) {
        self.remote = remote
        self.store = store
        self.dateProvider = dateProvider
    }

    func transactions(
        address: EVMAddress,
        limit: Int,
        pageKey: String?,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<TransactionPage>, Swift.Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    guard (1...100).contains(limit) else {
                        throw RepositoryError.invalidTransactionLimit(limit)
                    }

                    let key = TransactionRequestKey(address: address, limit: limit, pageKey: pageKey)
                    let cached = try await store.loadTransactionPage(
                        address: key.address,
                        limit: key.limit,
                        pageKey: key.pageKey
                    )
                    if let cached {
                        continuation.yield(.cached(cached.value))
                    }
                    guard shouldRefresh(cached: cached, policy: policy) else {
                        continuation.finish()
                        return
                    }

                    continuation.yield(.refreshing)
                    let page = try await refresh(key)
                    continuation.yield(.fresh(page))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func shouldRefresh(
        cached: CachedResource<TransactionPage>?,
        policy: RefreshPolicy
    ) -> Bool {
        policy == .force || cached.map {
            dateProvider.now().timeIntervalSince($0.fetchedAt) > 1_800
        } ?? true
    }

    private func refresh(_ key: TransactionRequestKey) async throws -> TransactionPage {
        if let task = tasks[key] {
            return try await task.value
        }

        let task = Task { @MainActor in
            let value = try await remote.fetchTransactions(
                address: key.address,
                limit: key.limit,
                pageKey: key.pageKey
            )
            try await store.saveTransactionPage(
                value,
                limit: key.limit,
                pageKey: key.pageKey,
                fetchedAt: dateProvider.now()
            )
            return value
        }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}
