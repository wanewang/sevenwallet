import Foundation
@testable import sevenwallet

enum RepositoryTestError: Swift.Error, Equatable, Sendable {
    case remoteFailure
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
