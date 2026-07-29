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

    @Test func loadPreservesCredentialBackedWalletWithoutPrompting() async throws {
        let reference = WalletCredentialReference()
        let wallet = try makeWallet(
            name: "Imported",
            credentialReference: reference
        )
        let vault = InMemoryWalletCredentialVault(items: [
            reference: WalletCredentialPayload(
                kind: .privateKey,
                bytes: Data(repeating: 1, count: 32)
            )
        ])
        let session = WalletSession(
            store: ScriptedSavedWalletStore(
                snapshot: .init(
                    wallets: [wallet],
                    selectedWalletID: wallet.id
                )
            ),
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )

        await session.load()

        #expect(session.wallets == [wallet])
        #expect(session.credentialRecoveryNotice == nil)
        #expect(await vault.calls == [.presence(reference)])
    }

    @Test func loadDowngradesMissingCredentialAndRaisesReimportNotice() async throws {
        let reference = WalletCredentialReference()
        let wallet = try makeWallet(
            name: "Imported",
            credentialReference: reference
        )
        let vault = InMemoryWalletCredentialVault()
        let session = WalletSession(
            store: ScriptedSavedWalletStore(
                snapshot: .init(
                    wallets: [wallet],
                    selectedWalletID: wallet.id
                )
            ),
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )

        await session.load()

        let downgraded = try #require(session.wallets.first)
        #expect(downgraded.credentialReference == nil)
        #expect(downgraded.id == wallet.id)
        #expect(downgraded.name == wallet.name)
        #expect(downgraded.address == wallet.address)
        #expect(session.credentialRecoveryNotice?.walletID == wallet.id)
        #expect(session.credentialRecoveryNotice?.walletName == "Imported")
        #expect(session.loadErrorMessage == nil)
    }

    @Test func indeterminateCredentialStatusFailsLoadWithoutDowngrade() async throws {
        let reference = WalletCredentialReference()
        let wallet = try makeWallet(
            name: "Imported",
            credentialReference: reference
        )
        let vault = InMemoryWalletCredentialVault()
        await vault.setError(
            WalletCredentialError.statusUnavailable,
            for: .presence(reference)
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )

        await session.load()

        #expect(session.wallets.isEmpty)
        #expect(session.loadErrorMessage == "Unable to load saved wallets.")
        #expect(session.credentialRecoveryNotice == nil)
        #expect(try await store.loadSnapshot().wallets == [wallet])
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

    @Test func credentialImportSelectsOnlyAfterVaultAndPortfolioSucceed() async throws {
        let store = ScriptedSavedWalletStore()
        let vault = InMemoryWalletCredentialVault()
        let controller = RecordingPortfolioLoadController(isResumeGated: true)
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            portfolioLoadController: controller,
            credentialVault: vault
        )
        let prepared = try makePreparedCredential()

        let importing = Task {
            try await session.importCredential(
                name: "Imported",
                prepared: prepared,
                cardColor: .teal
            )
        }
        await controller.waitUntilResumeStarted(address: prepared.address)

        #expect(session.wallets.isEmpty)
        let reference = try #require(
            (await vault.calls).compactMap { call -> WalletCredentialReference? in
                guard case let .store(reference) = call else { return nil }
                return reference
            }.first
        )
        #expect((await vault.payload(for: reference))?.bytes == prepared.payload.bytes)

        await controller.releaseResume(address: prepared.address)
        try await importing.value

        let imported = try #require(session.selectedWallet)
        #expect(imported.name == "Imported")
        #expect(imported.address == prepared.address)
        #expect(imported.cardColor == .teal)
        #expect(imported.credentialReference == reference)
        #expect(await store.operations == [.add])
    }

    @Test func unavailableProtectionPreventsCredentialPublicWrite() async throws {
        let store = ScriptedSavedWalletStore()
        let vault = InMemoryWalletCredentialVault(protectionAvailable: false)
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )

        await #expect(throws: WalletCredentialError.protectionUnavailable) {
            try await session.importCredential(
                name: "Imported",
                prepared: try makePreparedCredential(),
                cardColor: .blue
            )
        }

        #expect(await store.operations.isEmpty)
        #expect(await vault.calls == [.protectionAvailability])
        #expect(session.wallets.isEmpty)
    }

    @Test func publicWriteFailureDoesNotStoreCredential() async throws {
        let store = ScriptedSavedWalletStore()
        await store.setError(
            RepositoryTestError.storageWriteFailure,
            for: .add
        )
        let vault = InMemoryWalletCredentialVault()
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )

        await #expect(throws: RepositoryTestError.storageWriteFailure) {
            try await session.importCredential(
                name: "Imported",
                prepared: try makePreparedCredential(),
                cardColor: .blue
            )
        }

        #expect(await store.operations == [.add])
        #expect(await vault.calls == [.protectionAvailability])
        #expect(session.wallets.isEmpty)
    }

    @Test(arguments: [
        WalletCredentialError.authenticationCancelled,
        WalletCredentialError.authenticationFailed,
        WalletCredentialError.storageFailure
    ])
    func vaultFailureRollsBackPublicCredentialWallet(
        error: WalletCredentialError
    ) async throws {
        let store = ScriptedSavedWalletStore()
        let vault = InMemoryWalletCredentialVault()
        await vault.setError(error, for: WalletCredentialVaultOperation.store)
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )

        await #expect(throws: error) {
            try await session.importCredential(
                name: "Imported",
                prepared: try makePreparedCredential(),
                cardColor: .blue
            )
        }

        #expect(await store.operations == [
            .add,
            .rollbackCredentialBackedAdd
        ])
        #expect(try await store.loadSnapshot().wallets.isEmpty)
        #expect(session.wallets.isEmpty)
    }

    @Test func rollbackFailureLeavesUnpublishedReferenceForLoadRepair() async throws {
        let store = ScriptedSavedWalletStore()
        await store.setError(
            RepositoryTestError.storageWriteFailure,
            for: .rollbackCredentialBackedAdd
        )
        let vault = InMemoryWalletCredentialVault()
        await vault.setError(
            WalletCredentialError.storageFailure,
            for: WalletCredentialVaultOperation.store
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )

        await #expect(throws: WalletCredentialError.storageFailure) {
            try await session.importCredential(
                name: "Imported",
                prepared: try makePreparedCredential(),
                cardColor: .blue
            )
        }

        #expect(session.wallets.isEmpty)
        let persisted = try #require(
            try await store.loadSnapshot().wallets.first
        )
        #expect(persisted.credentialReference != nil)
        #expect(await store.operations == [
            .add,
            .rollbackCredentialBackedAdd
        ])
    }

    @Test func watchOnlyMatchRequiresExplicitUpgradeConfirmation() async throws {
        let watchOnly = try makeWallet(name: "Existing")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(
                wallets: [watchOnly],
                selectedWalletID: watchOnly.id
            )
        )
        let vault = InMemoryWalletCredentialVault()
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )
        await session.load()
        let prepared = try makePreparedCredential(address: watchOnly.address)

        #expect(
            session.credentialImportTarget(for: watchOnly.address)
                == .watchOnlyUpgrade(watchOnly)
        )
        await #expect(throws: WalletSessionError.upgradeConfirmationRequired) {
            try await session.importCredential(
                name: "Ignored",
                prepared: prepared,
                cardColor: .pink
            )
        }

        #expect(await store.operations.isEmpty)
        #expect(await vault.calls.isEmpty)
        #expect(session.wallets == [watchOnly])
    }

    @Test func confirmedUpgradePreservesIdentityAndCreatesNoDuplicate() async throws {
        let watchOnly = try makeWallet(name: "Existing")
        let other = SavedWallet(
            name: "Other",
            address: try EVMAddress(
                "0x0000000000000000000000000000000000000002"
            ),
            cardColor: .amber
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(
                wallets: [watchOnly, other],
                selectedWalletID: other.id
            )
        )
        let vault = InMemoryWalletCredentialVault()
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )
        await session.load()
        let prepared = try makePreparedCredential(address: watchOnly.address)

        try await session.importCredential(
            name: "Do Not Apply",
            prepared: prepared,
            cardColor: .pink,
            confirmedUpgradeWalletID: watchOnly.id
        )

        #expect(session.wallets.count == 2)
        let upgraded = try #require(
            session.wallets.first(where: { $0.id == watchOnly.id })
        )
        #expect(upgraded.name == watchOnly.name)
        #expect(upgraded.address == watchOnly.address)
        #expect(upgraded.cardColor == watchOnly.cardColor)
        #expect(upgraded.createdAt == watchOnly.createdAt)
        #expect(upgraded.credentialReference != nil)
        #expect(session.selectedWallet?.id == watchOnly.id)
        #expect(await store.operations == [.attachCredentialReference])
    }

    @Test func upgradeVaultFailureDetachesReferenceAndKeepsWallet() async throws {
        let watchOnly = try makeWallet(name: "Existing")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(
                wallets: [watchOnly],
                selectedWalletID: watchOnly.id
            )
        )
        let vault = InMemoryWalletCredentialVault()
        await vault.setError(
            WalletCredentialError.authenticationCancelled,
            for: WalletCredentialVaultOperation.store
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )
        await session.load()

        await #expect(throws: WalletCredentialError.authenticationCancelled) {
            try await session.importCredential(
                name: "Ignored",
                prepared: try makePreparedCredential(
                    address: watchOnly.address
                ),
                cardColor: .pink,
                confirmedUpgradeWalletID: watchOnly.id
            )
        }

        #expect(session.wallets == [watchOnly])
        #expect(try await store.loadSnapshot().wallets == [watchOnly])
        #expect(await store.operations == [
            .attachCredentialReference,
            .detachCredentialReference
        ])
    }

    @Test func confirmedUpgradeRechecksAndRejectsImportedDuplicate() async throws {
        let watchOnly = try makeWallet(name: "Existing")
        let reference = WalletCredentialReference()
        let store = ScriptedSavedWalletStore(
            snapshot: .init(
                wallets: [watchOnly],
                selectedWalletID: watchOnly.id
            )
        )
        let vault = InMemoryWalletCredentialVault(items: [
            reference: WalletCredentialPayload(
                kind: .privateKey,
                bytes: Data(repeating: 1, count: 32)
            )
        ])
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )
        await session.load()
        #expect(
            session.credentialImportTarget(for: watchOnly.address)
                == .watchOnlyUpgrade(watchOnly)
        )

        _ = try await store.attachCredentialReference(
            id: watchOnly.id,
            reference: reference
        )
        await session.load()
        await store.resetOperations()
        await vault.resetCalls()

        await #expect(throws: WalletCredentialError.credentialAlreadyImported) {
            try await session.importCredential(
                name: "Ignored",
                prepared: try makePreparedCredential(
                    address: watchOnly.address
                ),
                cardColor: .pink,
                confirmedUpgradeWalletID: watchOnly.id
            )
        }

        #expect(await store.operations.isEmpty)
        #expect(await vault.calls.isEmpty)
        #expect(session.wallets.count == 1)
        #expect(session.wallets.first?.credentialReference == reference)
    }

    @Test func selectPublishesTheChosenWallet() async throws {
        let first = try makeWallet(name: "First")
        let second = SavedWallet(
            name: "Second",
            address: try EVMAddress(
                "0x0000000000000000000000000000000000000002"
            ),
            cardColor: .purple
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(
                wallets: [first, second],
                selectedWalletID: first.id
            )
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()

        try await session.select(id: second.id)

        #expect(session.wallets == [first, second])
        #expect(session.selectedWallet == second)
    }

    @Test func selectingCurrentWalletClearsSelectionError() async throws {
        let first = try makeWallet(name: "First")
        let second = SavedWallet(
            name: "Second",
            address: try EVMAddress(
                "0x0000000000000000000000000000000000000002"
            ),
            cardColor: .purple
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(
                wallets: [first, second],
                selectedWalletID: first.id
            )
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()
        await store.setError(RepositoryTestError.storageWriteFailure)

        await #expect(throws: RepositoryTestError.storageWriteFailure) {
            try await session.select(id: second.id)
        }
        #expect(session.selectionErrorMessage == "Unable to switch wallet.")

        try await session.select(id: first.id)

        #expect(session.selectionErrorMessage == nil)
    }

    @Test func selectionErrorCanBeClearedAfterLeavingWalletList() async throws {
        let first = try makeWallet(name: "First")
        let second = SavedWallet(
            name: "Second",
            address: try EVMAddress(
                "0x0000000000000000000000000000000000000002"
            ),
            cardColor: .purple
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(
                wallets: [first, second],
                selectedWalletID: first.id
            )
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()
        await store.setError(RepositoryTestError.storageWriteFailure)
        await #expect(throws: RepositoryTestError.storageWriteFailure) {
            try await session.select(id: second.id)
        }

        session.clearSelectionError()

        #expect(session.selectionErrorMessage == nil)
        #expect(session.selectedWallet == first)
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

    @Test func importedDeletionRemovesSecretBeforeCachesAndIdentity() async throws {
        let reference = WalletCredentialReference()
        let wallet = try makeWallet(
            name: "Imported",
            credentialReference: reference
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let vault = InMemoryWalletCredentialVault(items: [
            reference: WalletCredentialPayload(
                kind: .privateKey,
                bytes: Data(repeating: 1, count: 32)
            )
        ])
        let purger = SecretAbsenceCheckingPurger(
            vault: vault,
            reference: reference
        )
        let session = WalletSession(
            store: store,
            cachePurger: purger,
            credentialVault: vault
        )
        await session.load()
        await vault.resetCalls()
        await store.resetOperations()

        try await session.delete(id: wallet.id)

        #expect(await purger.secretWasAbsent)
        #expect(await vault.payload(for: reference) == nil)
        #expect(await vault.calls == [.delete(reference)])
        #expect(await store.operations == [
            .detachCredentialReference,
            .delete
        ])
        #expect(session.wallets.isEmpty)
    }

    @Test func importedDeleteAuthenticationCancellationChangesNothing() async throws {
        let reference = WalletCredentialReference()
        let wallet = try makeWallet(
            name: "Imported",
            credentialReference: reference
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let vault = InMemoryWalletCredentialVault(items: [
            reference: WalletCredentialPayload(
                kind: .privateKey,
                bytes: Data(repeating: 1, count: 32)
            )
        ])
        await vault.setError(
            WalletCredentialError.authenticationCancelled,
            for: WalletCredentialVaultOperation.delete
        )
        let purger = RecordingAddressCachePurger()
        let session = WalletSession(
            store: store,
            cachePurger: purger,
            credentialVault: vault
        )
        await session.load()
        await vault.resetCalls()

        await #expect(throws: WalletCredentialError.authenticationCancelled) {
            try await session.delete(id: wallet.id)
        }

        #expect((await vault.payload(for: reference)) != nil)
        #expect(await store.operations.isEmpty)
        #expect(await purger.addresses.isEmpty)
        #expect(session.wallets == [wallet])
    }

    @Test func cacheFailureAfterSecretDeletionLeavesWalletWatchOnly() async throws {
        let reference = WalletCredentialReference()
        let wallet = try makeWallet(
            name: "Imported",
            credentialReference: reference
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let vault = InMemoryWalletCredentialVault(items: [
            reference: WalletCredentialPayload(
                kind: .privateKey,
                bytes: Data(repeating: 1, count: 32)
            )
        ])
        let purger = RecordingAddressCachePurger()
        await purger.setError(RepositoryTestError.storageWriteFailure)
        let controller = RecordingPortfolioLoadController()
        let session = WalletSession(
            store: store,
            cachePurger: purger,
            portfolioLoadController: controller,
            credentialVault: vault
        )
        await session.load()
        await store.resetOperations()

        await #expect(throws: RepositoryTestError.storageWriteFailure) {
            try await session.delete(id: wallet.id)
        }

        #expect(await vault.payload(for: reference) == nil)
        #expect(session.wallets.first?.credentialReference == nil)
        #expect(
            try await store.loadSnapshot().wallets.first?.credentialReference
                == nil
        )
        #expect(await store.operations == [.detachCredentialReference])
        #expect(!(await controller.isSuspended(address: wallet.address)))
    }

    @Test func metadataFailureAfterSecretDeletionLeavesWalletWatchOnly() async throws {
        let reference = WalletCredentialReference()
        let wallet = try makeWallet(
            name: "Imported",
            credentialReference: reference
        )
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        await store.setError(
            RepositoryTestError.storageWriteFailure,
            for: .delete
        )
        let vault = InMemoryWalletCredentialVault(items: [
            reference: WalletCredentialPayload(
                kind: .privateKey,
                bytes: Data(repeating: 1, count: 32)
            )
        ])
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )
        await session.load()
        await store.resetOperations()

        await #expect(throws: RepositoryTestError.storageWriteFailure) {
            try await session.delete(id: wallet.id)
        }

        #expect(await vault.payload(for: reference) == nil)
        #expect(session.wallets.first?.credentialReference == nil)
        #expect(await store.operations == [
            .detachCredentialReference,
            .delete
        ])
    }

    @Test func watchOnlyDeletionDoesNotTouchCredentialVault() async throws {
        let wallet = try makeWallet(name: "Watch")
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let vault = InMemoryWalletCredentialVault()
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )
        await session.load()

        try await session.delete(id: wallet.id)

        #expect(await vault.calls.isEmpty)
        #expect(await store.operations == [.delete])
    }

    private func makeWallet(
        name: String,
        credentialReference: WalletCredentialReference? = nil
    ) throws -> SavedWallet {
        SavedWallet(
            name: name,
            address: try EVMAddress(
                "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
            ),
            cardColor: .blue,
            credentialReference: credentialReference
        )
    }

    private func makePreparedCredential(
        address: EVMAddress? = nil
    ) throws -> PreparedWalletCredential {
        PreparedWalletCredential(
            address: try address ?? EVMAddress(
                "0x0000000000000000000000000000000000000001"
            ),
            payload: WalletCredentialPayload(
                kind: .privateKey,
                bytes: Data(repeating: 1, count: 32)
            )
        )
    }
}

private actor SecretAbsenceCheckingPurger: AddressCachePurging {
    private let vault: InMemoryWalletCredentialVault
    private let reference: WalletCredentialReference
    private(set) var secretWasAbsent = false

    init(
        vault: InMemoryWalletCredentialVault,
        reference: WalletCredentialReference
    ) {
        self.vault = vault
        self.reference = reference
    }

    func purgeAddressData(address: EVMAddress) async {
        if let _ = await vault.payload(for: reference) {
            secretWasAbsent = false
        } else {
            secretWasAbsent = true
        }
    }
}
