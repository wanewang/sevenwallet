import Foundation
import Testing
@testable import sevenwallet

@MainActor
struct TokenRepositoryTests {
    @Test func exactlyThirtyMinutesIsFresh() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cached = [makeRepositoryToken(price: "1900")]
        let store = WalletStoreSpy(
            nativeCache: CachedResource(value: cached, fetchedAt: now.addingTimeInterval(-1_800))
        )
        let remote = TokenRemoteDataSourceSpy(nativeResult: .success([makeRepositoryToken(price: "2000")]))
        let repository = TokenRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        #expect(try await collect(repository.nativeTokens(policy: .ifExpired)) == [.cached(cached)])
        #expect(await remote.nativeCallCount == 0)
    }

    @Test func olderNativeCachePublishesThenRefreshes() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cached = [makeRepositoryToken(price: "1900")]
        let fresh = [makeRepositoryToken(price: "2000")]
        let store = WalletStoreSpy(
            nativeCache: CachedResource(value: cached, fetchedAt: now.addingTimeInterval(-1_801))
        )
        let remote = TokenRemoteDataSourceSpy(nativeResult: .success(fresh))
        let repository = TokenRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        #expect(try await collect(repository.nativeTokens(policy: .ifExpired)) == [
            .cached(cached),
            .refreshing,
            .fresh(fresh)
        ])
        #expect(try await store.loadNativeTokens()?.fetchedAt == now)
        #expect(await store.nativeSaveDates == [now])
    }

    @Test func nativeCacheMissRefreshesWithoutCachedEvent() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let fresh = [makeRepositoryToken(price: "2000")]
        let store = WalletStoreSpy()
        let remote = TokenRemoteDataSourceSpy(nativeResult: .success(fresh))
        let repository = TokenRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        #expect(try await collect(repository.nativeTokens(policy: .ifExpired)) == [
            .refreshing,
            .fresh(fresh)
        ])
        #expect(try await store.loadNativeTokens()?.fetchedAt == now)
    }

    @Test func forceRefreshesFreshNativeCache() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cached = [makeRepositoryToken(price: "1900")]
        let fresh = [makeRepositoryToken(price: "2000")]
        let store = WalletStoreSpy(nativeCache: CachedResource(value: cached, fetchedAt: now))
        let remote = TokenRemoteDataSourceSpy(nativeResult: .success(fresh))
        let repository = TokenRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        #expect(try await collect(repository.nativeTokens(policy: .force)) == [
            .cached(cached),
            .refreshing,
            .fresh(fresh)
        ])
        #expect(await remote.nativeCallCount == 1)
    }

    @Test func failedNativeRefreshPropagatesTypedErrorAndPreservesTimestamp() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let originalDate = now.addingTimeInterval(-1_801)
        let cached = [makeRepositoryToken(price: "1900")]
        let store = WalletStoreSpy(nativeCache: CachedResource(value: cached, fetchedAt: originalDate))
        let remote = TokenRemoteDataSourceSpy(nativeResult: .failure(.remoteFailure))
        let repository = TokenRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        let recording = await record(repository.nativeTokens(policy: .ifExpired))

        #expect(recording.values == [.cached(cached), .refreshing])
        #expect(recording.error == .remoteFailure)
        #expect(try await store.loadNativeTokens()?.fetchedAt == originalDate)
        #expect(await store.nativeSaveDates.isEmpty)
    }

    @Test func nativeStorageReadFailureUsesConciseRepositoryError() async throws {
        let repository = TokenRepository(
            remote: TokenRemoteDataSourceSpy(),
            store: FailingWalletStore(readError: .storageReadFailure)
        )

        await #expect(throws: RepositoryError.storageReadFailed) {
            try await collect(repository.nativeTokens(policy: .ifExpired))
        }
    }

    @Test func nativeStorageWriteFailureUsesConciseRepositoryError() async throws {
        let repository = TokenRepository(
            remote: TokenRemoteDataSourceSpy(nativeResult: .success([makeRepositoryToken(price: "2000")])),
            store: FailingWalletStore(writeError: .storageWriteFailure)
        )

        await #expect(throws: RepositoryError.storageWriteFailed) {
            try await collect(repository.nativeTokens(policy: .ifExpired))
        }
    }

    @Test func stalePortfolioPublishesCacheThenRefreshesForItsAddress() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let address = try makeRepositoryAddress()
        let cached = makeRepositoryPortfolio(address: address, price: "1900")
        let fresh = makeRepositoryPortfolio(address: address, price: "2000")
        let store = WalletStoreSpy(
            portfolioCaches: [address: CachedResource(value: cached, fetchedAt: now.addingTimeInterval(-1_801))]
        )
        let remote = TokenRemoteDataSourceSpy(portfolioResults: [address: .success(fresh)])
        let repository = TokenRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        #expect(try await collect(repository.portfolio(address: address, policy: .ifExpired)) == [
            .cached(cached),
            .refreshing,
            .fresh(fresh)
        ])
        #expect(try await store.loadPortfolio(address: address)?.fetchedAt == now)
        #expect(await remote.portfolioCallCounts[address] == 1)
    }

    @Test func portfolioCachesRemainIndependentByAddress() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let firstAddress = try makeRepositoryAddress()
        let secondAddress = try makeRepositoryAddress("1234567890123456789012345678901234567890")
        let first = makeRepositoryPortfolio(address: firstAddress, price: "1900")
        let second = makeRepositoryPortfolio(address: secondAddress, price: "2000")
        let store = WalletStoreSpy(portfolioCaches: [
            firstAddress: CachedResource(value: first, fetchedAt: now),
            secondAddress: CachedResource(value: second, fetchedAt: now)
        ])
        let remote = TokenRemoteDataSourceSpy()
        let repository = TokenRepository(remote: remote, store: store, dateProvider: fixedDate(now))

        #expect(try await collect(repository.portfolio(address: firstAddress, policy: .ifExpired)) == [.cached(first)])
        #expect(try await collect(repository.portfolio(address: secondAddress, policy: .ifExpired)) == [.cached(second)])
        #expect(await remote.portfolioCallCounts.isEmpty)
    }

    @Test func simultaneousNativeRefreshesShareOneRequest() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let fresh = [makeRepositoryToken(price: "2000")]
        let store = WalletStoreSpy()
        let remote = TokenRemoteDataSourceSpy(nativeResult: .success(fresh), gatesNativeRequest: true)
        let repository = TokenRepository(remote: remote, store: store, dateProvider: fixedDate(now))
        var first = repository.nativeTokens(policy: .force).makeAsyncIterator()

        #expect(try await first.next() == .refreshing)

        var second = repository.nativeTokens(policy: .force).makeAsyncIterator()
        #expect(try await second.next() == .refreshing)
        #expect(await remote.nativeCallCount == 1)

        await remote.releaseNativeRequest()

        #expect(try await first.next() == .fresh(fresh))
        #expect(try await second.next() == .fresh(fresh))
        #expect(try await first.next() == nil)
        #expect(try await second.next() == nil)
        #expect(await remote.nativeCallCount == 1)
        #expect(await store.nativeSaveDates == [now])
    }

    @Test func simultaneousPortfolioRefreshesForSameAddressShareOneRequest() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let address = try makeRepositoryAddress()
        let fresh = makeRepositoryPortfolio(address: address, price: "2000")
        let store = WalletStoreSpy()
        let remote = TokenRemoteDataSourceSpy(
            portfolioResults: [address: .success(fresh)],
            gatedPortfolioAddresses: [address]
        )
        let repository = TokenRepository(remote: remote, store: store, dateProvider: fixedDate(now))
        var first = repository.portfolio(address: address, policy: .force).makeAsyncIterator()

        #expect(try await first.next() == .refreshing)

        var second = repository.portfolio(address: address, policy: .force).makeAsyncIterator()
        #expect(try await second.next() == .refreshing)
        #expect(await remote.portfolioCallCounts[address] == 1)

        await remote.releasePortfolioRequest(address: address)

        #expect(try await first.next() == .fresh(fresh))
        #expect(try await second.next() == .fresh(fresh))
        #expect(await remote.portfolioCallCounts[address] == 1)
        #expect(await store.portfolioSaveDates[address] == [now])
    }

    @Test func simultaneousDifferentPortfolioAddressesUseIndependentRequests() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let firstAddress = try makeRepositoryAddress()
        let secondAddress = try makeRepositoryAddress("1234567890123456789012345678901234567890")
        let firstFresh = makeRepositoryPortfolio(address: firstAddress, price: "1900")
        let secondFresh = makeRepositoryPortfolio(address: secondAddress, price: "2000")
        let store = WalletStoreSpy()
        let remote = TokenRemoteDataSourceSpy(
            portfolioResults: [firstAddress: .success(firstFresh), secondAddress: .success(secondFresh)],
            gatedPortfolioAddresses: [firstAddress, secondAddress]
        )
        let repository = TokenRepository(remote: remote, store: store, dateProvider: fixedDate(now))
        var first = repository.portfolio(address: firstAddress, policy: .force).makeAsyncIterator()
        var second = repository.portfolio(address: secondAddress, policy: .force).makeAsyncIterator()

        #expect(try await first.next() == .refreshing)
        #expect(try await second.next() == .refreshing)
        #expect(await remote.portfolioCallCounts[firstAddress] == 1)
        #expect(await remote.portfolioCallCounts[secondAddress] == 1)

        await remote.releasePortfolioRequest(address: firstAddress)
        await remote.releasePortfolioRequest(address: secondAddress)

        #expect(try await first.next() == .fresh(firstFresh))
        #expect(try await second.next() == .fresh(secondFresh))
    }

    @Test func cancelledDelayedPortfolioRefreshCannotSaveAfterPurge() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let address = try makeRepositoryAddress()
        let fresh = makeRepositoryPortfolio(address: address, price: "2000")
        let store = WalletStoreSpy()
        let remote = TokenRemoteDataSourceSpy(
            portfolioResults: [address: .success(fresh)],
            gatedPortfolioAddresses: [address]
        )
        let repository = TokenRepository(
            remote: remote,
            store: store,
            dateProvider: fixedDate(now)
        )
        var iterator = repository
            .portfolio(address: address, policy: .force)
            .makeAsyncIterator()

        #expect(try await iterator.next() == .refreshing)
        await remote.waitUntilPortfolioRequested(address: address)

        let cancellation = Task {
            await repository.suspendPortfolioLoads(address: address)
        }
        await remote.waitUntilPortfolioCancelled(address: address)
        try await store.purgeAddressData(address: address)
        await remote.releasePortfolioRequest(address: address)
        await cancellation.value

        #expect(try await iterator.next() == nil)
        #expect(try await store.loadPortfolio(address: address) == nil)
        #expect(await store.portfolioSaveDates[address] == nil)
    }

    @Test func cancellationDuringPortfolioSaveSuppressesFreshPublication() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let address = try makeRepositoryAddress()
        let fresh = makeRepositoryPortfolio(address: address, price: "2000")
        let store = WalletStoreSpy(gatedPortfolioSaveAddresses: [address])
        let remote = TokenRemoteDataSourceSpy(
            portfolioResults: [address: .success(fresh)]
        )
        let repository = TokenRepository(
            remote: remote,
            store: store,
            dateProvider: fixedDate(now)
        )
        var iterator = repository
            .portfolio(address: address, policy: .force)
            .makeAsyncIterator()

        #expect(try await iterator.next() == .refreshing)
        await store.waitUntilPortfolioSaveStarted(address: address)

        let cancellation = Task {
            await repository.suspendPortfolioLoads(address: address)
        }
        await store.waitUntilPortfolioSaveCancelled(address: address)
        await store.releasePortfolioSave(address: address)
        await cancellation.value

        #expect(try await iterator.next() == nil)
    }

    @Test func suspendedAddressRejectsPortfolioUntilResumed() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let address = try makeRepositoryAddress()
        let fresh = makeRepositoryPortfolio(address: address, price: "2000")
        let store = WalletStoreSpy()
        let remote = TokenRemoteDataSourceSpy(
            portfolioResults: [address: .success(fresh)]
        )
        let repository = TokenRepository(
            remote: remote,
            store: store,
            dateProvider: fixedDate(now)
        )

        await repository.suspendPortfolioLoads(address: address)
        var blocked = repository
            .portfolio(address: address, policy: .force)
            .makeAsyncIterator()

        #expect(try await blocked.next() == nil)
        #expect(await store.portfolioLoadCounts[address] == nil)
        #expect(await remote.portfolioCallCounts[address] == nil)

        await repository.resumePortfolioLoads(address: address)
        var resumed = repository
            .portfolio(address: address, policy: .force)
            .makeAsyncIterator()

        #expect(try await resumed.next() == .refreshing)
        #expect(try await resumed.next() == .fresh(fresh))
        #expect(await store.portfolioLoadCounts[address] == 1)
        #expect(await remote.portfolioCallCounts[address] == 1)
    }

    @Test func firstLoadAfterSettledSuspensionStartsFreshTask() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let address = try makeRepositoryAddress()
        let fresh = makeRepositoryPortfolio(address: address, price: "2000")
        let store = WalletStoreSpy()
        let cleanupGate = PortfolioTaskCleanupGate()
        let remote = TokenRemoteDataSourceSpy(
            portfolioResults: [address: .success(fresh)],
            gatedPortfolioAddresses: [address]
        )
        let repository = TokenRepository(
            remote: remote,
            store: store,
            dateProvider: fixedDate(now),
            beforePortfolioTaskCleanup: { _ in
                await cleanupGate.holdFirstCleanup()
            }
        )
        var initial = repository
            .portfolio(address: address, policy: .force)
            .makeAsyncIterator()
        #expect(try await initial.next() == .refreshing)
        await remote.waitUntilPortfolioRequested(address: address)

        let suspension = Task {
            await repository.suspendPortfolioLoads(address: address)
        }
        await remote.waitUntilPortfolioCancelled(address: address)
        await remote.releasePortfolioRequest(address: address)
        await cleanupGate.waitUntilFirstCleanupStarted()
        await suspension.value
        await repository.resumePortfolioLoads(address: address)

        var resumed = repository
            .portfolio(address: address, policy: .force)
            .makeAsyncIterator()
        #expect(try await resumed.next() == .refreshing)
        await remote.waitUntilPortfolioRequestCount(2, address: address)

        cleanupGate.releaseFirstCleanup()
        #expect(try await initial.next() == nil)
        #expect(repository.hasActivePortfolioTask(address: address))

        await remote.releasePortfolioRequest(address: address)
        #expect(try await resumed.next() == .fresh(fresh))
        #expect(await remote.portfolioCallCounts[address] == 2)
    }

    @Test func tokenMarketsRetryTwiceWithExactBackoffWithoutUsingStore() async throws {
        let address = try makeRepositoryAddress()
        let expected = makeTokenMarketPortfolio(address: address)
        let remote = ScriptedTokenMarketRemote(outcomes: [
            .apiFailure(.transport("offline")),
            .apiFailure(.http(status: 503, message: nil)),
            .success(expected)
        ])
        let store = WalletStoreSpy()
        let delays = MarketRetryDelayRecorder()
        let repository = TokenRepository(
            remote: remote,
            store: store,
            marketRetryDelay: { delay in await delays.record(delay) }
        )

        let value = try await repository.tokenMarkets(address: address)

        #expect(value == expected)
        #expect(remote.marketCallCount == 3)
        #expect(await delays.values == [.milliseconds(500), .seconds(1)])
        #expect(await store.portfolioLoadCounts.isEmpty)
        #expect(await store.portfolioSaveDates.isEmpty)
        #expect(await store.nativeSaveDates.isEmpty)
    }

    @Test func tokenMarketsRetriesEveryTransientErrorClass() async throws {
        let address = try makeRepositoryAddress()
        let expected = makeTokenMarketPortfolio(address: address)
        let errors: [APIError] = [
            .transport("offline"),
            .nonHTTPResponse,
            .http(status: 408, message: nil),
            .http(status: 429, message: nil),
            .http(status: 500, message: nil),
            .http(status: 599, message: nil)
        ]

        for error in errors {
            let remote = ScriptedTokenMarketRemote(outcomes: [
                .apiFailure(error),
                .success(expected)
            ])
            let repository = TokenRepository(
                remote: remote,
                store: WalletStoreSpy(),
                marketRetryDelay: { _ in }
            )

            #expect(try await repository.tokenMarkets(address: address) == expected)
            #expect(remote.marketCallCount == 2)
        }
    }

    @Test func tokenMarketsStopAfterThirdTransientFailure() async throws {
        let address = try makeRepositoryAddress()
        let remote = ScriptedTokenMarketRemote(outcomes: [
            .apiFailure(.transport("first")),
            .apiFailure(.transport("second")),
            .apiFailure(.transport("third")),
            .success(makeTokenMarketPortfolio(address: address))
        ])
        let delays = MarketRetryDelayRecorder()
        let repository = TokenRepository(
            remote: remote,
            store: WalletStoreSpy(),
            marketRetryDelay: { delay in await delays.record(delay) }
        )

        do {
            _ = try await repository.tokenMarkets(address: address)
            Issue.record("Expected the final transient error")
        } catch {
            #expect(error as? APIError == .transport("third"))
        }

        #expect(remote.marketCallCount == 3)
        #expect(await delays.values == [.milliseconds(500), .seconds(1)])
    }

    @Test func tokenMarketsFailImmediatelyForPermanentAndUnknownErrors() async throws {
        let address = try makeRepositoryAddress()
        let expected = makeTokenMarketPortfolio(address: address)
        let failures: [ScriptedTokenMarketRemote.Outcome] = [
            .apiFailure(.invalidRequest),
            .apiFailure(.invalidData),
            .apiFailure(.http(status: 404, message: nil)),
            .otherFailure
        ]

        for failure in failures {
            let remote = ScriptedTokenMarketRemote(outcomes: [
                failure,
                .success(expected)
            ])
            let delays = MarketRetryDelayRecorder()
            let repository = TokenRepository(
                remote: remote,
                store: WalletStoreSpy(),
                marketRetryDelay: { delay in await delays.record(delay) }
            )

            do {
                _ = try await repository.tokenMarkets(address: address)
                Issue.record("Expected a fail-fast market error")
            } catch {}

            #expect(remote.marketCallCount == 1)
            #expect(await delays.values.isEmpty)
        }
    }

    @Test func cancellationDuringMarketBackoffStopsRetries() async throws {
        let address = try makeRepositoryAddress()
        let remote = ScriptedTokenMarketRemote(outcomes: [
            .apiFailure(.transport("offline")),
            .success(makeTokenMarketPortfolio(address: address))
        ])
        let repository = TokenRepository(
            remote: remote,
            store: WalletStoreSpy()
        )

        let load = Task {
            try await repository.tokenMarkets(address: address)
        }
        while remote.marketCallCount == 0 { await Task.yield() }
        load.cancel()

        do {
            _ = try await load.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected cancellation, got \(error)")
        }

        #expect(remote.marketCallCount == 1)
    }

    @Test func simultaneousMarketRequestsShareOneAttemptChain() async throws {
        let address = try makeRepositoryAddress()
        let expected = makeTokenMarketPortfolio(address: address)
        // Two outcomes so a lost-coalescing regression reports the extra call
        // instead of starving the second request.
        let remote = ScriptedTokenMarketRemote(
            outcomes: [.success(expected), .success(expected)],
            isGated: true
        )
        let repository = TokenRepository(remote: remote, store: WalletStoreSpy())

        let first = Task { try await repository.tokenMarkets(address: address) }
        await remote.waitUntilGated()
        let second = Task { try await repository.tokenMarkets(address: address) }
        await Task.yield()
        remote.releaseGate()

        #expect(try await first.value == expected)
        #expect(try await second.value == expected)
        #expect(remote.marketCallCount == 1)
    }

    @Test func suspendedAddressSkipsMarketRequestEntirely() async throws {
        let address = try makeRepositoryAddress()
        let remote = ScriptedTokenMarketRemote(outcomes: [
            .success(makeTokenMarketPortfolio(address: address))
        ])
        let delays = MarketRetryDelayRecorder()
        let repository = TokenRepository(
            remote: remote,
            store: WalletStoreSpy(),
            marketRetryDelay: { delay in await delays.record(delay) }
        )

        await repository.suspendPortfolioLoads(address: address)

        do {
            _ = try await repository.tokenMarkets(address: address)
            Issue.record("Expected the suspended address to be rejected")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected cancellation, got \(error)")
        }

        #expect(remote.marketCallCount == 0)
        #expect(await delays.values.isEmpty)
    }

    @Test func suspendingDuringMarketBackoffStopsRemainingRetries() async throws {
        let address = try makeRepositoryAddress()
        let remote = ScriptedTokenMarketRemote(outcomes: [
            .apiFailure(.transport("offline")),
            .success(makeTokenMarketPortfolio(address: address))
        ])
        let repository = TokenRepository(
            remote: remote,
            store: WalletStoreSpy()
        )

        let load = Task { try await repository.tokenMarkets(address: address) }
        while remote.marketCallCount == 0 { await Task.yield() }
        await repository.suspendPortfolioLoads(address: address)

        do {
            _ = try await load.value
            Issue.record("Expected the suspended load to stop")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected cancellation, got \(error)")
        }

        #expect(remote.marketCallCount == 1)
    }

    private func fixedDate(_ date: Date) -> DateProvider {
        DateProvider(now: { date })
    }
}

@MainActor
private final class ScriptedTokenMarketRemote: TokenRemoteDataSourceProtocol {
    enum Outcome {
        case success(TokenMarketPortfolio)
        case apiFailure(APIError)
        case otherFailure
    }

    private var outcomes: [Outcome]
    private let isGated: Bool
    private var isReleased = false
    private var gates: [CheckedContinuation<Void, Never>] = []
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var marketCallCount = 0

    init(outcomes: [Outcome], isGated: Bool = false) {
        self.outcomes = outcomes
        self.isGated = isGated
    }

    func waitUntilGated() async {
        guard gates.isEmpty else { return }
        await withCheckedContinuation { gateWaiters.append($0) }
    }

    // Releases every parked call and lets later calls through, so a regression
    // that adds an extra request fails an expectation instead of hanging.
    func releaseGate() {
        isReleased = true
        let parked = gates
        gates = []
        parked.forEach { $0.resume() }
    }

    func fetchNativeTokens() async throws -> [WalletToken] {
        throw RepositoryTestError.remoteFailure
    }

    func fetchPortfolio(address: EVMAddress) async throws -> TokenPortfolio {
        throw RepositoryTestError.remoteFailure
    }

    func fetchTokenMarkets(address: EVMAddress) async throws -> TokenMarketPortfolio {
        marketCallCount += 1
        if isGated, !isReleased {
            await withCheckedContinuation { continuation in
                gates.append(continuation)
                let waiters = gateWaiters
                gateWaiters = []
                waiters.forEach { $0.resume() }
            }
        }
        switch outcomes.removeFirst() {
        case .success(let value):
            return value
        case .apiFailure(let error):
            throw error
        case .otherFailure:
            throw RepositoryTestError.remoteFailure
        }
    }
}

private actor MarketRetryDelayRecorder {
    private(set) var values: [Duration] = []

    func record(_ value: Duration) {
        values.append(value)
    }
}

@MainActor
private final class PortfolioTaskCleanupGate {
    private var shouldHold = true
    private var hasStarted = false
    private var holdContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func holdFirstCleanup() async {
        guard shouldHold else { return }
        shouldHold = false
        hasStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        await withCheckedContinuation { continuation in
            holdContinuation = continuation
        }
    }

    func waitUntilFirstCleanupStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstCleanup() {
        holdContinuation?.resume()
        holdContinuation = nil
    }
}
