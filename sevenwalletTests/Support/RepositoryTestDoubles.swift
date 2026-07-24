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
    case suspendPortfolio(EVMAddress)
    case resumePortfolio(EVMAddress)
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
    private let isAddGated: Bool
    private let isUpdateGated: Bool
    private let isDeleteGated: Bool
    private var addContinuation: CheckedContinuation<Void, Never>?
    private var addWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasStartedAdd = false
    private var updateContinuation: CheckedContinuation<Void, Never>?
    private var updateWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasStartedUpdate = false
    private var deleteContinuation: CheckedContinuation<Void, Never>?
    private var deleteWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasStartedDelete = false

    init(
        snapshot: SavedWalletSnapshot = .init(
            wallets: [],
            selectedWalletID: nil
        ),
        recorder: WalletSessionCallRecorder? = nil,
        isAddGated: Bool = false,
        isUpdateGated: Bool = false,
        isDeleteGated: Bool = false
    ) {
        self.snapshot = snapshot
        self.recorder = recorder
        self.isAddGated = isAddGated
        self.isUpdateGated = isUpdateGated
        self.isDeleteGated = isDeleteGated
    }

    func loadSnapshot() async throws -> SavedWalletSnapshot {
        await recorder?.record(.load)
        if let error { throw error }
        return snapshot
    }

    func addAndSelect(_ wallet: SavedWallet) async throws -> SavedWalletSnapshot {
        hasStartedAdd = true
        addWaiters.forEach { $0.resume() }
        addWaiters = []
        if isAddGated {
            await withCheckedContinuation { continuation in
                addContinuation = continuation
            }
        }
        if let error { throw error }
        snapshot = .init(
            wallets: snapshot.wallets + [wallet],
            selectedWalletID: wallet.id
        )
        return snapshot
    }

    func waitUntilAddStarted() async {
        guard !hasStartedAdd else { return }
        await withCheckedContinuation { continuation in
            addWaiters.append(continuation)
        }
    }

    func releaseAdd() {
        addContinuation?.resume()
        addContinuation = nil
    }

    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) async throws -> SavedWalletSnapshot {
        hasStartedUpdate = true
        updateWaiters.forEach { $0.resume() }
        updateWaiters = []
        if isUpdateGated {
            await withCheckedContinuation { continuation in
                updateContinuation = continuation
            }
        }
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

    func waitUntilUpdateStarted() async {
        guard !hasStartedUpdate else { return }
        await withCheckedContinuation { continuation in
            updateWaiters.append(continuation)
        }
    }

    func releaseUpdate() {
        updateContinuation?.resume()
        updateContinuation = nil
    }

    func delete(id: UUID) async throws -> SavedWalletSnapshot {
        await recorder?.record(.delete(id))
        hasStartedDelete = true
        deleteWaiters.forEach { $0.resume() }
        deleteWaiters = []
        if isDeleteGated {
            await withCheckedContinuation { continuation in
                deleteContinuation = continuation
            }
        }
        if let error { throw error }
        let wallets = snapshot.wallets.filter { $0.id != id }
        snapshot = .init(
            wallets: wallets,
            selectedWalletID: wallets.first?.id
        )
        return snapshot
    }

    func waitUntilDeleteStarted() async {
        guard !hasStartedDelete else { return }
        await withCheckedContinuation { continuation in
            deleteWaiters.append(continuation)
        }
    }

    func releaseDelete() {
        deleteContinuation?.resume()
        deleteContinuation = nil
    }

    func setError(_ error: (any Error & Sendable)?) {
        self.error = error
    }
}

actor RecordingAddressCachePurger: AddressCachePurging {
    private(set) var addresses: [EVMAddress] = []
    private var error: (any Error & Sendable)?
    private let recorder: WalletSessionCallRecorder?
    private let isGated: Bool
    private var purgeContinuation: CheckedContinuation<Void, Never>?
    private var purgeWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasStartedPurge = false

    init(
        recorder: WalletSessionCallRecorder? = nil,
        isGated: Bool = false
    ) {
        self.recorder = recorder
        self.isGated = isGated
    }

    func purgeAddressData(address: EVMAddress) async throws {
        await recorder?.record(.purge(address))
        hasStartedPurge = true
        purgeWaiters.forEach { $0.resume() }
        purgeWaiters = []
        if isGated {
            await withCheckedContinuation { continuation in
                purgeContinuation = continuation
            }
        }
        if let error { throw error }
        addresses.append(address)
    }

    func waitUntilPurgeStarted() async {
        guard !hasStartedPurge else { return }
        await withCheckedContinuation { continuation in
            purgeWaiters.append(continuation)
        }
    }

    func releasePurge() {
        purgeContinuation?.resume()
        purgeContinuation = nil
    }

    func setError(_ error: (any Error & Sendable)?) {
        self.error = error
    }
}

actor RecordingPortfolioLoadController: PortfolioLoadControlling {
    private let recorder: WalletSessionCallRecorder?
    private let isResumeGated: Bool
    private var suspendedAddresses: Set<EVMAddress> = []
    private var resumeContinuations: [
        EVMAddress: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var resumeWaiters: [
        EVMAddress: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var startedResumes: Set<EVMAddress> = []

    init(
        recorder: WalletSessionCallRecorder? = nil,
        isResumeGated: Bool = false
    ) {
        self.recorder = recorder
        self.isResumeGated = isResumeGated
    }

    func suspendPortfolioLoads(address: EVMAddress) async {
        await recorder?.record(.suspendPortfolio(address))
        suspendedAddresses.insert(address)
    }

    func resumePortfolioLoads(address: EVMAddress) async {
        await recorder?.record(.resumePortfolio(address))
        startedResumes.insert(address)
        let waiters = resumeWaiters.removeValue(forKey: address) ?? []
        waiters.forEach { $0.resume() }
        if isResumeGated {
            await withCheckedContinuation { continuation in
                resumeContinuations[address, default: []].append(continuation)
            }
        }
        suspendedAddresses.remove(address)
    }

    func waitUntilResumeStarted(address: EVMAddress) async {
        guard !startedResumes.contains(address) else { return }
        await withCheckedContinuation { continuation in
            resumeWaiters[address, default: []].append(continuation)
        }
    }

    func releaseResume(address: EVMAddress) {
        let continuations = resumeContinuations.removeValue(
            forKey: address
        ) ?? []
        continuations.forEach { $0.resume() }
    }

    func isSuspended(address: EVMAddress) -> Bool {
        suspendedAddresses.contains(address)
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

@MainActor
final class PortfolioTokenRepositorySpy: TokenRepositoryProtocol {
    typealias NativeEvent = RepositoryLoadEvent<[WalletToken]>
    typealias PortfolioEvent = RepositoryLoadEvent<TokenPortfolio>

    struct PortfolioScript: Sendable {
        let beforeGate: [PortfolioEvent]
        let afterGate: [PortfolioEvent]
        let error: RepositoryTestError?
        let isGated: Bool
        let holdsOpen: Bool

        init(
            events: [PortfolioEvent],
            error: RepositoryTestError? = nil,
            holdsOpen: Bool = false
        ) {
            beforeGate = events
            afterGate = []
            self.error = error
            isGated = false
            self.holdsOpen = holdsOpen
        }

        static func gated(
            before: [PortfolioEvent],
            after: [PortfolioEvent],
            error: RepositoryTestError? = nil
        ) -> PortfolioScript {
            PortfolioScript(
                beforeGate: before,
                afterGate: after,
                error: error,
                isGated: true,
                holdsOpen: false
            )
        }

        private init(
            beforeGate: [PortfolioEvent],
            afterGate: [PortfolioEvent],
            error: RepositoryTestError?,
            isGated: Bool,
            holdsOpen: Bool
        ) {
            self.beforeGate = beforeGate
            self.afterGate = afterGate
            self.error = error
            self.isGated = isGated
            self.holdsOpen = holdsOpen
        }
    }

    private struct PortfolioGate {
        let continuation: AsyncThrowingStream<
            PortfolioEvent,
            Swift.Error
        >.Continuation
        let events: [PortfolioEvent]
        let error: RepositoryTestError?
    }

    private var nativeScripts: [[NativeEvent]]
    private var portfolioScripts: [PortfolioScript]
    private var portfolioGates: [Int: PortfolioGate] = [:]
    private var portfolioGateWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var portfolioTerminationWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var requestedNativePolicies: [RefreshPolicy] = []
    private(set) var requestedPortfolioAddresses: [EVMAddress] = []
    private(set) var requestedPortfolioPolicies: [RefreshPolicy] = []
    private(set) var terminatedPortfolioRequests: Set<Int> = []

    init(
        nativeScripts: [[NativeEvent]] = [],
        portfolioScripts: [[PortfolioEvent]] = [],
        holdsPortfolioOpen: Bool = false
    ) {
        self.nativeScripts = nativeScripts
        self.portfolioScripts = portfolioScripts.map {
            PortfolioScript(events: $0, holdsOpen: holdsPortfolioOpen)
        }
    }

    init(
        nativeScripts: [[NativeEvent]] = [],
        portfolioRequestScripts: [PortfolioScript]
    ) {
        self.nativeScripts = nativeScripts
        portfolioScripts = portfolioRequestScripts
    }

    func nativeTokens(
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<NativeEvent, Swift.Error> {
        requestedNativePolicies.append(policy)
        return stream(events: nativeScripts.removeFirst(), holdsOpen: false)
    }

    func portfolio(
        address: EVMAddress,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<PortfolioEvent, Swift.Error> {
        let requestIndex = requestedPortfolioAddresses.count
        requestedPortfolioAddresses.append(address)
        requestedPortfolioPolicies.append(policy)
        let script = portfolioScripts.removeFirst()
        let repository = self

        return AsyncThrowingStream { continuation in
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    repository.recordPortfolioTermination(request: requestIndex)
                }
            }
            for event in script.beforeGate {
                continuation.yield(event)
            }
            if script.isGated {
                portfolioGates[requestIndex] = PortfolioGate(
                    continuation: continuation,
                    events: script.afterGate,
                    error: script.error
                )
                let waiters = portfolioGateWaiters.removeValue(
                    forKey: requestIndex
                ) ?? []
                waiters.forEach { $0.resume() }
            } else if !script.holdsOpen {
                finish(continuation, error: script.error)
            }
        }
    }

    func waitUntilPortfolioGated(request requestIndex: Int = 0) async {
        guard portfolioGates[requestIndex] == nil else { return }
        await withCheckedContinuation { continuation in
            portfolioGateWaiters[requestIndex, default: []].append(continuation)
        }
    }

    func releasePortfolioGate(request requestIndex: Int = 0) {
        guard let gate = portfolioGates.removeValue(forKey: requestIndex) else {
            return
        }
        for event in gate.events {
            gate.continuation.yield(event)
        }
        finish(gate.continuation, error: gate.error)
    }

    func waitUntilPortfolioTerminated(request requestIndex: Int = 0) async {
        guard !terminatedPortfolioRequests.contains(requestIndex) else { return }
        await withCheckedContinuation { continuation in
            portfolioTerminationWaiters[requestIndex, default: []].append(
                continuation
            )
        }
    }

    private func stream<Value: Sendable>(
        events: [RepositoryLoadEvent<Value>],
        holdsOpen: Bool
    ) -> AsyncThrowingStream<RepositoryLoadEvent<Value>, Swift.Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if !holdsOpen { continuation.finish() }
        }
    }

    private func finish(
        _ continuation: AsyncThrowingStream<
            PortfolioEvent,
            Swift.Error
        >.Continuation,
        error: RepositoryTestError?
    ) {
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }

    private func recordPortfolioTermination(request requestIndex: Int) {
        portfolioGates.removeValue(forKey: requestIndex)
        terminatedPortfolioRequests.insert(requestIndex)
        let waiters = portfolioTerminationWaiters.removeValue(
            forKey: requestIndex
        ) ?? []
        waiters.forEach { $0.resume() }
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
    private let gatedPortfolioRequestCounts: [EVMAddress: Int]
    private var nativeContinuations: [CheckedContinuation<[WalletToken], Swift.Error>] = []
    private var portfolioContinuations: [EVMAddress: [CheckedContinuation<TokenPortfolio, Swift.Error>]] = [:]
    private var portfolioRequestWaiters: [EVMAddress: [CheckedContinuation<Void, Never>]] = [:]
    private var portfolioRequestCountWaiters: [
        EVMAddress: [Int: [CheckedContinuation<Void, Never>]]
    ] = [:]
    private var cancelledPortfolioAddresses: Set<EVMAddress> = []
    private var portfolioCancellationWaiters: [EVMAddress: [CheckedContinuation<Void, Never>]] = [:]

    private(set) var nativeCallCount = 0
    private(set) var portfolioCallCounts: [EVMAddress: Int] = [:]

    init(
        nativeResult: Result<[WalletToken], RepositoryTestError> = .success([]),
        portfolioResults: [EVMAddress: Result<TokenPortfolio, RepositoryTestError>] = [:],
        gatesNativeRequest: Bool = false,
        gatedPortfolioAddresses: Set<EVMAddress> = [],
        gatedPortfolioRequestCounts: [EVMAddress: Int] = [:]
    ) {
        self.nativeResult = nativeResult
        self.portfolioResults = portfolioResults
        self.gatesNativeRequest = gatesNativeRequest
        self.gatedPortfolioAddresses = gatedPortfolioAddresses
        self.gatedPortfolioRequestCounts = gatedPortfolioRequestCounts
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
        let callCount = portfolioCallCounts[address, default: 0]
        let requestWaiters = portfolioRequestWaiters.removeValue(forKey: address) ?? []
        requestWaiters.forEach { $0.resume() }
        let countWaiters = portfolioRequestCountWaiters[address]?
            .removeValue(forKey: callCount) ?? []
        countWaiters.forEach { $0.resume() }
        let shouldGate = gatedPortfolioAddresses.contains(address)
            || callCount <= gatedPortfolioRequestCounts[address, default: 0]
        guard shouldGate else {
            return try result(for: address).get()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                portfolioContinuations[address, default: []].append(continuation)
            }
        } onCancel: {
            Task { await self.recordPortfolioCancellation(address: address) }
        }
    }

    func waitUntilPortfolioRequested(address: EVMAddress) async {
        guard portfolioCallCounts[address, default: 0] == 0 else { return }
        await withCheckedContinuation { continuation in
            portfolioRequestWaiters[address, default: []].append(continuation)
        }
    }

    func waitUntilPortfolioRequestCount(
        _ count: Int,
        address: EVMAddress
    ) async {
        guard portfolioCallCounts[address, default: 0] < count else { return }
        await withCheckedContinuation { continuation in
            portfolioRequestCountWaiters[address, default: [:]][
                count,
                default: []
            ].append(continuation)
        }
    }

    func waitUntilPortfolioCancelled(address: EVMAddress) async {
        guard !cancelledPortfolioAddresses.contains(address) else { return }
        await withCheckedContinuation { continuation in
            portfolioCancellationWaiters[address, default: []].append(continuation)
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

    private func recordPortfolioCancellation(address: EVMAddress) {
        cancelledPortfolioAddresses.insert(address)
        let waiters = portfolioCancellationWaiters.removeValue(forKey: address) ?? []
        waiters.forEach { $0.resume() }
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

actor WalletStoreSpy: WalletStoreProtocol, AddressCachePurging {
    private var nativeCache: CachedResource<[WalletToken]>?
    private var portfolioCaches: [EVMAddress: CachedResource<TokenPortfolio>]
    private var transactionCaches: [TransactionRequest: CachedResource<TransactionPage>]
    private let gatedPortfolioSaveAddresses: Set<EVMAddress>
    private var portfolioSaveContinuations: [
        EVMAddress: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var portfolioSaveWaiters: [
        EVMAddress: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var startedPortfolioSaves: Set<EVMAddress> = []
    private var cancelledPortfolioSaves: Set<EVMAddress> = []
    private var portfolioSaveCancellationWaiters: [
        EVMAddress: [CheckedContinuation<Void, Never>]
    ] = [:]

    private(set) var nativeSaveDates: [Date] = []
    private(set) var portfolioSaveDates: [EVMAddress: [Date]] = [:]
    private(set) var transactionSaveDates: [TransactionRequest: [Date]] = [:]
    private(set) var transactionLoadCount = 0
    private(set) var portfolioLoadCounts: [EVMAddress: Int] = [:]

    init(
        nativeCache: CachedResource<[WalletToken]>? = nil,
        portfolioCaches: [EVMAddress: CachedResource<TokenPortfolio>] = [:],
        transactionCaches: [TransactionRequest: CachedResource<TransactionPage>] = [:],
        gatedPortfolioSaveAddresses: Set<EVMAddress> = []
    ) {
        self.nativeCache = nativeCache
        self.portfolioCaches = portfolioCaches
        self.transactionCaches = transactionCaches
        self.gatedPortfolioSaveAddresses = gatedPortfolioSaveAddresses
    }

    func loadNativeTokens() async throws -> CachedResource<[WalletToken]>? {
        nativeCache
    }

    func saveNativeTokens(_ value: [WalletToken], fetchedAt: Date) async throws {
        nativeCache = CachedResource(value: value, fetchedAt: fetchedAt)
        nativeSaveDates.append(fetchedAt)
    }

    func loadPortfolio(address: EVMAddress) async throws -> CachedResource<TokenPortfolio>? {
        portfolioLoadCounts[address, default: 0] += 1
        return portfolioCaches[address]
    }

    func savePortfolio(_ value: TokenPortfolio, fetchedAt: Date) async throws {
        if gatedPortfolioSaveAddresses.contains(value.address) {
            startedPortfolioSaves.insert(value.address)
            let waiters = portfolioSaveWaiters.removeValue(
                forKey: value.address
            ) ?? []
            waiters.forEach { $0.resume() }
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    portfolioSaveContinuations[
                        value.address,
                        default: []
                    ].append(continuation)
                }
            } onCancel: {
                Task {
                    await self.recordPortfolioSaveCancellation(
                        address: value.address
                    )
                }
            }
        }
        portfolioCaches[value.address] = CachedResource(value: value, fetchedAt: fetchedAt)
        portfolioSaveDates[value.address, default: []].append(fetchedAt)
    }

    func waitUntilPortfolioSaveStarted(address: EVMAddress) async {
        guard !startedPortfolioSaves.contains(address) else { return }
        await withCheckedContinuation { continuation in
            portfolioSaveWaiters[address, default: []].append(continuation)
        }
    }

    func releasePortfolioSave(address: EVMAddress) {
        let continuations = portfolioSaveContinuations.removeValue(
            forKey: address
        ) ?? []
        continuations.forEach { $0.resume() }
    }

    func waitUntilPortfolioSaveCancelled(address: EVMAddress) async {
        guard !cancelledPortfolioSaves.contains(address) else { return }
        await withCheckedContinuation { continuation in
            portfolioSaveCancellationWaiters[address, default: []].append(
                continuation
            )
        }
    }

    private func recordPortfolioSaveCancellation(address: EVMAddress) {
        cancelledPortfolioSaves.insert(address)
        let waiters = portfolioSaveCancellationWaiters.removeValue(
            forKey: address
        ) ?? []
        waiters.forEach { $0.resume() }
    }

    func purgeAddressData(address: EVMAddress) async throws {
        portfolioCaches[address] = nil
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
        change24hPercent: nil,
        coinKey: "ethereum",
        marketCapUSD: nil,
        marketDataUpdatedAt: nil,
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
