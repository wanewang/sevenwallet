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

    @Test func addResumesPortfolioBeforePublishingSnapshot() async throws {
        let address = try makeWallet(name: "Reference").address
        let store = ScriptedSavedWalletStore()
        let controller = RecordingPortfolioLoadController(
            isResumeGated: true
        )
        await controller.suspendPortfolioLoads(address: address)
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            portfolioLoadController: controller
        )

        let addition = Task {
            try await session.add(
                name: "Main",
                address: address,
                cardColor: .blue
            )
        }
        await controller.waitUntilResumeStarted(address: address)

        #expect(session.wallets.isEmpty)
        #expect(session.selectedWallet == nil)
        #expect(await controller.isSuspended(address: address))

        await controller.releaseResume(address: address)
        try await addition.value

        #expect(session.selectedWallet?.address == address)
        #expect(!(await controller.isSuspended(address: address)))
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

    @Test func updateCannotStartWhileDeleteIsSuspended() async throws {
        let wallet = try makeWallet(name: "Main")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id),
            isDeleteGated: true
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()

        let deletion = Task { try await session.delete(id: wallet.id) }
        await store.waitUntilDeleteStarted()

        await #expect(throws: WalletSessionError.mutationInProgress) {
            try await session.update(
                id: wallet.id,
                name: "Too Late",
                cardColor: .pink
            )
        }

        await store.releaseDelete()
        try await deletion.value
        #expect(session.wallets.isEmpty)
    }

    @Test func deleteCannotStartWhileUpdateIsSuspended() async throws {
        let wallet = try makeWallet(name: "Main")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id),
            isUpdateGated: true
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()

        let update = Task {
            try await session.update(
                id: wallet.id,
                name: "Renamed",
                cardColor: .pink
            )
        }
        await store.waitUntilUpdateStarted()

        await #expect(throws: WalletSessionError.mutationInProgress) {
            try await session.delete(id: wallet.id)
        }
        #expect(!session.isDeletingWallet)

        await store.releaseUpdate()
        try await update.value
        #expect(session.selectedWallet?.name == "Renamed")
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
            portfolioLoadController: RecordingPortfolioLoadController(
                recorder: recorder
            )
        )
        await session.load()

        try await session.delete(id: wallet.id)

        #expect(await recorder.calls == [
            .load,
            .suspendPortfolio(wallet.address),
            .purge(wallet.address),
            .delete(wallet.id)
        ])
    }

    @Test
    func deleteBlocksNewLoadsUntilSameAddressIsReadded() async throws {
        let wallet = try makeWallet(name: "Main")
        let savedWalletStore = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id),
            isDeleteGated: true
        )
        let portfolioStore = WalletStoreSpy()
        let fresh = makeRepositoryPortfolio(
            address: wallet.address,
            price: "2000"
        )
        let remote = TokenRemoteDataSourceSpy(
            portfolioResults: [wallet.address: .success(fresh)]
        )
        let repository = TokenRepository(remote: remote, store: portfolioStore)
        let purger = RecordingAddressCachePurger()
        let session = WalletSession(
            store: savedWalletStore,
            cachePurger: purger,
            portfolioLoadController: repository
        )
        await session.load()

        let deletion = Task { try await session.delete(id: wallet.id) }
        await savedWalletStore.waitUntilDeleteStarted()

        #expect(session.isDeletingWallet)
        await #expect(throws: WalletSessionError.mutationInProgress) {
            try await session.add(
                name: "Too Soon",
                address: wallet.address,
                cardColor: .amber
            )
        }
        var duringDeletion = repository
            .portfolio(address: wallet.address, policy: .force)
            .makeAsyncIterator()
        #expect(try await duringDeletion.next() == nil)
        #expect(await portfolioStore.portfolioLoadCounts[wallet.address] == nil)
        #expect(await remote.portfolioCallCounts[wallet.address] == nil)

        await savedWalletStore.releaseDelete()
        try await deletion.value

        #expect(!session.isDeletingWallet)
        var afterDeletion = repository
            .portfolio(address: wallet.address, policy: .force)
            .makeAsyncIterator()
        #expect(try await afterDeletion.next() == nil)
        #expect(await portfolioStore.portfolioLoadCounts[wallet.address] == nil)
        #expect(await remote.portfolioCallCounts[wallet.address] == nil)

        try await session.add(
            name: "Restored",
            address: wallet.address,
            cardColor: .pink
        )
        var afterReadd = repository
            .portfolio(address: wallet.address, policy: .force)
            .makeAsyncIterator()
        #expect(try await afterReadd.next() == .refreshing)
        #expect(try await afterReadd.next() == .fresh(fresh))
        #expect(await portfolioStore.portfolioLoadCounts[wallet.address] == 1)
        #expect(await remote.portfolioCallCounts[wallet.address] == 1)
    }

    @Test func deleteCannotStartWhileAddIsSuspended() async throws {
        let recorder = WalletSessionCallRecorder()
        let existing = try makeWallet(name: "Existing")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(
                wallets: [existing],
                selectedWalletID: existing.id
            ),
            recorder: recorder,
            isAddGated: true
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(recorder: recorder),
            portfolioLoadController: RecordingPortfolioLoadController(
                recorder: recorder
            )
        )
        await session.load()

        let addition = Task {
            try await session.add(
                name: "Second",
                address: existing.address,
                cardColor: .pink
            )
        }
        await store.waitUntilAddStarted()

        await #expect(throws: WalletSessionError.mutationInProgress) {
            try await session.delete(id: existing.id)
        }
        #expect(!session.isDeletingWallet)
        #expect(await recorder.calls == [.load])

        await store.releaseAdd()
        try await addition.value
        #expect(session.wallets.count == 2)

        try await session.delete(id: existing.id)
        #expect(session.wallets.count == 1)
        #expect(await recorder.calls == [
            .load,
            .resumePortfolio(existing.address),
            .suspendPortfolio(existing.address),
            .purge(existing.address),
            .delete(existing.id),
            .resumePortfolio(existing.address)
        ])
    }

    @Test
    func deleteResumesWhenRemainingSelectionUsesSameAddress() async throws {
        let recorder = WalletSessionCallRecorder()
        let first = try makeWallet(name: "First")
        let second = SavedWallet(
            name: "Second",
            address: first.address,
            cardColor: .pink
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(
                wallets: [first, second],
                selectedWalletID: first.id
            ),
            recorder: recorder
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(recorder: recorder),
            portfolioLoadController: RecordingPortfolioLoadController(
                recorder: recorder
            )
        )
        await session.load()

        try await session.delete(id: first.id)

        #expect(session.selectedWallet == second)
        #expect(await recorder.calls == [
            .load,
            .suspendPortfolio(first.address),
            .purge(first.address),
            .delete(first.id),
            .resumePortfolio(first.address)
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
        let session = WalletSession(
            store: store,
            cachePurger: purger,
            portfolioLoadController: RecordingPortfolioLoadController(
                recorder: recorder
            )
        )
        await session.load()

        await #expect(throws: RepositoryTestError.storageWriteFailure) {
            try await session.delete(id: wallet.id)
        }

        #expect(await recorder.calls == [
            .load,
            .suspendPortfolio(wallet.address),
            .purge(wallet.address),
            .resumePortfolio(wallet.address)
        ])
        #expect(!session.isDeletingWallet)
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
        let session = WalletSession(
            store: store,
            cachePurger: purger,
            portfolioLoadController: RecordingPortfolioLoadController(
                recorder: recorder
            )
        )
        await session.load()
        await store.setError(RepositoryTestError.storageWriteFailure)

        await #expect(throws: RepositoryTestError.storageWriteFailure) {
            try await session.delete(id: wallet.id)
        }

        #expect(await recorder.calls == [
            .load,
            .suspendPortfolio(wallet.address),
            .purge(wallet.address),
            .delete(wallet.id),
            .resumePortfolio(wallet.address)
        ])
        #expect(!session.isDeletingWallet)
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
