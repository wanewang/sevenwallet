# Network Repository and Empty Wallet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded launch tokens with cache-first `/v1/native` data, implement SwiftData-backed repositories for every documented token and address operation, and show the approved no-wallet home state.

**Architecture:** A configuration object supplies an injected service origin to a URLSession API client. Feature-specific token and transaction repositories stream cached SwiftData snapshots before optional network refreshes and coalesce matching requests. `WalletHomeViewModel` consumes repository events and maps native-token domain values into SwiftUI.

**Tech Stack:** Swift 5 language mode, SwiftUI, Observation, SwiftData, Foundation URLSession, Swift Testing, XCTest UI testing, Xcode 26.3, iOS 26.2.

## Global Constraints

- Do not commit a real `BASE_URL` value or hardcode the service URL.
- Resolve `BASE_URL` from `ProcessInfo` first and generated Info.plist second; accept only absolute HTTP(S) origins without path, query, or fragment.
- Append `/v1` inside the client.
- Keep DTOs, domain values, SwiftData models, repositories, view models, and views separate.
- Use `Decimal` for API balance and USD-price values.
- Expire cache only when its successful-fetch age is greater than 30 minutes.
- The third pull inside a rolling 60-second window forces refresh and resets pull history.
- Coalesce matching in-flight requests.
- Implement `/v1/native`, `/v1/addresses/{address}/tokens`, and paginated `/v1/addresses/{address}/transactions`.
- Only `/v1/native` is consumed by the current UI; address import remains out of scope.
- Empty and populated wallet cards share a 212-point minimum height.
- Add no dependency or Fastlane setup; tests never contact the live service.

## File Map

Create focused files under `Configuration`, `Domain`, `Network`, `Persistence`, `Repository`, `Application`, and the existing `View` folders. Create matching focused test files under `sevenwalletTests` and update `sevenwalletUITests/sevenwalletUITests.swift`. The Xcode project uses file-system-synchronized groups, so new files under target directories require no manual PBX file references.

---

### Task 1: Runtime BASE_URL Configuration

**Files:**
- Create: `sevenwallet/Configuration/AppConfiguration.swift`
- Create: `sevenwalletTests/AppConfigurationTests.swift`
- Modify: `sevenwallet.xcodeproj/project.pbxproj:399-456`

**Interfaces:**
- Consumes: process environment and generated Info.plist dictionaries.
- Produces: `AppConfiguration.init(environment:infoDictionary:) throws` and `baseURL: URL`.

- [ ] **Step 1: Write failing configuration tests**

```swift
import Foundation
import Testing
@testable import sevenwallet

struct AppConfigurationTests {
    @Test func environmentWins() throws {
        let value = try AppConfiguration(
            environment: ["BASE_URL": "https://environment.example/"],
            infoDictionary: ["BASE_URL": "https://bundle.example"]
        )
        #expect(value.baseURL.absoluteString == "https://environment.example")
    }

    @Test func bundleSupportsArchiveInjection() throws {
        let value = try AppConfiguration(
            environment: [:],
            infoDictionary: ["BASE_URL": "https://archive.example"]
        )
        #expect(value.baseURL.absoluteString == "https://archive.example")
    }

    @Test(arguments: ["", "wallet.example", "ftp://wallet.example", "https://wallet.example/path", "https://wallet.example?x=1", "https://wallet.example#x"])
    func invalidOriginsFail(_ raw: String) {
        #expect(throws: AppConfiguration.Error.self) {
            try AppConfiguration(environment: ["BASE_URL": raw], infoDictionary: [:])
        }
    }

    @Test func missingOriginIsTyped() {
        #expect(throws: AppConfiguration.Error.missingBaseURL) {
            try AppConfiguration(environment: [:], infoDictionary: [:])
        }
    }
}
```

- [ ] **Step 2: Run the focused suite and verify failure**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletTests/AppConfigurationTests -parallel-testing-enabled NO test
```

Expected: build fails because `AppConfiguration` is undefined.

- [ ] **Step 3: Implement strict origin resolution**

```swift
import Foundation

struct AppConfiguration: Sendable {
    enum Error: Swift.Error, Equatable {
        case missingBaseURL
        case invalidBaseURL(String)
    }

    let baseURL: URL

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) throws {
        let environmentValue = environment["BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleValue = (infoDictionary["BASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = [environmentValue, bundleValue].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw Error.missingBaseURL
        }
        guard var parts = URLComponents(string: raw),
              let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              parts.host != nil,
              parts.user == nil,
              parts.password == nil,
              parts.query == nil,
              parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else {
            throw Error.invalidBaseURL(raw)
        }
        parts.path = ""
        guard let url = parts.url else { throw Error.invalidBaseURL(raw) }
        baseURL = url
    }
}
```

Add this expansion wiring to both app-target build configurations, without a URL value:

```text
INFOPLIST_KEY_BASE_URL = "$(BASE_URL)";
```

- [ ] **Step 4: Verify tests and build-setting injection**

Run Step 2, then:

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -configuration Release -showBuildSettings BASE_URL=https://archive.example
```

Expected: tests pass and build settings show the command-line URL expanded into `INFOPLIST_KEY_BASE_URL`.

- [ ] **Step 5: Commit**

```bash
git add sevenwallet/Configuration/AppConfiguration.swift sevenwalletTests/AppConfigurationTests.swift sevenwallet.xcodeproj/project.pbxproj
git commit -m "feat: add runtime API configuration"
```

---

### Task 2: Domain Values, EVM Validation, and Decimal Formatting

**Files:**
- Create: `sevenwallet/Domain/EVMAddress.swift`
- Create: `sevenwallet/Domain/WalletAPIModels.swift`
- Create: `sevenwalletTests/WalletAPIModelsTests.swift`
- Modify: `sevenwallet/Theme/Formatting.swift:8-35`
- Modify: `sevenwalletTests/FormattingTests.swift`

**Interfaces:**
- Consumes: address and numeric strings.
- Produces: `EVMAddress`, `WalletToken`, `TokenPrice`, `TokenPortfolio`, `WalletTransfer`, `TransactionPage`, and Decimal `Fmt` overloads.

- [ ] **Step 1: Write failing validation and formatting tests**

```swift
import Foundation
import Testing
@testable import sevenwallet

struct WalletAPIModelsTests {
    @Test func addressNormalizes() throws {
        let address = try EVMAddress("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
        #expect(address.rawValue == "0x71a2b3c4d5e6f7890a1b2c3d4e5f67890abc8f92")
    }

    @Test(arguments: ["", "71a2", "0x1234", "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F9Z"])
    func invalidAddressFails(_ raw: String) {
        #expect(throws: EVMAddress.Error.invalid(raw)) { try EVMAddress(raw) }
    }
}
```

Add to `FormattingTests`:

```swift
@Test func decimalFormattingIsExact() {
    #expect(Fmt.usd(Decimal(string: "1926.42")!) == "$1,926.42")
    #expect(Fmt.amount(Decimal(string: "0.0934")!) == "0.0934")
    #expect(Fmt.pct(nil as Decimal?) == "-")
}
```

- [ ] **Step 2: Run focused tests and verify undefined-type failures**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletTests/WalletAPIModelsTests -only-testing:sevenwalletTests/FormattingTests -parallel-testing-enabled NO test
```

- [ ] **Step 3: Implement address and domain values**

```swift
import Foundation

struct EVMAddress: RawRepresentable, Codable, Hashable, Sendable {
    enum Error: Swift.Error, Equatable { case invalid(String) }
    let rawValue: String

    init(_ raw: String) throws {
        let normalized = raw.lowercased()
        let body = normalized.dropFirst(2)
        guard normalized.hasPrefix("0x"), body.count == 40, body.allSatisfy(\.isHexDigit) else {
            throw Error.invalid(raw)
        }
        rawValue = normalized
    }

    init(rawValue: String) {
        precondition((try? EVMAddress(rawValue)) != nil)
        self.rawValue = rawValue.lowercased()
    }
}
```

```swift
import Foundation

struct TokenPrice: Codable, Equatable, Sendable {
    let currency: String?
    let value: Decimal?
    let lastUpdatedAt: Date?
}

struct WalletToken: Codable, Equatable, Identifiable, Sendable {
    let tokenAddress: String?
    let symbol: String
    let name: String
    let decimals: Int
    let rawBalance: String
    let balance: Decimal
    let isNative: Bool
    let price: TokenPrice?
    let logoURL: URL?
    let coinKey: String
    let priceUSD: Decimal?
    var id: String { "\(coinKey):\(tokenAddress?.lowercased() ?? "native")" }
}

struct TokenPortfolio: Codable, Equatable, Sendable {
    let address: EVMAddress
    let fetchedAt: Date?
    let network: String?
    let tokens: [WalletToken]
}

struct WalletTransfer: Codable, Equatable, Sendable {
    let asset: String?
    let blockNumber: String?
    let category: String?
    let from: String?
    let hash: String?
    let to: String?
    let value: String?
}

struct TransactionPage: Codable, Equatable, Sendable {
    let address: EVMAddress
    let nextPageKey: String?
    let transfers: [WalletTransfer]
}
```

- [ ] **Step 4: Add Decimal formatting overloads**

Use `NSDecimalNumber(decimal:)` and one POSIX `NumberFormatter` helper:

```swift
static func usd(_ value: Decimal) -> String {
    let number = NSDecimalNumber(decimal: value)
    let negative = number.compare(.zero) == .orderedAscending
    let magnitude = negative ? number.multiplying(by: -1) : number
    return (negative ? "-$" : "$") + (decimalFormatter(minimum: 2, maximum: 2).string(from: magnitude) ?? "0.00")
}

static func amount(_ value: Decimal) -> String {
    decimalFormatter(minimum: 2, maximum: 4).string(from: NSDecimalNumber(decimal: value)) ?? "0"
}

static func pct(_ value: Decimal?) -> String {
    guard let value else { return "-" }
    let number = NSDecimalNumber(decimal: value)
    return (number.compare(.zero) == .orderedDescending ? "+" : "") + String(format: "%.2f%%", number.doubleValue)
}
```

Keep existing Double overloads until all existing callers migrate.

- [ ] **Step 5: Run Step 2 and commit**

Expected: tests pass.

```bash
git add sevenwallet/Domain sevenwallet/Theme/Formatting.swift sevenwalletTests/WalletAPIModelsTests.swift sevenwalletTests/FormattingTests.swift
git commit -m "feat: add wallet API domain values"
```

---

### Task 3: API Client and Every Remote Operation

**Files:**
- Create: `sevenwallet/Network/APIEndpoint.swift`
- Create: `sevenwallet/Network/APIClient.swift`
- Create: `sevenwallet/Network/WalletRemoteDataSources.swift`
- Create: `sevenwalletTests/APIClientTests.swift`

**Interfaces:**
- Consumes: base URL, EVM addresses, and domain values.
- Produces: `APIClientProtocol`, `TokenRemoteDataSourceProtocol`, and `TransactionRemoteDataSourceProtocol`.

- [ ] **Step 1: Write failing request, error, and decoding tests**

```swift
@Suite(.serialized)
struct APIClientTests {
    @Test func nativeUsesV1AndDecodesNullAddress() async throws {
        let (client, recorder) = makeClient(status: 200, body: #"[{"tokenAddress":null,"symbol":"ETH","name":"ETH","decimals":18,"rawBalance":"0","balance":"0","isNative":true,"price":{"currency":"usd","value":"1926.42","lastUpdatedAt":"2026-07-22T19:26:30Z"},"logoURI":null,"coinKey":"ETH","priceUSD":"1926.42"}]"#)
        let tokens = try await TokenRemoteDataSource(client: client).fetchNativeTokens()
        #expect(await recorder.lastRequest?.url?.absoluteString == "https://wallet.example/v1/native")
        #expect(tokens.first?.tokenAddress == nil)
        #expect(tokens.first?.priceUSD == Decimal(string: "1926.42"))
    }

    @Test func transactionQueryIsEncoded() throws {
        let address = try EVMAddress("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
        let endpoint = APIEndpoint.transactions(address, limit: 100, pageKey: "next key")
        #expect(endpoint.queryItems == [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "pageKey", value: "next key")])
    }

    @Test func serverErrorIsTyped() async {
        let (client, _) = makeClient(status: 503, body: #"{"error":"upstream unavailable"}"#)
        await #expect(throws: APIError.http(status: 503, message: "upstream unavailable")) {
            try await client.data(for: .nativeTokens)
        }
    }
}
```

Implement `makeClient` with a serialized URLProtocol stub, an ephemeral session, and an actor request recorder.

- [ ] **Step 2: Run and verify missing-type failure**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletTests/APIClientTests -parallel-testing-enabled NO test
```

- [ ] **Step 3: Implement endpoint and client contracts**

```swift
enum APIEndpoint: Equatable, Sendable {
    case nativeTokens
    case portfolio(EVMAddress)
    case transactions(EVMAddress, limit: Int, pageKey: String?)

    var path: String {
        switch self {
        case .nativeTokens: "/v1/native"
        case .portfolio(let address): "/v1/addresses/\(address.rawValue)/tokens"
        case .transactions(let address, _, _): "/v1/addresses/\(address.rawValue)/transactions"
        }
    }

    var queryItems: [URLQueryItem] {
        guard case .transactions(_, let limit, let pageKey) = self else { return [] }
        var result = [URLQueryItem(name: "limit", value: String(limit))]
        if let pageKey { result.append(URLQueryItem(name: "pageKey", value: pageKey)) }
        return result
    }
}
```

```swift
enum APIError: Swift.Error, Equatable {
    case invalidRequest
    case transport(String)
    case nonHTTPResponse
    case http(status: Int, message: String?)
    case invalidData
}

protocol APIClientProtocol: Sendable {
    func data(for endpoint: APIEndpoint) async throws -> Data
}

struct APIClient: APIClientProtocol, Sendable {
    let baseURL: URL
    let session: URLSession

    func data(for endpoint: APIEndpoint) async throws -> Data {
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        parts.path = endpoint.path
        parts.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems
        guard let url = parts.url else { throw APIError.invalidRequest }
        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse else { throw APIError.nonHTTPResponse }
            guard 200..<300 ~= http.statusCode else {
                let message = try? JSONDecoder().decode(ErrorPayload.self, from: data).error
                throw APIError.http(status: http.statusCode, message: message)
            }
            return data
        } catch let error as APIError { throw error }
        catch { throw APIError.transport(error.localizedDescription) }
    }
}

private struct ErrorPayload: Decodable { let error: String }
```

- [ ] **Step 4: Implement DTO mapping and source protocols**

```swift
protocol TokenRemoteDataSourceProtocol: Sendable {
    func fetchNativeTokens() async throws -> [WalletToken]
    func fetchPortfolio(address: EVMAddress) async throws -> TokenPortfolio
}

protocol TransactionRemoteDataSourceProtocol: Sendable {
    func fetchTransactions(address: EVMAddress, limit: Int, pageKey: String?) async throws -> TransactionPage
}
```

Define DTOs with exact keys `logoURI`, `priceUSD`, `blockNum`, and `nextPageKey`. `TokenRemoteDataSource` decodes `[TokenDTO]` for `.nativeTokens` and `PortfolioDTO` for `.portfolio(address)`. `TransactionRemoteDataSource` decodes `TransactionPageDTO` for `.transactions`. Require symbol, name, decimals, raw balance, display balance, native flag, and coin key. Parse numeric strings using `Decimal(string:locale:)` with `en_US_POSIX`, timestamps with `ISO8601DateFormatter`, and invalid required fields as `APIError.invalidData`. Require returned portfolio/page addresses to match the requested normalized address. Transfer fields stay optional.

- [ ] **Step 5: Add portfolio and transaction fixtures and run tests**

Assert portfolio network/token count and transaction next cursor/hash/request query. Expected: Step 2 passes with no live network.

- [ ] **Step 6: Commit**

```bash
git add sevenwallet/Network sevenwalletTests/APIClientTests.swift
git commit -m "feat: add wallet API remote sources"
```

---

### Task 4: SwiftData Snapshot Store

**Files:**
- Create: `sevenwallet/Persistence/WalletCacheModels.swift`
- Create: `sevenwallet/Persistence/WalletStore.swift`
- Create: `sevenwalletTests/WalletStoreTests.swift`

**Interfaces:**
- Consumes: Codable domain values.
- Produces: `WalletStoreProtocol`, `CachedResource<Value>`, and `WalletCacheSchema.models`.

- [ ] **Step 1: Write failing in-memory store tests**

```swift
@MainActor
struct WalletStoreTests {
    @Test func nativeSnapshotReplacesAtomically() async throws {
        let store = try makeStore()
        let first = [makeToken(price: "1926.42")]
        let second = [makeToken(price: "2000.00")]
        try await store.saveNativeTokens(first, fetchedAt: Date(timeIntervalSince1970: 100))
        try await store.saveNativeTokens(second, fetchedAt: Date(timeIntervalSince1970: 200))
        let cached = try await store.loadNativeTokens()
        #expect(cached?.value == second)
        #expect(cached?.fetchedAt == Date(timeIntervalSince1970: 200))
    }

    @Test func transactionKeyIncludesLimitAndCursor() async throws {
        let store = try makeStore()
        let address = try testAddress()
        let page = TransactionPage(address: address, nextPageKey: "next", transfers: [])
        try await store.saveTransactionPage(page, limit: 25, pageKey: nil, fetchedAt: .distantPast)
        #expect(try await store.loadTransactionPage(address: address, limit: 25, pageKey: nil)?.value == page)
        #expect(try await store.loadTransactionPage(address: address, limit: 100, pageKey: nil) == nil)
        #expect(try await store.loadTransactionPage(address: address, limit: 25, pageKey: "next") == nil)
    }
}
```

`makeStore()` creates an in-memory `ModelContainer` from `WalletCacheSchema.models`.

- [ ] **Step 2: Run and verify missing-store failure**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletTests/WalletStoreTests -parallel-testing-enabled NO test
```

- [ ] **Step 3: Create three snapshot records**

```swift
@Model final class NativeTokensCacheRecord {
    @Attribute(.unique) var key = "native"
    var payload: Data
    var fetchedAt: Date
    init(payload: Data, fetchedAt: Date) { self.payload = payload; self.fetchedAt = fetchedAt }
}

@Model final class PortfolioCacheRecord {
    @Attribute(.unique) var address: String
    var payload: Data
    var fetchedAt: Date
    init(address: String, payload: Data, fetchedAt: Date) {
        self.address = address; self.payload = payload; self.fetchedAt = fetchedAt
    }
}

@Model final class TransactionPageCacheRecord {
    @Attribute(.unique) var key: String
    var address: String
    var limit: Int
    var pageKey: String?
    var payload: Data
    var fetchedAt: Date
    init(key: String, address: String, limit: Int, pageKey: String?, payload: Data, fetchedAt: Date) {
        self.key = key; self.address = address; self.limit = limit; self.pageKey = pageKey
        self.payload = payload; self.fetchedAt = fetchedAt
    }
}

enum WalletCacheSchema {
    static let models: [any PersistentModel.Type] = [
        NativeTokensCacheRecord.self, PortfolioCacheRecord.self, TransactionPageCacheRecord.self
    ]
}
```

- [ ] **Step 4: Implement typed actor-isolated reads and upserts**

```swift
struct CachedResource<Value: Sendable>: Sendable {
    let value: Value
    let fetchedAt: Date
}

protocol WalletStoreProtocol: Sendable {
    func loadNativeTokens() async throws -> CachedResource<[WalletToken]>?
    func saveNativeTokens(_ value: [WalletToken], fetchedAt: Date) async throws
    func loadPortfolio(address: EVMAddress) async throws -> CachedResource<TokenPortfolio>?
    func savePortfolio(_ value: TokenPortfolio, fetchedAt: Date) async throws
    func loadTransactionPage(address: EVMAddress, limit: Int, pageKey: String?) async throws -> CachedResource<TransactionPage>?
    func saveTransactionPage(_ value: TransactionPage, limit: Int, pageKey: String?, fetchedAt: Date) async throws
}

@ModelActor
actor WalletStore: WalletStoreProtocol {
    func loadNativeTokens() throws -> CachedResource<[WalletToken]>? {
        var descriptor = FetchDescriptor<NativeTokensCacheRecord>()
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        return CachedResource(value: try JSONDecoder().decode([WalletToken].self, from: record.payload), fetchedAt: record.fetchedAt)
    }

    func saveNativeTokens(_ value: [WalletToken], fetchedAt: Date) throws {
        let payload = try JSONEncoder().encode(value)
        var descriptor = FetchDescriptor<NativeTokensCacheRecord>()
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.payload = payload; record.fetchedAt = fetchedAt
        } else {
            modelContext.insert(NativeTokensCacheRecord(payload: payload, fetchedAt: fetchedAt))
        }
        try modelContext.save()
    }
}
```

Implement portfolio and page methods with normalized-address predicates and the same decode/upsert/save sequence. Build page keys collision-safely:

```swift
private func transactionKey(address: EVMAddress, limit: Int, pageKey: String?) -> String {
    let cursor = pageKey ?? ""
    return "\(address.rawValue)|\(limit)|\(cursor.utf8.count):\(cursor)"
}
```

- [ ] **Step 5: Add portfolio-isolation and corrupt-payload tests**

Verify replacing one address leaves another untouched and corrupt payload throws rather than returning a default value.

- [ ] **Step 6: Run Step 2 and commit**

```bash
git add sevenwallet/Persistence sevenwalletTests/WalletStoreTests.swift
git commit -m "feat: add SwiftData wallet cache"
```

---

### Task 5: Cache-First Token Repository

**Files:**
- Create: `sevenwallet/Repository/RepositoryTypes.swift`
- Create: `sevenwallet/Repository/TokenRepository.swift`
- Create: `sevenwalletTests/Support/RepositoryTestDoubles.swift`
- Create: `sevenwalletTests/TokenRepositoryTests.swift`

**Interfaces:**
- Consumes: token remote source, store, and injected date provider.
- Produces: cache-first native and portfolio event streams.

- [ ] **Step 1: Write failing freshness, failure, and coalescing tests**

```swift
@MainActor
struct TokenRepositoryTests {
    @Test func exactlyThirtyMinutesIsFresh() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cached = [makeToken(price: "1900")]
        let harness = try await TokenHarness(cache: cached, fetchedAt: now.addingTimeInterval(-1_800), now: now)
        #expect(try await collect(harness.repository.nativeTokens(policy: .ifExpired)) == [.cached(cached)])
        #expect(await harness.remote.nativeCallCount == 0)
    }

    @Test func olderCachePublishesThenRefreshes() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cached = [makeToken(price: "1900")]
        let fresh = [makeToken(price: "2000")]
        let harness = try await TokenHarness(cache: cached, fetchedAt: now.addingTimeInterval(-1_801), remote: fresh, now: now)
        #expect(try await collect(harness.repository.nativeTokens(policy: .ifExpired)) == [.cached(cached), .refreshing, .fresh(fresh)])
        #expect(try await harness.store.loadNativeTokens()?.fetchedAt == now)
    }
}
```

Add cache-miss, forced-fresh-cache, failed-refresh timestamp preservation, independent portfolio address, and simultaneous native-call tests. Gate the coalescing remote with a continuation instead of a timing assumption.

- [ ] **Step 2: Run and verify missing-repository failure**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletTests/TokenRepositoryTests -parallel-testing-enabled NO test
```

- [ ] **Step 3: Define shared repository types**

```swift
enum RefreshPolicy: Equatable, Sendable { case ifExpired, force }

enum RepositoryLoadEvent<Value: Equatable & Sendable>: Equatable, Sendable {
    case cached(Value)
    case refreshing
    case fresh(Value)
}

struct DateProvider: Sendable {
    let now: @Sendable () -> Date
    static let system = DateProvider(now: Date.init)
}

protocol TokenRepositoryProtocol: Sendable {
    func nativeTokens(policy: RefreshPolicy) -> AsyncThrowingStream<RepositoryLoadEvent<[WalletToken]>, Swift.Error>
    func portfolio(address: EVMAddress, policy: RefreshPolicy) -> AsyncThrowingStream<RepositoryLoadEvent<TokenPortfolio>, Swift.Error>
}
```

Test support supplies actor spies, in-memory stores, explicit domain factories, fixed dates, and a `collect` stream helper.

- [ ] **Step 4: Implement streams and request coalescing**

```swift
@MainActor
final class TokenRepository: TokenRepositoryProtocol {
    private let remote: any TokenRemoteDataSourceProtocol
    private let store: any WalletStoreProtocol
    private let dateProvider: DateProvider
    private var nativeTask: Task<[WalletToken], Swift.Error>?
    private var portfolioTasks: [EVMAddress: Task<TokenPortfolio, Swift.Error>] = [:]

    init(remote: any TokenRemoteDataSourceProtocol, store: any WalletStoreProtocol, dateProvider: DateProvider = .system) {
        self.remote = remote; self.store = store; self.dateProvider = dateProvider
    }

    func nativeTokens(policy: RefreshPolicy) -> AsyncThrowingStream<RepositoryLoadEvent<[WalletToken]>, Swift.Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    let cached = try await store.loadNativeTokens()
                    if let cached { continuation.yield(.cached(cached.value)) }
                    guard policy == .force || cached.map({ dateProvider.now().timeIntervalSince($0.fetchedAt) > 1_800 }) ?? true else {
                        continuation.finish(); return
                    }
                    continuation.yield(.refreshing)
                    let value = try await refreshNative()
                    continuation.yield(.fresh(value)); continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    private func refreshNative() async throws -> [WalletToken] {
        if let nativeTask { return try await nativeTask.value }
        let task = Task { @MainActor in
            let value = try await remote.fetchNativeTokens()
            try await store.saveNativeTokens(value, fetchedAt: dateProvider.now())
            return value
        }
        nativeTask = task
        defer { nativeTask = nil }
        return try await task.value
    }
}
```

Implement portfolio with the same event order and one task per normalized address. Remove in-flight entries with `defer` after success or failure.

- [ ] **Step 5: Run Step 2 twice and commit**

Expected: both runs pass and matching concurrent loads make one remote call.

```bash
git add sevenwallet/Repository sevenwalletTests/Support sevenwalletTests/TokenRepositoryTests.swift
git commit -m "feat: add cache-first token repository"
```

---

### Task 6: Paginated Transaction Repository

**Files:**
- Create: `sevenwallet/Repository/TransactionRepository.swift`
- Create: `sevenwalletTests/TransactionRepositoryTests.swift`
- Modify: `sevenwallet/Repository/RepositoryTypes.swift`
- Modify: `sevenwalletTests/Support/RepositoryTestDoubles.swift`

**Interfaces:**
- Consumes: transaction remote source, store, date provider, and repository event types.
- Produces: `transactions(address:limit:pageKey:policy:)`.

- [ ] **Step 1: Write failing key, cursor, and coalescing tests**

```swift
@MainActor
@Test func samePageCoalescesAndDifferentCursorDoesNot() async throws {
    let harness = try TransactionHarness()
    async let first = collect(harness.repository.transactions(address: harness.address, limit: 25, pageKey: nil, policy: .force))
    async let duplicate = collect(harness.repository.transactions(address: harness.address, limit: 25, pageKey: nil, policy: .force))
    async let next = collect(harness.repository.transactions(address: harness.address, limit: 25, pageKey: "next", policy: .force))
    _ = try await (first, duplicate, next)
    #expect(await harness.remote.callCount == 2)
}
```

Also test independent limits/cursors, strict expiration, preserved `nextPageKey`, failed-refresh timestamps, and invalid limits 0 and 101.

- [ ] **Step 2: Run and verify failure**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletTests/TransactionRepositoryTests -parallel-testing-enabled NO test
```

- [ ] **Step 3: Define contract and request key**

```swift
protocol TransactionRepositoryProtocol: Sendable {
    func transactions(address: EVMAddress, limit: Int, pageKey: String?, policy: RefreshPolicy)
        -> AsyncThrowingStream<RepositoryLoadEvent<TransactionPage>, Swift.Error>
}

struct TransactionRequestKey: Hashable, Sendable {
    let address: EVMAddress
    let limit: Int
    let pageKey: String?
}

enum RepositoryError: Swift.Error, Equatable {
    case invalidTransactionLimit(Int)
}
```

- [ ] **Step 4: Implement page cache streams and per-key tasks**

Build `@MainActor final class TransactionRepository` with the same strict cache-event order as `TokenRepository` and:

```swift
private var tasks: [TransactionRequestKey: Task<TransactionPage, Swift.Error>] = [:]

private func refresh(_ key: TransactionRequestKey) async throws -> TransactionPage {
    if let task = tasks[key] { return try await task.value }
    let task = Task { @MainActor in
        let value = try await remote.fetchTransactions(address: key.address, limit: key.limit, pageKey: key.pageKey)
        try await store.saveTransactionPage(value, limit: key.limit, pageKey: key.pageKey, fetchedAt: dateProvider.now())
        return value
    }
    tasks[key] = task
    defer { tasks[key] = nil }
    return try await task.value
}
```

Reject limits outside `1...100` before cache access.

- [ ] **Step 5: Run Step 2 and commit**

```bash
git add sevenwallet/Repository sevenwalletTests/TransactionRepositoryTests.swift sevenwalletTests/Support/RepositoryTestDoubles.swift
git commit -m "feat: add transaction repository"
```

---

### Task 7: Pull Policy and Repository-Driven Home View Model

**Files:**
- Create: `sevenwallet/View/Wallet/PullRefreshCoordinator.swift`
- Create: `sevenwalletTests/PullRefreshCoordinatorTests.swift`
- Modify: `sevenwallet/View/Token/TokenViewModel.swift`
- Modify: `sevenwallet/View/Wallet/WalletCardViewModel.swift`
- Modify: `sevenwallet/View/Wallet/WalletHomeViewModel.swift`
- Modify: corresponding view-model tests and `sevenwalletTests/Support/RepositoryTestDoubles.swift`

**Interfaces:**
- Consumes: token repository streams and date provider.
- Produces: async load/refresh/retry methods, mutable rows, spinner state, error state, and optional wallet card.

- [ ] **Step 1: Write pull-counter tests**

```swift
@Test func thirdPullForcesAndResets() {
    var value = PullRefreshCoordinator()
    let start = Date(timeIntervalSince1970: 1_000)
    #expect(value.recordPull(at: start) == .ifExpired)
    #expect(value.recordPull(at: start.addingTimeInterval(20)) == .ifExpired)
    #expect(value.recordPull(at: start.addingTimeInterval(59)) == .force)
    #expect(value.recordPull(at: start.addingTimeInterval(60)) == .ifExpired)
}
```

Add a test proving timestamps older than 60 seconds do not accumulate.

- [ ] **Step 2: Write failing home event tests**

```swift
@MainActor
@Test func cachedThenFreshUpdatesRows() async {
    let repository = ScriptedTokenRepository(events: [
        .cached([makeToken(price: "1900")]), .refreshing, .fresh([makeToken(price: "2000")])
    ])
    let home = WalletHomeViewModel(tokenRepository: repository)
    await home.loadTokens()
    #expect(home.tokens.first?.formattedPrice == "$2,000.00")
    #expect(!home.isLoadingTokens)
    #expect(home.tokenErrorMessage == nil)
    #expect(home.walletCard == nil)
}
```

Add gated-spinner, initial-error, cached-refresh-error, retry-policy, three-pull-policy, and theme tests.

- [ ] **Step 3: Run focused tests and verify failures**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletTests/PullRefreshCoordinatorTests -only-testing:sevenwalletTests/TokenViewModelTests -only-testing:sevenwalletTests/WalletCardViewModelTests -only-testing:sevenwalletTests/WalletHomeViewModelTests -parallel-testing-enabled NO test
```

- [ ] **Step 4: Implement the rolling coordinator**

```swift
struct PullRefreshCoordinator {
    private var pulls: [Date] = []
    mutating func recordPull(at date: Date) -> RefreshPolicy {
        pulls.removeAll { date.timeIntervalSince($0) > 60 }
        pulls.append(date)
        guard pulls.count >= 3 else { return .ifExpired }
        pulls.removeAll(keepingCapacity: true)
        return .force
    }
}
```

- [ ] **Step 5: Convert token and wallet presentation to Decimal**

```swift
@MainActor @Observable
final class TokenViewModel: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let balance: Decimal
    let marketPrice: Decimal?
    let dailyChange: Decimal? = nil
    let logoURL: URL?

    init(token: WalletToken) {
        id = token.id; symbol = token.symbol; name = token.name; balance = token.balance
        marketPrice = token.priceUSD ?? token.price?.value; logoURL = token.logoURL
    }

    var formattedPrice: String { marketPrice.map(Fmt.usd) ?? "-" }
    var formattedBalance: String { "\(Fmt.amount(balance)) \(symbol)" }
    var formattedDailyChange: String { Fmt.pct(dailyChange) }
    var iconText: String { String(symbol.prefix(1)) }
    var holdingValue: Decimal { balance * (marketPrice ?? 0) }
}
```

Change `WalletCardViewModel.totalValue` to `Decimal`, retaining its derived sum and formatted result.

- [ ] **Step 6: Consume repository events in `WalletHomeViewModel`**

Add `private(set) var tokens`, `isLoadingTokens`, `tokenErrorMessage`, optional `walletCard`, injected repository/date provider, and:

```swift
func loadTokens() async { await consume(policy: .ifExpired) }
func refreshTokens() async { await consume(policy: refreshCoordinator.recordPull(at: dateProvider.now())) }
func retryTokens() async { await consume(policy: .ifExpired) }

private func consume(policy: RefreshPolicy) async {
    tokenErrorMessage = nil
    do {
        for try await event in tokenRepository.nativeTokens(policy: policy) {
            switch event {
            case .cached(let value), .fresh(let value):
                tokens = value.map(TokenViewModel.init); isLoadingTokens = false
            case .refreshing:
                isLoadingTokens = true
            }
        }
    } catch {
        isLoadingTokens = false
        tokenErrorMessage = error.localizedDescription
    }
}
```

Give typed data-layer errors concise `LocalizedError` messages.

- [ ] **Step 7: Run Step 3 and commit**

```bash
git add sevenwallet/View sevenwallet/Theme/Formatting.swift sevenwalletTests
git commit -m "feat: load native tokens in home view model"
```

---

### Task 8: Empty Wallet Card and Token Loading UI

**Files:**
- Create: `sevenwallet/View/Wallet/EmptyWalletCardView.swift`
- Modify: `sevenwallet/Theme/Theme.swift`, `sevenwallet/View/Wallet/WalletCardView.swift`, `sevenwallet/View/Token/TokenRowView.swift`, `sevenwallet/View/Wallet/WalletHomePage.swift`
- Modify: `sevenwalletUITests/sevenwalletUITests.swift`

**Interfaces:**
- Consumes: optional wallet, native rows, loading/error state, and async actions.
- Produces: approved empty card, market-price rows, spinner, retry, and pull-to-refresh.

- [ ] **Step 1: Write failing UI tests**

```swift
@MainActor
func testNoWalletHomeContent() throws {
    let app = XCUIApplication()
    app.launchArguments = ["UI_TEST_FIXTURE"]
    app.launch()
    XCTAssertTrue(app.otherElements["empty-wallet-card"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["SEVEN WALLET"].exists)
    XCTAssertTrue(app.staticTexts["Add your first wallet"].exists)
    XCTAssertTrue(app.staticTexts["Import an address to start tracking"].exists)
    XCTAssertFalse(app.buttons["copy-wallet-address-button"].exists)
    XCTAssertTrue(app.staticTexts["ETH"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["-"].firstMatch.exists)
    XCTAssertTrue(app.staticTexts["$1,926.42"].exists)
}
```

Add loading and initial-error tests using `UI_TEST_DELAYED_TOKENS` and `UI_TEST_TOKEN_ERROR`; assert `tokens-loading-indicator`, `token-error-message`, and `retry-tokens-button`.

- [ ] **Step 2: Run and verify failures**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletUITests/sevenwalletUITests/testNoWalletHomeContent -only-testing:sevenwalletUITests/sevenwalletUITests/testTokenLoadingIndicator -only-testing:sevenwalletUITests/sevenwalletUITests/testInitialTokenError -parallel-testing-enabled NO test
```

- [ ] **Step 3: Add shared height and empty card**

Add `Theme.walletCardMinimumHeight = 212`, apply it to `WalletCardView`, and create:

```swift
struct EmptyWalletCardView: View {
    let theme: Theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SEVEN WALLET").font(.subheadline.weight(.medium)).tracking(2.4).foregroundStyle(theme.fg3)
            Spacer()
            VStack(spacing: 22) {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .medium)).foregroundStyle(Theme.accentHi)
                    .frame(width: 56, height: 56)
                    .background(Theme.accent.opacity(0.10), in: Circle())
                    .overlay { Circle().stroke(Theme.accent.opacity(0.55), lineWidth: 1) }
                    .shadow(color: Theme.accent.opacity(0.40), radius: 12)
                VStack(spacing: 6) {
                    Text("Add your first wallet").font(.title2.bold()).foregroundStyle(theme.fg1)
                    Text("Import an address to start tracking").font(.subheadline).foregroundStyle(theme.fg2)
                }.frame(maxWidth: .infinity)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: Theme.walletCardMinimumHeight)
        .background(theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(theme.edge, style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty-wallet-card")
    }
}
```

- [ ] **Step 4: Update rows and home state**

Use `AsyncImage` with circular success and symbol fallback phases. Show `formattedDailyChange`, `formattedPrice`, and `formattedBalance`. Add `.task { await viewModel.loadTokens() }`, `.refreshable { await viewModel.refreshTokens() }`, optional wallet rendering, and this header indicator:

```swift
if viewModel.isLoadingTokens {
    ProgressView().controlSize(.small)
        .accessibilityLabel("Loading tokens")
        .accessibilityIdentifier("tokens-loading-indicator")
}
```

With an error and no rows, show message and Retry running `Task { await viewModel.retryTokens() }`; with cached rows, keep rows and show a compact error.

- [ ] **Step 5: Build and commit**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/sevenwallet-network CODE_SIGNING_ALLOWED=NO build
git add sevenwallet/Theme/Theme.swift sevenwallet/View sevenwalletUITests/sevenwalletUITests.swift
git commit -m "feat: add empty wallet network states"
```

Expected: build succeeds; UI tests pass after Task 9 supplies fixtures.

---

### Task 9: Composition Root and Deterministic UI Fixtures

**Files:**
- Create: `sevenwallet/Application/AppDependencies.swift`
- Modify: `sevenwallet/sevenwalletApp.swift`, `sevenwalletTests/WalletHomeViewModelTests.swift`, `sevenwalletUITests/sevenwalletUITests.swift`

**Interfaces:**
- Consumes: configuration, client, ModelContainer, repositories, and launch arguments.
- Produces: live view-model construction and explicit UI fixtures.

- [ ] **Step 1: Write failing startup test**

```swift
@MainActor
@Test func missingConfigurationBecomesHomeError() async {
    let home = AppDependencies.makeHomeViewModel(arguments: [], environment: [:], infoDictionary: [:], inMemoryStore: true)
    await home.loadTokens()
    #expect(home.tokens.isEmpty)
    #expect(home.tokenErrorMessage == "BASE_URL is not configured.")
}
```

- [ ] **Step 2: Run and verify failure**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletTests/WalletHomeViewModelTests -parallel-testing-enabled NO test
```

- [ ] **Step 3: Compose live dependencies**

```swift
@MainActor enum AppDependencies {
    static func makeHomeViewModel(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        inMemoryStore: Bool = false
    ) -> WalletHomeViewModel {
        if arguments.contains("UI_TEST_FIXTURE") { return fixtureHome(arguments: arguments) }
        do {
            let configuration = try AppConfiguration(environment: environment, infoDictionary: infoDictionary)
            let schema = Schema(WalletCacheSchema.models)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemoryStore)])
            let store = WalletStore(modelContainer: container)
            let client = APIClient(baseURL: configuration.baseURL, session: .shared)
            return WalletHomeViewModel(tokenRepository: TokenRepository(remote: TokenRemoteDataSource(client: client), store: store))
        } catch {
            return WalletHomeViewModel(tokenRepository: FailingTokenRepository(error: error))
        }
    }
}
```

`FailingTokenRepository` yields `.refreshing`, then throws its captured localized error.

- [ ] **Step 4: Implement exact fixtures**

`fixtureHome(arguments:)` supports: `UI_TEST_FIXTURE` (ETH at 1926.42, no wallet), `UI_TEST_LONG_TOKEN_LIST` (four unique copies), `UI_TEST_DELAYED_TOKENS` (refreshing, 750 ms, fresh), `UI_TEST_TOKEN_ERROR` (localized `Unable to load tokens.`), and `UI_TEST_POPULATED_WALLET` (`Main Wallet`). Fixtures create no URLSession or SwiftData container.

- [ ] **Step 5: Replace app sample construction**

```swift
@main
struct sevenwalletApp: App {
    @State private var homeViewModel = AppDependencies.makeHomeViewModel()
    var body: some Scene { WindowGroup { WalletHomeView(viewModel: homeViewModel) } }
}
```

- [ ] **Step 6: Verify height and existing UI behavior**

Launch empty then populated fixtures; assert both card heights are at least 212 and equal within one point. Add `UI_TEST_FIXTURE` to all existing UI tests and keep `UI_TEST_LONG_TOKEN_LIST` for pinning.

- [ ] **Step 7: Run and commit**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletTests/WalletHomeViewModelTests -only-testing:sevenwalletUITests/sevenwalletUITests -parallel-testing-enabled NO test
git add sevenwallet/Application/AppDependencies.swift sevenwallet/sevenwalletApp.swift sevenwalletTests/WalletHomeViewModelTests.swift sevenwalletUITests/sevenwalletUITests.swift
git commit -m "feat: compose live wallet repositories"
```

---

### Task 10: Full Regression and Release Verification

**Files:**
- Modify only files required to correct failures caused by Tasks 1-9.

**Interfaces:**
- Consumes: completed implementation.
- Produces: clean verified branch with no committed URL.

- [ ] **Step 1: Run all tests**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletTests -parallel-testing-enabled NO test
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-network -only-testing:sevenwalletUITests/sevenwalletUITests -parallel-testing-enabled NO test
```

Expected: TEST SUCCEEDED twice without live requests.

- [ ] **Step 2: Build Debug and Release**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/sevenwallet-network CODE_SIGNING_ALLOWED=NO build
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/sevenwallet-network BASE_URL=https://archive.example CODE_SIGNING_ALLOWED=NO build
```

Expected: BUILD SUCCEEDED twice; `plutil -p` on the Release product Info.plist reports the command-line `BASE_URL`.

- [ ] **Step 3: Audit scope and hygiene**

```bash
git grep -n 'wallet-api-100439333239\|us-central1.run.app' -- . ':!docs/superpowers/specs/2026-07-23-network-repository-empty-wallet-design.md'
git diff --check
git status --short
```

Expected: no service URL outside the approved spec, no whitespace errors, and only intended changes. Confirm no import UI exists, address repositories have no screen consumer, and production samples are unreachable.

- [ ] **Step 4: Commit verification fixes only when needed**

If verification required edits, stage only those exact files and commit `fix: resolve wallet integration regressions`. If no edits were required, do not create an empty commit.
