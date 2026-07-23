import Foundation
import Testing
@testable import sevenwallet

@MainActor
struct TransactionRepositoryTests {
    @Test func samePageCoalescesAndDifferentCursorDoesNot() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let address = try makeRepositoryAddress()
        let firstRequest = TransactionRequest(address: address, limit: 25, pageKey: nil)
        let nextRequest = TransactionRequest(address: address, limit: 25, pageKey: "next")
        let firstPage = makeRepositoryTransactionPage(address: address, nextPageKey: "next")
        let nextPage = makeRepositoryTransactionPage(address: address)
        let remote = TransactionRemoteDataSourceSpy(
            results: [firstRequest: .success(firstPage), nextRequest: .success(nextPage)],
            gatedRequests: [firstRequest, nextRequest]
        )
        let store = WalletStoreSpy()
        let repository = TransactionRepository(remote: remote, store: store, dateProvider: fixedDate(now))
        var first = repository.transactions(address: address, limit: 25, pageKey: nil, policy: .force).makeAsyncIterator()
        var duplicate = repository.transactions(address: address, limit: 25, pageKey: nil, policy: .force).makeAsyncIterator()
        var next = repository.transactions(address: address, limit: 25, pageKey: "next", policy: .force).makeAsyncIterator()

        #expect(try await first.next() == .refreshing)
        #expect(try await duplicate.next() == .refreshing)
        #expect(try await next.next() == .refreshing)
        #expect(await remote.callCount == 2)

        await remote.releaseRequest(firstRequest)
        await remote.releaseRequest(nextRequest)

        #expect(try await first.next() == .fresh(firstPage))
        #expect(try await duplicate.next() == .fresh(firstPage))
        #expect(try await next.next() == .fresh(nextPage))
        #expect(await remote.callCount == 2)
        #expect(await store.transactionSaveDates[firstRequest] == [now])
        #expect(await store.transactionSaveDates[nextRequest] == [now])
    }

    @Test func cachedPagesRemainIndependentByLimitAndCursor() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let address = try makeRepositoryAddress()
        let firstRequest = TransactionRequest(address: address, limit: 25, pageKey: nil)
        let secondRequest = TransactionRequest(address: address, limit: 100, pageKey: "next")
        let firstPage = makeRepositoryTransactionPage(address: address, nextPageKey: "next")
        let secondPage = makeRepositoryTransactionPage(address: address)
        let store = WalletStoreSpy(transactionCaches: [
            firstRequest: CachedResource(value: firstPage, fetchedAt: now),
            secondRequest: CachedResource(value: secondPage, fetchedAt: now)
        ])
        let remote = TransactionRemoteDataSourceSpy()
        let repository = TransactionRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        #expect(try await collect(repository.transactions(address: address, limit: 25, pageKey: nil, policy: .ifExpired)) == [.cached(firstPage)])
        #expect(try await collect(repository.transactions(address: address, limit: 100, pageKey: "next", policy: .ifExpired)) == [.cached(secondPage)])
        #expect(await remote.callCount == 0)
    }

    @Test func exactlyThirtyMinutesIsFresh() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let address = try makeRepositoryAddress()
        let request = TransactionRequest(address: address, limit: 25, pageKey: nil)
        let page = makeRepositoryTransactionPage(address: address, nextPageKey: "next")
        let store = WalletStoreSpy(transactionCaches: [
            request: CachedResource(value: page, fetchedAt: now.addingTimeInterval(-1_800))
        ])
        let remote = TransactionRemoteDataSourceSpy()
        let repository = TransactionRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        #expect(try await collect(repository.transactions(address: address, limit: 25, pageKey: nil, policy: .ifExpired)) == [.cached(page)])
        #expect(await remote.callCount == 0)
    }

    @Test func stalePagePublishesCacheThenRefreshesAndPreservesNextPageKey() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let address = try makeRepositoryAddress()
        let request = TransactionRequest(address: address, limit: 25, pageKey: "cursor")
        let cached = makeRepositoryTransactionPage(address: address)
        let fresh = makeRepositoryTransactionPage(address: address, nextPageKey: "next")
        let store = WalletStoreSpy(transactionCaches: [
            request: CachedResource(value: cached, fetchedAt: now.addingTimeInterval(-1_801))
        ])
        let remote = TransactionRemoteDataSourceSpy(results: [request: .success(fresh)])
        let repository = TransactionRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        #expect(try await collect(repository.transactions(address: address, limit: 25, pageKey: "cursor", policy: .ifExpired)) == [
            .cached(cached),
            .refreshing,
            .fresh(fresh)
        ])
        #expect(try await store.loadTransactionPage(address: address, limit: 25, pageKey: "cursor")?.value.nextPageKey == "next")
        #expect(await store.transactionSaveDates[request] == [now])
    }

    @Test func failedRefreshPropagatesTypedErrorAndPreservesTimestamp() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let originalDate = now.addingTimeInterval(-1_801)
        let address = try makeRepositoryAddress()
        let request = TransactionRequest(address: address, limit: 25, pageKey: nil)
        let cached = makeRepositoryTransactionPage(address: address)
        let store = WalletStoreSpy(transactionCaches: [
            request: CachedResource(value: cached, fetchedAt: originalDate)
        ])
        let remote = TransactionRemoteDataSourceSpy(results: [request: .failure(.remoteFailure)])
        let repository = TransactionRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        let recording = await record(repository.transactions(address: address, limit: 25, pageKey: nil, policy: .ifExpired))

        #expect(recording.values == [.cached(cached), .refreshing])
        #expect(recording.error == .remoteFailure)
        #expect(try await store.loadTransactionPage(address: address, limit: 25, pageKey: nil)?.fetchedAt == originalDate)
        #expect(await store.transactionSaveDates[request]?.isEmpty ?? true)
    }

    @Test(arguments: [0, 101]) func invalidLimitsFailBeforeCacheAccess(limit: Int) async throws {
        let address = try makeRepositoryAddress()
        let store = WalletStoreSpy()
        let remote = TransactionRemoteDataSourceSpy()
        let repository = TransactionRepository(remote: remote, store: store)

        await #expect(throws: RepositoryError.invalidTransactionLimit(limit)) {
            try await collect(repository.transactions(address: address, limit: limit, pageKey: nil, policy: .ifExpired))
        }
        #expect(await store.transactionLoadCount == 0)
        #expect(await remote.callCount == 0)
    }

    @Test func invalidLimitHasConciseDescription() {
        #expect(
            RepositoryError.invalidTransactionLimit(101).localizedDescription
                == "Transaction limit must be between 1 and 100."
        )
    }

    @Test func transactionStorageReadFailureUsesConciseRepositoryError() async throws {
        let address = try makeRepositoryAddress()
        let repository = TransactionRepository(
            remote: TransactionRemoteDataSourceSpy(),
            store: FailingWalletStore(readError: .storageReadFailure)
        )

        await #expect(throws: RepositoryError.storageReadFailed) {
            try await collect(
                repository.transactions(
                    address: address,
                    limit: 25,
                    pageKey: nil,
                    policy: .ifExpired
                )
            )
        }
    }

    private func fixedDate(_ date: Date) -> DateProvider {
        DateProvider(now: { date })
    }
}
