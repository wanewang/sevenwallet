# Wallet Input and Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add, persist, display, edit, and delete an imported Ethereum wallet while loading its address portfolio and preserving a persistence model that accepts multiple wallets.

**Architecture:** A dedicated SwiftData `SavedWalletStore` owns wallet identity and selection, while the existing cache store owns API snapshots and address-data purging. An app-level `WalletSession` coordinates those stores, and `WalletHomeViewModel` switches between native-token and selected-address portfolio streams. One typed `NavigationStack` presents a mode-driven wallet form from the empty card or populated-card edit control.

**Tech Stack:** Swift 5 language mode, SwiftUI, Observation, SwiftData, Foundation, Swift Testing, XCTest UI testing, Xcode 26.3, iOS 26.2.

## Global Constraints

- Wallet name is trimmed, required, and limited to 20 Swift characters.
- Address input is required and must be `0x` followed by exactly 40 hexadecimal characters.
- Persist and request the lowercase-normalized `EVMAddress`.
- The app never generates a key, seed phrase, or address.
- Ethereum is the only supported and displayed network.
- Expose the add-wallet route only from the empty wallet card in this release.
- The persistence store accepts multiple wallets and selects the newest added wallet.
- Edit mode can change only wallet name and card color.
- Delete requires confirmation and purges that address's portfolio and transaction caches before deleting wallet identity.
- Native-token metadata and caches for other addresses survive wallet deletion.
- Keep the address-copy control independent from edit navigation.
- Use exactly five stable card-color values: blue, purple, pink, teal, and amber.
- Reuse the current 212-point wallet-card minimum height, theme behavior, cache freshness, refresh, retry, and in-flight request rules.
- Add no third-party dependency and never contact the live service from tests.

## File Map

- `sevenwallet/Domain/SavedWallet.swift`: wallet identity, stable card-color value, and input validation.
- `sevenwallet/Persistence/SavedWalletModels.swift`: SwiftData wallet and selected-wallet records.
- `sevenwallet/Persistence/SavedWalletStore.swift`: wallet CRUD, selection, ordering, and snapshots.
- `sevenwallet/Persistence/WalletStore.swift`: existing API cache store plus address purge.
- `sevenwallet/Application/WalletSession.swift`: observable saved-wallet load/add/edit/delete state.
- `sevenwallet/Application/AppDependencies.swift`: one shared SwiftData container, production stores, repositories, and deterministic fixtures.
- `sevenwallet/View/Navigation/Screen.swift`: typed add and edit routes.
- `sevenwallet/View/Wallet/WalletFormViewModel.swift`: form mode, field state, validation visibility, and async actions.
- `sevenwallet/View/Wallet/WalletFormView.swift`: supplied add/edit layout and confirmation dialog.
- `sevenwallet/View/Wallet/WalletRootView.swift`: navigation ownership and session/home composition.
- `sevenwallet/View/Wallet/WalletCardColor+View.swift`: gradient mapping kept out of the domain layer.
- Existing home/card views and view models: selected-wallet rendering, portfolio loading, add/edit callbacks, and copy separation.
- Focused new test files mirror each new unit; existing home, store, card, and UI suites cover integration and regressions.

The Xcode project uses file-system-synchronized groups, so files added below the existing target directories do not require manual PBX file references.

---

### Task 1: Saved Wallet Domain and Validation

**Files:**
- Create: `sevenwallet/Domain/SavedWallet.swift`
- Create: `sevenwalletTests/SavedWalletTests.swift`

**Interfaces:**
- Consumes: existing `EVMAddress`.
- Produces: `WalletCardColor`, `SavedWallet`, and `WalletInputValidator`.

- [ ] **Step 1: Write failing domain and validation tests**

```swift
import Foundation
import Testing
@testable import sevenwallet

struct SavedWalletTests {
    private let validAddress = "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"

    @Test func nameTrimsAndAcceptsTwentyCharacters() {
        #expect(WalletInputValidator.validatedName("  Main Wallet  ") == "Main Wallet")
        #expect(WalletInputValidator.validatedName(String(repeating: "a", count: 20)) != nil)
        #expect(WalletInputValidator.validatedName("   ") == nil)
        #expect(WalletInputValidator.validatedName(String(repeating: "a", count: 21)) == nil)
    }

    @Test func nameInputIsCappedBySwiftCharacters() {
        #expect(WalletInputValidator.limitedName("12345678901234567890x") == "12345678901234567890")
        #expect(WalletInputValidator.limitedName(String(repeating: "🙂", count: 21)).count == 20)
    }

    @Test func addressTrimsValidatesAndNormalizes() throws {
        let address = try #require(WalletInputValidator.validatedAddress("  \(validAddress)  "))
        #expect(address.rawValue == validAddress.lowercased())
        #expect(WalletInputValidator.validatedAddress("0x1234") == nil)
        #expect(WalletInputValidator.validatedAddress(
            "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F9Z"
        ) == nil)
    }

    @Test func colorsAreStableAndComplete() {
        #expect(WalletCardColor.allCases == [.blue, .purple, .pink, .teal, .amber])
        #expect(Set(WalletCardColor.allCases.map(\.rawValue)).count == 5)
    }

    @Test func walletKeepsStableIdentity() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 100)
        let wallet = SavedWallet(
            id: id,
            name: "Main",
            address: try EVMAddress(validAddress),
            cardColor: .teal,
            createdAt: date
        )
        #expect(wallet.id == id)
        #expect(wallet.name == "Main")
        #expect(wallet.cardColor == .teal)
        #expect(wallet.createdAt == date)
    }
}
```

- [ ] **Step 2: Run the focused suite and verify it fails**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-input -only-testing:sevenwalletTests/SavedWalletTests -parallel-testing-enabled NO test
```

Expected: compilation fails because `SavedWallet`, `WalletCardColor`, and `WalletInputValidator` do not exist.

- [ ] **Step 3: Implement the domain values and validator**

Create `sevenwallet/Domain/SavedWallet.swift`:

```swift
import Foundation

nonisolated enum WalletCardColor: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case blue
    case purple
    case pink
    case teal
    case amber

    var id: String { rawValue }
}

nonisolated struct SavedWallet: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let address: EVMAddress
    let cardColor: WalletCardColor
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        address: EVMAddress,
        cardColor: WalletCardColor,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.cardColor = cardColor
        self.createdAt = createdAt
    }
}

nonisolated enum WalletInputValidator {
    static let maximumNameLength = 20

    static func limitedName(_ value: String) -> String {
        String(value.prefix(maximumNameLength))
    }

    static func validatedName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumNameLength else { return nil }
        return trimmed
    }

    static func validatedAddress(_ value: String) -> EVMAddress? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return try? EVMAddress(trimmed)
    }
}
```

- [ ] **Step 4: Run the focused suite and verify it passes**

Run the Step 2 command.

Expected: `SavedWalletTests` passes with no failures.

- [ ] **Step 5: Commit**

```bash
git add sevenwallet/Domain/SavedWallet.swift sevenwalletTests/SavedWalletTests.swift
git commit -m "feat: add saved wallet domain values"
```

---

### Task 2: SwiftData Wallet Persistence and Selection

**Files:**
- Create: `sevenwallet/Persistence/SavedWalletModels.swift`
- Create: `sevenwallet/Persistence/SavedWalletStore.swift`
- Create: `sevenwalletTests/SavedWalletStoreTests.swift`
- Modify: `sevenwallet/Persistence/WalletCacheModels.swift`

**Interfaces:**
- Consumes: `SavedWallet` and `WalletCardColor`.
- Produces: `SavedWalletSnapshot`, `SavedWalletStoreProtocol`, and `SavedWalletStore`.

- [ ] **Step 1: Write failing persistence tests**

Create `sevenwalletTests/SavedWalletStoreTests.swift` with an in-memory factory and a disk-backed relaunch check:

```swift
import Foundation
import SwiftData
import Testing
@testable import sevenwallet

@MainActor
struct SavedWalletStoreTests {
    @Test func addAllowsMultipleAndSelectsNewest() async throws {
        let store = try makeStore()
        let first = try wallet(name: "First", suffix: "1111", date: 100)
        let second = try wallet(name: "Second", suffix: "2222", date: 200)

        _ = try await store.addAndSelect(first)
        let snapshot = try await store.addAndSelect(second)

        #expect(snapshot.wallets.map(\.id) == [first.id, second.id])
        #expect(snapshot.selectedWalletID == second.id)
    }

    @Test func updateChangesOnlyNameAndColor() async throws {
        let store = try makeStore()
        let original = try wallet(name: "Original", suffix: "1111", date: 100)
        _ = try await store.addAndSelect(original)

        let snapshot = try await store.update(
            id: original.id,
            name: "Renamed",
            cardColor: .pink
        )
        let updated = try #require(snapshot.wallets.first)

        #expect(updated.name == "Renamed")
        #expect(updated.cardColor == .pink)
        #expect(updated.address == original.address)
        #expect(updated.createdAt == original.createdAt)
    }

    @Test func deletingSelectedWalletSelectsOldestRemaining() async throws {
        let store = try makeStore()
        let first = try wallet(name: "First", suffix: "1111", date: 100)
        let second = try wallet(name: "Second", suffix: "2222", date: 200)
        _ = try await store.addAndSelect(first)
        _ = try await store.addAndSelect(second)

        let snapshot = try await store.delete(id: second.id)

        #expect(snapshot.wallets == [first])
        #expect(snapshot.selectedWalletID == first.id)
    }

    @Test func deletingNonSelectedWalletPreservesSelection() async throws {
        let store = try makeStore()
        let first = try wallet(name: "First", suffix: "1111", date: 100)
        let second = try wallet(name: "Second", suffix: "2222", date: 200)
        _ = try await store.addAndSelect(first)
        _ = try await store.addAndSelect(second)

        let snapshot = try await store.delete(id: first.id)

        #expect(snapshot.wallets == [second])
        #expect(snapshot.selectedWalletID == second.id)
    }

    @Test func staleSelectionRepairsToOldestWallet() async throws {
        let container = try makeContainer()
        let first = try wallet(name: "First", suffix: "1111", date: 100)
        let context = ModelContext(container)
        context.insert(SavedWalletRecord(wallet: first))
        context.insert(WalletSelectionRecord(walletID: UUID()))
        try context.save()

        let store = SavedWalletStore(modelContainer: container)
        let repaired = try await store.loadSnapshot()

        #expect(repaired.selectedWalletID == first.id)
        let verificationContext = ModelContext(container)
        #expect(
            try verificationContext.fetch(
                FetchDescriptor<WalletSelectionRecord>()
            ).first?.walletID == first.id
        )
    }

    @Test func diskStoreReloadsWalletAndSelection() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).store")
        let firstContainer = try makeContainer(url: url)
        let original = try wallet(name: "Persistent", suffix: "1111", date: 100)
        _ = try await SavedWalletStore(modelContainer: firstContainer).addAndSelect(original)

        let secondContainer = try makeContainer(url: url)
        let snapshot = try await SavedWalletStore(modelContainer: secondContainer).loadSnapshot()

        #expect(snapshot.wallets == [original])
        #expect(snapshot.selectedWalletID == original.id)
        try? FileManager.default.removeItem(at: url)
    }

    private func makeStore() throws -> SavedWalletStore {
        SavedWalletStore(modelContainer: try makeContainer())
    }

    private func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(WalletCacheSchema.models)
        let configuration = url.map {
            ModelConfiguration("SavedWalletTests", schema: schema, url: $0)
        } ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func wallet(name: String, suffix: String, date: TimeInterval) throws -> SavedWallet {
        let body = String(repeating: "0", count: 36) + suffix
        return SavedWallet(
            name: name,
            address: try EVMAddress("0x\(body)"),
            cardColor: .blue,
            createdAt: Date(timeIntervalSince1970: date)
        )
    }
}
```

- [ ] **Step 2: Run the focused suite and verify it fails**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-input -only-testing:sevenwalletTests/SavedWalletStoreTests -parallel-testing-enabled NO test
```

Expected: compilation fails because the saved-wallet models and store are undefined.

- [ ] **Step 3: Add SwiftData records to the shared schema**

Create `sevenwallet/Persistence/SavedWalletModels.swift`:

```swift
import Foundation
import SwiftData

@Model
final class SavedWalletRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String
    var cardColor: String
    var createdAt: Date

    init(wallet: SavedWallet) {
        id = wallet.id
        name = wallet.name
        address = wallet.address.rawValue
        cardColor = wallet.cardColor.rawValue
        createdAt = wallet.createdAt
    }
}

@Model
final class WalletSelectionRecord {
    @Attribute(.unique) var key = "selected"
    var walletID: UUID

    init(walletID: UUID) {
        self.walletID = walletID
    }
}
```

Append both types to `WalletCacheSchema.models`:

```swift
SavedWalletRecord.self,
WalletSelectionRecord.self
```

- [ ] **Step 4: Implement snapshot-based CRUD**

Create `sevenwallet/Persistence/SavedWalletStore.swift`:

```swift
import Foundation
import SwiftData

nonisolated struct SavedWalletSnapshot: Equatable, Sendable {
    let wallets: [SavedWallet]
    let selectedWalletID: UUID?

    var selectedWallet: SavedWallet? {
        wallets.first { $0.id == selectedWalletID } ?? wallets.first
    }
}

protocol SavedWalletStoreProtocol: Sendable {
    func loadSnapshot() async throws -> SavedWalletSnapshot
    func addAndSelect(_ wallet: SavedWallet) async throws -> SavedWalletSnapshot
    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) async throws -> SavedWalletSnapshot
    func delete(id: UUID) async throws -> SavedWalletSnapshot
}

enum SavedWalletStoreError: Error, Equatable {
    case walletNotFound
    case corruptRecord
}

@ModelActor
actor SavedWalletStore: SavedWalletStoreProtocol {
    func loadSnapshot() throws -> SavedWalletSnapshot {
        let wallets = try wallets()
        let storedSelection = try selectionRecord()?.walletID
        let resolvedSelection = wallets.contains { $0.id == storedSelection }
            ? storedSelection
            : wallets.first?.id
        if storedSelection != resolvedSelection {
            do {
                try setSelection(resolvedSelection)
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw error
            }
        }
        return SavedWalletSnapshot(
            wallets: wallets,
            selectedWalletID: resolvedSelection
        )
    }

    func addAndSelect(_ wallet: SavedWallet) throws -> SavedWalletSnapshot {
        do {
            modelContext.insert(SavedWalletRecord(wallet: wallet))
            try setSelection(wallet.id)
            try modelContext.save()
            return try snapshot()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) throws -> SavedWalletSnapshot {
        var descriptor = FetchDescriptor<SavedWalletRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw SavedWalletStoreError.walletNotFound
        }
        do {
            record.name = name
            record.cardColor = cardColor.rawValue
            try modelContext.save()
            return try snapshot()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func delete(id: UUID) throws -> SavedWalletSnapshot {
        var descriptor = FetchDescriptor<SavedWalletRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw SavedWalletStoreError.walletNotFound
        }
        do {
            let storedSelection = try selectionRecord()?.walletID
            let remaining = try wallets().filter { $0.id != id }
            modelContext.delete(record)
            let selectionStillExists = remaining.contains {
                $0.id == storedSelection
            }
            if storedSelection == id || !selectionStillExists {
                try setSelection(remaining.first?.id)
            }
            try modelContext.save()
            return try snapshot()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func snapshot() throws -> SavedWalletSnapshot {
        SavedWalletSnapshot(
            wallets: try wallets(),
            selectedWalletID: try selectionRecord()?.walletID
        )
    }

    private func wallets() throws -> [SavedWallet] {
        let records = try modelContext.fetch(FetchDescriptor<SavedWalletRecord>())
            .sorted {
                if $0.createdAt == $1.createdAt {
                    $0.id.uuidString < $1.id.uuidString
                } else {
                    $0.createdAt < $1.createdAt
                }
            }
        return try records.map { record in
            guard let address = EVMAddress(rawValue: record.address),
                  let color = WalletCardColor(rawValue: record.cardColor) else {
                throw SavedWalletStoreError.corruptRecord
            }
            return SavedWallet(
                id: record.id,
                name: record.name,
                address: address,
                cardColor: color,
                createdAt: record.createdAt
            )
        }
    }

    private func selectionRecord() throws -> WalletSelectionRecord? {
        var descriptor = FetchDescriptor<WalletSelectionRecord>(
            predicate: #Predicate { $0.key == "selected" }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func setSelection(_ id: UUID?) throws {
        if let record = try selectionRecord() {
            if let id {
                record.walletID = id
            } else {
                modelContext.delete(record)
            }
        } else if let id {
            modelContext.insert(WalletSelectionRecord(walletID: id))
        }
    }
}
```

Keep record decoding strict: corrupt address/color data must surface an error instead of being silently omitted.

- [ ] **Step 5: Run tests and commit**

Run the Step 2 command.

Expected: `SavedWalletStoreTests` passes, including the disk-backed reload.

```bash
git add sevenwallet/Persistence/SavedWalletModels.swift sevenwallet/Persistence/SavedWalletStore.swift sevenwallet/Persistence/WalletCacheModels.swift sevenwalletTests/SavedWalletStoreTests.swift
git commit -m "feat: persist saved wallets and selection"
```

---

### Task 3: Address-Linked Cache Purging

**Files:**
- Modify: `sevenwallet/Persistence/WalletStore.swift`
- Modify: `sevenwalletTests/WalletStoreTests.swift`

**Interfaces:**
- Consumes: existing `WalletStoreProtocol`, `PortfolioCacheRecord`, and `TransactionPageCacheRecord`.
- Produces: `AddressCachePurging.purgeAddressData(address:)`.

- [ ] **Step 1: Write a failing purge-isolation test**

Add to `WalletStoreTests`:

```swift
@Test func purgeDeletesOnlyMatchingAddressData() async throws {
    let store = try makeStore()
    let deletedAddress = try testAddress()
    let keptAddress = try EVMAddress("0x1234567890123456789012345678901234567890")
    let deletedPortfolio = TokenPortfolio(
        address: deletedAddress,
        fetchedAt: nil,
        network: "ethereum",
        tokens: []
    )
    let keptPortfolio = TokenPortfolio(
        address: keptAddress,
        fetchedAt: nil,
        network: "ethereum",
        tokens: []
    )
    try await store.saveNativeTokens([makeToken(price: "100")], fetchedAt: .distantPast)
    try await store.savePortfolio(deletedPortfolio, fetchedAt: .distantPast)
    try await store.savePortfolio(keptPortfolio, fetchedAt: .distantPast)
    try await store.saveTransactionPage(
        TransactionPage(address: deletedAddress, nextPageKey: nil, transfers: []),
        limit: 25,
        pageKey: nil,
        fetchedAt: .distantPast
    )

    try await store.purgeAddressData(address: deletedAddress)

    #expect(try await store.loadPortfolio(address: deletedAddress) == nil)
    #expect(try await store.loadTransactionPage(
        address: deletedAddress,
        limit: 25,
        pageKey: nil
    ) == nil)
    #expect(try await store.loadPortfolio(address: keptAddress)?.value == keptPortfolio)
    #expect(try await store.loadNativeTokens() != nil)
}
```

- [ ] **Step 2: Run the focused suite and verify it fails**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-input -only-testing:sevenwalletTests/WalletStoreTests -parallel-testing-enabled NO test
```

Expected: compilation fails because `purgeAddressData(address:)` is missing.

- [ ] **Step 3: Add the purge protocol and atomic cache deletion**

Add above `WalletStoreProtocol`:

```swift
protocol AddressCachePurging: Sendable {
    func purgeAddressData(address: EVMAddress) async throws
}
```

Make the existing protocol inherit it:

```swift
protocol WalletStoreProtocol: AddressCachePurging {
    // existing load/save declarations remain unchanged
}
```

Add to `WalletStore`:

```swift
func purgeAddressData(address: EVMAddress) throws {
    let normalizedAddress = address.rawValue
    let portfolios = try modelContext.fetch(
        FetchDescriptor<PortfolioCacheRecord>(
            predicate: #Predicate { $0.address == normalizedAddress }
        )
    )
    let pages = try modelContext.fetch(
        FetchDescriptor<TransactionPageCacheRecord>(
            predicate: #Predicate { $0.address == normalizedAddress }
        )
    )
    do {
        portfolios.forEach(modelContext.delete)
        pages.forEach(modelContext.delete)
        try modelContext.save()
    } catch {
        modelContext.rollback()
        throw error
    }
}
```

- [ ] **Step 4: Run tests and commit**

Run the Step 2 command.

Expected: all `WalletStoreTests` pass.

```bash
git add sevenwallet/Persistence/WalletStore.swift sevenwalletTests/WalletStoreTests.swift
git commit -m "feat: purge address-linked wallet caches"
```

---

### Task 4: Observable Wallet Session

**Files:**
- Create: `sevenwallet/Application/WalletSession.swift`
- Create: `sevenwalletTests/WalletSessionTests.swift`
- Modify: `sevenwalletTests/Support/RepositoryTestDoubles.swift`

**Interfaces:**
- Consumes: `SavedWalletStoreProtocol` and `AddressCachePurging`.
- Produces: `WalletSession.load()`, `add(name:address:cardColor:)`, `update(id:name:cardColor:)`, and `delete(id:)`.

- [ ] **Step 1: Add controllable store doubles and failing session tests**

Add actor-backed doubles to `RepositoryTestDoubles.swift`:

```swift
actor ScriptedSavedWalletStore: SavedWalletStoreProtocol {
    var snapshot: SavedWalletSnapshot
    var error: (any Error & Sendable)?

    init(snapshot: SavedWalletSnapshot = .init(wallets: [], selectedWalletID: nil)) {
        self.snapshot = snapshot
    }

    func loadSnapshot() throws -> SavedWalletSnapshot {
        if let error { throw error }
        return snapshot
    }

    func addAndSelect(_ wallet: SavedWallet) throws -> SavedWalletSnapshot {
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
    ) throws -> SavedWalletSnapshot {
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

    func delete(id: UUID) throws -> SavedWalletSnapshot {
        if let error { throw error }
        let wallets = snapshot.wallets.filter { $0.id != id }
        snapshot = .init(wallets: wallets, selectedWalletID: wallets.first?.id)
        return snapshot
    }

    func setError(_ error: (any Error & Sendable)?) {
        self.error = error
    }
}

actor RecordingAddressCachePurger: AddressCachePurging {
    var addresses: [EVMAddress] = []
    var error: (any Error & Sendable)?

    func purgeAddressData(address: EVMAddress) throws {
        if let error { throw error }
        addresses.append(address)
    }

    func setError(_ error: (any Error & Sendable)?) {
        self.error = error
    }
}
```

Create `WalletSessionTests.swift`:

```swift
import Foundation
import Testing
@testable import sevenwallet

@MainActor
struct WalletSessionTests {
    @Test func loadPublishesSelectedWallet() async throws {
        let wallet = try makeWallet(name: "Main")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )

        await session.load()

        #expect(session.wallets == [wallet])
        #expect(session.selectedWallet == wallet)
        #expect(session.loadErrorMessage == nil)
    }

    @Test func addAndEditPublishOnlySuccessfulSnapshots() async throws {
        let store = ScriptedSavedWalletStore()
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        let address = try EVMAddress(
            "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
        )

        try await session.add(name: "Main", address: address, cardColor: .blue)
        let id = try #require(session.selectedWallet?.id)
        try await session.update(id: id, name: "Renamed", cardColor: .pink)

        #expect(session.selectedWallet?.name == "Renamed")
        #expect(session.selectedWallet?.address == address)
        #expect(session.selectedWallet?.cardColor == .pink)
    }

    @Test func purgeFailureStopsDeletion() async throws {
        let wallet = try makeWallet(name: "Main")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let purger = RecordingAddressCachePurger()
        await purger.setError(RepositoryTestError.remoteFailure)
        let session = WalletSession(store: store, cachePurger: purger)
        await session.load()

        await #expect(throws: RepositoryTestError.remoteFailure) {
            try await session.delete(id: wallet.id)
        }

        #expect(session.selectedWallet == wallet)
        #expect(try await store.loadSnapshot().wallets == [wallet])
    }

    private func makeWallet(name: String) throws -> SavedWallet {
        SavedWallet(
            name: name,
            address: try EVMAddress(
                "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
            ),
            cardColor: .blue
        )
    }
}
```

- [ ] **Step 2: Run the focused suite and verify it fails**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-input -only-testing:sevenwalletTests/WalletSessionTests -parallel-testing-enabled NO test
```

Expected: compilation fails because `WalletSession` is undefined.

- [ ] **Step 3: Implement session state and purge-first deletion**

Create `sevenwallet/Application/WalletSession.swift`:

```swift
import Observation

@MainActor
@Observable
final class WalletSession {
    private(set) var wallets: [SavedWallet] = []
    private(set) var selectedWallet: SavedWallet?
    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?

    private let store: any SavedWalletStoreProtocol
    private let cachePurger: any AddressCachePurging

    init(
        store: any SavedWalletStoreProtocol,
        cachePurger: any AddressCachePurging
    ) {
        self.store = store
        self.cachePurger = cachePurger
    }

    func load() async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }
        do {
            apply(try await store.loadSnapshot())
        } catch {
            loadErrorMessage = "Unable to load saved wallets."
        }
    }

    func add(
        name: String,
        address: EVMAddress,
        cardColor: WalletCardColor
    ) async throws {
        let wallet = SavedWallet(
            name: name,
            address: address,
            cardColor: cardColor
        )
        apply(try await store.addAndSelect(wallet))
    }

    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) async throws {
        apply(try await store.update(id: id, name: name, cardColor: cardColor))
    }

    func delete(id: UUID) async throws {
        guard let wallet = wallets.first(where: { $0.id == id }) else {
            throw SavedWalletStoreError.walletNotFound
        }
        try await cachePurger.purgeAddressData(address: wallet.address)
        apply(try await store.delete(id: id))
    }

    private func apply(_ snapshot: SavedWalletSnapshot) {
        wallets = snapshot.wallets
        selectedWallet = snapshot.selectedWallet
    }
}
```

Do not clear published wallets before a failing load or mutation. The UI must retain its last valid state.

- [ ] **Step 4: Run tests and commit**

Run the Step 2 command.

Expected: `WalletSessionTests` passes.

```bash
git add sevenwallet/Application/WalletSession.swift sevenwalletTests/WalletSessionTests.swift sevenwalletTests/Support/RepositoryTestDoubles.swift
git commit -m "feat: coordinate saved wallet session"
```

---

### Task 5: Selected-Address Portfolio Home State

**Files:**
- Modify: `sevenwallet/View/Wallet/WalletHomeViewModel.swift`
- Modify: `sevenwallet/View/Wallet/WalletCardViewModel.swift`
- Modify: `sevenwalletTests/WalletHomeViewModelTests.swift`
- Modify: `sevenwalletTests/WalletCardViewModelTests.swift`

**Interfaces:**
- Consumes: `SavedWallet`, `TokenRepositoryProtocol.nativeTokens`, and `TokenRepositoryProtocol.portfolio`.
- Produces: `WalletHomeViewModel.load(wallet:)` and a card view model containing wallet ID/color.

- [ ] **Step 1: Write failing portfolio-switching tests**

Add this focused repository spy to `RepositoryTestDoubles.swift`:

```swift
@MainActor
final class PortfolioTokenRepositorySpy: TokenRepositoryProtocol {
    typealias NativeEvent = RepositoryLoadEvent<[WalletToken]>
    typealias PortfolioEvent = RepositoryLoadEvent<TokenPortfolio>

    private var nativeScripts: [[NativeEvent]]
    private var portfolioScripts: [[PortfolioEvent]]
    private let holdsPortfolioOpen: Bool
    private(set) var requestedPortfolioAddresses: [EVMAddress] = []

    init(
        nativeScripts: [[NativeEvent]] = [],
        portfolioScripts: [[PortfolioEvent]] = [],
        holdsPortfolioOpen: Bool = false
    ) {
        self.nativeScripts = nativeScripts
        self.portfolioScripts = portfolioScripts
        self.holdsPortfolioOpen = holdsPortfolioOpen
    }

    func nativeTokens(
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<NativeEvent, Swift.Error> {
        stream(events: nativeScripts.removeFirst(), holdsOpen: false)
    }

    func portfolio(
        address: EVMAddress,
        policy: RefreshPolicy
    ) -> AsyncThrowingStream<PortfolioEvent, Swift.Error> {
        requestedPortfolioAddresses.append(address)
        return stream(
            events: portfolioScripts.removeFirst(),
            holdsOpen: holdsPortfolioOpen
        )
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
}
```

Add these tests:

```swift
@Test func selectedWalletLoadsItsPortfolio() async throws {
    let wallet = SavedWallet(
        name: "Main",
        address: try EVMAddress(
            "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
        ),
        cardColor: .purple
    )
    let portfolio = TokenPortfolio(
        address: wallet.address,
        fetchedAt: nil,
        network: "ethereum",
        tokens: [makeRepositoryToken(price: "2000")]
    )
    let repository = PortfolioTokenRepositorySpy(
        portfolioScripts: [[.fresh(portfolio)]]
    )
    let home = WalletHomeViewModel(tokenRepository: repository)

    await home.load(wallet: wallet)

    #expect(repository.requestedPortfolioAddresses == [wallet.address])
    #expect(home.walletCard?.id == wallet.id)
    #expect(home.walletCard?.name == "Main")
    #expect(home.walletCard?.cardColor == .purple)
    #expect(home.tokens.first?.formattedPrice == "$2,000.00")
}

@Test func editingIdentityRebuildsCardWithoutReloadingPortfolio() async throws {
    let original = try makeSavedWallet(name: "Main", color: .blue)
    let edited = SavedWallet(
        id: original.id,
        name: "Renamed",
        address: original.address,
        cardColor: .amber,
        createdAt: original.createdAt
    )
    let repository = PortfolioTokenRepositorySpy(
        portfolioScripts: [
            [.fresh(TokenPortfolio(
                address: original.address,
                fetchedAt: nil,
                network: "ethereum",
                tokens: [makeRepositoryToken(price: "2000")]
            ))]
        ]
    )
    let home = WalletHomeViewModel(tokenRepository: repository)

    await home.load(wallet: original)
    await home.load(wallet: edited)

    #expect(repository.requestedPortfolioAddresses == [original.address])
    #expect(home.walletCard?.name == "Renamed")
    #expect(home.walletCard?.cardColor == .amber)
}

@Test func deletingSelectionReturnsToNativeTokensAndIgnoresOldResults() async throws {
    let wallet = try makeSavedWallet(name: "Main", color: .blue)
    let repository = PortfolioTokenRepositorySpy(
        nativeScripts: [[.fresh([makeRepositoryToken(price: "1900")])]],
        portfolioScripts: [[.refreshing]],
        holdsPortfolioOpen: true
    )
    let home = WalletHomeViewModel(tokenRepository: repository)

    let oldLoad = Task { await home.load(wallet: wallet) }
    await waitForLoading(home)
    await home.load(wallet: nil)
    oldLoad.cancel()

    #expect(home.walletCard == nil)
    #expect(home.tokens.first?.formattedPrice == "$1,900.00")
}

private func makeSavedWallet(
    name: String,
    color: WalletCardColor
) throws -> SavedWallet {
    SavedWallet(
        name: name,
        address: try EVMAddress(
            "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
        ),
        cardColor: color
    )
}
```

- [ ] **Step 2: Run the focused suites and verify failure**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-input -only-testing:sevenwalletTests/WalletHomeViewModelTests -only-testing:sevenwalletTests/WalletCardViewModelTests -parallel-testing-enabled NO test
```

Expected: tests fail because home has no `load(wallet:)` and the card model has no wallet ID/color.

- [ ] **Step 3: Extend the wallet card view model**

Change its stored identity and initializer to:

```swift
let id: UUID
let name: String
let address: String
let cardColor: WalletCardColor
let tokens: [TokenViewModel]

init(wallet: SavedWallet, tokens: [TokenViewModel]) {
    id = wallet.id
    name = wallet.name
    address = wallet.address.rawValue
    cardColor = wallet.cardColor
    self.tokens = tokens
}
```

Update existing card tests to construct a `SavedWallet` and assert ID, color, shortened address, and totals.

- [ ] **Step 4: Make home choose native or portfolio repository streams**

Replace constructor wallet strings with:

```swift
private var selectedWallet: SavedWallet?
```

Add:

```swift
func load(wallet: SavedWallet?) async {
    let addressChanged = selectedWallet?.address != wallet?.address
    selectedWallet = wallet
    rebuildWalletCard()

    guard addressChanged || tokens.isEmpty else { return }
    await consume(policy: .ifExpired)
}
```

Change `consume(policy:)` to choose the stream:

```swift
let stream: AsyncThrowingStream<
    RepositoryLoadEvent<[WalletToken]>,
    Swift.Error
>
if let selectedWallet {
    stream = tokenRepository
        .portfolio(address: selectedWallet.address, policy: policy)
        .mapValues(\.tokens)
} else {
    stream = tokenRepository.nativeTokens(policy: policy)
}
```

Implement `mapValues` as a private `AsyncThrowingStream` adapter in the same file:

```swift
private extension AsyncThrowingStream {
    func mapValues<Input, Output>(
        _ transform: @escaping @Sendable (Input) -> Output
    ) -> AsyncThrowingStream<RepositoryLoadEvent<Output>, Swift.Error>
    where Element == RepositoryLoadEvent<Input>, Failure == Swift.Error {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in self {
                        switch event {
                        case .cached(let value):
                            continuation.yield(.cached(transform(value)))
                        case .refreshing:
                            continuation.yield(.refreshing)
                        case .fresh(let value):
                            continuation.yield(.fresh(transform(value)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
```

Keep request-generation checks around every event. Rebuild the card after token changes:

```swift
private func rebuildWalletCard() {
    walletCard = selectedWallet.map {
        WalletCardViewModel(wallet: $0, tokens: tokens)
    }
}
```

`refreshTokens()` and `retryTokens()` use the currently selected resource. A wallet identity-only edit rebuilds the card without contacting the repository.

- [ ] **Step 5: Run tests and commit**

Run the Step 2 command.

Expected: focused home and card suites pass, including stale-request cancellation.

```bash
git add sevenwallet/View/Wallet/WalletHomeViewModel.swift sevenwallet/View/Wallet/WalletCardViewModel.swift sevenwalletTests/WalletHomeViewModelTests.swift sevenwalletTests/WalletCardViewModelTests.swift sevenwalletTests/Support/RepositoryTestDoubles.swift
git commit -m "feat: load selected wallet portfolio"
```

---

### Task 6: Wallet Form State and Actions

**Files:**
- Create: `sevenwallet/View/Wallet/WalletFormViewModel.swift`
- Create: `sevenwalletTests/WalletFormViewModelTests.swift`

**Interfaces:**
- Consumes: `WalletSession`, `WalletInputValidator`, and optional `SavedWallet`.
- Produces: `WalletFormMode` and async `submit(session:)` / `delete(session:)` results.

- [ ] **Step 1: Write failing form-state tests**

```swift
import Testing
@testable import sevenwallet

@MainActor
struct WalletFormViewModelTests {
    @Test func addRequiresValidNameAndAddress() {
        let form = WalletFormViewModel(mode: .add)
        form.setName("Main")
        form.address = "0x1234"
        #expect(!form.canSubmit)
        #expect(form.addressError == nil)

        form.didInteractWithAddress = true
        #expect(form.addressError == "Enter a valid Ethereum address.")

        form.address = "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
        #expect(form.canSubmit)
        #expect(form.primaryActionTitle == "Add wallet")
    }

    @Test func nameInputCapsAtTwentyCharacters() {
        let form = WalletFormViewModel(mode: .add)
        form.setName("12345678901234567890x")
        #expect(form.name == "12345678901234567890")
    }

    @Test func editPrefillsAndLocksAddress() throws {
        let wallet = SavedWallet(
            name: "Main",
            address: try EVMAddress(
                "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
            ),
            cardColor: .teal
        )
        let form = WalletFormViewModel(mode: .edit(wallet))
        #expect(form.title == "Edit wallet")
        #expect(form.primaryActionTitle == "Save changes")
        #expect(form.name == "Main")
        #expect(form.address == wallet.address.rawValue)
        #expect(!form.isAddressEditable)
        #expect(form.showsDelete)
    }

    @Test func failedSavePreservesInputAndShowsError() async throws {
        let store = ScriptedSavedWalletStore()
        await store.setError(RepositoryTestError.remoteFailure)
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        let form = WalletFormViewModel(mode: .add)
        form.setName("Main")
        form.address = "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"

        #expect(await form.submit(session: session) == false)
        #expect(form.name == "Main")
        #expect(form.submissionError == "Unable to save wallet.")
        #expect(!form.isSubmitting)
    }
}
```

- [ ] **Step 2: Run the focused suite and verify it fails**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-input -only-testing:sevenwalletTests/WalletFormViewModelTests -parallel-testing-enabled NO test
```

Expected: compilation fails because the form mode and view model are undefined.

- [ ] **Step 3: Implement mode-specific form state**

Create `WalletFormViewModel.swift`:

```swift
import Observation

nonisolated enum WalletFormMode: Hashable, Sendable {
    case add
    case edit(SavedWallet)
}

@MainActor
@Observable
final class WalletFormViewModel {
    let mode: WalletFormMode
    var name: String
    var address: String
    var selectedColor: WalletCardColor
    var didInteractWithName = false
    var didInteractWithAddress = false
    private(set) var isSubmitting = false
    private(set) var submissionError: String?

    init(mode: WalletFormMode) {
        self.mode = mode
        switch mode {
        case .add:
            name = ""
            address = ""
            selectedColor = .blue
        case .edit(let wallet):
            name = wallet.name
            address = wallet.address.rawValue
            selectedColor = wallet.cardColor
        }
    }

    var title: String {
        if case .add = mode { "Add wallet" } else { "Edit wallet" }
    }

    var primaryActionTitle: String {
        if case .add = mode { "Add wallet" } else { "Save changes" }
    }

    var isAddressEditable: Bool {
        if case .add = mode { true } else { false }
    }

    var showsDelete: Bool {
        if case .edit = mode { true } else { false }
    }

    var nameError: String? {
        guard didInteractWithName,
              WalletInputValidator.validatedName(name) == nil else { return nil }
        return "Enter a wallet name."
    }

    var addressError: String? {
        guard isAddressEditable,
              didInteractWithAddress,
              WalletInputValidator.validatedAddress(address) == nil else { return nil }
        return "Enter a valid Ethereum address."
    }

    var canSubmit: Bool {
        guard !isSubmitting,
              WalletInputValidator.validatedName(name) != nil else { return false }
        return !isAddressEditable ||
            WalletInputValidator.validatedAddress(address) != nil
    }

    func setName(_ value: String) {
        name = WalletInputValidator.limitedName(value)
    }

    func submit(session: WalletSession) async -> Bool {
        didInteractWithName = true
        didInteractWithAddress = true
        guard let validName = WalletInputValidator.validatedName(name),
              canSubmit else { return false }
        isSubmitting = true
        submissionError = nil
        defer { isSubmitting = false }
        do {
            switch mode {
            case .add:
                guard let validAddress =
                    WalletInputValidator.validatedAddress(address) else { return false }
                try await session.add(
                    name: validName,
                    address: validAddress,
                    cardColor: selectedColor
                )
            case .edit(let wallet):
                try await session.update(
                    id: wallet.id,
                    name: validName,
                    cardColor: selectedColor
                )
            }
            return true
        } catch {
            submissionError = "Unable to save wallet."
            return false
        }
    }

    func delete(session: WalletSession) async -> Bool {
        guard case .edit(let wallet) = mode, !isSubmitting else { return false }
        isSubmitting = true
        submissionError = nil
        defer { isSubmitting = false }
        do {
            try await session.delete(id: wallet.id)
            return true
        } catch {
            submissionError = "Unable to delete wallet."
            return false
        }
    }
}
```

The view owns confirmation presentation; `delete(session:)` runs only after confirmation.

- [ ] **Step 4: Run tests and commit**

Run the Step 2 command.

Expected: `WalletFormViewModelTests` passes.

```bash
git add sevenwallet/View/Wallet/WalletFormViewModel.swift sevenwalletTests/WalletFormViewModelTests.swift
git commit -m "feat: add wallet form state and actions"
```

---

### Task 7: Navigation, Form UI, and Card Interactions

**Files:**
- Create: `sevenwallet/View/Wallet/WalletCardColor+View.swift`
- Create: `sevenwallet/View/Wallet/WalletFormView.swift`
- Create: `sevenwallet/View/Wallet/WalletRootView.swift`
- Modify: `sevenwallet/View/Navigation/Screen.swift`
- Modify: `sevenwallet/View/Wallet/EmptyWalletCardView.swift`
- Modify: `sevenwallet/View/Wallet/WalletCardView.swift`
- Modify: `sevenwallet/View/Wallet/WalletHomePage.swift`
- Modify: `sevenwallet/Application/AppDependencies.swift`
- Modify: `sevenwallet/sevenwalletApp.swift`

**Interfaces:**
- Consumes: `WalletSession`, `WalletHomeViewModel`, `WalletFormViewModel`, and `Screen`.
- Produces: complete add/edit/delete navigation and the supplied form layout.

- [ ] **Step 1: Add typed routes and gradient mapping**

Replace `Screen` with:

```swift
import Foundation

enum Screen: Hashable {
    case addWallet
    case editWallet(UUID)
    case detail
    case manage
    case token(String)
}
```

Create `WalletCardColor+View.swift`:

```swift
import SwiftUI

extension WalletCardColor {
    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .blue: colors = [Color(hex: 0x3B82F6), Color(hex: 0x252762)]
        case .purple: colors = [Color(hex: 0x9B4DFF), Color(hex: 0x50167F)]
        case .pink: colors = [Color(hex: 0xE13C99), Color(hex: 0x77105F)]
        case .teal: colors = [Color(hex: 0x1AAE9F), Color(hex: 0x075D58)]
        case .amber: colors = [Color(hex: 0xF59E0B), Color(hex: 0x854300)]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
```

- [ ] **Step 2: Make empty and populated cards expose separate controls**

Change `EmptyWalletCardView` to accept `onAdd` and wrap its existing content in a plain button:

```swift
let onAdd: () -> Void

Button(action: onAdd) {
    emptyCardContent
}
.buttonStyle(.plain)
.accessibilityLabel("Add your first wallet")
.accessibilityIdentifier("empty-wallet-card")
```

Change `WalletCardView` to accept:

```swift
let onEdit: () -> Void
```

Replace the name `Text` with a plain button whose label contains the full tappable name region:

```swift
Button(action: onEdit) {
    HStack(spacing: 8) {
        Text(viewModel.name)
            .font(.headline)
        Image(systemName: "pencil")
            .font(.caption.weight(.semibold))
    }
    .foregroundStyle(.white)
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
.accessibilityLabel("Edit \(viewModel.name)")
.accessibilityIdentifier("edit-wallet-button")
```

Keep the existing address-copy `Button` as a sibling, not inside the edit button. Use white-opacity foregrounds and:

```swift
.background(viewModel.cardColor.gradient)
```

Retain the 212-point minimum height and `wallet-card` identifier.

- [ ] **Step 3: Build the mode-driven form**

Create `WalletFormView.swift` with:

```swift
import SwiftUI

struct WalletFormView: View {
    @State private var viewModel: WalletFormViewModel
    let session: WalletSession
    let theme: Theme
    let onComplete: () -> Void
    let onCancel: () -> Void
    @State private var confirmsDelete = false

    init(
        mode: WalletFormMode,
        session: WalletSession,
        theme: Theme,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: WalletFormViewModel(mode: mode))
        self.session = session
        self.theme = theme
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    preview
                    walletNameField
                    addressField
                    networkRow
                    colorPicker
                    primaryButton
                    if viewModel.showsDelete { deleteButton }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Delete wallet?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete wallet", role: .destructive) {
                Task {
                    if await viewModel.delete(session: session) { onComplete() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the wallet and its cached address data from this device.")
        }
    }
}
```

Implement its private subviews directly from the approved reference:

- Header back button and `viewModel.title`.
- Preview at 130-point minimum height using `selectedColor.gradient`, uppercase name fallback `WALLET NAME`, `ETHEREUM`, and `Fmt.short(address)` fallback `0x…`.
- Themed rounded input rows; name uses an explicit `Binding` that calls `setName`.
- Add-mode address uses `.textInputAutocapitalization(.never)` and `.autocorrectionDisabled()`.
- Edit-mode address is a `Text` value, not a disabled `TextField`.
- Locked Ethereum row with `lock.fill` and supporting copy.
- Five `WalletCardColor.allCases` controls with selected blue outline.
- Disabled/loading primary action with identifiers `wallet-primary-action`.
- Inline `nameError`, `addressError`, and `submissionError`.
- Edit-only red bordered `Delete wallet` button with identifier `delete-wallet-button`.

Use these identifiers for fields:

```swift
"wallet-name-field"
"wallet-address-field"
"wallet-color-\(color.rawValue)"
"wallet-primary-action"
"delete-wallet-button"
```

The primary action is:

```swift
Button {
    Task {
        if await viewModel.submit(session: session) { onComplete() }
    }
} label: {
    if viewModel.isSubmitting {
        ProgressView().frame(maxWidth: .infinity)
    } else {
        Text(viewModel.primaryActionTitle).frame(maxWidth: .infinity)
    }
}
.disabled(!viewModel.canSubmit)
```

- [ ] **Step 4: Add root navigation and session-driven home**

Create `WalletRootView.swift`:

```swift
import SwiftUI

@MainActor
struct WalletRootView: View {
    @State var session: WalletSession
    @State var homeViewModel: WalletHomeViewModel
    @State private var path: [Screen] = []

    private var theme: Theme {
        homeViewModel.isThemeLight ? .light : .dark
    }

    var body: some View {
        NavigationStack(path: $path) {
            WalletHomeView(
                viewModel: homeViewModel,
                wallet: session.selectedWallet,
                walletLoadError: session.loadErrorMessage,
                onRetryWallets: { Task { await session.load() } },
                onAddWallet: { path.append(.addWallet) },
                onEditWallet: { path.append(.editWallet($0)) }
            )
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .addWallet:
                    form(mode: .add)
                case .editWallet(let id):
                    if let wallet = session.wallets.first(where: { $0.id == id }) {
                        form(mode: .edit(wallet))
                    } else {
                        Color.clear.task { path.removeAll() }
                    }
                default:
                    Color.clear
                }
            }
        }
        .task { await session.load() }
    }

    private func form(mode: WalletFormMode) -> some View {
        WalletFormView(
            mode: mode,
            session: session,
            theme: theme,
            onComplete: { path.removeAll() },
            onCancel: { if !path.isEmpty { path.removeLast() } }
        )
    }
}
```

Update `WalletHomeView` parameters and card section:

```swift
let wallet: SavedWallet?
let walletLoadError: String?
let onRetryWallets: () -> Void
let onAddWallet: () -> Void
let onEditWallet: (UUID) -> Void
```

Use `EmptyWalletCardView(theme:onAdd:)` or `WalletCardView(..., onEdit:)`. Add:

```swift
.task(id: wallet) {
    await viewModel.load(wallet: wallet)
}
```

When `walletLoadError` is present, show the same concise inline error/Retry pattern above the card instead of treating storage failure as an empty state.

- [ ] **Step 5: Compose one shared model container**

Replace `makeHomeViewModel` with:

```swift
@MainActor
struct WalletAppState {
    let session: WalletSession
    let homeViewModel: WalletHomeViewModel
}

@MainActor
static func makeAppState(
    arguments: [String] = ProcessInfo.processInfo.arguments,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
    inMemoryStore: Bool = false
) -> WalletAppState
```

Create the SwiftData schema/container before resolving `BASE_URL`, so saved wallets remain available even when API configuration is missing. Create:

```swift
let cacheStore = WalletStore(modelContainer: container)
let savedWalletStore = SavedWalletStore(modelContainer: container)
let session = WalletSession(store: savedWalletStore, cachePurger: cacheStore)
```

Use the existing real or failing token repository to create `WalletHomeViewModel`. Preserve current fixture arguments with in-memory scripted repositories and a deterministic `SavedWalletStoreProtocol` fixture.

Update existing app-dependency tests from the old factory:

```swift
let state = AppDependencies.makeAppState(
    arguments: arguments,
    environment: environment,
    infoDictionary: infoDictionary,
    inMemoryStore: true
)
await state.session.load()
await state.homeViewModel.load(wallet: state.session.selectedWallet)
let home = state.homeViewModel
```

For the existing `UI_TEST_POPULATED_WALLET` fixture, initialize the fixture
saved-wallet snapshot with `Main Wallet`; otherwise initialize it empty. Keep
the existing long-list, delayed-loading, and token-error repository scripts
unchanged.

Update the app:

```swift
@main
struct sevenwalletApp: App {
    @State private var state = AppDependencies.makeAppState()

    var body: some Scene {
        WindowGroup {
            WalletRootView(
                session: state.session,
                homeViewModel: state.homeViewModel
            )
        }
    }
}
```

- [ ] **Step 6: Run unit tests and simulator build**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-input -only-testing:sevenwalletTests -parallel-testing-enabled NO test
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/sevenwallet-wallet-input CODE_SIGNING_ALLOWED=NO build
```

Expected: unit suite passes and the app builds. Manually inspect compiler diagnostics for accidental nested buttons or non-Sendable captures; the copy and edit controls must remain sibling buttons.

- [ ] **Step 7: Commit**

```bash
git add sevenwallet/View/Navigation/Screen.swift sevenwallet/View/Wallet/WalletCardColor+View.swift sevenwallet/View/Wallet/WalletFormView.swift sevenwallet/View/Wallet/WalletRootView.swift sevenwallet/View/Wallet/EmptyWalletCardView.swift sevenwallet/View/Wallet/WalletCardView.swift sevenwallet/View/Wallet/WalletHomePage.swift sevenwallet/Application/AppDependencies.swift sevenwallet/sevenwalletApp.swift
git commit -m "feat: add wallet form and navigation"
```

---

### Task 8: UI Flows, Relaunch Persistence, and Full Regression

**Files:**
- Modify: `sevenwallet/Application/AppDependencies.swift`
- Modify: `sevenwalletUITests/sevenwalletUITests.swift`
- Modify: affected unit tests for new app-state factory signatures.

**Interfaces:**
- Consumes: completed wallet UI, deterministic fixture arguments, and persistent SwiftData app storage.
- Produces: end-to-end coverage of add, edit, copy separation, delete confirmation, and relaunch.

- [ ] **Step 1: Add deterministic UI-test storage controls**

In `AppDependencies.makeAppState`, support these UI-test-only arguments before session creation:

```swift
"UI_TEST_PERSIST_SAVED_WALLETS"
"UI_TEST_CLEAR_SAVED_WALLETS"
"UI_TEST_SEED_SAVED_WALLET"
```

For `UI_TEST_FIXTURE`, use a stable on-disk `ModelConfiguration` named
`UITestWallets` only when `UI_TEST_PERSIST_SAVED_WALLETS` is present. Otherwise
retain isolated in-memory fixture storage. On clear, delete all
`SavedWalletRecord` and `WalletSelectionRecord` values before constructing the
session. On seed, insert this exact wallet only when the wallet table is empty:

```swift
SavedWallet(
    name: "Main Wallet",
    address: try EVMAddress(
        "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
    ),
    cardColor: .blue
)
```

Keep all API responses fixture-backed. Never read the production `BASE_URL`.

- [ ] **Step 2: Add the first-wallet add flow UI test**

```swift
@MainActor
func testAddWalletFlow() throws {
    let app = XCUIApplication()
    app.launchArguments = [
        "UI_TEST_FIXTURE",
        "UI_TEST_PERSIST_SAVED_WALLETS",
        "UI_TEST_CLEAR_SAVED_WALLETS"
    ]
    app.launch()

    let emptyCard = app.buttons["empty-wallet-card"]
    XCTAssertTrue(emptyCard.waitForExistence(timeout: 2))
    emptyCard.tap()

    let name = app.textFields["wallet-name-field"]
    let address = app.textFields["wallet-address-field"]
    XCTAssertTrue(name.waitForExistence(timeout: 2))
    name.tap()
    name.typeText("Main Wallet")
    address.tap()
    address.typeText("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
    app.buttons["wallet-color-teal"].tap()
    app.buttons["wallet-primary-action"].tap()

    XCTAssertTrue(app.otherElements["wallet-card"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Main Wallet"].exists)
    XCTAssertFalse(app.buttons["empty-wallet-card"].exists)
}
```

- [ ] **Step 3: Add edit, copy, and delete-confirmation UI tests**

```swift
@MainActor
func testCopyDoesNotOpenEditButEditButtonDoes() throws {
    let app = seededWalletApp()
    app.launch()

    app.buttons["copy-wallet-address-button"].tap()
    XCTAssertFalse(app.textFields["wallet-name-field"].exists)

    app.buttons["edit-wallet-button"].tap()
    XCTAssertTrue(app.staticTexts["Edit wallet"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.textFields["wallet-address-field"].exists)
    XCTAssertTrue(app.staticTexts[
        "0x71a2b3c4d5e6f7890a1b2c3d4e5f67890abc8f92"
    ].exists)
}

@MainActor
func testEditAndConfirmedDelete() throws {
    let app = seededWalletApp()
    app.launch()
    app.buttons["edit-wallet-button"].tap()

    let name = app.textFields["wallet-name-field"]
    name.tap()
    name.clearAndEnterText("Renamed")
    app.buttons["wallet-color-amber"].tap()
    app.buttons["wallet-primary-action"].tap()
    XCTAssertTrue(app.staticTexts["Renamed"].waitForExistence(timeout: 2))

    app.buttons["edit-wallet-button"].tap()
    app.buttons["delete-wallet-button"].tap()
    XCTAssertTrue(app.buttons["Cancel"].exists)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.textFields["wallet-name-field"].exists)

    app.buttons["delete-wallet-button"].tap()
    app.buttons["Delete wallet"].tap()
    XCTAssertTrue(app.buttons["empty-wallet-card"].waitForExistence(timeout: 2))
}
```

Add this UI-test helper:

```swift
private func seededWalletApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
        "UI_TEST_FIXTURE",
        "UI_TEST_PERSIST_SAVED_WALLETS",
        "UI_TEST_CLEAR_SAVED_WALLETS",
        "UI_TEST_SEED_SAVED_WALLET"
    ]
    return app
}
```

Add an `XCUIElement.clearAndEnterText(_:)` helper that selects existing text with Command-A and types the replacement.

Update the existing empty-card and populated-card UI assertions to query
`app.buttons["empty-wallet-card"]` and `app.otherElements["wallet-card"]`
respectively. Preserve the existing card-height, theme, loading, error, and
pinned-header assertions.

- [ ] **Step 4: Verify persistence across relaunch**

```swift
@MainActor
func testWalletPersistsAcrossRelaunch() throws {
    let firstLaunch = seededWalletApp()
    firstLaunch.launch()
    XCTAssertTrue(firstLaunch.staticTexts["Main Wallet"].waitForExistence(timeout: 2))
    firstLaunch.terminate()

    let secondLaunch = XCUIApplication()
    secondLaunch.launchArguments = [
        "UI_TEST_FIXTURE",
        "UI_TEST_PERSIST_SAVED_WALLETS"
    ]
    secondLaunch.launch()

    XCTAssertTrue(secondLaunch.staticTexts["Main Wallet"].waitForExistence(timeout: 2))
    XCTAssertTrue(secondLaunch.otherElements["wallet-card"].exists)
}
```

Ensure the next UI test begins with `UI_TEST_CLEAR_SAVED_WALLETS` so tests do not leak state.

- [ ] **Step 5: Run focused UI flows**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-input -only-testing:sevenwalletUITests/sevenwalletUITests/testAddWalletFlow -only-testing:sevenwalletUITests/sevenwalletUITests/testCopyDoesNotOpenEditButEditButtonDoes -only-testing:sevenwalletUITests/sevenwalletUITests/testEditAndConfirmedDelete -only-testing:sevenwalletUITests/sevenwalletUITests/testWalletPersistsAcrossRelaunch -parallel-testing-enabled NO test
```

Expected: all four wallet flows pass without a live network request.

- [ ] **Step 6: Run the complete verification matrix**

```bash
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-input -only-testing:sevenwalletTests -parallel-testing-enabled NO test
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/sevenwallet-wallet-input -only-testing:sevenwalletUITests/sevenwalletUITests -parallel-testing-enabled NO test
xcodebuild -project sevenwallet.xcodeproj -scheme sevenwallet -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/sevenwallet-wallet-input CODE_SIGNING_ALLOWED=NO build
git diff --check
git status --short
```

Expected:

- Unit tests pass.
- UI tests pass.
- Simulator build succeeds.
- `git diff --check` emits no output.
- `git status --short` lists only the intended task changes before the final commit.

- [ ] **Step 7: Commit**

```bash
git add sevenwallet/Application/AppDependencies.swift sevenwalletUITests/sevenwalletUITests.swift sevenwalletTests
git commit -m "test: cover wallet input and editing flows"
```

---

## Final Review Checklist

- The add route is visible only while no wallet is selected.
- The store accepts more than one wallet and selects the newest.
- Add and selection are one SwiftData transaction.
- Name and address use the approved validation rules.
- Edit cannot change address or network.
- The selected gradient appears in preview and home card.
- Copy and edit are sibling controls with distinct accessibility actions.
- Portfolio loading uses the normalized selected address.
- Identity-only edits do not force portfolio refresh.
- Delete confirmation runs cache purge before identity deletion.
- Cache purge leaves native tokens and other-address data intact.
- Late portfolio events cannot restore deleted-wallet UI.
- Wallet identity survives app relaunch.
- All existing theme, loading, retry, pull-to-refresh, pinned-header, card-height, and copy tests still pass.
