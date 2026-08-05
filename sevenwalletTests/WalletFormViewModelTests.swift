import Foundation
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

    @Test func addDefaultsToWatchAddressAndOffersThreeMethods() {
        let form = WalletFormViewModel(mode: .add)

        #expect(form.importMethod == .watchAddress)
        #expect(WalletImportMethod.allCases == [
            .watchAddress,
            .recoveryPhrase,
            .privateKey
        ])
    }

    @Test func recoveryPhraseValidatesAndPreviewsDerivedAddress() throws {
        let form = WalletFormViewModel(mode: .add)
        form.setName("Imported")
        form.setImportMethod(.recoveryPhrase)
        form.setSecretInput(
            Array(repeating: "abandon", count: 11).joined(separator: " ")
                + " about"
        )

        #expect(form.secretError == nil)
        #expect(
            form.derivedAddress == (try EVMAddress(
                "0x9858effd232b4033e47d90003d41ec34ecaeda94"
            ))
        )
        #expect(form.canSubmit)

        form.setSecretInput(Array(repeating: "abandon", count: 12).joined(separator: " "))
        #expect(form.secretError == WalletCredentialError.invalidRecoveryPhrase.errorDescription)
        #expect(form.derivedAddress == nil)
        #expect(!form.canSubmit)
    }

    @Test func unchangedSecretInputDoesNotRevealValidation() {
        let form = WalletFormViewModel(mode: .add)
        form.setImportMethod(.recoveryPhrase)

        form.setSecretInput("")
        #expect(form.secretError == nil)

        form.setSecretInput("invalid")
        #expect(
            form.secretError
                == WalletCredentialError.invalidRecoveryPhrase.errorDescription
        )
    }

    @Test func privateKeyValidatesAndPreviewsDerivedAddress() throws {
        let form = WalletFormViewModel(mode: .add)
        form.setName("Imported")
        form.setImportMethod(.privateKey)
        form.setSecretInput("0x" + String(repeating: "0", count: 63) + "1")

        #expect(
            form.derivedAddress == (try EVMAddress(
                "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
            ))
        )
        #expect(form.canSubmit)

        form.setSecretInput("not-a-key")
        #expect(form.secretError == WalletCredentialError.invalidPrivateKey.errorDescription)
        #expect(!form.canSubmit)
    }

    @Test func classifiesWatchOnlyUpgradeAndImportedDuplicate() async throws {
        let address = try EVMAddress(
            "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
        )
        let watchOnly = SavedWallet(
            name: "Watch",
            address: address,
            cardColor: .blue
        )
        let watchSession = WalletSession(
            store: ScriptedSavedWalletStore(
                snapshot: .init(
                    wallets: [watchOnly],
                    selectedWalletID: watchOnly.id
                )
            ),
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: InMemoryWalletCredentialVault()
        )
        await watchSession.load()
        let form = makePrivateKeyForm()

        #expect(
            form.credentialImportTarget(session: watchSession)
                == .watchOnlyUpgrade(watchOnly)
        )

        let reference = WalletCredentialReference()
        let imported = SavedWallet(
            id: watchOnly.id,
            name: watchOnly.name,
            address: address,
            cardColor: watchOnly.cardColor,
            createdAt: watchOnly.createdAt,
            credentialReference: reference
        )
        let importedSession = WalletSession(
            store: ScriptedSavedWalletStore(
                snapshot: .init(
                    wallets: [imported],
                    selectedWalletID: imported.id
                )
            ),
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: InMemoryWalletCredentialVault(items: [
                reference: WalletCredentialPayload(
                    kind: .privateKey,
                    bytes: Data(repeating: 1, count: 32)
                )
            ])
        )
        await importedSession.load()

        #expect(
            form.credentialImportTarget(session: importedSession)
                == .importedDuplicate(imported)
        )
    }

    @Test func credentialFailureShowsNonSecretErrorAndKeepsFormUsable() async {
        let vault = InMemoryWalletCredentialVault()
        await vault.setError(
            WalletCredentialError.storageFailure,
            for: WalletCredentialVaultOperation.store
        )
        let session = WalletSession(
            store: ScriptedSavedWalletStore(),
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: vault
        )
        let form = makePrivateKeyForm()
        let secret = form.secretInput

        #expect(await form.submitCredential(session: session) == false)
        #expect(form.secretInput == secret)
        #expect(form.submissionError == WalletCredentialError.storageFailure.errorDescription)
        #expect(!(form.submissionError ?? "").contains(secret))
        #expect(!form.isSubmitting)
    }

    @Test func derivationFailureAfterConfirmationReportsAnError() async {
        // `canSubmit` derives once before the guard, so failing from the second
        // call reproduces a derivation that stops succeeding mid-submission.
        let form = WalletFormViewModel(
            mode: .add,
            deriver: FlakyCredentialDeriver(succeedingCalls: 1)
        )
        form.setName("Imported")
        form.setImportMethod(.privateKey)
        form.setSecretInput(String(repeating: "0", count: 63) + "1")
        let session = WalletSession(
            store: ScriptedSavedWalletStore(),
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: InMemoryWalletCredentialVault()
        )

        #expect(await form.submitCredential(session: session) == false)
        #expect(
            form.submissionError
                == WalletCredentialError.invalidPrivateKey.errorDescription
        )
        #expect(!form.isSubmitting)
    }

    @Test func clearsSecretOnMethodChangeCancelSuccessAndInactiveScene() async {
        let form = makePrivateKeyForm()
        form.setImportMethod(.recoveryPhrase)
        #expect(form.secretInput.isEmpty)

        form.setSecretInput("temporary")
        form.cancel()
        #expect(form.secretInput.isEmpty)

        let successfulForm = makePrivateKeyForm()
        let session = WalletSession(
            store: ScriptedSavedWalletStore(),
            cachePurger: RecordingAddressCachePurger(),
            credentialVault: InMemoryWalletCredentialVault()
        )
        #expect(await successfulForm.submitCredential(session: session))
        #expect(successfulForm.secretInput.isEmpty)

        let inactiveForm = makePrivateKeyForm()
        inactiveForm.sceneDidBecomeInactive()
        #expect(inactiveForm.secretInput.isEmpty)
    }

    @Test func nameInputCapsAtTwentyCharacters() {
        let form = WalletFormViewModel(mode: .add)

        form.setName("12345678901234567890x")

        #expect(form.name == "12345678901234567890")
    }

    @Test func editPrefillsAndLocksAddress() throws {
        let wallet = try makeWallet(name: "Main", cardColor: .teal)
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

    @Test func failedEditSavePreservesInputAndShowsError() async throws {
        let wallet = try makeWallet(name: "Main", cardColor: .blue)
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()
        let form = WalletFormViewModel(mode: .edit(wallet))
        form.setName("Renamed")
        form.selectedColor = .pink
        await store.setError(RepositoryTestError.storageWriteFailure)

        #expect(await form.submit(session: session) == false)
        #expect(form.name == "Renamed")
        #expect(form.selectedColor == .pink)
        #expect(form.address == wallet.address.rawValue)
        #expect(form.submissionError == "Unable to save wallet.")
        #expect(!form.isSubmitting)
        #expect(session.selectedWallet == wallet)
    }

    @Test func addNormalizesNameAndAddressBeforeSaving() async throws {
        let store = ScriptedSavedWalletStore()
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        let form = WalletFormViewModel(mode: .add)
        form.setName("  Main  ")
        form.address = "  0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92  "

        #expect(await form.submit(session: session))
        #expect(session.selectedWallet?.name == "Main")
        #expect(session.selectedWallet?.address.rawValue == "0x71a2b3c4d5e6f7890a1b2c3d4e5f67890abc8f92")
    }

    @Test func editOnlySavesNameAndColor() async throws {
        let wallet = try makeWallet(name: "Main", cardColor: .blue)
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()
        let form = WalletFormViewModel(mode: .edit(wallet))
        form.setName("Renamed")
        form.selectedColor = .pink
        form.address = "0x0000000000000000000000000000000000000000"

        #expect(await form.submit(session: session))
        #expect(session.selectedWallet?.name == "Renamed")
        #expect(session.selectedWallet?.cardColor == .pink)
        #expect(session.selectedWallet?.address == wallet.address)
    }

    @Test func failedDeletePreservesInputAndShowsError() async throws {
        let wallet = try makeWallet(name: "Main", cardColor: .blue)
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()
        await store.setError(RepositoryTestError.remoteFailure)
        let form = WalletFormViewModel(mode: .edit(wallet))
        form.setName("Renamed")

        #expect(await form.delete(session: session) == false)
        #expect(form.name == "Renamed")
        #expect(form.submissionError == "Unable to delete wallet.")
        #expect(!form.isSubmitting)
    }

    @Test func addModeCannotDelete() async {
        let session = WalletSession(
            store: ScriptedSavedWalletStore(),
            cachePurger: RecordingAddressCachePurger()
        )
        let form = WalletFormViewModel(mode: .add)

        #expect(await form.delete(session: session) == false)
        #expect(!form.isSubmitting)
    }

    @Test func duplicateSubmissionsDoNotSaveTwice() async {
        let store = GatedSavedWalletStore()
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        let form = WalletFormViewModel(mode: .add)
        form.setName("Main")
        form.address = "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"

        let first = Task { @MainActor in
            await form.submit(session: session)
        }
        await store.waitUntilAddStarted()

        #expect(await form.submit(session: session) == false)
        #expect(await store.addCallCount == 1)

        await store.releaseAdd()
        #expect(await first.value)
    }

    private func makeWallet(
        name: String,
        cardColor: WalletCardColor
    ) throws -> SavedWallet {
        SavedWallet(
            name: name,
            address: try EVMAddress(
                "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
            ),
            cardColor: cardColor
        )
    }

    private func makePrivateKeyForm() -> WalletFormViewModel {
        let form = WalletFormViewModel(mode: .add)
        form.setName("Imported")
        form.setImportMethod(.privateKey)
        form.setSecretInput("0x" + String(repeating: "0", count: 63) + "1")
        return form
    }

    private actor GatedSavedWalletStore: SavedWalletStoreProtocol {
        private var addStarted = false
        private var addStartedContinuation: CheckedContinuation<Void, Never>?
        private var releaseAddContinuation: CheckedContinuation<Void, Never>?
        private(set) var addCallCount = 0

        func loadSnapshot() async throws -> SavedWalletSnapshot {
            .init(wallets: [], selectedWalletID: nil)
        }

        func addAndSelect(_ wallet: SavedWallet) async throws -> SavedWalletSnapshot {
            addCallCount += 1
            addStarted = true
            addStartedContinuation?.resume()
            addStartedContinuation = nil
            await withCheckedContinuation { continuation in
                releaseAddContinuation = continuation
            }
            return .init(wallets: [wallet], selectedWalletID: wallet.id)
        }

        func select(id: UUID) async throws -> SavedWalletSnapshot {
            .init(wallets: [], selectedWalletID: nil)
        }

        func update(
            id: UUID,
            name: String,
            cardColor: WalletCardColor
        ) async throws -> SavedWalletSnapshot {
            .init(wallets: [], selectedWalletID: nil)
        }

        func delete(id: UUID) async throws -> SavedWalletSnapshot {
            .init(wallets: [], selectedWalletID: nil)
        }

        func attachCredentialReference(
            id: UUID,
            reference: WalletCredentialReference
        ) async throws -> SavedWalletSnapshot {
            .init(wallets: [], selectedWalletID: nil)
        }

        func detachCredentialReference(
            id: UUID
        ) async throws -> SavedWalletSnapshot {
            .init(wallets: [], selectedWalletID: nil)
        }

        func rollbackCredentialBackedAdd(
            id: UUID,
            restoringSelection selection: UUID?
        ) async throws -> SavedWalletSnapshot {
            .init(wallets: [], selectedWalletID: nil)
        }

        func waitUntilAddStarted() async {
            guard !addStarted else { return }
            await withCheckedContinuation { continuation in
                addStartedContinuation = continuation
            }
        }

        func releaseAdd() {
            releaseAddContinuation?.resume()
            releaseAddContinuation = nil
        }
    }
}

private final class FlakyCredentialDeriver: WalletCredentialDeriving, @unchecked Sendable {
    private let real = TrustWalletCredentialDeriver()
    private let succeedingCalls: Int
    private var calls = 0

    init(succeedingCalls: Int) {
        self.succeedingCalls = succeedingCalls
    }

    func prepare(_ input: WalletSecretInput) throws -> PreparedWalletCredential {
        calls += 1
        guard calls <= succeedingCalls else {
            throw WalletCredentialError.invalidPrivateKey
        }
        return try real.prepare(input)
    }
}
