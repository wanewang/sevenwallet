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
        let original = try wallet(name: "Persistent", suffix: "1111", date: 100)
        do {
            let firstContainer = try makeContainer(url: url)
            _ = try await SavedWalletStore(modelContainer: firstContainer).addAndSelect(original)
        }

        do {
            let secondContainer = try makeContainer(url: url)
            let snapshot = try await SavedWalletStore(modelContainer: secondContainer).loadSnapshot()

            #expect(snapshot.wallets == [original])
            #expect(snapshot.selectedWalletID == original.id)
        }
        try? FileManager.default.removeItem(at: url)
    }

    @Test func failedSnapshotDoesNotPersistAddOrSelection() async throws {
        let container = try makeContainer()
        let original = try wallet(name: "Original", suffix: "1111", date: 100)
        let corruptRecord = SavedWalletRecord(wallet: original)
        corruptRecord.address = "invalid"
        let context = ModelContext(container)
        context.insert(corruptRecord)
        context.insert(WalletSelectionRecord(walletID: original.id))
        try context.save()
        let candidate = try wallet(name: "Candidate", suffix: "2222", date: 200)

        await #expect(throws: SavedWalletStoreError.corruptRecord) {
            try await SavedWalletStore(modelContainer: container).addAndSelect(candidate)
        }

        let verificationContext = ModelContext(container)
        let walletIDs = try verificationContext.fetch(
            FetchDescriptor<SavedWalletRecord>()
        ).map(\.id)
        let selection = try verificationContext.fetch(
            FetchDescriptor<WalletSelectionRecord>()
        ).first?.walletID
        #expect(!walletIDs.contains(candidate.id))
        #expect(selection == original.id)
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
