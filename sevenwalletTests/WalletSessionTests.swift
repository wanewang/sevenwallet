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
        #expect(session.isLoading == false)
    }

    @Test func failedLoadRetainsLastPublishedSnapshot() async throws {
        let wallet = try makeWallet(name: "Main")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()
        await store.setError(RepositoryTestError.storageReadFailure)

        await session.load()

        #expect(session.wallets == [wallet])
        #expect(session.selectedWallet == wallet)
        #expect(session.loadErrorMessage == "Unable to load saved wallets.")
        #expect(session.isLoading == false)
    }

    @Test func addAndUpdatePublishSuccessfulSnapshots() async throws {
        let store = ScriptedSavedWalletStore()
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        let address = try EVMAddress(
            "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
        )

        try await session.add(
            name: "Main",
            address: address,
            cardColor: .blue
        )
        let id = try #require(session.selectedWallet?.id)
        try await session.update(
            id: id,
            name: "Renamed",
            cardColor: .pink
        )

        #expect(session.wallets.count == 1)
        #expect(session.selectedWallet?.name == "Renamed")
        #expect(session.selectedWallet?.address == address)
        #expect(session.selectedWallet?.cardColor == .pink)
    }

    @Test func failedUpdateRetainsLastPublishedSnapshot() async throws {
        let wallet = try makeWallet(name: "Main")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()
        await store.setError(RepositoryTestError.storageWriteFailure)

        await #expect(throws: RepositoryTestError.storageWriteFailure) {
            try await session.update(
                id: wallet.id,
                name: "Renamed",
                cardColor: .pink
            )
        }

        #expect(session.wallets == [wallet])
        #expect(session.selectedWallet == wallet)
    }

    @Test func deletePurgesNormalizedAddressBeforeDeletingIdentity() async throws {
        let recorder = WalletSessionCallRecorder()
        let wallet = try makeWallet(name: "Main")
        let normalizedAddress = try EVMAddress(
            "0x71a2b3c4d5e6f7890a1b2c3d4e5f67890abc8f92"
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id),
            recorder: recorder
        )
        let purger = RecordingAddressCachePurger(recorder: recorder)
        let session = WalletSession(store: store, cachePurger: purger)
        await session.load()

        try await session.delete(id: wallet.id)

        #expect(await recorder.calls == [
            .load,
            .purge(normalizedAddress),
            .delete(wallet.id)
        ])
        #expect(await purger.addresses == [normalizedAddress])
        #expect(session.wallets.isEmpty)
        #expect(session.selectedWallet == nil)
    }

    @Test func deleteSettlesPortfolioBeforePurgeAndIdentityDeletion() async throws {
        let recorder = WalletSessionCallRecorder()
        let wallet = try makeWallet(name: "Main")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id),
            recorder: recorder
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(recorder: recorder),
            portfolioLoadCanceller: RecordingPortfolioLoadCanceller(
                recorder: recorder
            )
        )
        await session.load()

        try await session.delete(id: wallet.id)

        #expect(await recorder.calls == [
            .load,
            .cancelPortfolio(wallet.address),
            .purge(wallet.address),
            .delete(wallet.id)
        ])
    }

    @Test func purgeFailureStopsDeletionAndRetainsPublishedSnapshot() async throws {
        let recorder = WalletSessionCallRecorder()
        let wallet = try makeWallet(name: "Main")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id),
            recorder: recorder
        )
        let purger = RecordingAddressCachePurger(recorder: recorder)
        await purger.setError(RepositoryTestError.storageWriteFailure)
        let session = WalletSession(store: store, cachePurger: purger)
        await session.load()

        await #expect(throws: RepositoryTestError.storageWriteFailure) {
            try await session.delete(id: wallet.id)
        }

        #expect(await recorder.calls == [.load, .purge(wallet.address)])
        #expect(session.wallets == [wallet])
        #expect(session.selectedWallet == wallet)
    }

    @Test func identityDeletionFailureRetainsPublishedSnapshot() async throws {
        let recorder = WalletSessionCallRecorder()
        let wallet = try makeWallet(name: "Main")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id),
            recorder: recorder
        )
        let purger = RecordingAddressCachePurger(recorder: recorder)
        let session = WalletSession(store: store, cachePurger: purger)
        await session.load()
        await store.setError(RepositoryTestError.storageWriteFailure)

        await #expect(throws: RepositoryTestError.storageWriteFailure) {
            try await session.delete(id: wallet.id)
        }

        #expect(await recorder.calls == [
            .load,
            .purge(wallet.address),
            .delete(wallet.id)
        ])
        #expect(session.wallets == [wallet])
        #expect(session.selectedWallet == wallet)
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
