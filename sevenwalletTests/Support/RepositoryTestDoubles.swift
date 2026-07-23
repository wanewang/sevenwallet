import Foundation
@testable import sevenwallet

enum RepositoryTestError: Swift.Error, Equatable, Sendable {
    case remoteFailure
    case storageReadFailure
    case storageWriteFailure
}

extension RepositoryTestError: LocalizedError {
    var errorDescription: String? {
        "Unable to load tokens."
    }
}

enum WalletSessionDependencyCall: Equatable, Sendable {
    case load
    case purge(EVMAddress)
    case delete(UUID)
}

actor WalletSessionCallRecorder {
    private(set) var calls: [WalletSessionDependencyCall] = []

    func record(_ call: WalletSessionDependencyCall) {
        calls.append(call)
    }
}

actor ScriptedSavedWalletStore: SavedWalletStoreProtocol {
    private var snapshot: SavedWalletSnapshot
    private var error: (any Error & Sendable)?
    private let recorder: WalletSessionCallRecorder?

    init(
        snapshot: SavedWalletSnapshot = .init(
            wallets: [],
            selectedWalletID: nil
        ),
        recorder: WalletSessionCallRecorder? = nil
    ) {
        self.snapshot = snapshot
        self.recorder = recorder
    }

    func loadSnapshot() async throws -> SavedWalletSnapshot {
        await recorder?.record(.load)
        if let error { throw error }
        return snapshot
    }

    func addAndSelect(_ wallet: SavedWallet) async throws -> SavedWalletSnapshot {
        if let error { throw error }
        snapshot = .init(
            wallets: snapshot.wallets + [wallet],
            selectedWalletID: wallet.id
        )
        return snapshot
    }

    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) async throws -> SavedWalletSnapshot {
        if let error { throw error }
        snapshot = .init(
            wallets: snapshot.wallets.map {
                guard $0.id == id else { return $0 }
                return SavedWallet(
                    id: $0.id,
                    name: name,
                    address: $0.address,
                    cardColor: cardColor,
                    createdAt: $0.createdAt
                )
            },
            selectedWalletID: snapshot.selectedWalletID
        )
        return snapshot
    }

    func delete(id: UUID) async throws -> SavedWalletSnapshot {
        await recorder?.record(.delete(id))
        if let error { throw error }
        let wallets = snapshot.wallets.filter { $0.id != id }
        snapshot = .init(
            wallets: wallets,
            selectedWalletID: wallets.first?.id
        )
        return snapshot
    }

    func setError(_ error: (any Error & Sendable)?) {
        self.error = error
    }
}

actor RecordingAddressCachePurger: AddressCachePurging {
    private(set) var addresses: [EVMAddress] = []
    private var error: (any Error & Sendable)?
    private let recorder: WalletSessionCallRecorder?

    init(recorder: WalletSessionCallRecorder? = nil) {
        self.recorder = recorder
    }

    func purgeAddressData(address: EVMAddress) async throws {
        await recorder?.record(.purge(address))
        if let error { throw error }
        addresses.append(address)
    }

    func setError(_ error: (any Error & Sendable)?) {
        self.error = error
    }
}

@MainActor
final class ScriptedTokenRepository: TokenRepositoryProtocol {
    typealias Event = RepositoryLoadEvent<[WalletToken]>

    struct Script: Sendable {
        let beforeGate: [Event]
        let afterGate: [Event]
        let error: RepositoryTestError?
        let isGated: Bool

        init(events: [Event], error: RepositoryTestError? = nil) {
            beforeGate = events
            afterGate = []
            self.error = error
            isGated = false
        }

        static func gated(
            before: [Event],
            after: [Event],
            error: RepositoryTestError? = nil
        ) -> Script {
            Script(
                beforeGate: before,
                afterGate: after,
                error: error,
                isGated: true
            )
        }

        private init(
            beforeGate: [Event],
            afterGate: [Event],
            error: RepositoryTestError?,
            isGated: Bool
        ) {
            self.beforeGate = beforeGate
            self.afterGate = afterGate
            self.error = error
            self.isGated = isGated
        }
    }

    private struct Gate {
        let continuation: AsyncThrowingStream<Event, Swift.Error>.Continuation
        let events: [Event]
        let error: RepositoryTestError?
    }

    private var scripts: [Script]
    private var gates: [Int: Gate] = [:]
    private var gateWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var requestedPolicies: [RefreshPolicy] = []

    init(events: [Event], error: RepositoryTestError? = nil) {
        scripts = [Script(events: events, error: error)]
    }

    init(scripts: [Script]) {
        self.scripts = scripts
    }

    func nativeTokens(
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<Event, Swift.Error> {
        let requestIndex = requestedPolicies.count
        requestedPolicies.append(policy)
        let script = scripts.removeFirst()
        return AsyncThrowingStream<Event, Swift.Error> { continuation in
            for event in script.beforeGate {
                continuation.yield(event)
            }
            if script.isGated {
                gates[requestIndex] = Gate(
                    continuation: continuation,
                    events: script.afterGate,
                    error: script.error
                )
                let waiters = gateWaiters.removeValue(forKey: requestIndex) ?? []
                waiters.forEach { $0.resume() }
            } else {
                finish(continuation, error: script.error)
            }
        }
    }

    func portfolio(
        address: EVMAddress,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<RepositoryLoadEvent<TokenPortfolio>, Swift.Error> {
        AsyncThrowingStream<RepositoryLoadEvent<TokenPortfolio>, Swift.Error> {
            $0.finish()
        }
    }

    func waitUntilGated(request requestIndex: Int = 0) async {
        guard gates[requestIndex] == nil else { return }
        await withCheckedContinuation { continuation in
            gateWaiters[requestIndex, default: []].append(continuation)
        }
    }

    func releaseGate(request requestIndex: Int = 0) {
        guard let gate = gates.removeValue(forKey: requestIndex) else { return }
        for event in gate.events {
            gate.continuation.yield(event)
        }
        finish(gate.continuation, error: gate.error)
    }

    private func finish(
        _ continuation: AsyncThrowingStream<Event, Swift.Error>.Continuation,
        error: RepositoryTestError?
    ) {
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

final class ScriptedDateProvider: @unchecked Sendable {
    private var dates: [Date]

    init(_ dates: [Date]) {
        self.dates = dates
    }

    var provider: DateProvider {
        DateProvider { [self] in dates.removeFirst() }
    }
}

struct TransactionRequest: Hashable, Sendable {
    let address: EVMAddress
    let limit: Int
    let pageKey: String?
}

actor TokenRemoteDataSourceSpy: TokenRemoteDataSourceProtocol {
    private let nativeResult: Result<[WalletToken], RepositoryTestError>
    private let portfolioResults: [EVMAddress: Result<TokenPortfolio, RepositoryTestError>]
    private let gatesNativeRequest: Bool
    private let gatedPortfolioAddresses: Set<EVMAddress>
    private var nativeContinuations: [CheckedContinuation<[WalletToken], Swift.Error>] = []
    private var portfolioContinuations: [EVMAddress: [CheckedContinuation<TokenPortfolio, Swift.Error>]] = [:]

    private(set) var nativeCallCount = 0
    private(set) var portfolioCallCounts: [EVMAddress: Int] = [:]

    init(
        nativeResult: Result<[WalletToken], RepositoryTestError> = .success([]),
        portfolioResults: [EVMAddress: Result<TokenPortfolio, RepositoryTestError>] = [:],
        gatesNativeRequest: Bool = false,
        gatedPortfolioAddresses: Set<EVMAddress> = []
    ) {
        self.nativeResult = nativeResult
        self.portfolioResults = portfolioResults
        self.gatesNativeRequest = gatesNativeRequest
        self.gatedPortfolioAddresses = gatedPortfolioAddresses
    }

    func fetchNativeTokens() async throws -> [WalletToken] {
        nativeCallCount += 1
        guard gatesNativeRequest else { return try nativeResult.get() }
        return try await withCheckedThrowingContinuation { continuation in
            nativeContinuations.append(continuation)
        }
    }

    func fetchPortfolio(address: EVMAddress) async throws -> TokenPortfolio {
        portfolioCallCounts[address, default: 0] += 1
        guard gatedPortfolioAddresses.contains(address) else {
            return try result(for: address).get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            portfolioContinuations[address, default: []].append(continuation)
        }
    }

    func releaseNativeRequest() {
        let continuations = nativeContinuations
        nativeContinuations.removeAll()
        continuations.forEach { $0.resume(with: nativeResult) }
    }

    func releasePortfolioRequest(address: EVMAddress) {
        let continuations = portfolioContinuations.removeValue(forKey: address) ?? []
        let result = result(for: address)
        continuations.forEach { $0.resume(with: result) }
    }

    private func result(for address: EVMAddress) -> Result<TokenPortfolio, RepositoryTestError> {
        portfolioResults[address] ?? .failure(.remoteFailure)
    }
}

actor TransactionRemoteDataSourceSpy: TransactionRemoteDataSourceProtocol {
    private let results: [TransactionRequest: Result<TransactionPage, RepositoryTestError>]
    private let gatedRequests: Set<TransactionRequest>
    private var continuations: [TransactionRequest: [CheckedContinuation<TransactionPage, Swift.Error>]] = [:]

    private(set) var callCount = 0
    private(set) var callCounts: [TransactionRequest: Int] = [:]

    init(
        results: [TransactionRequest: Result<TransactionPage, RepositoryTestError>] = [:],
        gatedRequests: Set<TransactionRequest> = []
    ) {
        self.results = results
        self.gatedRequests = gatedRequests
    }

    func fetchTransactions(address: EVMAddress, limit: Int, pageKey: String?) async throws -> TransactionPage {
        let request = TransactionRequest(address: address, limit: limit, pageKey: pageKey)
        callCount += 1
        callCounts[request, default: 0] += 1
        guard gatedRequests.contains(request) else {
            return try result(for: request).get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[request, default: []].append(continuation)
        }
    }

    func releaseRequest(_ request: TransactionRequest) {
        let continuations = continuations.removeValue(forKey: request) ?? []
        let result = result(for: request)
        continuations.forEach { $0.resume(with: result) }
    }

    private func result(for request: TransactionRequest) -> Result<TransactionPage, RepositoryTestError> {
        results[request] ?? .failure(.remoteFailure)
    }
}

actor WalletStoreSpy: WalletStoreProtocol {
    private var nativeCache: CachedResource<[WalletToken]>?
    private var portfolioCaches: [EVMAddress: CachedResource<TokenPortfolio>]
    private var transactionCaches: [TransactionRequest: CachedResource<TransactionPage>]

    private(set) var nativeSaveDates: [Date] = []
    private(set) var portfolioSaveDates: [EVMAddress: [Date]] = [:]
    private(set) var transactionSaveDates: [TransactionRequest: [Date]] = [:]
    private(set) var transactionLoadCount = 0

    init(
        nativeCache: CachedResource<[WalletToken]>? = nil,
        portfolioCaches: [EVMAddress: CachedResource<TokenPortfolio>] = [:],
        transactionCaches: [TransactionRequest: CachedResource<TransactionPage>] = [:]
    ) {
        self.nativeCache = nativeCache
        self.portfolioCaches = portfolioCaches
        self.transactionCaches = transactionCaches
    }

    func loadNativeTokens() async throws -> CachedResource<[WalletToken]>? {
        nativeCache
    }

    func saveNativeTokens(_ value: [WalletToken], fetchedAt: Date) async throws {
        nativeCache = CachedResource(value: value, fetchedAt: fetchedAt)
        nativeSaveDates.append(fetchedAt)
    }

    func loadPortfolio(address: EVMAddress) async throws -> CachedResource<TokenPortfolio>? {
        portfolioCaches[address]
    }

    func savePortfolio(_ value: TokenPortfolio, fetchedAt: Date) async throws {
        portfolioCaches[value.address] = CachedResource(value: value, fetchedAt: fetchedAt)
        portfolioSaveDates[value.address, default: []].append(fetchedAt)
    }

    func loadTransactionPage(
        address: EVMAddress,
        limit: Int,
        pageKey: String?
    ) async throws -> CachedResource<TransactionPage>? {
        transactionLoadCount += 1
        return transactionCaches[TransactionRequest(address: address, limit: limit, pageKey: pageKey)]
    }

    func saveTransactionPage(
        _ value: TransactionPage,
        limit: Int,
        pageKey: String?,
        fetchedAt: Date
    ) async throws {
        let request = TransactionRequest(address: value.address, limit: limit, pageKey: pageKey)
        transactionCaches[request] = CachedResource(value: value, fetchedAt: fetchedAt)
        transactionSaveDates[request, default: []].append(fetchedAt)
    }
}

actor FailingWalletStore: WalletStoreProtocol {
    private let readError: RepositoryTestError?
    private let writeError: RepositoryTestError?

    init(
        readError: RepositoryTestError? = nil,
        writeError: RepositoryTestError? = nil
    ) {
        self.readError = readError
        self.writeError = writeError
    }

    func loadNativeTokens() async throws -> CachedResource<[WalletToken]>? {
        if let readError { throw readError }
        return nil
    }

    func saveNativeTokens(_ value: [WalletToken], fetchedAt: Date) async throws {
        if let writeError { throw writeError }
    }

    func loadPortfolio(address: EVMAddress) async throws -> CachedResource<TokenPortfolio>? {
        if let readError { throw readError }
        return nil
    }

    func savePortfolio(_ value: TokenPortfolio, fetchedAt: Date) async throws {
        if let writeError { throw writeError }
    }

    func loadTransactionPage(
        address: EVMAddress,
        limit: Int,
        pageKey: String?
    ) async throws -> CachedResource<TransactionPage>? {
        if let readError { throw readError }
        return nil
    }

    func saveTransactionPage(
        _ value: TransactionPage,
        limit: Int,
        pageKey: String?,
        fetchedAt: Date
    ) async throws {
        if let writeError { throw writeError }
    }
}

struct StreamRecording<Value> {
    let values: [Value]
    let error: RepositoryTestError?
}

func collect<Value: Sendable>(
    _ stream: AsyncThrowingStream<Value, Swift.Error>
) async throws -> [Value] {
    var values: [Value] = []
    for try await value in stream {
        values.append(value)
    }
    return values
}

func record<Value: Sendable>(
    _ stream: AsyncThrowingStream<Value, Swift.Error>
) async -> StreamRecording<Value> {
    var values: [Value] = []
    do {
        for try await value in stream {
            values.append(value)
        }
        return StreamRecording(values: values, error: nil)
    } catch {
        return StreamRecording(values: values, error: error as? RepositoryTestError)
    }
}

func makeRepositoryToken(price: String) -> WalletToken {
    WalletToken(
        tokenAddress: nil,
        symbol: "ETH",
        name: "Ether",
        decimals: 18,
        rawBalance: "1000000000000000000",
        balance: 1,
        isNative: true,
        price: TokenPrice(currency: "USD", value: Decimal(string: price), lastUpdatedAt: nil),
        logoURL: nil,
        coinKey: "ethereum",
        priceUSD: Decimal(string: price)
    )
}

func makeRepositoryAddress(_ suffix: String = "71a2b3c4d5e6f7890a1b2c3d4e5f67890abc8f92") throws -> EVMAddress {
    try EVMAddress("0x\(suffix)")
}

func makeRepositoryPortfolio(address: EVMAddress, price: String) -> TokenPortfolio {
    TokenPortfolio(
        address: address,
        fetchedAt: nil,
        network: "ethereum",
        tokens: [makeRepositoryToken(price: price)]
    )
}

func makeRepositoryTransactionPage(address: EVMAddress, nextPageKey: String? = nil) -> TransactionPage {
    TransactionPage(
        address: address,
        nextPageKey: nextPageKey,
        transfers: [
            WalletTransfer(
                asset: "ETH",
                blockNumber: "1",
                category: "external",
                from: "0xfrom",
                hash: "0xhash",
                to: "0xto",
                value: "1"
            )
        ]
    )
}
